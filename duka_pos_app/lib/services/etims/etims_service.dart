import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend_service.dart';
import '../../db/database_helper.dart';
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
}) {
  final receiptNumber = db.receiptNumberFor(saleRow);
  return {
    'receipt_number': receiptNumber,
    'issued_at': sale.createdAt,
    'payment_method': sale.paymentMethod,
    'payment_reference': sale.paymentReference,
    'total': sale.total.minorUnits,
    'vat_rate_percent': vatRatePercent,
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
              'vat_amount': vatComponentOf(item.total,
                      ratePercent: vatRatePercent,
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

  /// Only one flush at a time: the sell flow, the dashboard and tax settings
  /// can all call `flushPending` at once, and two runs must not read the same
  /// pending rows before either resolves them — otherwise the same sale could
  /// be issued to KRA twice.
  static Future<void>? _flushInProgress;

  static Future<T> _serialiseFlush<T>(Future<T> Function() body) async {
    final previous = _flushInProgress;
    if (previous != null) await previous;
    final current = body();
    _flushInProgress = current;
    return current;
  }

  DatabaseHelper get _db => DatabaseHelper.instance;

  /// Whether a sale recorded now should be queued for KRA.
  ///
  /// Requires the shop's own switch to be on. The backend is never asked at
  /// this point: it is unreachable by definition in the case that matters.
  Future<bool> isEnabledForSales() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(etimsEnabledPrefKey) ?? false;
  }

  static const etimsEnabledPrefKey = 'etims_enabled_local';

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
  Future<EtimsIssuedReceipt?> flushFor(int saleId,
      {Duration cap = kInlineIssueCap}) async {
    return _serialiseFlush(() async {
      if (!await isEnabledForSales()) return null;
      final entry = await _db.getPendingEtimsReceiptBySaleId(saleId);
      if (entry == null) return null;
      final sale = await _db.getSaleById(saleId);
      final row = await _db.getSaleRowById(saleId);
      if (sale == null || row == null || sale.items.isEmpty) return null;
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
      );
      try {
        final issued = await _uploadWithCap(payload, device: device, cap: cap);
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
        if (_isPermanent(error, attempts: entry.attempts)) {
          await _db.markEtimsRejected(saleId, _describe(error));
        }
        return null;
      }
    });
  }

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
        if (_isPermanent(error, attempts: entry.attempts)) {
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

  static bool _isPermanent(Object error, {int attempts = 0}) {
    if (error is EtimsRejectedException) return true;
    // A 400/409/422 arrives as a DioException, not an EtimsRejectedException,
    // and KRA will say the same thing on every retry — map it to permanent so
    // the row is marked rejected and the owner sees it instead of being retried
    // forever. But require a few attempts first so a deploy bug or a
    // transient KRA-side 4xx doesn't mass-reject the entire backlog. 5xx,
    // timeouts and offline stay transient.
    if (error is DioException) {
      final c = error.response?.statusCode ?? 0;
      if (c == 400 || c == 409 || c == 422) return attempts >= 2;
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
