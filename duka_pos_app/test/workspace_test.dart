// The multi-shop guarantee: several shops on one device, and nothing leaks.
//
// A shop owner running two dukas from one phone is the whole point of the
// workspace layer, so the property that matters is not "shops can be added" —
// it is that shop A's stock, staff and owner are invisible to shop B, and that
// switching back restores exactly what was left. That is what this suite
// asserts.
//
// What it deliberately does NOT assert is "two files exist on disk". That is the
// implementation that buys the property, `_initDb` names the file after the
// workspace key, and the observable consequence — a shop B that cannot see shop
// A's rows — is what a user would actually report as a leak. Testing the path
// would mean adding test-only surface to production for no extra safety.

import 'dart:io';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/settings_screen.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/backend_service.dart';
import 'package:duka_pos/services/workspace_service.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Where the ffi backend puts its files in a plain `flutter test` run.
///
/// `getDatabasesPath()` resolves to this directory on Linux, and sqlite leaves
/// the files behind. This suite therefore uses a unique workspace key per case
/// rather than deleting mid-suite: `resetForTests()` nulls the singleton
/// WITHOUT closing the handle, so deleting a file a previous case still has
/// open leaves that connection holding a deleted inode and every later write
/// to the path fails with "attempt to write a readonly database".
final Directory _ffiDatabases =
    Directory('.dart_tool/sqflite_common_ffi/databases');

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Start from a clean directory, then never delete from it again.
    if (_ffiDatabases.existsSync()) {
      for (final FileSystemEntity file in _ffiDatabases.listSync()) {
        if (file is File && file.path.endsWith('.db')) {
          file.deleteSync();
        }
      }
    }
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    // An empty device: no shops registered, none active. Each case registers
    // what it needs, so a case can never pass because a previous case's shop
    // happened to be there.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'workspace_registry_v1': '{}',
    });
  });

  // NO tearDownAll deletion of the shared ffi directory.
  //
  // A suite that deletes .db files here removes them out from under every
  // OTHER suite's still-open connections, and every later write to such a file
  // fails with sqlite error 1032 — "attempt to write a readonly database" —
  // reported against whichever test happens to write next, which is not the
  // suite that caused it. `setUpAll` already clears the directory before this
  // suite runs, so nothing is left behind for the NEXT run either.

  group('workspace registry', () {
    test('a second shop is registered alongside the first', () async {
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki');
      await WorkspaceService.register(
          workspaceKey: 'local-a', shopName: 'Njeri', tenantId: 'ten_1');

      final List<LocalShop> shops = await WorkspaceServiceShops.localShops();
      expect(shops.length, 2);
      expect(shops.first.workspaceKey, 'legacy',
          reason: 'the original shop leads, whatever the registry order');
      expect(shops.last.isBackendLinked, isTrue);
    });

    test('failed-shop cleanup removes only the newly registered workspace',
        () async {
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki');
      await WorkspaceService.register(
          workspaceKey: 'failed-shop', shopName: 'Incomplete');

      await WorkspaceService.unregister('failed-shop');

      final Map<String, Map<String, String>> registry =
          await WorkspaceService.registryForTests();
      expect(registry, contains('legacy'));
      expect(registry, isNot(contains('failed-shop')));
    });

    test('failed shop creation rollback restores the prior shop and file',
        () async {
      const String previous = 'rollback-previous';
      const String failed = 'rollback-failed';
      await WorkspaceService.register(
          workspaceKey: previous, shopName: 'Existing shop');
      await WorkspaceService.setActiveWorkspace(previous);
      await DatabaseHelper.instance.initializeWorkspace(previous);
      await DatabaseHelper.instance.createOwner(Owner(
        id: 1,
        name: 'Owner',
        pinHash: 'hash',
        email: 'owner@example.com',
        shopName: 'Existing shop',
        createdAt: DateTime.now().toIso8601String(),
      ));
      final AppState state = AppState();
      await state.loadOwner();

      await WorkspaceService.register(
          workspaceKey: failed, shopName: 'Incomplete shop');
      await state.switchWorkspace(
        failed,
        createOwnerFor: Owner(
          id: 1,
          name: 'Owner',
          pinHash: 'hash',
          email: 'owner@example.com',
          shopName: 'Incomplete shop',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      final String failedPath = await DatabaseHelper.databasePathFor(failed);
      expect(File(failedPath).existsSync(), isTrue);

      await rollbackFailedShopCreation(
        state: state,
        workspaceKey: failed,
        previousWorkspaceKey: previous,
      );

      expect(await WorkspaceService.activeWorkspaceKey(), previous);
      expect(state.workspaceKey, previous);
      expect(state.owner?.shopName, 'Existing shop');
      expect(File(failedPath).existsSync(), isFalse);
      expect(
        (await WorkspaceService.registryForTests()).containsKey(failed),
        isFalse,
      );
    });

    test('the active shop is switchable by key, not by name', () async {
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki');
      await WorkspaceService.register(
          workspaceKey: 'local-a', shopName: 'Njeri');

      await WorkspaceService.setActiveWorkspace('local-a');
      expect(await WorkspaceService.activeWorkspaceKey(), 'local-a');

      await WorkspaceService.setActiveWorkspace('legacy');
      expect(await WorkspaceService.activeWorkspaceKey(), 'legacy');
    });

    // The cross-shop tenant leak, pinned.
    //
    // The active tenant used to live in ONE global preference that was written
    // by whichever shop verified last and posted from every shop on the device.
    // With two shops on one phone, the second shop's syncs, staff calls and
    // analytics went under the first shop's tenant id — cross-shop data mixing
    // the server resolves in the caller's favour, so it is both a privacy and a
    // correctness fault.
    test('the active tenant follows the active workspace', () async {
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki', tenantId: 'ten_first');
      await WorkspaceService.register(
          workspaceKey: 'local-a', shopName: 'Njeri', tenantId: 'ten_second');

      // The first shop's tenant, because the first shop is active.
      expect(await BackendService.tenantId, 'ten_first');

      // Switching shops must switch the tenant. This is the line that failed.
      await WorkspaceService.setActiveWorkspace('local-a');
      expect(await BackendService.tenantId, 'ten_second');

      await WorkspaceService.setActiveWorkspace('legacy');
      expect(await BackendService.tenantId, 'ten_first');
    });

    test('a shop with no tenant posts no tenant at all', () async {
      // An unlinked shop must not borrow a neighbour's id: that would be the
      // same leak with a quieter symptom.
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki', tenantId: 'ten_first');
      await WorkspaceService.register(
          workspaceKey: 'local-a', shopName: 'Njeri');

      await WorkspaceService.setActiveWorkspace('local-a');
      expect(await BackendService.tenantId, isNull);
    });

    test('two shops that share a name are still two shops', () async {
      // Two dukas in the same town are plausibly both called "Amina's Shop".
      // They must not collapse into one workspace entry.
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Amina');
      await WorkspaceService.register(
          workspaceKey: 'local-a', shopName: 'Amina');

      final List<LocalShop> shops = await WorkspaceServiceShops.localShops();
      expect(shops.length, 2);
      expect(shops.map((s) => s.workspaceKey).toSet().length, 2);
    });

    test('a blank shop name is never rendered as an empty row', () async {
      await WorkspaceService.register(workspaceKey: 'legacy', shopName: '');

      final List<LocalShop> shops = await WorkspaceServiceShops.localShops();
      expect(shops.single.shopName, 'Unnamed shop');
    });
  });

  group('per-shop data isolation', () {
    late String shopA;
    late String shopB;

    setUp(() async {
      // A unique key per case, INCLUDING the first shop. `legacy` maps to the
      // fixed filename `duka_pos.db`, and reusing it means reopening a file a
      // previous case's still-open connection left behind — `resetForTests`
      // nulls the singleton without closing the handle, so the delete-then-
      // reopen sequence yields "attempt to write a readonly database". Two
      // fresh keys per case avoid the whole class of problem and are closer to
      // what a device does anyway: every shop it adds gets its own key.
      final String run = DateTime.now().microsecondsSinceEpoch.toString();
      shopA = 'ws-a-$run';
      shopB = 'ws-b-$run';
      await WorkspaceService.register(workspaceKey: shopA, shopName: 'Shop A');
      await WorkspaceService.register(workspaceKey: shopB, shopName: 'Shop B');
    });

    Future<void> seedShopA() async {
      await DatabaseHelper.instance.initializeWorkspace(shopA);
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
    }

    test('a product in one shop is invisible in the other', () async {
      await seedShopA();

      await DatabaseHelper.instance.switchWorkspace(shopB);
      final List<Product> inB = await DatabaseHelper.instance.getProducts();
      expect(inB.where((p) => p.name == 'Tusker 500ml'), isEmpty,
          reason: 'shop B must not see shop A\'s product — this is the leak '
              'the workspace layer exists to prevent');
    });

    test('staff in one shop cannot sign in to the other', () async {
      await DatabaseHelper.instance.initializeWorkspace(shopA);
      await DatabaseHelper.instance
          .addStaff(Staff(name: 'Joseph', pinHash: 'h', role: 'cashier'));

      await DatabaseHelper.instance.switchWorkspace(shopB);
      final List<Staff> staffInB = await DatabaseHelper.instance.getStaff();
      expect(staffInB.where((s) => s.name == 'Joseph'), isEmpty);
    });

    test('each shop has its own owner and its own till code', () async {
      await DatabaseHelper.instance.initializeWorkspace(shopA);
      await DatabaseHelper.instance.createOwner(Owner(
          id: 1,
          name: 'Amina',
          pinHash: 'p',
          email: 'a@b.c',
          shopName: 'Shop A',
          createdAt: '2026-01-01'));

      await DatabaseHelper.instance.switchWorkspace(shopB);
      // Shop B is a fresh shop: no owner yet, and its own default till code.
      // If shop A's owner showed up here, one phone would sign the same four
      // digits into both shops.
      expect(await DatabaseHelper.instance.getOwner(), isNull);
      expect(await DatabaseHelper.instance.getTillCode(), isNotEmpty);
    });

    test('a stock adjustment in one shop does not touch the other', () async {
      await seedShopA();

      // Shop A sells out.
      await DatabaseHelper.instance.initializeWorkspace(shopA);
      final products = await DatabaseHelper.instance.getProducts();
      await DatabaseHelper.instance
          .upsertProduct(products.first.copyWith(stockQty: 0));

      await DatabaseHelper.instance.switchWorkspace(shopB);
      // Shop B never had the row, so there is nothing to be decremented — and
      // a decrement that appears here would be a cross-shop write.
      final List<Product> inB = await DatabaseHelper.instance.getProducts();
      expect(inB.isEmpty, isTrue);

      await DatabaseHelper.instance.switchWorkspace(shopA);
      final List<Product> back = await DatabaseHelper.instance.getProducts();
      expect(back.single.stockQty, 0,
          reason: 'shop A\'s own write must survive the round trip');
    });

    test('switching back restores exactly what was left', () async {
      await seedShopA();

      await DatabaseHelper.instance.switchWorkspace(shopB);
      expect(await DatabaseHelper.instance.getProducts(), isEmpty);

      await DatabaseHelper.instance.switchWorkspace(shopA);
      final List<Product> back = await DatabaseHelper.instance.getProducts();
      expect(back.length, 1);
      expect(back.single.name, 'Tusker 500ml');
      expect(back.single.stockQty, 24);
    });

    test('re-initialising the active workspace is a no-op, not a reopen',
        () async {
      await seedShopA();

      // The guard is "already on this key". Without it, a second switch would
      // close and reopen the same file mid-session, and the singleton would be
      // holding a connection to a database it no longer owns.
      await DatabaseHelper.instance.initializeWorkspace(shopA);
      expect((await DatabaseHelper.instance.getProducts()).length, 1);
    });
  });
}
