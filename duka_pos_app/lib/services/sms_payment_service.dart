/// Android SMS payment support is intentionally disabled in this app build.
///
/// The project does not ship the `telephony` package anymore, so the app must
/// not import it or reference its public API. The service is kept as a tiny,
/// compatibility stub so any legacy callers still compile without crashing the
/// analyzer or the build.
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

/// A compatibility shim for the old SMS-payment feature.
///
/// This app deliberately does not read SMS messages for payments. The service
/// therefore returns an empty list unless the feature is reintroduced with a
/// supported Android API or a different dependency.
class SmsPaymentService {
  SmsPaymentService._();
  static final SmsPaymentService instance = SmsPaymentService._();

  Future<List<SmsMessage>> recentMessages({int limit = 50}) async {
    return const <SmsMessage>[];
  }
}
