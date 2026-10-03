import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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

  /// Interval between automatic backups. Deliberately hours rather than
  /// minutes: each cycle builds and encrypts a full workbook, and on a budget
  /// phone that is expensive enough to be felt as UI jank if it runs often.
  static const Duration _interval = Duration(hours: 6);

  /// Retained backups are rotated so an always-on till cannot fill its storage
  /// with encrypted snapshots.
  static const int _maxRetainedBackups = 12;

  static void _schedule() {
    _timer ??= Timer.periodic(_interval, (_) => runNow());
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
      // Runs on the main isolate on purpose: the catalogue read (sqflite) and
      // the file write (path_provider) both need platform channels that are
      // not available in a background isolate. Only the AES-GCM step is
      // dispatched off-thread, from inside EncryptedBackupService. The
      // "last backup" timestamp is recorded by the delegate itself, so a
      // manual and an automatic backup stay consistent.
      await writeAutomaticInventoryBackup(const InventoryBackupRequest());
      await _rotateBackups();
    } catch (error) {
      // The next timer/app start retries; the local till remains available.
      // Swallowing silently made a completely broken backup path look healthy,
      // so at least record why nothing was written.
      debugPrint('Automatic backup cycle failed: $error');
    } finally {
      _running = false;
    }
  }

  /// Deletes the oldest encrypted snapshots beyond [_maxRetainedBackups].
  static Future<void> _rotateBackups() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      // Async stream rather than `listSync`, which walks the whole documents
      // directory (exports included) synchronously on the UI isolate.
      final entities = await dir.list().toList();
      final backups = entities
          .whereType<File>()
          .where((f) =>
              f.path.contains('duka-inventory') && f.path.endsWith('.duka'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final stale in backups.skip(_maxRetainedBackups)) {
        await stale.delete();
      }
    } catch (error) {
      // Rotation is housekeeping; never fail the sync because of it.
      debugPrint('Backup rotation failed: $error');
    }
  }
}
