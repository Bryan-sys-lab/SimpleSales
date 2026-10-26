import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duka_pos/services/auto_sync_service.dart';
import 'package:duka_pos/services/workspace_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('automatic backup sync preference belongs to the active shop', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      WorkspaceService.activeKey: 'shop-a',
      AutoSyncService.enabledKeyForWorkspace('shop-a'): true,
      AutoSyncService.enabledKeyForWorkspace('shop-b'): false,
    });

    expect(await AutoSyncService.enabled, isTrue);

    await WorkspaceService.setActiveWorkspace('shop-b');
    expect(await AutoSyncService.enabled, isFalse);
  });

  test('the old global preference is adopted once by the active shop',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      WorkspaceService.activeKey: 'shop-a',
      'automatic_backup_sync_enabled': true,
    });

    expect(await AutoSyncService.enabled, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('automatic_backup_sync_enabled'), isNull);
    expect(
      prefs.getBool(AutoSyncService.enabledKeyForWorkspace('shop-a')),
      isTrue,
    );
  });

  test('the recovery jitter slot is stable and scoped to each shop', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      WorkspaceService.activeKey: 'shop-a',
      AutoSyncService.jitterSeedKeyForWorkspace('shop-a'): 12345,
      AutoSyncService.jitterSeedKeyForWorkspace('shop-b'): 67890,
    });

    final prefs = await SharedPreferences.getInstance();
    expect(
      AutoSyncService.jitterSecondsForSeed(
        prefs.getInt(AutoSyncService.jitterSeedKeyForWorkspace('shop-a'))!,
      ),
      AutoSyncService.jitterSecondsForSeed(12345),
    );

    await WorkspaceService.setActiveWorkspace('shop-b');
    expect(
      prefs.getInt(AutoSyncService.jitterSeedKeyForWorkspace('shop-b')),
      67890,
    );
    expect(
      AutoSyncService.jitterSecondsForSeed(12345),
      isNot(AutoSyncService.jitterSecondsForSeed(67890)),
    );
  });
}
