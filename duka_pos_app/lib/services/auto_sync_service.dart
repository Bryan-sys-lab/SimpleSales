import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'backend_service.dart';
import 'excel_service.dart';

/// Best-effort, opt-in online sync. Offline work never waits for this timer
/// and mobile OS background execution is not assumed; a retry occurs while
/// the app is open and whenever it is started again.
class AutoSyncService {
  static const _enabledKey = 'automatic_backup_sync_enabled';
  static Timer? _timer;
  static bool _running = false;

  static Future<bool> get enabled async =>
      (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? false;

  static Future<void> start() async {
    if (await enabled) _schedule();
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (value) {
      _schedule();
      await runNow();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  static void _schedule() {
    _timer ??= Timer.periodic(const Duration(minutes: 5), (_) => runNow());
  }

  static Future<void> runNow() async {
    if (_running || !await enabled) return;
    _running = true;
    try {
      // This call is intentionally best-effort. Dio timeouts make offline
      // retries cheap and never interrupt an active sale.
      if (await BackendService.isBackendLinked) {
        await BackendService.syncProductsToBackend();
        await BackendService.syncStaffToBackend();
      }
      await ExcelService().saveAutomaticInventoryBackup();
    } catch (_) {
      // The next timer/app start retries; the local till remains available.
    } finally {
      _running = false;
    }
  }
}
