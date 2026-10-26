import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backend_service.dart';
import 'excel_service.dart';
import 'owner_business_sync_service.dart';
import 'workspace_service.dart';

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
  static const _jitterSeedKey = 'automatic_backup_sync_jitter_seed';
  static Timer? _timer;
  static bool _running = false;

  static Future<String> _enabledKeyForActiveWorkspace() async =>
      '$_enabledKey@${await WorkspaceService.activeWorkspaceKey()}';

  @visibleForTesting
  static String enabledKeyForWorkspace(String workspaceKey) =>
      '$_enabledKey@$workspaceKey';

  static Future<bool> get enabled async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _enabledKeyForActiveWorkspace();
    final scoped = prefs.getBool(key);
    if (scoped != null) return scoped;
    // Adopt the pre-workspace setting once for whichever shop is active at
    // upgrade time. Leaving the old global key in place would make every
    // later shop inherit it.
    final legacy = prefs.getBool(_enabledKey);
    if (legacy != null) {
      await prefs.setBool(key, legacy);
      await prefs.remove(_enabledKey);
      return legacy;
    }
    return false;
  }

  /// Each shop on an installation keeps one recovery slot.  Re-rolling this
  /// value on every launch made tills that came back after the same outage
  /// bunch up again on a later launch, defeating the point of the jitter.
  /// The key is scoped to the workspace so switching shops on one handset
  /// cannot make their schedules share a slot.
  static Future<int> _jitterSeed() async {
    final prefs = await SharedPreferences.getInstance();
    final key =
        '$_jitterSeedKey@${await WorkspaceService.activeWorkspaceKey()}';
    final existing = prefs.getInt(key);
    if (existing != null) return existing;
    final created = Random.secure().nextInt(1 << 31);
    await prefs.setInt(key, created);
    return created;
  }

  @visibleForTesting
  static String jitterSeedKeyForWorkspace(String workspaceKey) =>
      '$_jitterSeedKey@$workspaceKey';

  @visibleForTesting
  static int jitterSecondsForSeed(int seed) =>
      seed.abs() % (_jitterWindow.inSeconds + 1);

  static Future<void> start() async {
    if (!await enabled) return;
    _schedule();
    // Re-opening a till is a sync opportunity, but every till in a shop often
    // opens at the same time. A small per-process jitter prevents a fleet of
    // tills returning after an outage from stampeding the API together.
    unawaited(_runStartupJitter());
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _enabledKeyForActiveWorkspace();
    await prefs.setBool(key, value);
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
  static const Duration _jitterWindow = Duration(minutes: 15);

  /// Retained backups are rotated so an always-on till cannot fill its storage
  /// with encrypted snapshots.
  static const int _maxRetainedBackups = 12;

  /// Prefix for automatic backups, distinct from manual `duka-inventory`
  /// exports so rotation never deletes an export the owner may not have shared.
  static const String _backupPrefix = 'duka-autobackup';

  static void _schedule() {
    if (_timer != null) return;
    unawaited(_scheduleWithStableJitter());
  }

  static Future<void> _scheduleWithStableJitter() async {
    if (_timer != null || !await enabled) return;
    final jitter = jitterSecondsForSeed(await _jitterSeed());
    // The setting may have been switched off while SharedPreferences was
    // being read. Do not leave a timer behind in that case.
    if (_timer != null || !await enabled) return;
    _timer = Timer(_interval + Duration(seconds: jitter), () {
      _timer = null;
      unawaited(_runScheduled());
    });
  }

  static Future<void> _runStartupJitter() async {
    final jitter = jitterSecondsForSeed(await _jitterSeed());
    await Future<void>.delayed(Duration(seconds: jitter));
    if (await enabled) await runNow();
  }

  static Future<void> _runScheduled() async {
    if (await enabled) await runNow();
    if (await enabled) _schedule();
  }

  /// Runs the complete local-to-server cycle. Automatic calls respect the
  /// owner's opt-in; an explicit "Sync now" action is allowed to run once
  /// without enabling the recurring backup setting.
  static Future<void> runNow({bool force = false}) async {
    // Claim the process-local gate before the first await.  Without this,
    // startup jitter, the timer and a manual "Sync now" can all observe
    // `_running == false`, then enter together after their enabled read.
    if (_running) return;
    _running = true;
    try {
      if (!force && !await enabled) return;
      // The local copy is the safety boundary. Write it before any network
      // request so an unreachable server cannot delay the only fresh backup
      // on the device.
      try {
        // Runs on the main isolate on purpose: the catalogue read (sqflite)
        // and the file write (path_provider) both need platform channels that
        // are not available in a background isolate. Only the AES-GCM step is
        // dispatched off-thread, from inside EncryptedBackupService. The
        // "last backup" timestamp is recorded by the delegate itself, so a
        // manual and an automatic backup stay consistent.
        await writeAutomaticFullBackup(const InventoryBackupRequest());
      } catch (error) {
        debugPrint('Automatic local backup failed: $error');
      }

      // Network steps are best-effort: a failure in one must not skip the
      // remaining queues. Each step is isolated so one failing request does
      // not abort the whole cycle.
      // A tenant link alone is not permission to sync. During the
      // linked-but-unverified state the till keeps all queues local and
      // retries them only after identity verification.
      if (await BackendService.isIdentityVerified) {
        final report = await OwnerBusinessSyncService.run();
        for (final failure in report.failed) {
          debugPrint(
              'Automatic owner business sync failed (${failure.domain}): ${failure.message}');
        }
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
