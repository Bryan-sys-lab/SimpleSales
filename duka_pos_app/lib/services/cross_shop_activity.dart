import '../profile/shop_profile.dart';
import '../utils/money.dart';

/// A normalized owner activity row. The source identifiers are kept separate
/// from display text so a row can later open its originating shop safely.
class CrossShopActivity {
  const CrossShopActivity({
    required this.eventId,
    required this.sourceId,
    required this.sourceType,
    required this.tenantId,
    required this.shopName,
    required this.businessProfile,
    required this.createdAt,
    required this.type,
    required this.status,
    required this.amount,
    required this.workspaceKey,
    this.detail,
    this.profit = Money.zero,
    this.paymentMethod,
    this.actor,
    this.isRemote = false,
    this.isStale = false,
  });

  final String eventId;
  final String sourceId;
  final String sourceType;
  final String tenantId;
  final String shopName;
  final ShopProfile businessProfile;
  final DateTime createdAt;
  final String type;
  final String status;
  final Money amount;
  final String workspaceKey;
  final String? detail;
  final Money profit;
  final String? paymentMethod;
  final String? actor;
  final bool isRemote;
  final bool isStale;

  factory CrossShopActivity.fromJson(Map<String, dynamic> json) {
    int minor(Object? value) => switch (value) {
          final int v => v,
          final double v => v.round(),
          final String v => int.tryParse(v) ?? 0,
          _ => 0,
        };
    return CrossShopActivity(
      eventId: json['eventId'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      sourceType: json['sourceType'] as String? ?? 'activity',
      tenantId: json['tenantId'] as String? ?? '',
      shopName: json['shopName'] as String? ?? '',
      businessProfile: ShopProfile.fromWire(json['businessProfile'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      type: json['type'] as String? ?? 'activity',
      status: json['status'] as String? ?? 'unknown',
      amount: Money.fromMinor(minor(json['amountMinor'])),
      workspaceKey:
          json['workspaceKey'] as String? ?? json['tenantId'] as String? ?? '',
      detail: json['detail'] as String?,
      profit: Money.fromMinor(minor(json['profitMinor'])),
      paymentMethod: json['paymentMethod'] as String?,
      actor: json['actor'] as String?,
      isRemote: json['isRemote'] == true,
      isStale: json['isStale'] == true,
    );
  }
}

class CrossShopActivityPage {
  const CrossShopActivityPage({required this.events, this.nextCursor});

  final List<CrossShopActivity> events;
  final String? nextCursor;

  factory CrossShopActivityPage.fromJson(Map<String, dynamic> json) {
    final rows = (json['events'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
            (row) => CrossShopActivity.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    return CrossShopActivityPage(
      events: rows,
      nextCursor: json['nextCursor'] as String?,
    );
  }

  /// Stable cursor for the next page, based on the final normalized row.
  static String cursorFor(CrossShopActivity event) =>
      '${event.createdAt.toUtc().toIso8601String()}|${event.eventId}';
}
