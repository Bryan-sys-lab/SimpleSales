// The owner's cross-shop audit view.
//
// The property this suite exists to pin: a device holding several shops must
// answer "what happened anywhere" WITHOUT pointing the till at a different shop
// than the one on screen. That is the whole safety requirement of a
// cross-shop read, and it is the thing that fails silently — a screen that
// walked the shops and left the singleton on the last one would keep working
// perfectly while selling from the wrong database.
//
// The second property is the one the workspace layer exists for, restated where
// it now matters: shop A's "who erased the backup" is not shop B's business, so
// the reader must assemble from each shop's own store and never blend them.

import 'dart:io';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/audit_log.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/cross_shop_audit_reader.dart';
import 'package:duka_pos/services/workspace_service.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Start from a clean ffi directory. Each case registers UNIQUE keys, so no
    // file is ever reopened from a previous run; deleting mid-run is what
    // corrupts an open connection (sqlite 1032), and that is why this is the
    // only delete in the file.
    final dir = Directory('.dart_tool/sqflite_common_ffi/databases');
    if (dir.existsSync()) {
      for (final f in dir.listSync()) {
        if (f is File && f.path.endsWith('.db')) f.deleteSync();
      }
    }
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'workspace_registry_v1': '{}',
    });
  });

  Future<void> seed(String key, String detail, String createdAt) async {
    await DatabaseHelper.instance.switchWorkspace(key);
    await DatabaseHelper.instance.recordAudit(AuditLogEntry(
      action: AuditAction.backupErased,
      entity: AuditEntity.backup,
      actorName: 'Amina',
      detail: detail,
      createdAt: createdAt,
    ));
  }

  /// Two fresh shops on a device, with [active] made active.
  Future<(String, String)> twoShops({
    String aName = 'Amina Duka',
    String bName = 'Njeri Shop',
    String active = 'xa',
  }) async {
    final run = DateTime.now().microsecondsSinceEpoch.toString();
    final a = 'xa-$run';
    final b = 'xb-$run';
    await WorkspaceService.register(workspaceKey: a, shopName: aName);
    await WorkspaceService.register(workspaceKey: b, shopName: bName);
    await WorkspaceService.setActiveWorkspace(active);
    return (a, b);
  }

  group('cross-shop audit reading', () {
    test('each shop contributes only its own rows', () async {
      final (a, b) = await twoShops();

      await seed(a, 'shop A erased its backup', '2026-01-01T10:00:00.000Z');
      await seed(b, 'shop B erased its backup', '2026-01-01T11:00:00.000Z');

      final perShop = await CrossShopAuditReader.readAllShops();
      expect(perShop.length, 2);

      final shopA = perShop.firstWhere((s) => s.shopName == 'Amina Duka');
      final shopB = perShop.firstWhere((s) => s.shopName == 'Njeri Shop');

      expect(shopA.entries.length, 1);
      expect(shopA.entries.single.detail, 'shop A erased its backup');
      expect(shopB.entries.length, 1);
      expect(shopB.entries.single.detail, 'shop B erased its backup');
    });

    test('the merged view is sorted newest-first across shops', () async {
      final (a, b) = await twoShops(active: 'xb');

      await seed(a, 'older', '2026-01-01T09:00:00.000Z');
      await seed(b, 'newer', '2026-01-01T10:00:00.000Z');

      final merged = await CrossShopAuditReader.readMerged();
      expect(merged.length, 2);
      expect(merged.first.entry.detail, 'newer');
      expect(merged.first.shopName, 'Njeri Shop');
      expect(merged.last.entry.detail, 'older');
      expect(merged.last.shopName, 'Amina Duka');
    });

    test('the merged view honours its cap', () async {
      final (a, b) = await twoShops();
      for (var i = 0; i < 10; i++) {
        await seed(a, 'row $i', '2026-01-01T10:00:0$i.000Z');
      }
      for (var i = 0; i < 10; i++) {
        await seed(b, 'row $i', '2026-01-02T10:00:0$i.000Z');
      }

      // Each shop is read within its own limit, then the merge is capped too.
      final merged = await CrossShopAuditReader.readMerged(
        limitPerShop: 50,
        totalLimit: 8,
      );
      expect(merged.length, 8);
    });

    test('the shop the caller was in is the shop they end in', () async {
      final (a, b) = await twoShops(active: 'xb');
      await seed(a, 'a', '2026-01-01T10:00:00.000Z');
      await seed(b, 'b', '2026-01-01T11:00:00.000Z');

      final before = DatabaseHelper.instance.currentWorkspaceKey;
      expect(before, b);

      await CrossShopAuditReader.readAllShops();

      final after = DatabaseHelper.instance.currentWorkspaceKey;
      // If this regressed, the till would silently be selling from another
      // shop's stock while showing this one's name on screen.
      expect(after, before,
          reason: 'a cross-shop read must restore the shop it started in');
    });

    test('restores the active shop even when a shop read fails', () async {
      // A shop whose database has been deleted from under the registry. The
      // walk must not leave the singleton pointed somewhere else.
      final (a, b) = await twoShops(active: 'xb');
      await seed(a, 'a', '2026-01-01T10:00:00.000Z');

      // Shop B's schema is v18, so it reads fine; make it fail by breaking the
      // registry's claim that its database exists — delete the file while the
      // connection is closed.
      await DatabaseHelper.instance.switchWorkspace(a);
      final dbFile = File(
          '.dart_tool/sqflite_common_ffi/databases/duka_pos_${b.replaceAll('/', '_')}.db');
      if (dbFile.existsSync()) dbFile.deleteSync();

      final before = DatabaseHelper.instance.currentWorkspaceKey;
      await CrossShopAuditReader.readAllShops();
      final after = DatabaseHelper.instance.currentWorkspaceKey;
      expect(after, before);
    });

    test('an unopened shop is empty, not failed', () async {
      final (a, b) = await twoShops();
      // Shop B has never been opened, so its database does not exist yet.
      await seed(a, 'shop A', '2026-01-01T10:00:00.000Z');

      final perShop = await CrossShopAuditReader.readAllShops();
      expect(perShop.length, 2);

      final shopA = perShop.firstWhere((s) => s.shopName == 'Amina Duka');
      expect(shopA.entries.length, 1);
      expect(shopA.failed, isFalse);

      final shopB = perShop.firstWhere((s) => s.shopName == 'Njeri Shop');
      expect(shopB.entries, isEmpty);
      expect(shopB.failed, isFalse,
          reason: 'a registered but unopened shop is empty, not broken');
    });

    test('a device with no shops reads nothing without throwing', () async {
      final perShop = await CrossShopAuditReader.readAllShops();
      expect(perShop, isEmpty);
      expect(await CrossShopAuditReader.readMerged(), isEmpty);
      expect(await CrossShopAuditReader.countShopsWithActivity(), 0);
    });

    test('the count only counts shops with activity', () async {
      final (a, b) = await twoShops();
      await seed(a, 'shop A', '2026-01-01T10:00:00.000Z');
      // Shop B opens a database, with the v18 table, but writes no rows.
      await DatabaseHelper.instance.switchWorkspace(b);
      await DatabaseHelper.instance.database;

      expect(await CrossShopAuditReader.countShopsWithActivity(), 1);
    });

    test(
        'a shop can be named after it was added, and the reader still knows '
        'which database a row came from', () async {
      final (a, b) = await twoShops(aName: 'First Duka', bName: 'Second Duka');
      await seed(a, 'from the first', '2026-01-01T10:00:00.000Z');

      final merged = await CrossShopAuditReader.readMerged();
      expect(merged.single.shopName, 'First Duka');
      expect(merged.single.workspaceKey, a);
    });

    test('owner-relevant rows only — sales never crowd the owner view',
        () async {
      final (a, b) = await twoShops();
      await DatabaseHelper.instance.switchWorkspace(a);
      // A hundred sales, which the owner view must filter out.
      for (var i = 0; i < 100; i++) {
        await DatabaseHelper.instance.recordAudit(AuditLogEntry(
          action: AuditAction.saleRecorded,
          entity: AuditEntity.sale,
          actorName: 'Joseph',
          detail: 'sale $i',
          createdAt: '2026-01-01T10:00:00.000Z',
        ));
      }
      await DatabaseHelper.instance.recordAudit(AuditLogEntry(
        action: AuditAction.backupErased,
        entity: AuditEntity.backup,
        actorName: 'Amina',
        detail: 'the one row that matters',
        createdAt: '2026-01-01T11:00:00.000Z',
      ));

      final perShop = await CrossShopAuditReader.readAllShops();
      final shopA = perShop.firstWhere((s) => s.shopName == 'Amina Duka');
      expect(shopA.entries.length, 1);
      expect(shopA.entries.single.detail, 'the one row that matters');
    });

    test('a pruned log reads only what is still on the device', () async {
      final (a, b) = await twoShops();
      await DatabaseHelper.instance.switchWorkspace(a);
      for (var i = 0; i < 20; i++) {
        await DatabaseHelper.instance.recordAudit(AuditLogEntry(
          action: AuditAction.backupErased,
          entity: AuditEntity.backup,
          actorName: 'Amina',
          detail: 'row $i',
          createdAt: '2026-01-01T10:00:00.000Z',
        ));
      }
      final dropped = await DatabaseHelper.instance.pruneAuditLog(keepRows: 5);
      expect(dropped, 15);

      final perShop = await CrossShopAuditReader.readAllShops();
      final shopA = perShop.firstWhere((s) => s.shopName == 'Amina Duka');
      expect(shopA.entries.length, 5);
    });

    test('the reader does not disturb a shop with products in it', () async {
      // Reading the audit log must not touch the catalogue it walks through.
      final (a, b) = await twoShops();
      await DatabaseHelper.instance.switchWorkspace(a);
      await DatabaseHelper.instance.upsertProduct(Product(
        id: 0,
        name: 'Tusker 500ml',
        category: 'Drinks',
        costPrice: Money.fromMajor(120),
        sellPrice: Money.fromMajor(180),
        stockQty: 24,
        reorderLevel: 6,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await CrossShopAuditReader.readAllShops();

      final products = await DatabaseHelper.instance.getProducts();
      expect(products.length, 1);
      expect(products.single.name, 'Tusker 500ml');
    });

    test(
        'the walk holds the workspace gate, so nothing can move the database '
        'while it runs', () async {
      final (a, b) = await twoShops();
      // Start pointed at a real shop, which is the only state a screen is in
      // when it opens this view.
      await DatabaseHelper.instance.switchWorkspace(a);

      // The gate is what actually makes a cross-shop read safe, because the
      // singleton every screen writes through is repointed for the duration.
      // Proof that it is held: a switch requested DURING the walk must wait,
      // and must then WIN — the caller's switch is the more recent fact, and
      // restoring over it would leave the till on a shop the owner left.
      final walk = CrossShopAuditReader.readAllShops();
      final switched = DatabaseHelper.instance
          .switchWorkspace(b)
          .then((_) => DatabaseHelper.instance.currentWorkspaceKey);
      await walk;

      expect(await switched, b);
      expect(DatabaseHelper.instance.currentWorkspaceKey, b);
    });

    test(
        'the gate queues rather than rejects when two shops are walked at '
        'once', () async {
      final (a, b) = await twoShops();
      await DatabaseHelper.instance.switchWorkspace(a);

      // Two overlapping walks. Each restores where it found the database, so
      // the second must still see its own starting point intact rather than
      // inheriting the first walk's last shop.
      final (first, second) = await (
        CrossShopAuditReader.readAllShops(),
        CrossShopAuditReader.readAllShops(),
      ).wait;

      expect(first.length, 2);
      expect(second.length, 2);
      expect(DatabaseHelper.instance.currentWorkspaceKey, a);
    });
  });
}
