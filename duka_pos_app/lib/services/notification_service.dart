import '../db/database_helper.dart';
import '../models/credit.dart';
import '../models/notification.dart';

/// A notification candidate deliberately carries a count, never business
/// names, customer details or money. This keeps lock-screen content private.
class NotificationCandidate {
  const NotificationCandidate({
    required this.type,
    required this.dedupeKey,
    required this.count,
    this.minimumInterval = const Duration(hours: 24),
  }) : assert(count >= 0);

  final ShopNotificationType type;
  final String dedupeKey;
  final int count;
  final Duration minimumInterval;
}

class ScheduledNotification {
  const ScheduledNotification({
    required this.type,
    required this.count,
    required this.title,
    required this.body,
    required this.destination,
    required this.requiresPin,
  });

  final ShopNotificationType type;
  final int count;
  final String title;
  final String body;
  final String destination;
  final bool requiresPin;
}

/// Local notification policy and durable deduplication.
///
/// Platform delivery is an adapter concern. The scheduler is usable in a
/// closed-loop background runner, foreground refresh, and tests without a
/// platform plugin or a network connection.
class NotificationService {
  NotificationService({DatabaseHelper? database, DateTime Function()? clock})
      : _database = database ?? DatabaseHelper.instance,
        _clock = clock ?? DateTime.now;

  final DatabaseHelper _database;
  final DateTime Function() _clock;

  static const Set<ShopNotificationType> _cashierTypes = {
    ShopNotificationType.shiftOpen,
    ShopNotificationType.incomingMpesa,
  };

  /// Computes the local, offline-safe attention conditions from the same
  /// database queries used by the dashboard and Sync Center. Counts are the
  /// only values that leave this method.
  Future<List<NotificationCandidate>> localCandidates({DateTime? now}) async {
    final at = now ?? _clock();
    final candidates = <NotificationCandidate>[];

    final lowStock = await _database.countLowStockProducts();
    if (lowStock > 0) {
      candidates.add(NotificationCandidate(
        type: ShopNotificationType.lowStock,
        dedupeKey: 'low-stock:$lowStock',
        count: lowStock,
      ));
    }

    final pendingEtims = await _database.getPendingEtimsReceipts(limit: 200);
    final oldEtims = pendingEtims
        .where((receipt) => at.difference(receipt.createdAt).inHours >= 4)
        .length;
    if (oldEtims > 0) {
      candidates.add(NotificationCandidate(
        type: ShopNotificationType.etimsAttention,
        dedupeKey: 'etims-attention:$oldEtims',
        count: oldEtims,
        minimumInterval: const Duration(hours: 4),
      ));
    }

    final unverified = await _database.countUnverifiedPayments();
    if (unverified > 0) {
      candidates.add(NotificationCandidate(
        type: ShopNotificationType.mpesaUnverified,
        dedupeKey: 'mpesa-unverified:$unverified',
        count: unverified,
      ));
    }

    final incoming = await _database.countIncomingPayments(status: 'unclaimed');
    if (incoming > 0) {
      candidates.add(NotificationCandidate(
        type: ShopNotificationType.incomingMpesa,
        dedupeKey: 'incoming-mpesa:$incoming',
        count: incoming,
      ));
    }

    final aging = await _database.creditAging(now: at);
    final overdue = aging[DebtAgeBucket.over60Days]?.customers ?? 0;
    if (overdue > 0) {
      candidates.add(NotificationCandidate(
        type: ShopNotificationType.overdueCredit,
        dedupeKey: 'overdue-credit:$overdue',
        count: overdue,
      ));
    }

    final expiring = await _database.getExpiringProducts(days: 7);
    if (expiring.isNotEmpty) {
      candidates.add(NotificationCandidate(
        type: ShopNotificationType.stockExpiring,
        dedupeKey: 'stock-expiring:${expiring.length}',
        count: expiring.length,
      ));
    }

    final openShift = await _database.getAnyOpenShift();
    if (openShift != null) {
      candidates.add(NotificationCandidate(
        type: ShopNotificationType.shiftOpen,
        dedupeKey: 'shift-open:${openShift.id}',
        count: 1,
      ));
    }

    final backups = await _database.getBackupLog(limit: 50);
    Map<String, dynamic>? latestPortable;
    for (final row in backups) {
      if (row['kind'] == 'cloud_full_portable' && row['status'] == 'uploaded') {
        latestPortable = row;
        break;
      }
    }
    final portableAt = latestPortable == null
        ? null
        : DateTime.tryParse(latestPortable['created_at'] as String? ?? '');
    if (portableAt == null || at.difference(portableAt).inDays >= 7) {
      candidates.add(const NotificationCandidate(
        type: ShopNotificationType.backupOverdue,
        dedupeKey: 'backup-overdue',
        count: 1,
      ));
    }
    return candidates;
  }

  /// Runs the local checks for one signed-in person. Missing preferences use
  /// the safe default (enabled, no quiet hours), while persisted preferences
  /// override only that person in that shop.
  Future<List<ScheduledNotification>> runLocalChecks({
    required int staffId,
    required String role,
    DateTime? now,
  }) async {
    final saved = await _database.getNotificationPreferences(staffId);
    final preferences = <ShopNotificationType, NotificationPreference>{
      for (final preference in saved) preference.type: preference,
    };
    final scheduled = <ScheduledNotification>[];
    for (final candidate in await localCandidates(now: now)) {
      final preference = preferences[candidate.type] ??
          NotificationPreference(staffId: staffId, type: candidate.type);
      final result = await schedule(
        staffId: staffId,
        role: role,
        preference: preference,
        candidate: candidate,
      );
      if (result != null) scheduled.add(result);
    }
    return scheduled;
  }

  Future<ScheduledNotification?> schedule({
    required int staffId,
    required String role,
    required NotificationPreference preference,
    required NotificationCandidate candidate,
  }) async {
    await _database.pruneNotifications();
    if (!preference.enabled ||
        (role == 'cashier' && !_cashierTypes.contains(candidate.type))) {
      return null;
    }
    final now = _clock();
    if (_isQuiet(now, preference)) return null;
    final recorded = await _database.recordNotificationIfDue(
      staffId: staffId,
      type: candidate.type,
      dedupeKey: candidate.dedupeKey,
      count: candidate.count,
      firedAt: now,
      minimumInterval: candidate.minimumInterval,
    );
    if (!recorded) {
      return null;
    }
    return ScheduledNotification(
      type: candidate.type,
      count: candidate.count,
      title: _title(candidate.type),
      body: _body(candidate.type, candidate.count),
      destination: _destination(candidate.type),
      requiresPin: true,
    );
  }

  String _title(ShopNotificationType type) => switch (type) {
        ShopNotificationType.lowStock => 'Low stock',
        ShopNotificationType.etimsAttention => 'Tax receipts',
        ShopNotificationType.backupOverdue => 'Backup reminder',
        ShopNotificationType.mpesaUnverified => 'Payment matching',
        ShopNotificationType.overdueCredit => 'Credit follow-up',
        ShopNotificationType.stockExpiring => 'Expiry reminder',
        ShopNotificationType.shiftOpen => 'Open shift',
        ShopNotificationType.incomingMpesa => 'Incoming payment',
      };

  String _body(ShopNotificationType type, int count) {
    final noun = switch (type) {
      ShopNotificationType.lowStock => 'low-stock item${count == 1 ? '' : 's'}',
      ShopNotificationType.etimsAttention =>
        'tax receipt${count == 1 ? '' : 's'}',
      ShopNotificationType.backupOverdue => 'backup reminder',
      ShopNotificationType.mpesaUnverified =>
        'payment${count == 1 ? '' : 's'} to match',
      ShopNotificationType.overdueCredit =>
        'overdue account${count == 1 ? '' : 's'}',
      ShopNotificationType.stockExpiring =>
        'expiring item${count == 1 ? '' : 's'}',
      ShopNotificationType.shiftOpen => 'open shift',
      ShopNotificationType.incomingMpesa =>
        'incoming payment${count == 1 ? '' : 's'}',
    };
    return '$count $noun need attention';
  }

  bool _isQuiet(DateTime now, NotificationPreference preference) {
    final start = preference.quietStartMinutes;
    final end = preference.quietEndMinutes;
    if (start == null || end == null || start == end) return false;
    final minute = now.hour * 60 + now.minute;
    return start < end
        ? minute >= start && minute < end
        : minute >= start || minute < end;
  }

  String _destination(ShopNotificationType type) => switch (type) {
        ShopNotificationType.lowStock => '/inventory',
        ShopNotificationType.etimsAttention => '/settings/sync-center',
        ShopNotificationType.backupOverdue => '/settings',
        ShopNotificationType.mpesaUnverified => '/settings/incoming-payments',
        ShopNotificationType.overdueCredit => '/dashboard/customers',
        ShopNotificationType.stockExpiring => '/inventory',
        ShopNotificationType.shiftOpen => '/analytics/shift',
        ShopNotificationType.incomingMpesa => '/settings/incoming-payments',
      };
}
