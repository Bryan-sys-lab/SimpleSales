/// The bounded set of operational alerts a shop can receive.
enum ShopNotificationType {
  lowStock,
  etimsAttention,
  backupOverdue,
  mpesaUnverified,
  overdueCredit,
  stockExpiring,
  shiftOpen,
  incomingMpesa,
}

extension ShopNotificationTypeWire on ShopNotificationType {
  String get wire => switch (this) {
        ShopNotificationType.lowStock => 'low_stock',
        ShopNotificationType.etimsAttention => 'etims_attention',
        ShopNotificationType.backupOverdue => 'backup_overdue',
        ShopNotificationType.mpesaUnverified => 'mpesa_unverified',
        ShopNotificationType.overdueCredit => 'overdue_credit',
        ShopNotificationType.stockExpiring => 'stock_expiring',
        ShopNotificationType.shiftOpen => 'shift_open',
        ShopNotificationType.incomingMpesa => 'incoming_mpesa',
      };

  static ShopNotificationType? parse(String? value) {
    for (final type in ShopNotificationType.values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

class NotificationPreference {
  const NotificationPreference({
    required this.staffId,
    required this.type,
    this.enabled = true,
    this.quietStartMinutes,
    this.quietEndMinutes,
  });

  final int staffId;
  final ShopNotificationType type;
  final bool enabled;
  final int? quietStartMinutes;
  final int? quietEndMinutes;
}

class NotificationRecord {
  const NotificationRecord({
    required this.id,
    required this.staffId,
    required this.type,
    required this.dedupeKey,
    required this.count,
    required this.firedAt,
    this.openedAt,
  });

  final int id;
  final int staffId;
  final ShopNotificationType type;
  final String dedupeKey;
  final int count;
  final DateTime firedAt;
  final DateTime? openedAt;
}
