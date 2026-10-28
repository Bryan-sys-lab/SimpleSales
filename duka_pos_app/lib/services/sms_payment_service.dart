/// This app no longer uses the Android telephony package.
///
/// The package was removed from `pubspec.yaml` because the SMS payment flow was
/// disabled and the dependency caused Gradle configuration failures on Android.
/// We keep a tiny compatibility shim here so any stale callers still compile
/// cleanly without importing `package:telephony/telephony.dart`.
class SmsMessage {
  const SmsMessage({
    this.address = '',
    this.body = '',
    this.date = 0,
  });

  final String address;
  final String body;
  final int date;
}

enum SmsColumn { address, body, date }

enum Sort { asc, desc }

class OrderBy {
  const OrderBy(this.column, {required this.sort});

  final SmsColumn column;
  final Sort sort;
}

/// Legacy SMS payment entry point.
///
/// The feature is intentionally disabled in this build, so this service returns
/// no messages. If SMS payment support is reinstated later, this file should be
/// replaced with a real implementation backed by a supported dependency.
class SmsPaymentService {
  SmsPaymentService._();
  static final SmsPaymentService instance = SmsPaymentService._();

  Future<List<SmsMessage>> recentMessages({int limit = 50}) async {
    return const <SmsMessage>[];
  }
}
