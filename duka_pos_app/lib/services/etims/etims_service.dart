import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend_service.dart';
import '../../db/database_helper.dart';
import '../../models/credit.dart' show Customer;
import '../../models/models.dart';
import '../../utils/money.dart';

/// One sale, shaped for the backend's eTIMS endpoint.
///
/// Rebuilt from the stored sale at flush time rather than snapshotted into the
/// queue, so there is exactly one copy of the amounts on the till and no way
/// for the queue and the ledger to disagree about what was sold.
Map<String, dynamic> buildEtimsPayload({
  required Sale sale,
  required Map<String, dynamic> saleRow,
  required DatabaseHelper db,
  required String tillCode,
  required String tin,
  required int vatRatePercent,
  required bool pricesIncludeVat,
  String? paymentMethod,
  Customer? customer,
}) {
  final receiptNumber = db.receiptNumberFor(saleRow);
  return {
    'receipt_number': receiptNumber,
    'issued_at': sale.createdAt,
    'payment_method': paymentMethod ?? sale.paymentMethod,
    'payment_reference': sale.paymentReference,
    'total': sale.total.minorUnits,
    'vat_rate_percent': vatRatePercent,
    // Business-customer details ride the invoice when the sale carries a
    // customer (spec 7.6). The TIN is what KRA validates; the name only
    // identifies the buyer on the document.
    if (customer != null || sale.buyerName != null) ...{
      'buyer_name': customer?.name ?? sale.buyerName,
      if ((customer?.tin ?? sale.buyerTin)?.trim().isNotEmpty ?? false)
        'buyer_tin': (customer?.tin ?? sale.buyerTin)!.trim(),
    },
    'items': sale.items
        .map((item) => {
              'name': item.productName,
              'qty': item.qty,
              'unit_price': item.unitPrice.minorUnits,
              'portion': item.portion,
              'portion_ml': item.portionMl,
              // The VAT contained in this line, in minor units. Sent rather
              // than recomputed server-side so the figure KRA records is
              // exactly the figure printed on the customer's receipt.
              'vat_amount': vatComponentForTaxClass(item.total,
                      ratePercent: vatRatePercent,
                      taxClass: item.taxClass,
                      pricesIncludeVat: pricesIncludeVat)
                  .minorUnits,
              'line_total': item.total.minorUnits,
            })
        .toList(),
  };
}

/// Drives eTIMS receipt issuance from the till.
///
/// The shape is copied wholesale from the M-Pesa `pending_payments` queue,
/// and deliberately so. A till in a Kenyan shop loses signal constantly, and
/// an unreachable KRA must never stop the shop taking money — so a sale is
/// recorded locally first, marked pending, and uploaded when a connection
/// exists. Inventing a second, differently-shaped reconciliation for the same
/// problem is how offline sales end up unreconciled.
class EtimsService {
  EtimsService();

  /// Only one BACKGROUND flush at a time: the sell flow, the dashboard and tax
  /// settings can all call `flushPending` at once, and two runs must not read
  /// the same pending rows before either resolves them — otherwise the same
  /// sale could be issued to KRA twice.
  static Future<void>? _flushInProgress;

  /// The sales an inline attempt is issuing right now.
  ///
  /// The background flush skips them. The inline attempt is already talking to
  /// KRA about that sale, and the backend's idempotency key would resolve a
  /// double upload — but a race that can be avoided is better avoided.
  static final Set<int> _inlineInFlight = <int>{};

  static Future<T> _serialiseFlush<T>(Future<T> Function() body) async {
    final previous = _flushInProgress;
    if (previous != null) await previous;
    final current = body();
    _flushInProgress = current;
    return current;
  }

  DatabaseHelper get _db => DatabaseHelper.instance;

  /// KRA receives one payment mode. For a split sale the largest tender is
  /// the stable summary, while the local sale-payments rows retain every part.
  Future<String> _paymentMethodForEtims(Sale sale) async {
    if (sale.id == null || sale.paymentMethod != 'split') {
      return sale.paymentMethod;
    }
    final payments = await _db.getSalePayments(sale.id!);
    if (payments.isEmpty) return sale.paymentMethod;
    final largest = payments.reduce(
      (a, b) => a.amountMinor >= b.amountMinor ? a : b,
    );
    return largest.method;
  }

  /// Whether a sale recorded now should be queued for KRA.
  ///
  /// Tax reporting is deliberately not activated in this release. The old
  /// local preference is still read nowhere in the decision, so an upgraded
  /// till cannot keep retrying a KRA queue that the backend has disabled.
  Future<bool> isEnabledForSales() async {
    final prefs = await SharedPreferences.getInstance();
    if (!taxReportingActivated) {
      if (prefs.getBool(etimsEnabledPrefKey) == true) {
        await prefs.setBool(etimsEnabledPrefKey, false);
      }
      return false;
    }
    return prefs.getBool(etimsEnabledPrefKey) ?? false;
  }

  static const etimsEnabledPrefKey = 'etims_enabled_local';

  /// Build-time activation stays off until Risiti merchant onboarding and KRA
  /// approval are complete. This is intentionally not user-editable.
  static const taxReportingActivated = false;

  /// Whether the shop has completed the KRA configuration this shop needs.
  ///
  /// A TIN and a device identifier are the two things a receipt cannot be
  /// issued without. Absence is reported rather than guessed at, because a
  /// receipt issued against the wrong TIN is worse than one not issued.
  Future<bool> isConfigured() async {
    final tin = (await _db.getSetting(DatabaseHelper.settingTin))?.trim();
    final device =
        (await _db.getSetting(DatabaseHelper.settingEtimsDeviceId))?.trim();
    return (tin?.isNotEmpty ?? false) && (device?.isNotEmpty ?? false);
  }

  /// The hardest deadline the inline post-sale attempt is allowed: the till
  /// must not hold a customer at the counter while KRA is slow. Dio's own
  /// timeouts (10s connect, 20s receive) can each elapse, so the cap is
  /// shorter than either and the caller prints "eTIMS pending" when it fires.
  static const Duration kInlineIssueCap = Duration(seconds: 5);

  /// Queues every pending sale, oldest first, and returns how many KRA
  /// accepted.
  ///
  /// Bounded per call: a till that has been offline for a week can have
  /// thousands of receipts, and a single unbounded request would time out and
  /// achieve nothing. The caller runs this again on the next reconnect.
  Future<EtimsFlushResult> flushPending({int limit = 100}) async =>
      _serialiseFlush(() => _flushPendingInner(limit: limit));

  /// Issues the receipt for one *specific* sale, inline, with a hard cap.
  ///
  /// Used right after a sale so the customer's paper carries KRA's number when
  /// KRA answers in time. Any older stuck row cannot steal this sale's receipt,
  /// and when the cap fires the caller prints an "eTIMS pending" line and
  /// reprints the official copy once the background flush issues it.
  ///
  /// The inline attempt does NOT queue behind a background flush. It used to:
  /// the customer's receipt was issued behind whatever the background flush was
  /// working through, so a till with a backlog held the customer at the
  /// counter for as long as the backlog took — long past the deadline this
  /// method promises. The current sale is now issued on its own, and the
  /// background flush steps around any sale an inline attempt is dealing with.
  ///
  /// The cap covers the WHOLE attempt, not just the upload: a caller that
  /// promised the customer five seconds must not spend six of them on a slow
  /// database read and then start the upload anyway.
  Future<EtimsIssuedReceipt?> flushFor(int saleId,
      {Duration cap = kInlineIssueCap}) async {
    final DateTime deadline = DateTime.now().add(cap);
    if (!await isEnabledForSales()) return null;
    final entry = await _db.getPendingEtimsReceiptBySaleId(saleId);
    if (entry == null) return null;
    final sale = await _db.getSaleById(saleId);
    final row = await _db.getSaleRowById(saleId);
    if (sale == null || row == null || sale.items.isEmpty) return null;
    _inlineInFlight.add(saleId);
    try {
      final tin =
          (await _db.getSetting(DatabaseHelper.settingTin))?.trim() ?? '';
      final tillCode = await _db.getTillCode();
      final device =
          (await _db.getSetting(DatabaseHelper.settingEtimsDeviceId))?.trim() ??
              '';
      final prefs = await SharedPreferences.getInstance();
      final pricesIncludeVat = prefs.getBool('prices_include_vat') ?? true;
      final fallbackVatRate = await _db.getVatRatePercent();
      final payload = buildEtimsPayload(
        sale: sale,
        saleRow: row,
        db: _db,
        tillCode: tillCode,
        tin: tin,
        vatRatePercent:
            await _db.vatRateForSale(row, fallback: fallbackVatRate),
        pricesIncludeVat: pricesIncludeVat,
        paymentMethod: await _paymentMethodForEtims(sale),
        // Buyer identity is read from the sale snapshot, never the mutable
        // customer directory. This keeps retries and reprints deterministic.
        customer: null,
      );
      try {
        final issued = await _uploadWithCap(
          payload,
          device: device,
          cap: _remaining(deadline),
        );
        _lastIssued = issued;
        await _db.resolveEtimsReceipt(
          saleId: saleId,
          kraReceiptNumber: issued.receiptNumber,
          qrPayload: issued.verificationUrl,
        );
        return issued;
      } catch (error) {
        await _db.recordEtimsAttemptFailure(
          saleId: saleId,
          error: _describe(error),
        );
        if (_isPermanent(error)) {
          await _db.markEtimsRejected(saleId, _describe(error));
        }
        return null;
      }
    } finally {
      _inlineInFlight.remove(saleId);
    }
  }

  /// How much of the deadline is left, floored so a spent deadline still
  /// produces a real (if tiny) timeout rather than an immediate one.
  static Duration _remaining(DateTime deadline) {
    final Duration left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) return const Duration(milliseconds: 1);
    return left;
  }

  /// Puts every refused receipt back in the queue and tries again.
  ///
  /// A refusal is permanent for the receipt that caused it and not for the
  /// shop: the owner fixes the cause — a wrong TIN, a buyer PIN that does not
  /// verify, a KRA scheme that was briefly misbehaving — and then wants those
  /// invoices filed. This is the action that makes a refusal a thing to
  /// resolve rather than a thing to stare at.
  ///
  /// The queue is re-armed first and flushed second, so the receipts are
  /// uploaded in the order they were taken.
  Future<EtimsFlushResult> retryRejected() async {
    final int requeued = await _db.requeueRejectedEtimsReceipts();
    if (requeued == 0) {
      return const EtimsFlushResult(uploaded: 0, remaining: 0);
    }
    return flushPending();
  }

  /// How many receipts KRA has refused and nobody has put back.
  Future<int> countRejected() => _db.countRejectedEtimsReceipts();

  /// Like [_upload] but bounded by [cap] so the checkout path cannot hang.
  ///
  /// When the cap fires the receipt is left `pending` and the caller prints a
  /// placeholder line; the background flush completes it later. The underlying
  /// Dio request is cancelled immediately so it does not leak a socket for
  /// another 15s until Dio's own receive timeout fires.
  Future<EtimsIssuedReceipt> _uploadWithCap(
    Map<String, dynamic> payload, {
    required String device,
    required Duration cap,
  }) async {
    final cancelToken = CancelToken();
    try {
      return await _upload(payload, device: device, cancelToken: cancelToken)
          .timeout(cap);
    } on TimeoutException {
      cancelToken.cancel();
      rethrow;
    }
  }

  Future<EtimsFlushResult> _flushPendingInner({int limit = 100}) async {
    if (!await isEnabledForSales()) {
      return const EtimsFlushResult(uploaded: 0, remaining: 0, skipped: true);
    }
    final pending = await _db.getPendingEtimsReceipts(limit: limit);
    if (pending.isEmpty) {
      return const EtimsFlushResult(uploaded: 0, remaining: 0);
    }
    final tin = (await _db.getSetting(DatabaseHelper.settingTin))?.trim() ?? '';
    final tillCode = await _db.getTillCode();
    final device =
        (await _db.getSetting(DatabaseHelper.settingEtimsDeviceId))?.trim() ??
            '';
    final prefs = await SharedPreferences.getInstance();
    final pricesIncludeVat = prefs.getBool('prices_include_vat') ?? true;
    // Fetch the VAT rate once before the loop instead of per-entry, so legacy
    // sales (NULL vat_rate_percent) that fall through to getVatRatePercent()
    // do not each issue a separate database query.
    final fallbackVatRate = await _db.getVatRatePercent();

    var uploaded = 0;
    for (final entry in pending) {
      // An inline attempt is already talking to KRA about this sale. Stepping
      // around it keeps the two from racing for the same receipt.
      if (_inlineInFlight.contains(entry.saleId)) continue;
      final sale = await _db.getSaleById(entry.saleId);
      final row = await _db.getSaleRowById(entry.saleId);
      if (sale == null || row == null) {
        // The sale is not in this ledger any more. Leave the row alone: it is
        // the only remaining record that this receipt is outstanding, and
        // silently dropping it would hide the gap from the owner.
        continue;
      }
      if (sale.items.isEmpty) {
        // Nothing was sold, so KRA has nothing to accept. Mark it rejected
        // with a reason so the row stops being retried on every flush.
        await _db.markEtimsRejected(entry.saleId, 'No items on sale');
        continue;
      }
      final payload = buildEtimsPayload(
        sale: sale,
        saleRow: row,
        db: _db,
        tillCode: tillCode,
        tin: tin,
        vatRatePercent:
            await _db.vatRateForSale(row, fallback: fallbackVatRate),
        pricesIncludeVat: pricesIncludeVat,
        paymentMethod: await _paymentMethodForEtims(sale),
        customer: null,
      );
      try {
        final issued = await _upload(payload, device: device);
        _lastIssued = issued;
        await _db.resolveEtimsReceipt(
          saleId: entry.saleId,
          kraReceiptNumber: issued.receiptNumber,
          qrPayload: issued.verificationUrl,
        );
        uploaded++;
      } catch (error) {
        // The row survives with its attempt count incremented. A network blip
        // must not turn a committed sale into a permanently unissued invoice,
        // and a KRA refusal must stay visible rather than be retried forever.
        await _db.recordEtimsAttemptFailure(
          saleId: entry.saleId,
          error: _describe(error),
        );
        if (_isPermanent(error)) {
          await _db.markEtimsRejected(entry.saleId, _describe(error));
          // A permanent refusal will be refused again forever: move on to the
          // next receipt instead of letting one bad row block everything newer.
          continue;
        }
        // Transient (network) error: stop this pass and try again on the next
        // reconnect. Newer receipts are not held behind a temporary outage.
        break;
      }
    }

    final remaining = await _db.countPendingEtimsReceipts();
    return EtimsFlushResult(uploaded: uploaded, remaining: remaining);
  }

  Future<EtimsIssuedReceipt> _upload(
    Map<String, dynamic> payload, {
    required String device,
    CancelToken? cancelToken,
  }) async {
    final result = await BackendService.issueEtimsReceipt(
      payload,
      deviceId: device.isEmpty ? null : device,
      cancelToken: cancelToken,
    );
    // The QR payload is preferred over the plain verification URL: KRA's
    // verification page expects specific parameters, so encoding a URL built
    // locally is how a receipt ends up with a QR that scans to a 404.
    return EtimsIssuedReceipt(
      receiptNumber: result.kraReceiptNumber,
      verificationUrl: result.qrPayload ?? result.verificationUrl,
    );
  }

  EtimsIssuedReceipt? _lastIssued;

  /// The receipt issued by the most recent successful [flushPending] call.
  EtimsIssuedReceipt? get lastIssued => _lastIssued;

  /// One operator-facing message for a flush result.
  static String describeResult(EtimsFlushResult result) {
    if (result.skipped) return 'eTIMS is switched off.';
    if (result.uploaded == 0 && result.remaining == 0) {
      return 'All receipts have been issued to KRA.';
    }
    if (result.uploaded == 0) {
      return 'Could not reach KRA. ${result.remaining} receipt(s) still waiting; '
          'they will upload on the next connection.';
    }
    if (result.remaining == 0) {
      return '${result.uploaded} receipt(s) issued to KRA.';
    }
    return '${result.uploaded} receipt(s) issued. ${result.remaining} still waiting.';
  }

  /// Whether this error will be refused again, exactly as it was refused now.
  ///
  /// A 400, a 409 and a 422 are the server saying "this receipt is not
  /// acceptable" — a wrong TIN, a buyer PIN that does not verify, a line the
  /// KRA scheme cannot accept. The same payload gets the same answer, so
  /// retrying it forever achieves nothing but hides the problem.
  ///
  /// A 5xx, a timeout and an unreachable KRA are different: they say nothing
  /// about the receipt, and the same payload may well be accepted a minute
  /// later. Those stay transient and are retried on the next connection.
  ///
  /// A shop that is not linked to the backend is transient too. It is a
  /// temporary state of the shop, not a fault in the receipt, and the receipt
  /// must not be marked as refused for it.
  static bool _isPermanent(Object error) {
    if (error is EtimsRejectedException) return true;
    if (error is EtimsNotLinkedException) return false;
    if (error is DioException) {
      final c = error.response?.statusCode ?? 0;
      if (c == 400 || c == 409 || c == 422) return true;
    }
    return false;
  }

  static String _describe(Object error) {
    if (error is EtimsRejectedException) return error.reason;
    if (error is EtimsNotLinkedException) return error.reason;
    if (error is StateError) return error.message;
    return error.runtimeType.toString();
  }
}

/// What a flush achieved.
@immutable
class EtimsFlushResult {
  const EtimsFlushResult({
    required this.uploaded,
    required this.remaining,
    this.skipped = false,
  });

  final int uploaded;

  /// Still queued after this pass. Zero means the local ledger and KRA agree.
  final int remaining;

  /// eTIMS is off, so nothing was attempted.
  final bool skipped;
}

/// The KRA receipt number and the URL a customer scans to verify it.
@immutable
class EtimsIssuedReceipt {
  const EtimsIssuedReceipt({
    required this.receiptNumber,
    this.verificationUrl,
  });

  final String receiptNumber;
  final String? verificationUrl;
}

/// KRA has refused this receipt permanently.
///
/// Separate from a transport failure because the two need opposite responses:
/// a network error should be retried on the next reconnect, while a refusal
/// will be refused again forever and has to be put in front of the owner.
class EtimsRejectedException implements Exception {
  const EtimsRejectedException(this.reason, {this.fieldErrors});

  final String reason;
  final Map<String, String>? fieldErrors;

  @override
  String toString() => 'EtimsRejectedException: $reason';
}

/// The shop is not linked to the backend, so no receipt can be issued right
/// now.
///
/// Deliberately *transient*: the sale stays queued and the flush retries on the
/// next connection, instead of being marked rejected and hidden from the owner.
class EtimsNotLinkedException implements Exception {
  const EtimsNotLinkedException(this.reason);

  final String reason;

  @override
  String toString() => 'EtimsNotLinkedException: $reason';
}

/// VAT contained inside a VAT-inclusive amount.
///
/// Deliberately *not* reimplemented here: the figure quoted on a printed
/// receipt and the figure filed with KRA must be the same cent, so both call
/// [vatComponentOf] in utils/money.dart rather than each having their own copy
/// of the rounding rule.
