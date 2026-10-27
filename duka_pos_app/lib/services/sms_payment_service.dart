import 'package:telephony/telephony.dart';

/// Reads mobile-money SMS from the device and extracts payment details.
///
/// Requires the READ_SMS/RECEIVE_SMS permissions declared in the manifest and
/// granted by the owner at runtime.
class SmsPaymentService {
  SmsPaymentService._();
  static final SmsPaymentService instance = SmsPaymentService._();

  final Telephony _telephony = Telephony.instance;

  /// Returns the most recent mobile-money messages on the device.
  Future<List<SmsMessage>> recentMessages({int limit = 50}) async {
    final granted = await _telephony.requestPhoneAndSmsPermissions;
    if (granted != true) return const [];
    return _telephony.getInboxSms(
      columns: <SmsColumn>[SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      sortOrder: <OrderBy>[OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    ).then((list) => list.take(limit).toList());
  }
}
