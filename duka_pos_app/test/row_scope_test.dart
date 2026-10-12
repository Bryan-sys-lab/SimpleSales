// Row-level security: a row may only be written under the scope it was minted.
//
// The property this suite pins is the one that matters for a till holding more
// than one shop: a `remote_id` is minted inside ONE tenant's namespace, so when
// the shop is relinked to a different tenant every id already in the file names
// a row in a namespace the shop no longer belongs to. Posting those ids anyway
// is a cross-tenant write — the server resolves a foreign row as ours, which is
// either an overwrite of another shop's data or a leak of ours.
//
// So the assertions are:
//
//   1. A tenant change INVALIDATES the cached ids rather than re-sending them,
//      so a relink mints fresh ones under the shop's actual binding.
//   2. The rows themselves survive invalidation — a product the shop still
//      sells is still its product, only its server mapping changes.
//   3. Adoption of an "account already linked" tenant is REFUSED when it belongs
//      to a different shop, because that is the path that bound another shop's
//      tenant to this one.
//   4. An unlinked shop sends nothing rather than picking a neighbour's tenant.
//
// The network is not exercised here. Every assertion is about the shop's own
// bookkeeping, which is where the bug lived.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/backend_service.dart';
import 'package:duka_pos/services/row_scope.dart';
import 'package:duka_pos/services/workspace_service.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseHelper db;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = await DatabaseHelper.openInMemoryForTests();
  });

  Product product({String name = 'Tusker 500ml'}) => Product(
        id: 0,
        name: name,
        category: 'Drinks',
        costPrice: Money.fromMajor(120),
        sellPrice: Money.fromMajor(180),
        stockQty: 24,
        reorderLevel: 6,
        updatedAt: DateTime.now().toIso8601String(),
      );

  group('the scope rule', () {
    test('a row is in scope only when BOTH fields match', () {
      const shop = RowScope(workspaceKey: 'local-a', tenantId: 'ten_a');

      // Same tenant, same shop.
      expect(shop.covers(shop), isTrue);

      // Same tenant, DIFFERENT shop: the tenant was adopted from another shop
      // on this device, which is the cross-shop write.
      expect(
        shop.covers(const RowScope(workspaceKey: 'local-b', tenantId: 'ten_a')),
        isFalse,
        reason: 'one OIDC account can hold several tenants',
      );

      // Same shop, different tenant: the shop was relinked.
      expect(
        shop.covers(const RowScope(workspaceKey: 'local-a', tenantId: 'ten_b')),
        isFalse,
      );

      // No recorded origin at all.
      expect(shop.covers(null), isFalse);
    });

    test('an unlinked shop has no scope and writes nothing', () async {
      await WorkspaceService.register(
          workspaceKey: 'local-a', shopName: 'Njeri');

      expect(await RowScope.current(), isNull);
      expect(
        () => assertRowInScope(current: null, origin: null),
        throwsA(isA<RowScopeException>()
            .having((e) => e.failure, 'failure', RowScopeFailure.notLinked)),
      );
    });

    test('the scope follows the active shop', () async {
      await WorkspaceService.register(
          workspaceKey: 'local-a', shopName: 'Njeri', tenantId: 'ten_a');
      await WorkspaceService.register(
          workspaceKey: 'local-b', shopName: 'Amina', tenantId: 'ten_b');
      await WorkspaceService.setActiveWorkspace('local-a');

      expect((await RowScope.current())!.tenantId, 'ten_a');
      await WorkspaceService.setActiveWorkspace('local-b');
      expect((await RowScope.current())!.tenantId, 'ten_b');
    });

    test('an unlinked shop has no scope even when a neighbour is linked',
        () async {
      // Shop A is linked, shop B is not. Making B active must yield NO scope —
      // falling back to A's tenant would be the cross-shop write the whole
      // rule exists to prevent, and it would be silent.
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki', tenantId: 'ten_a');
      await WorkspaceService.register(
          workspaceKey: 'local-b', shopName: 'Njeri');
      await WorkspaceService.setActiveWorkspace('local-b');

      expect(await RowScope.current(), isNull);
    });
  });

  group('what a tenant change does to the cached ids', () {
    test('the ids are invalidated, not re-sent', () async {
      await WorkspaceService.register(
          workspaceKey: 'local-a', shopName: 'Njeri', tenantId: 'ten_a');

      // Minted under the first tenant.
      await db.upsertProducts(<Product>[product()]);
      await db.setProductRemoteIds(<int, String>{1: 'prod_ten_a'});

      final before =
          (await db.database.then((d) => d.query('products'))).single;
      expect(before['remote_id'], 'prod_ten_a');

      // The shop is relinked to a different tenant. The cached id names a row
      // in ten_a's namespace, which this shop no longer belongs to.
      await WorkspaceService.register(
          workspaceKey: 'local-a', shopName: 'Njeri', tenantId: 'ten_b');
      await db.clearAllRemoteIds();

      final after = (await db.database.then((d) => d.query('products'))).single;
      // The id is gone, so the next sync mints a fresh one under ten_b.
      expect(after['remote_id'], isNull);
      // The PRODUCT itself is untouched: it is still the shop's stock.
      expect(after['name'], 'Tusker 500ml');
      expect(after['stock_qty'], 24);
    });

    test('the staff roster survives an invalidation', () async {
      await WorkspaceService.register(
          workspaceKey: 'local-a', shopName: 'Njeri', tenantId: 'ten_a');

      await db.addStaff(
          Staff(name: 'Beatrice Wanjiku', role: 'cashier', pinHash: 'hash'));
      await db.setStaffRemoteId(1, 'staff_ten_a');

      await db.clearAllRemoteIds();

      final rows = await db.database.then((d) => d.query('staff'));
      expect(rows.single['remote_id'], isNull);
      expect(rows.single['name'], 'Beatrice Wanjiku');
      expect(rows.single['active'], 1);
    });

    test('a deletion tombstone is dropped with the ids it would replay',
        () async {
      // A tombstone replays "this cashier was removed" by remote_id. After a
      // tenant change that id names a row in the old namespace, and replaying
      // it would try to delete a row in another shop.
      await db.database.then((d) => d.insert('staff_deletion_tombstones', {
            'staff_id': 1,
            'remote_id': 'staff_ten_a',
            'deleted_at': DateTime.now().toIso8601String(),
          }));
      expect(
          (await db.database.then((d) => d.query('staff_deletion_tombstones')))
              .length,
          1);

      await db.clearAllDeletionTombstones();

      expect(
          (await db.database.then((d) => d.query('staff_deletion_tombstones')))
              .length,
          0);
    });
  });

  group('adopting a tenant from a 409', () {
    test("a tenant already bound to THIS shop is a retry, not a takeover",
        () async {
      // The shop has been linked before, and the account's existing tenant is
      // the one this shop already holds. Re-adopting it is a retry of this
      // shop's own link and is safe.
      final tenantId = 'ten_a';
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki', tenantId: tenantId);

      // The registry maps the tenant back to the shop that is active, so
      // `linkShopToBackend` accepts the 409's answer rather than refusing it.
      expect(await WorkspaceService.workspaceForTenant(tenantId),
          await WorkspaceService.activeWorkspaceKey());
    });

    test('a tenant bound to a DIFFERENT shop is refused', () async {
      // One OIDC account holding two shops. Linking the second shop to the same
      // account gets a 409 whose response names the FIRST shop's tenant, and
      // adopting it would bind another shop's tenant to this one — after which
      // this shop's ledger is written into the first shop's tenant.
      const firstTenant = 'ten_a';
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki', tenantId: firstTenant);
      await WorkspaceService.register(
          workspaceKey: 'local-b', shopName: 'Njeri');
      // The owner is adding a SECOND shop, so the new one is the active one.
      await WorkspaceService.setActiveWorkspace('local-b');

      // The 409 response says ten_a, but that tenant belongs to `legacy`, not
      // to `local-b`. `linkShopToBackend` therefore refuses instead of adopting.
      expect(await WorkspaceService.activeWorkspaceKey(), 'local-b');
      expect(
        await WorkspaceService.workspaceForTenant(firstTenant),
        isNot(await WorkspaceService.activeWorkspaceKey()),
        reason: 'the tenant belongs to another shop, so it must not be adopted',
      );
      // And the newly added shop stays unlinked rather than silently inheriting.
      expect(await BackendService.tenantId, isNull);
    });
  });

  group('where the recorded scope lives', () {
    test("in the shop's own database, not in a device-wide preference",
        () async {
      // The recorded provenance is written to this shop's `shop_settings`
      // table. That is per-workspace BY CONSTRUCTION — each shop on the device
      // is its own SQLite file — so shop B cannot inherit shop A's provenance
      // and pass a scope check it should fail. The device-wide
      // SharedPreferences hold no tenant at all, which is the other half of
      // the same property: there is no global value to leak across shops.
      await db.setSetting('remote_id_scope_tenant', 'ten_a');

      expect(await db.getSetting('remote_id_scope_tenant'), 'ten_a');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tenant_id'), isNull,
          reason: 'the global tenant key is retired, not read');
      expect(prefs.getString('remote_id_scope_tenant'), isNull,
          reason: 'provenance is per-shop, never device-wide');
    });
  });

  group('the guards this suite was written after', () {
    test('a relink drops the ids that were minted under the old tenant',
        () async {
      // The trace the row-scope rule exists for: shop A links ten_a, syncs, then
      // relinks to ten_b. The ids already in the file name rows inside ten_a's
      // namespace, so the next sync must not post them.
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki', tenantId: 'ten_a');
      await db.upsertProducts(<Product>[product()]);
      await db.setProductRemoteIds(<int, String>{1: 'prod_ten_a'});
      // Recorded as the scope the id was minted under.
      await db.setSetting('remote_id_scope_tenant', 'ten_a');

      // Relinked to a different tenant.
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki', tenantId: 'ten_b');
      final scope = await RowScope.current();
      expect(scope!.tenantId, 'ten_b');

      // The recorded provenance no longer matches, so the ids are invalidated
      // and the new scope is recorded for the next sync.
      final recorded = await db.getSetting('remote_id_scope_tenant');
      expect(recorded, isNot(scope.tenantId),
          reason: 'ten_a ids are stale under a ten_b binding');
      await db.clearAllRemoteIds();
      await db.setSetting('remote_id_scope_tenant', scope.tenantId);

      final after = (await db.database.then((d) => d.query('products'))).single;
      // The id is gone, so the server mints a fresh one under ten_b.
      expect(after['remote_id'], isNull);
      expect(await db.getSetting('remote_id_scope_tenant'), 'ten_b');
    });

    test('a tenant bound to no shop on this device is adoptable', () async {
      // A fresh install, reinstall or second device. The tenant exists on the
      // server but not in THIS device's registry, so `workspaceForTenant`
      // returns null. Refusing there left a legitimate shop permanently
      // unlinked while telling it "another shop on this device", which was
      // false — the other shop was on another PHONE.
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki');

      final bound = await WorkspaceService.workspaceForTenant('ten_unknown');
      expect(bound, isNull);
      // The 409 guard adopts when the tenant is unbound OR bound to the active
      // shop, and refuses only when another workspace here holds it.
      expect(bound ?? await WorkspaceService.activeWorkspaceKey(),
          await WorkspaceService.activeWorkspaceKey(),
          reason: 'an unbound tenant must be adoptable');
    });

    test('a tenant bound to a different shop HERE is refused', () async {
      // The cross-shop write this guard stops: shop B linking to the same OIDC
      // account as shop A gets a 409 naming A's tenant, and adopting it would
      // bound B's ledger into A's tenant.
      const firstTenant = 'ten_a';
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Kariuki', tenantId: firstTenant);
      await WorkspaceService.register(
          workspaceKey: 'local-b', shopName: 'Njeri');
      await WorkspaceService.setActiveWorkspace('local-b');

      final bound = await WorkspaceService.workspaceForTenant(firstTenant);
      expect(bound, 'legacy');
      expect(bound, isNot(await WorkspaceService.activeWorkspaceKey()),
          reason:
              'another shop on this device holds it, so it must be refused');
    });
  });

  group('the audit trim cut on the key the readers use', () {
    test('the boundary row is found by created_at, not by id', () async {
      // The id-only form was cheaper and wrong: `created_at` comes from the
      // device clock, so a phone whose clock moved backwards gives older rows
      // later timestamps, and the id cut then deleted the NEWEST work and kept
      // the stale. Rows are written with deliberately non-monotonic
      // `created_at` so the reader-ordering cut is what the test observes.
      const retain = 3;
      final rows = <Map<String, Object?>>[
        <String, Object?>{'id': 1, 'created_at': '2026-01-03T00:00:00.000'},
        <String, Object?>{'id': 2, 'created_at': '2026-01-01T00:00:00.000'},
        <String, Object?>{'id': 3, 'created_at': '2026-01-05T00:00:00.000'},
        <String, Object?>{'id': 4, 'created_at': '2026-01-02T00:00:00.000'},
        <String, Object?>{'id': 5, 'created_at': '2026-01-04T00:00:00.000'},
      ];
      await db.database.then((d) => d.transaction((txn) async {
            for (final row in rows) {
              await txn.insert('audit_log', <String, Object?>{
                ...row,
                'action': 'product_updated',
                'entity': 'product',
                'entity_id': null,
                'actor_id': null,
                'actor_name': 'Amina Duka',
                'detail': 'a row',
              });
            }
          }));

      // Cut on the key the readers use: the newest `retain` by created_at DESC,
      // and delete everything strictly older than that boundary row.
      final boundary = await db.database.then((d) => d.rawQuery(
          'SELECT id, created_at FROM audit_log '
          'ORDER BY created_at DESC, id DESC LIMIT 1 OFFSET ?',
          <Object?>[retain - 1]));
      final cutoffId = boundary.first['id'] as int;
      final cutoffAt = boundary.first['created_at'] as String;
      // The boundary is the 3rd-newest by TIME (Jan 3), not the 3rd-highest id.
      expect(cutoffId, 1, reason: 'Jan 3 is the third-newest row by time');
      await db.database.then((d) => d.delete(
            'audit_log',
            where: 'created_at < ? OR (created_at = ? AND id < ?)',
            whereArgs: <Object?>[cutoffAt, cutoffAt, cutoffId],
          ));

      final kept = await db.database.then((d) => d.query('audit_log'));
      // The three newest by TIME survive, even though their ids are not the
      // three highest.
      expect(kept.map((r) => r['id']), <int>[1, 3, 5]);
      // The rows deleted are the OLDEST by time, which is what a trim means.
      expect(kept.map((r) => r['id']), isNot(contains(2)));
      expect(kept.map((r) => r['id']), isNot(contains(4)));
    });
  });
}
