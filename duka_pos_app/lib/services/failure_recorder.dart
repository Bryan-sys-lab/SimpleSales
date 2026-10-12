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

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/crash_log.dart';

/// How long the trail is.
///
/// Ten events is the difference between "the sell screen" and "the sell screen,
/// after a shift was opened, after inventory was imported, after a sync
/// failed" — and it is still one screen of text.
const int breadcrumbLimit = 10;

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
  Future<void> record({
    required CrashKind kind,
    required String message,
    String? stack,
    String? operation,
    String? route,
    String? actorName,
    List<String>? breadcrumbs,
  }) async {
    try {
      await _db.recordCrash(CrashLogEntry(
        kind: kind,
        message: _describe(message),
        stack: stack,
        route: route ?? context.route,
        actorName: actorName ?? context.actorName,
        action: operation ?? context.operation,
        breadcrumbs:
            breadcrumbs ?? trail.crumbs, // the trail as of now, at read time
        at: DateTime.now().toIso8601String(),
      ));
    } catch (_) {
      // Swallowed by design, and documented in the file header: a failed
      // diagnostic write is never the reason a sale does not happen.
    }
  }

  /// Notes something the shop did, for the trail.
  void jot(String note) => trail.jot(note);

  /// The build and platform, written into every entry.
  Map<String, String> environment() {
    return _environment ??= <String, String>{
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'locale': PlatformDispatcher.instance.locale.toString(),
    };
  }
}
