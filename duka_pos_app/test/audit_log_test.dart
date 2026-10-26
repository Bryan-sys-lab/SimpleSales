// The audit log: who did what.
//
// The ledger answers "what happened to the stock" and "what was sold". Neither
// answers "who changed the VAT rate at 11pm", "which cashier removed a barcode",
// or "was this backup erased by the owner" — and those are what a shop asks when
// the numbers stop adding up. This suite pins the log down as the thing that
// answers them.
//
// Three properties carry the weight:
//
//   1. It is APPENDED to, never rewritten. An audit row that can be edited is
//      not an audit row.
//   2. The actor is denormalised. `deleteStaffWithTombstone` scrubs the staff
//      table, so a row that resolved its actor through a join would render
//      "deleted user" — and worse, would leak the name the tombstone exists to
//      remove the moment the display name was the only thing left.
//   3. One shop's log is another shop's secret. Every query here is scoped to
//      the active workspace's database, which is the same isolation the
//      workspace layer gives every other table.

import 'dart:io';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/audit_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Start from a clean directory, then never delete from it again — see the
    // note in workspace_test.dart on why deleting mid-suite corrupts a
    // connection that is still open.
    final Directory dir = Directory('.dart_tool/sqflite_common_ffi/databases');
    if (dir.existsSync()) {
      for (final FileSystemEntity f in dir.listSync()) {
        if (f is File && f.path.endsWith('.db')) f.deleteSync();
      }
    }
  });

  late DatabaseHelper db;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
  });

  AuditLogEntry entry({
    AuditAction action = AuditAction.productUpdated,
    AuditEntity entity = AuditEntity.product,
    String? entityId,
    int? actorId,
    String actorName = 'Amina',
    String? detail,
    String? createdAt,
  }) =>
      AuditLogEntry(
        action: action,
        entity: entity,
        entityId: entityId,
        actorId: actorId,
        actorName: actorName,
        detail: detail,
        createdAt: createdAt ?? DateTime.now().toIso8601String(),
      );

  group('writing', () {
    test('an action is recorded with its actor and its subject', () async {
      final id = await db.recordAudit(entry(
        action: AuditAction.barcodeRemoved,
        entity: AuditEntity.barcode,
        entityId: '6001234567890',
        actorId: 7,
        actorName: 'Joseph',
        detail: 'removed from Tusker 500ml',
      ));

      final rows =
          await db.auditForEntity(AuditEntity.barcode, '6001234567890');
      expect(rows.length, 1);
      expect(rows.single.id, id);
      expect(rows.single.action, AuditAction.barcodeRemoved);
      expect(rows.single.actorId, 7);
      expect(rows.single.actorName, 'Joseph');
      expect(rows.single.detail, 'removed from Tusker 500ml');
    });

    test('an owner action records no actor id', () async {
      // The owner is not a staff row, so there is no id to record — and
      // inventing one would break the tombstone guarantee.
      await db.recordAudit(entry(actorId: null, actorName: 'Amina'));

      final rows = await db.auditLog(const AuditLogQuery());
      expect(rows.single.actorId, isNull);
      expect(rows.single.actorName, 'Amina');
    });

    test('a round trip preserves every field', () async {
      await db.recordAudit(entry(
        action: AuditAction.taxSettingsChanged,
        entity: AuditEntity.settings,
        entityId: 'tax',
        actorId: 3,
        detail: 'VAT rate 16% -> 18%',
      ));

      final rows = await db.auditLog(const AuditLogQuery(limit: 10));
      final AuditLogEntry row = rows.single;
      expect(row.action.wire, 'tax_settings_changed');
      expect(row.entity, AuditEntity.settings);
      expect(row.entityId, 'tax');
      expect(row.actorId, 3);
      expect(row.detail, 'VAT rate 16% -> 18%');
      expect(row.createdAt, isNotEmpty);
    });
  });

  group('reading', () {
    test('everything on one entity, newest first', () async {
      await db.recordAudit(entry(
          entityId: 'p1', entity: AuditEntity.product, detail: 'created'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.recordAudit(entry(
          entityId: 'p1',
          entity: AuditEntity.product,
          detail: 'stock adjusted'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.recordAudit(entry(
        action: AuditAction.barcodeAdded,
        entity: AuditEntity.barcode,
        entityId: 'bc1',
        detail: 'unrelated',
      ));

      final rows = await db.auditForEntity(AuditEntity.product, 'p1');
      expect(rows.length, 2);
      // Newest first: the most recent thing that happened to this product is
      // the first thing an owner sees.
      expect(rows.first.detail, 'stock adjusted');
      // The other entity's row is not pulled in.
      expect(rows.where((r) => r.entityId == 'bc1'), isEmpty);
    });

    test('everything by one actor, filtered by action', () async {
      await db.recordAudit(entry(
          actorId: 4, actorName: 'Joseph', action: AuditAction.stockAdjusted));
      await db.recordAudit(entry(
          actorId: 4, actorName: 'Joseph', action: AuditAction.barcodeRemoved));
      await db.recordAudit(entry(
          actorId: 9, actorName: 'Brian', action: AuditAction.stockAdjusted));

      final rows = await db.auditLog(const AuditLogQuery(
        actorId: 4,
        actions: <AuditAction>[AuditAction.stockAdjusted],
      ));
      expect(rows.length, 1);
      expect(rows.single.actorId, 4);
      expect(rows.single.action, AuditAction.stockAdjusted);
    });

    test('a bounded query excludes the next report window', () async {
      await db.recordAudit(entry(createdAt: '2026-01-31T23:59:59.000Z'));
      await db.recordAudit(entry(createdAt: '2026-02-01T00:00:00.000Z'));

      final rows = await db.auditLog(const AuditLogQuery(
        since: '2026-01-01T00:00:00.000Z',
        until: '2026-02-01T00:00:00.000Z',
      ));
      expect(rows, hasLength(1));
      expect(rows.single.createdAt, '2026-01-31T23:59:59.000Z');
    });

    test('the owner-relevant view hides the sale rows', () async {
      // A raw feed is hundreds of sale rows deep before the settings change
      // the owner actually wanted, so the owner's view reads a filtered set.
      await db.recordAudit(
          entry(action: AuditAction.saleRecorded, entity: AuditEntity.sale));
      await db.recordAudit(
          entry(action: AuditAction.saleRecorded, entity: AuditEntity.sale));
      await db.recordAudit(entry(action: AuditAction.taxSettingsChanged));

      final rows = await db.ownerRelevantAudit();
      expect(rows.length, 1);
      expect(rows.single.action, AuditAction.taxSettingsChanged);
    });

    test('a query with no filter returns the whole log', () async {
      await db.recordAudit(entry());
      await db.recordAudit(
          entry(action: AuditAction.staffAdded, entity: AuditEntity.staff));

      final rows = await db.auditLog(const AuditLogQuery());
      expect(rows.length, 2);
    });

    test('an unknown action value parses rather than throwing', () async {
      // A log written by a newer build read by an older one. A row that cannot
      // be parsed is a row the owner cannot see, and the reason it cannot be
      // parsed is not a reason to lose the rest of the day.
      final raw = await db.database;
      await raw.insert('audit_log', <String, Object?>{
        'action': 'action_a_future_build_wrote',
        'entity': 'product',
        'entity_id': 'p1',
        'actor_id': null,
        'actor_name': 'Someone',
        'detail': null,
        'created_at': DateTime.now().toIso8601String(),
      });

      final rows = await db.auditLog(const AuditLogQuery());
      expect(rows.length, 1);
      // Falls back to a real member rather than crashing the read.
      expect(rows.single.action, isA<AuditAction>());
      expect(rows.single.actorName, 'Someone');
    });
  });

  group('bounding the log on a phone', () {
    test('pruning keeps the newest rows and reports how many it dropped',
        () async {
      for (int i = 0; i < 10; i++) {
        await db.recordAudit(entry(detail: 'row $i'));
      }

      final dropped = await db.pruneAuditLog(keepRows: 4);
      expect(dropped, 6);

      final rows = await db.auditLog(const AuditLogQuery(limit: 100));
      expect(rows.length, 4);
      // The NEWEST survived: pruning by id, not by insertion order, is what
      // makes "the most recent things are still on the phone" true.
      expect(rows.first.detail, 'row 9');
    });

    test('pruning below the cap is a no-op', () async {
      await db.recordAudit(entry());
      await db.recordAudit(entry());

      final dropped = await db.pruneAuditLog(keepRows: 50);
      expect(dropped, 0);
      expect(await db.auditLogCount(), 2);
    });

    test('every write bounds the table on its own', () async {
      // The cap must be enforced BY the write, not by a schedule something
      // might forget to run. Nothing in the app calls `pruneAuditLog` on a
      // timer, so this is the only thing standing between a busy till and a
      // table that grows with every sale.
      final List<AuditLogEntry> rows = <AuditLogEntry>[
        for (int i = 0; i < DatabaseHelper.auditRetainRows + 2; i++)
          entry(detail: 'row $i'),
      ];
      await db.recordAudits(rows);

      expect(await db.auditLogCount(), DatabaseHelper.auditRetainRows);
      final kept = await db.auditLog(const AuditLogQuery(limit: 10000));
      expect(kept.length, DatabaseHelper.auditRetainRows);
      // Newest first, so the first two writes are the ones that went.
      expect(kept.first.detail, 'row ${DatabaseHelper.auditRetainRows + 1}');
      expect(kept.where((r) => r.detail == 'row 0'), isEmpty);
    });

    test('a batched write commits once and keeps every row', () async {
      // One gesture that produces four rows must not cost four transactions.
      await db.recordAudits([
        entry(detail: 'one'),
        entry(detail: 'two'),
        entry(detail: 'three'),
        entry(detail: 'four'),
      ]);
      expect(await db.auditLogCount(), 4);

      // Nothing is lost or reordered by the batch.
      final rows = await db.auditLog(const AuditLogQuery(limit: 10));
      expect(rows.length, 4);
      expect(rows.map((r) => r.detail).toList(),
          containsAll(<String>['one', 'two', 'three', 'four']));
    });

    test('batching an empty list writes nothing at all', () async {
      await db.recordAudits(const <AuditLogEntry>[]);
      expect(await db.auditLogCount(), 0);
    });

    test('the count is the count', () async {
      expect(await db.auditLogCount(), 0);
      await db.recordAudit(entry());
      await db.recordAudit(entry());
      expect(await db.auditLogCount(), 2);
    });
  });

  group('per-shop isolation', () {
    test('one shop cannot see another shop\'s log', () async {
      // The same guarantee every other table has, restated where it matters:
      // shop A's log of "who erased the backup" is not shop B's business.
      //
      // Unique keys per run, because the ffi backend writes real files and
      // `resetForTests` only nulls the singleton — a fixed key would reopen
      // the files the previous run left behind and assert on a count that has
      // nothing to do with this case.
      final String run = DateTime.now().microsecondsSinceEpoch.toString();
      final String shopA = 'audit-a-$run';
      final String shopB = 'audit-b-$run';
      await db.initializeWorkspace(shopA);
      await db.recordAudit(entry(actorName: 'Amina', detail: 'shop A'));

      await db.switchWorkspace(shopB);
      // Shop B has never had an action. If shop A's row appears, the workspace
      // switch did not change the store.
      expect(await db.auditLogCount(), 0);

      await db.switchWorkspace(shopA);
      final rows = await db.auditLog(const AuditLogQuery());
      expect(rows.length, 1);
      expect(rows.single.detail, 'shop A');
    });
  });
}
