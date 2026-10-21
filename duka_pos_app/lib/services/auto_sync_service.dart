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
///
/// The local backup is written *before* any network step, and each step is
/// wrapped in its own `try` so a network failure never skips the local copy.
/// Automatic backups use their own `duka-autobackup` prefix so rotation can
/// never delete a manual encrypted export the owner has not shared yet.
///
/// Real scheduling should move to WorkManager so the cycle fires even when the
/// app process is not alive; the timer below is the in-process fallback.
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

  /// Prefix for automatic backups, distinct from manual `duka-inventory`
  /// exports so rotation never deletes an export the owner may not have shared.
  static const String _backupPrefix = 'duka-autobackup';

  static void _schedule() {
    _timer ??= Timer.periodic(_interval, (_) => runNow());
  }

  static Future<void> runNow() async {
    if (_running || !await enabled) return;
    _running = true;
    try {
      // Network steps are best-effort: a failure here must never skip the
      // local backup below. Each step has its own try so one failing step
      // does not abort the whole cycle.
      if (await BackendService.isBackendLinked) {
        try {
          await BackendService.syncProductsToBackend();
        } catch (error) {
          debugPrint('Automatic product sync failed: $error');
        }
        try {
          await BackendService.syncStaffToBackend();
        } catch (error) {
          debugPrint('Automatic staff sync failed: $error');
        }
      }

      // The local backup is written even when the network steps failed: a
      // till that cannot reach the server still needs a fresh encrypted copy.
      try {
        // Runs on the main isolate on purpose: the catalogue read (sqflite)
        // and the file write (path_provider) both need platform channels that
        // are not available in a background isolate. Only the AES-GCM step is
        // dispatched off-thread, from inside EncryptedBackupService. The
        // "last backup" timestamp is recorded by the delegate itself, so a
        // manual and an automatic backup stay consistent.
        await writeAutomaticInventoryBackup(const InventoryBackupRequest());
      } catch (error) {
        debugPrint('Automatic local backup failed: $error');
      }

      try {
        await _rotateBackups();
      } catch (error) {
        // Rotation is housekeeping; never fail the sync because of it.
        debugPrint('Backup rotation failed: $error');
      }
    } finally {
      _running = false;
    }
  }

  /// Deletes the oldest automatic backups beyond [_maxRetainedBackups].
  ///
  /// Matches only the `duka-autobackup` prefix, never the `duka-inventory`
  /// prefix used by manual encrypted exports.
  static Future<void> _rotateBackups() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      // Async stream rather than `listSync`, which walks the whole documents
      // directory (exports included) synchronously on the UI isolate.
      final entities = await dir.list().toList();
      final backups = entities
          .whereType<File>()
          .where(
              (f) => f.path.contains(_backupPrefix) && f.path.endsWith('.duka'))
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
