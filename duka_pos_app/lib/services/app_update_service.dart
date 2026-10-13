// Updates a running till without uninstalling it.
//
// ## Why this matters more than it sounds
//
// Uninstalling to update is not a neutral act on this app. The shop's whole
// ledger — every product, every sale, the audit log, the encrypted backups —
// lives in the app's private data directory, and Android DELETES that directory
// when the app is uninstalled. So "uninstall and install the new one" is "delete
// your business and set it up again". This service exists so that never has to
// happen.
//
// ## What makes an update possible at all
//
// Three things must all hold, and OS rules rather than anything here decide the
// first two:
//
//   1. The same `applicationId`. A renamed package is a different app to
//      Android, and the old one can only be removed. This has already happened
//      once (com.dukapos.duka_pos -> com.dukapos.simplepos) and it cost a shop
//      a re-setup; it must not happen again.
//   2. The same signing key. A different key is refused with
//      INSTALL_FAILED_UPDATE_INCOMPATIBLE, and the only way past it is an
//      uninstall.
//   3. A HIGHER `versionCode`. An equal or lower one is refused with
//      INSTALL_FAILED_VERSION_DOWNGRADE.
//
// (1) and (2) are enforced outside this app: (1) by convention, documented on
// `applicationId` itself, and (2) by CI, which rebuilds one keystore from a
// secret for every release. (3) is enforced by CI too, which now refuses a
// release whose build number is not greater than the previous one — so a
// non-upgrade cannot even be published.
//
// ## What this service deliberately does NOT do
//
// It does not install silently, and it does not bypass the user. Android
// requires the "install unknown apps" permission per-app, and an update the shop
// did not approve is not an update, it is an infection. This downloads, shows
// the notes, and hands the APK to the system installer.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_release.dart';
import 'backend_service.dart';

/// How far the download has got, for a progress bar.
@immutable
class UpdateProgress {
  const UpdateProgress({required this.received, required this.total});

  final int received;
  final int total;

  /// 0 to 1, or null when the server did not send a length.
  double? get fraction =>
      total <= 0 ? null : (received / total).clamp(0.0, 1.0);
}

/// Why an update could not be completed.
enum UpdateFailure {
  /// The manifest could not be read.
  manifestUnavailable,

  /// The manifest was read but did not describe a release.
  manifestMalformed,

  /// The APK could not be downloaded.
  downloadFailed,

  /// The downloaded file is not a whole APK.
  downloadIncomplete,

  /// The OS refused it — a signing-key or version-code mismatch, almost always.
  installRefused,

  /// The phone has no room for the download.
  storage,
}

/// Thrown or returned when an update cannot proceed.
class UpdateException implements Exception {
  const UpdateException(this.failure, [this.cause]);

  final UpdateFailure failure;
  final Object? cause;

  @override
  String toString() => 'UpdateException($failure)';
}

/// Owns the check-download-install flow.
///
/// A `ChangeNotifier` rather than a lone stream, for the same reason the live
/// channel is one: the app's own state layer is `provider` + `ChangeNotifier`,
/// and a second paradigm for one feature is more machinery than the feature is
/// worth. A screen listens with `context.watch<AppUpdateService>()`.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Where the server publishes the release it is serving.
  ///
  /// Derived from the API base URL rather than duplicated, so a shop pointed at
  /// a staging backend gets staging's manifest instead of production's APK —
  /// which would be worse than no update at all.
  static String get _manifestUrl {
    final base = BackendService.backendUrl.replaceAll(RegExp(r'/+$'), '');
    // The API base carries its own `/api`; the manifest lives beside it.
    final withoutApi = base.replaceAll(RegExp(r'/api$'), '');
    return '$withoutApi/api/app/latest';
  }

  /// The folder a downloaded APK is written to.
  ///
  /// MUST match the FileProvider's allowed path — see
  /// `res/xml/update_paths.xml`. Writing anywhere else means the provider
  /// refuses the URI and the install cannot start.
  static const _downloadSubfolder = 'Download/SimpleSales';

  UpdateCheck? _check;
  UpdateCheck? get check => _check;

  UpdateProgress? _progress;
  UpdateProgress? get progress => _progress;

  /// The APK on disk, once downloaded and verified.
  File? _downloadedApk;
  File? get downloadedApk => _downloadedApk;

  bool _busy = false;
  bool get busy => _busy;

  UpdateException? _error;
  UpdateException? get error => _error;

  /// This build's number, read from the platform once.
  int? _currentBuild;

  /// This build's version name, for a prompt that can say what it is replacing.
  String? _currentVersion;

  /// The version this build reports itself as, for the prompt's "you have X".
  String? get currentVersionName => _currentVersion;

  /// Whether a release is known to be waiting.
  bool get hasUpdate => _check is UpdateAvailable;

  /// The release waiting, if any.
  AppRelease? get pendingRelease =>
      _check is UpdateAvailable ? (_check as UpdateAvailable).release : null;

  /// Asks the server what the current release is.
  ///
  /// Never throws: every outcome is a [UpdateCheck] a screen can render. A shop
  /// on a till that cannot reach the server must still be able to sell, so a
  /// failed check is a silent no-op at boot and a visible one in Settings.
  Future<UpdateCheck> checkForUpdate() async {
    if (_busy) return _check ?? const UpdateUpToDate();
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _client
          .get(Uri.parse(_manifestUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return _finish(UpdateCheckFailed('manifest ${response.statusCode}'));
      }

      final decoded = _decode(response.body);
      if (decoded == null) {
        return _finish(const UpdateCheckFailed('manifest not JSON'));
      }

      final release = AppRelease.tryParse(decoded);
      if (release == null) {
        return _finish(const UpdateCheckFailed('manifest malformed'));
      }

      final current = await _buildNumber();
      // An unknown current build is treated as up to date rather than as an
      // update: offering an APK the shop is already running would be a prompt
      // they cannot dismiss and cannot act on.
      if (current == null || release.build <= current) {
        return _finish(const UpdateUpToDate());
      }

      // The server may say this release cannot be installed over what is
      // running. The shop is told that rather than handed an APK that will
      // open a database it cannot read.
      if (release.minimumBuild != null && current < release.minimumBuild!) {
        return _finish(
          const UpdateCheckFailed('this build is too old to update in place'),
        );
      }

      return _finish(UpdateAvailable(release));
    } on Object catch (error) {
      // Includes the timeout and every socket error. Swallowed so a dead
      // network is not a crash on launch.
      return _finish(UpdateCheckFailed('$error'));
    } finally {
      _busy = false;
    }
  }

  /// Downloads the pending APK.
  ///
  /// [onProgress] is called with the running total so a screen can show a bar
  /// rather than a spinner that might have stalled. The file is written to
  /// `.part` and renamed on completion, so an interrupted download cannot be
  /// mistaken for a finished one and installed half-finished.
  Future<File> download({ValueChanged<UpdateProgress>? onProgress}) async {
    final release = pendingRelease;
    if (release == null) {
      throw const UpdateException(UpdateFailure.downloadFailed);
    }
    if (_busy) throw const UpdateException(UpdateFailure.downloadFailed);
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final target = await _apkTarget();
      final request = http.Request('GET', Uri.parse(release.downloadUrl));
      final response = await _client.send(request);

      if (response.statusCode != 200) {
        throw UpdateException(
          UpdateFailure.downloadFailed,
          'HTTP ${response.statusCode}',
        );
      }

      final total = response.contentLength ?? 0;
      final part = File('${target.path}.part');
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          final progress = UpdateProgress(received: received, total: total);
          _progress = progress;
          onProgress?.call(progress);
          notifyListeners();
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      // A truncated download is the failure that would install a broken APK, so
      // it is checked rather than assumed: a proxy that cut the stream early
      // still returns 200.
      if (total > 0 && received != total) {
        await part.delete();
        throw const UpdateException(UpdateFailure.downloadIncomplete);
      }

      await part.rename(target.path);
      _downloadedApk = target;
      _progress = null;
      return target;
    } on UpdateException {
      rethrow;
    } on FileSystemException catch (error) {
      // ENOSPC reaches here. The owner is told the phone is full rather than
      // seeing a silent failure halfway through the bar.
      final failure = error.osError?.errorCode == 28
          ? UpdateFailure.storage
          : UpdateFailure.downloadFailed;
      throw UpdateException(failure, error);
    } on Object catch (error) {
      throw UpdateException(UpdateFailure.downloadFailed, error);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Hands the downloaded APK to the system installer.
  ///
  /// The platform channel does the hand-off, because it is the only place that
  /// can build a `content://` URI from the FileProvider and start an `ACTION_VIEW`
  /// that the package manager will accept. Returns false when the OS refuses —
  /// a signing-key or version-code mismatch, both of which mean this build can
  /// never update in place and the shop has to be told that plainly rather than
  /// looping on a download.
  Future<bool> installDownloaded() async {
    final file = _downloadedApk;
    if (file == null || !await file.exists()) {
      throw const UpdateException(
          UpdateFailure.installRefused, 'no APK on disk');
    }
    try {
      const channel = MethodChannel('duka.app.update');
      final granted =
          await channel.invokeMethod<bool>('requestInstallPermission') ?? false;
      if (!granted) {
        // The shop has not granted "install unknown apps". Nothing can be done
        // from here except tell them, and the answer is a settings screen.
        return false;
      }
      final installed =
          await channel.invokeMethod<bool>('installApk', <String, Object?>{
        'path': file.path,
      });
      if (installed != true) {
        throw const UpdateException(UpdateFailure.installRefused);
      }
      return true;
    } on PlatformException catch (error) {
      if (error.code == 'install_refused') {
        throw const UpdateException(UpdateFailure.installRefused);
      }
      throw UpdateException(UpdateFailure.installRefused, error);
    }
  }

  /// Opens the OS screen that grants "install unknown apps" to this app.
  ///
  /// Returns whether the screen actually opened, so a caller can tell a shop
  /// "I have opened it" from "find it yourself" — the two need different words,
  /// and a void return would have had to guess.
  ///
  /// A shop that has never granted it would otherwise be stuck at a button that
  /// does nothing, with no way to find the setting it needs.
  Future<bool> openInstallPermissionSettings() async {
    try {
      const channel = MethodChannel('duka.app.update');
      await channel.invokeMethod<void>('openInstallPermissionSettings');
      return true;
    } on PlatformException {
      // The screen is a convenience for a shop that refused the prompt. The
      // permission can still be granted from the device's own Settings.
      return false;
    }
  }

  /// Clears the state after a check, so a second one is not mistaken for a retry.
  void reset() {
    _check = null;
    _progress = null;
    _error = null;
    _downloadedApk = null;
    notifyListeners();
  }

  /// The file the APK is written to.
  Future<File> _apkTarget() async {
    final external = await getExternalStorageDirectory();
    // Falls back to the app's own external dir. The FileProvider path is
    // `external-path`, whose root is the shared external storage — if the
    // device has none, the download still lands somewhere writable and the
    // install fails loudly rather than silently.
    final root =
        external?.path ?? (await getApplicationDocumentsDirectory()).path;
    final dir = Directory('$root/$_downloadSubfolder');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/update.apk');
  }

  /// This build's number, from the platform.
  Future<int?> _buildNumber() async {
    if (_currentBuild != null) return _currentBuild;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      _currentBuild = int.tryParse(info.buildNumber);
      return _currentBuild;
    } on Object catch (_) {
      // A missing PackageInfo is a platform that cannot report its own build.
      return null;
    }
  }

  UpdateCheck _finish(UpdateCheck result) {
    _check = result;
    if (result is UpdateCheckFailed) {
      _error = const UpdateException(UpdateFailure.manifestUnavailable);
    }
    notifyListeners();
    return result;
  }

  static Map<String, Object?>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on Object {
      // A proxy's error page, an empty body, a truncated response: all the same
      // answer, "the manifest did not say".
      return null;
    }
  }
}
