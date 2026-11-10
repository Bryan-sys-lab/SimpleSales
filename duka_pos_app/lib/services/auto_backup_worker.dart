import 'package:workmanager/workmanager.dart';

import 'auto_sync_service.dart';

/// Top-level callback invoked by WorkManager in a headless isolate when the
/// six-hour automatic backup cycle is due. Runs even after Android has killed
/// the app process, so a till that sits idle overnight still gets its
/// scheduled backup rather than waiting until the owner next opens the app.
///
/// Registered as `autoBackupDispatcher` in `AutoSyncService.registerWorkManager`.
void autoBackupDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'autoBackup') {
      await AutoSyncService.runNow();
    }
    return Future.value(true);
  });
}
