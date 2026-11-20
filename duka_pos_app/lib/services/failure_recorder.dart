// The failure recorder: what the phone writes when something goes wrong.
//
// Three jobs, and no more:
//
//   1. CAPTURE. Hook the places an error can escape — the framework's own
//      `onError`, and the run guard `main` already wraps. A code path that
//      "should never be reached" is a stack trace in production, not a story.
//   2. RECONSTRUCT. An entry carries the route, the actor, the operation and a
//      trail of the last few things the shop did. That trail is what turns "the
//      app crashed" into "it crashed on the sell screen, printing, right after
//      importing inventory".
//   3. REFUSE TO GET IN THE WAY. Every write is best-effort and late. A shop
//      that cannot sell must never be told a diagnostic insert failed, and a
//      recorder that throws while reporting a throw is worse than no recorder.
//
// The log is bounded and self-deleting on every write — see
// [DatabaseHelper.recordCrash]. Nothing here decides retention, because
// retention has to hold even when nothing calls this class.
//
// When the build is connected to a backend, every recorded failure is also
// pushed to the system admin panel (debounced, best-effort) so an admin can
// see what broke, on what phone, under what conditions — without the shop
// owner having to send anything manually.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/crash_log.dart';
import 'build_configuration.dart';
import 'diagnostics_upload_service.dart';

/// How long the trail is.
///
/// Ten events is the difference between "the sell screen" and the sell screen,
/// after a shift was opened, after inventory was imported, after a sync
/// failed" — and it is still one screen of text.
const int breadcrumbLimit = 10;

/// Debounce window for automatic diagnostic uploads. A crash loop must not
/// POST to the backend on every single failure.
const Duration _autoUploadDebounce = Duration(seconds: 30);

/// The trail of what the shop was doing.
///
/// In memory, deliberately: the last ten navigation and feature events are
/// worth having and not worth a table, because they are re-read on every
/// failure entry and only the current run ever needs them. A crash at
/// 3am must not be missing its trail because an earlier write to disk failed.
class BreadcrumbTrail {
  BreadcrumbTrail([this._capacity = breadcrumbLimit]);

  final int _capacity;
  final List<String> _crumbs = <String>[];

  /// Records one thing that happened, newest last.
  void jot(String note) {
    _crumbs.add(note);
    while (_crumbs.length > _capacity) {
      _crumbs.removeAt(0);
    }
  }

  /// The trail, oldest first.
  List<String> get crumbs => List<String>.unmodifiable(_crumbs);

  void clear() => _crumbs.clear();

  int get length => _crumbs.length;
}

/// Where the recorder was when something happened.
///
/// Value-set rather than read from a router: the router is built once at the
/// top of the tree, and the recorder wants an answer without holding a
/// reference to it. [DiagnosticsContext] is that answer, and the app sets it —
/// the recorder holds nothing that could leak a disposed context.
class DiagnosticsContext {
  DiagnosticsContext({this.route, this.actorName});

  /// The current route's location.
  String? route;

  /// Who is signed in. A display name only, denormalised for the same reason
  /// the audit row is: a staff name that may be scrubbed must not take the
  /// failure log with it.
  String? actorName;

  /// The last operation, while one is running. "Opening the shift" is the
  /// difference between a crash in a screen and a crash in the act of doing
  /// something.
  String? operation;
}

/// The one recorder the app posts its failures to.
///
/// Top-level rather than a provider, because the framework's error handlers are
/// set before `runApp` and have no BuildContext to read from: an error must
/// never go unrecorded because a provider was not yet mounted. It writes
/// through the same singleton every other part of the app writes through, so it
/// is no more global than the database is.
///
/// The surface is deliberately small — [record], [jot], [environment] and
/// [context] — and it is exactly the set with a caller. It used to carry an
/// `install()` (overwritten by `main`'s own handler two lines later), plus
/// `recordUnhandled`, `failure`, `notice`, `entries`, `count`, `clear` and
/// `report`, none of which anything called; the entries they duplicated are
/// read straight off the database by the diagnostics screen.
final FailureRecorder failureRecorder = FailureRecorder();

/// The recorder the app owns one of.
class FailureRecorder {
  FailureRecorder({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;
  CrashLogEntry? _lastFailure;

  /// Kept in memory so a database-open failure still has a useful diagnostic.
  CrashLogEntry? get lastFailure => _lastFailure;

  final BreadcrumbTrail trail = BreadcrumbTrail();

  /// Set once at boot, updated by whatever knows where the shop is.
  ///
  /// The router fills in [DiagnosticsContext.route] as it navigates and the
  /// session fills in [DiagnosticsContext.actorName] on sign-in, so a failure
  /// recorded anywhere carries where it happened and who was there.
  final DiagnosticsContext context = DiagnosticsContext();

  /// The build and platform, written into every entry.
  ///
  /// A stack trace from an unknown build is a stack trace nobody can map onto
  /// a line of code, so it is captured once here rather than per entry.
  Map<String, String>? _environment;
  bool _environmentCaptured = false;

  /// Debounce timer for automatic diagnostic uploads.
  Timer? _uploadTimer;

  /// A message the framework would otherwise only print.
  ///
  /// Bounded, because a message is a body of text: a truncated one is the
  /// diagnosis, a whole one is a phone's storage.
  String _describe(String raw) {
    final String line = raw.trim();
    if (line.length <= CrashLogEntry.maxMessageChars) return line;
    return '${line.substring(0, CrashLogEntry.maxMessageChars)}…';
  }

  /// Records a failure, filling in whatever the context knows.
  ///
  /// This is the one method call sites make directly, and it is where
  /// reconstruction happens: an error with a route, an actor, an operation and
  /// a trail is a bug report; an error alone is a mystery.
  ///
  /// After the entry is written to the local log, an automatic upload to the
  /// system admin panel is scheduled (debounced, best-effort) when this build
  /// is connected to a backend. A shop owner never has to send anything.
  Future<void> record({
    required CrashKind kind,
    required String message,
    String? stack,
    String? operation,
    String? route,
    String? actorName,
    List<String>? breadcrumbs,
  }) async {
    remember(
      kind: kind,
      message: message,
      stack: stack,
      operation: operation,
      route: route,
      actorName: actorName,
      breadcrumbs: breadcrumbs,
    );
    try {
      await _db.recordCrash(_lastFailure!);
    } catch (_) {
      // Swallowed by design, and documented in the file header: a failed
      // diagnostic write is never the reason a sale does not happen.
    }
    _scheduleAutoUpload();
  }

  /// Schedules a best-effort, debounced upload of the local failure log to the
  /// system admin panel. Only connected builds upload; local-only builds keep
  /// the log on the phone.
  void _scheduleAutoUpload() {
    if (!BuildConfiguration.isConnected) return;
    _uploadTimer?.cancel();
    _uploadTimer = Timer(_autoUploadDebounce, () async {
      _uploadTimer = null;
      try {
        await DiagnosticsUploadService.instance.uploadAndClear();
      } catch (_) {
        // Best-effort: a failed upload never stops a till from selling.
      }
    });
  }

  /// Records a failure without touching SQLite. This is used while the local
  /// database is the thing that failed to open.
  void remember({
    required CrashKind kind,
    required String message,
    String? stack,
    String? operation,
    String? route,
    String? actorName,
    List<String>? breadcrumbs,
  }) {
    _lastFailure = CrashLogEntry(
      kind: kind,
      message: _describe(message),
      stack: stack,
      route: route ?? context.route,
      actorName: actorName ?? context.actorName,
      action: operation ?? context.operation,
      breadcrumbs: breadcrumbs ?? trail.crumbs,
      environment: environment(),
      at: DateTime.now().toIso8601String(),
    );
  }

  /// Notes something the shop did, for the trail.
  void jot(String note) => trail.jot(note);

  /// Reads /system/build.prop on Android and returns a map of key=value
  /// pairs. Returns an empty map on any failure.
  Future<Map<String, String>> _readBuildProp() async {
    final result = <String, String>{};
    try {
      final file = File('/system/build.prop');
      if (!await file.exists()) return result;
      final lines = await file.readAsLines();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final idx = trimmed.indexOf('=');
        if (idx > 0) {
          result[trimmed.substring(0, idx).trim()] =
              trimmed.substring(idx + 1).trim();
        }
      }
    } catch (_) {
      // Best-effort.
    }
    return result;
  }

  /// Captures device and platform facts once, so every failure entry carries
  /// them for reconstruction. Safe to call repeatedly; only the first call
  /// does work.
  Future<void> captureEnvironment() async {
    if (_environmentCaptured) return;
    _environmentCaptured = true;
    final env = <String, String>{
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'locale': PlatformDispatcher.instance.locale.toString(),
    };
    try {
      if (Platform.isAndroid) {
        // Read device facts from /system/build.prop, which carries the
        // consumer-visible brand, model and manufacturer without needing
        // a native plugin.
        final buildProp = await _readBuildProp();
        if (buildProp['ro.product.brand'] != null) {
          env['brand'] = buildProp['ro.product.brand']!;
        }
        if (buildProp['ro.product.model'] != null) {
          env['model'] = buildProp['ro.product.model']!;
        }
        if (buildProp['ro.product.manufacturer'] != null) {
          env['manufacturer'] = buildProp['ro.product.manufacturer']!;
        }
        if (buildProp['ro.product.device'] != null) {
          env['device'] = buildProp['ro.product.device']!;
        }
        if (buildProp['ro.product.name'] != null) {
          env['product'] = buildProp['ro.product.name']!;
        }
        if (buildProp['ro.hardware'] != null) {
          env['hardware'] = buildProp['ro.hardware']!;
        }
        if (buildProp['ro.build.display.id'] != null) {
          env['display'] = buildProp['ro.build.display.id']!;
        }
        if (buildProp['ro.build.fingerprint'] != null) {
          env['fingerprint'] = buildProp['ro.build.fingerprint']!;
        }
      } else if (Platform.isIOS || Platform.isMacOS) {
        env['model'] = Platform.localHostname;
      } else if (Platform.isWindows || Platform.isLinux) {
        env['hostName'] = Platform.localHostname;
      }
    } catch (_) {
      // Device info is best-effort: a failure here must not prevent the
      // app from recording crashes.
    }
    _environment = env;
  }

  /// The build and platform, written into every entry.
  Map<String, String> environment() {
    return _environment ??= <String, String>{
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'locale': PlatformDispatcher.instance.locale.toString(),
    };
  }
}
