import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/notification.dart';
import 'package:duka_pos/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;
  late DateTime now;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
    now = DateTime(2026, 10, 25, 23, 30);
  });

  tearDown(() => DatabaseHelper.resetForTests());

  test('deduplicates and keeps notification text counts-only', () async {
    final service = NotificationService(database: db, clock: () => now);
    const preference = NotificationPreference(
      staffId: 1,
      type: ShopNotificationType.lowStock,
    );
    const candidate = NotificationCandidate(
      type: ShopNotificationType.lowStock,
      dedupeKey: 'low-stock:2026-10-25',
      count: 5,
    );

    final first = await service.schedule(
      staffId: 1,
      role: 'admin',
      preference: preference,
      candidate: candidate,
    );
    final duplicate = await service.schedule(
      staffId: 1,
      role: 'admin',
      preference: preference,
      candidate: candidate,
    );

    expect(first, isNotNull);
    expect(first!.body, '5 low-stock items need attention');
    expect(first.body, isNot(contains('product-name')));
    expect(first.requiresPin, isTrue);
    expect(duplicate, isNull);
  });

  test('quiet hours cross midnight', () async {
    final service = NotificationService(database: db, clock: () => now);
    const preference = NotificationPreference(
      staffId: 1,
      type: ShopNotificationType.shiftOpen,
      quietStartMinutes: 22 * 60,
      quietEndMinutes: 6 * 60,
    );
    final result = await service.schedule(
      staffId: 1,
      role: 'cashier',
      preference: preference,
      candidate: const NotificationCandidate(
        type: ShopNotificationType.shiftOpen,
        dedupeKey: 'shift:1',
        count: 1,
      ),
    );
    expect(result, isNull);
  });

  test('cashiers only receive shift and incoming-payment alerts', () async {
    final service = NotificationService(database: db, clock: () => now);
    const preference = NotificationPreference(
      staffId: 1,
      type: ShopNotificationType.lowStock,
    );
    final result = await service.schedule(
      staffId: 1,
      role: 'cashier',
      preference: preference,
      candidate: const NotificationCandidate(
        type: ShopNotificationType.lowStock,
        dedupeKey: 'low-stock:1',
        count: 2,
      ),
    );
    expect(result, isNull);
  });

  test(
      'local checks are offline-safe and flag a missing off-phone backup',
      () async {
    final service = NotificationService(database: db, clock: () => now);
    final candidates = await service.localCandidates(now: now);
    expect(candidates, hasLength(1));
    expect(candidates.single.type, ShopNotificationType.backupOverdue);
    expect(
      await service.runLocalChecks(staffId: 1, role: 'admin', now: now),
      hasLength(1),
    );
  });
}
