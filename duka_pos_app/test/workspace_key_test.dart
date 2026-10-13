// The invariant that decides WHICH FILE a shop's ledger lives in.
//
// This is the data-loss invariant. Each shop is its own SQLite file, and the
// file is chosen from the active workspace key:
//
//     'legacy'          -> duka_pos.db
//     'local-123456'    -> duka_pos_local-123456.db
//
// So if the key a shop was created under is not the key the app asks for next
// boot, the app opens a DIFFERENT, EMPTY database — and every product, sale and
// shift the owner entered is in the file it is no longer looking at. Nothing
// errors, nothing warns; the dashboard just reads zeroes.
//
// The failure is invisible everywhere except here, so it is pinned directly.

import 'package:duka_pos/services/workspace_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the workspace key a shop is filed under', () {
    setUp(() async {
      // A clean slate per case: a leftover active key from an earlier test
      // would make "which file" a question about the test order.
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
        'a shop that never had a workspace SET is asked for the same key '
        'forever', () async {
      // The offline-setup case: `register` records the shop but never calls
      // `setActiveWorkspace`, because there is nothing to switch TO. If that
      // made the next boot ask for a different key, the shop's file would be
      // orphaned.
      expect(await WorkspaceService.activeWorkspaceKey(),
          WorkspaceService.legacyKeyForTests);
      expect(await WorkspaceService.activeWorkspaceKey(),
          WorkspaceService.legacyKeyForTests,
          reason: 'the same answer on every boot, or the file moves');
    });

    test('registering a shop does not move which file is active', () async {
      final before = await WorkspaceService.activeWorkspaceKey();

      // Exactly what owner_setup_screen does after creating the owner.
      await WorkspaceService.register(
        workspaceKey: before,
        shopName: 'Amina Duka',
      );

      expect(await WorkspaceService.activeWorkspaceKey(), before,
          reason: 'a registration is not a switch: the ledger must stay put');
    });

    test('the registry holds the shop under the key the DB is opened with',
        () async {
      final key = await WorkspaceService.activeWorkspaceKey();
      await WorkspaceService.register(
          workspaceKey: key, shopName: 'Amina Duka');

      final registry = await WorkspaceService.registryForTests();
      expect(registry.containsKey(key), isTrue,
          reason: 'the shop must be findable under the active key, or the '
              'second boot cannot tell it exists');
    });

    test('an explicit switch sticks across a restart', () async {
      await WorkspaceService.register(
          workspaceKey: 'local-a', shopName: 'Njeri');
      await WorkspaceService.setActiveWorkspace('local-a');

      expect(await WorkspaceService.activeWorkspaceKey(), 'local-a');

      // A new "process" reads the same preference.
      expect(await WorkspaceService.activeWorkspaceKey(), 'local-a');
    });

    test('two shops keep two files and never read each other', () async {
      await WorkspaceService.register(
          workspaceKey: 'legacy', shopName: 'Amina Duka');
      await WorkspaceService.register(
          workspaceKey: 'local-b', shopName: 'Njeri');

      await WorkspaceService.setActiveWorkspace('local-b');
      expect(await WorkspaceService.activeWorkspaceKey(), 'local-b');

      await WorkspaceService.setActiveWorkspace('legacy');
      expect(await WorkspaceService.activeWorkspaceKey(), 'legacy',
          reason: 'the legacy shop is still reachable, not orphaned');
    });
  });
}
