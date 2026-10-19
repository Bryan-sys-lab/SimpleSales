import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../db/database_helper.dart';
import 'esc_pos_encoder.dart';
import 'esc_pos_printer.dart';
import 'printer_config.dart';
import 'printer_service.dart';
import 'receipt_builder.dart';

/// Why a print attempt ended the way it did.
///
/// Typed rather than a message so a caller can decide whether to offer a
/// retry, a settings shortcut, or nothing at all — and so a shop that has
/// printing switched off never sees an error.
enum PrintOutcome {
  /// Paper came out.
  printed,

  /// The shop has not turned printing on. Not a failure.
  disabled,

  /// No paper. The caller should offer a reprint; the sale is untouched.
  failed,
}

/// The result of one print attempt.
@immutable
class PrintResult {
  const PrintResult(this.outcome, {this.failure});

  final PrintOutcome outcome;
  final PrinterFailure? failure;

  bool get printed => outcome == PrintOutcome.printed;

  /// True when retrying unchanged is pointless — the operator has to grant a
  /// permission, pair a printer, or switch printing on first.
  bool get needsUserAction =>
      failure == PrinterFailure.permissionDenied ||
      failure == PrinterFailure.permissionPermanentlyDenied ||
      failure == PrinterFailure.notPaired ||
      failure == PrinterFailure.unavailable;
}

/// Builds and prints a receipt for a *recorded* sale.
///
/// This is the only place a receipt is produced. Print-after-sale and reprint
/// are the same call with the same arguments, which is the whole point: two
/// code paths that render a receipt independently are how a reprint quietly
/// starts showing a different total, a different cashier or no VAT line from
/// the receipt the customer was originally handed.
///
/// Everything comes from the stored `Sale`, re-fetched by id. Building from the
/// live cart instead would print whatever the cart holds at print time — which,
/// for a reprint, is a cart the cashier has since emptied and refilled.
class ReceiptPrinter {
  ReceiptPrinter({
    PrinterService? printer,
    EscPosEncoder encoder = const EscPosEncoder(),
  })  : _printer = printer ?? EscPosPrinter(),
        _encoder = encoder;

  final PrinterService _printer;
  final EscPosEncoder _encoder;
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Prints the receipt for sale [saleId].
  ///
  /// [shopName] and [staffRole] are passed in rather than read from `AppState`,
  /// so this stays free of the widget tree and testable.
  ///
  /// There is deliberately no `isReprint` flag. A reprint is the same document
  /// from the same stored sale, so giving it a flag would invite callers to
  /// print *something different* on a reprint — "REPRINT" in the header, a
  /// second subtraction of stock. If a reprint audit trail is ever wanted it
  /// belongs in the ledger, not on the customer's copy.
  ///
  /// Never throws. A print failure must not propagate into checkout: the sale
  /// is already committed, and a caller that treated an exception as a failed
  /// sale would be tempted to roll back money that has been taken.
  Future<PrintResult> printSale({
    required int saleId,
    required String shopName,
    required String staffRole,
    required PrinterConfig config,
    required int vatRatePercent,
    required bool pricesIncludeVat,
    String? etimsReceiptNumber,
    String? etimsVerificationPayload,
    bool etimsPending = false,
  }) async {
    if (!config.isConfigured) return const PrintResult(PrintOutcome.disabled);

    final sale = await _db.getSaleById(saleId);
    if (sale == null) {
      // The id is not in this workspace's ledger — a stale id from another
      // shop. There is nothing to print and nothing to retry.
      return const PrintResult(PrintOutcome.failed,
          failure: PrinterFailure.printFailed);
    }
    final row = await _db.getSaleRowById(saleId);
    final receiptNumber = row == null
        ? 'POS-${saleId.toString().padLeft(6, '0')}'
        : _db.receiptNumberFor(row);

    final input = ReceiptInput(
      shopName: shopName,
      receiptNumber: receiptNumber,
      // The recorded timestamp is authoritative. The till's clock at print time
      // can differ from the one at sale time, and a receipt that shows a
      // different time from the ledger is a receipt an auditor cannot match.
      issuedAt: DateTime.tryParse(sale.createdAt) ?? DateTime.now(),
      cashierName: sale.staffName,
      cashierRole: staffRole,
      items: sale.items,
      total: sale.total,
      amountTendered: sale.amountTendered,
      changeGiven: sale.changeGiven,
      paymentMethodLabel: paymentLabelFor(sale.paymentMethod),
      vatRatePercent: vatRatePercent,
      pricesIncludeVat: pricesIncludeVat,
      etimsReceiptNumber:
          etimsReceiptNumber ?? row?['etims_receipt_number'] as String?,
      etimsVerificationPayload:
          etimsVerificationPayload ?? await verificationPayloadFor(row),
      etimsPending: etimsPending,
    );

    if (input.items.isEmpty) {
      return const PrintResult(PrintOutcome.failed,
          failure: PrinterFailure.printFailed);
    }

    final bytes = _encoder.encode(
      // The builder is given the paper's budget, not left on its 58mm default:
      // the two places it uses the budget (the shop-name magnification, and any
      // truncation) must agree with the encoder, or an 80mm roll gets a
      // 58mm-ruled layout.
      ReceiptBuilder(columnBudget: config.paperWidth.columnBudget).build(input),
      columnBudget: config.paperWidth.columnBudget,
    );

    try {
      // Lazy connect, before every print. Reconnection after a dropped link is
      // the common case, not an edge case: these printers power themselves off
      // between customers. A pairing lost mid-shift must degrade to "couldn't
      // print" rather than to a hang, so the timeout is short and bounded.
      await _printer.connect(config.macAddress,
          timeout: const Duration(seconds: 8));
      await _printer.send(bytes);
      return const PrintResult(PrintOutcome.printed);
    } on PrinterException catch (error) {
      debugPrint('Receipt print failed: ${error.detail ?? error.failure.name}');
      return PrintResult(PrintOutcome.failed, failure: error.failure);
    } catch (error) {
      // A platform channel can fail in ways that are not a PrinterException —
      // a codec error on a malformed byte list, for instance. Still must not
      // reach the caller as a throw.
      debugPrint('Receipt print failed unexpectedly: $error');
      return const PrintResult(PrintOutcome.failed,
          failure: PrinterFailure.printFailed);
    }
  }

  /// The eTIMS verification payload for a sale.
  ///
  /// KRA's own `qr_payload`, persisted on the sale when the receipt was issued.
  /// Only used as the QR: a URL built locally is how a receipt ends up with a QR
  /// that scans to a 404. When nothing was stored — the shop is not linked, the
  /// upload is still pending, or KRA returned no payload — this returns null and
  /// the receipt prints the eTIMS number only, with no QR.
  static Future<String?> verificationPayloadFor(
      Map<String, dynamic>? row) async {
    if (row == null) return null;
    final payload = row['etims_qr_payload'] as String?;
    if (payload != null && payload.trim().isNotEmpty) return payload.trim();
    return null;
  }

  /// Customer-facing payment names.
  ///
  /// The wire vocabulary (`bank_transfer`, `mobile_money_manual`) is not the
  /// name a customer reads on a receipt, and the wire vocabulary is exactly the
  /// thing that changes most often.
  static String paymentLabelFor(String paymentMethod) =>
      switch (paymentMethod) {
        'cash' => 'Cash',
        'card' => 'Card',
        'bank_transfer' => 'Bank transfer',
        'mobile_money_manual' => 'Mobile money',
        'mpesa' => 'M-Pesa',
        _ => 'Payment',
      };
}
