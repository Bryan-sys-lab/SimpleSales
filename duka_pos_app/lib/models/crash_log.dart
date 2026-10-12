/// What the phone recorded when something went wrong.
///
/// ### Why this exists beside `audit_log`
///
/// The audit log answers "who did what" — every state-changing action, with an
/// actor. It is written when something goes right. This table is the other
/// half: it is written when something goes WRONG, and it answers the question
/// a shop owner actually asks a developer: "what was the app doing when it
/// failed?" A stack trace with a route, an actor and a trail of the last few
/// things the cashier tapped is answerable; a bare stack trace is a bug report
/// that takes a week of guessing.
///
/// ### Three properties, in order of how expensive they are to lose
///
/// 1. IT NEVER BLOCKS. Recording a failure happens after the fact, in a
///    `try`/`catch` that swallows its own errors. A shop that cannot sell must
///    not be told a diagnostic insert failed.
/// 2. IT IS BOUNDED AND SELF-DELETING. The table keeps its newest
///    [DatabaseHelper.crashRetainRows] rows and deletes the rest ON WRITE, so a
///    crash loop on a phone left on a shelf cannot fill the phone's storage
///    before anyone reads it.
/// 3. IT CARRIES NO SECRETS. No PINs, no tokens, no card data. The stack is
///    trimmed, the breadcrumb trail is route names, and the actor is a display
///    name — enough to reconstruct, not enough to leak.

library;

/// How badly something went wrong, which is what the list is sorted by.
enum CrashKind {
  /// The app died: an unhandled error, or one that took the run down with it.
  crash('crash'),

  /// A failure the app caught and survived — a sync that failed, a save that
  /// refused, a branch of the code that decided today was not the day.
  error('error'),

  /// Something that did not fail but should be noticed: an offline write
  /// queued, a retry given up on.
  warning('warning');

  const CrashKind(this.wire);

  /// The stored value. Single word, lower case, so the rows read the same in
  /// SQLite as they do in the admin dashboard's JSON.
  final String wire;

  static CrashKind fromWire(String? value) => CrashKind.values
      .firstWhere((kind) => kind.wire == value, orElse: () => CrashKind.error);
}

/// One recorded failure.
class CrashLogEntry {
  const CrashLogEntry({
    required this.kind,
    required this.message,
    required this.at,
    this.stack,
    this.route,
    this.actorName,
    this.action,
    this.breadcrumbs = const <String>[],
    this.id,
  });

  factory CrashLogEntry.fromMap(Map<String, Object?> row) => CrashLogEntry(
        id: row['id'] as int?,
        kind: CrashKind.fromWire(row['kind'] as String?),
        message: row['message'] as String? ?? '',
        stack: row['stack'] as String?,
        route: row['route'] as String?,
        actorName: row['actor_name'] as String?,
        action: row['action'] as String?,
        // Stored newline-joined: the trail is read far more often than it is
        // queried, and a table of one row per breadcrumb is a join to render a
        // log line.
        breadcrumbs: (row['breadcrumbs'] as String? ?? '')
            .split('\n')
            .where((String crumb) => crumb.isNotEmpty)
            .toList(growable: false),
        at: row['created_at'] as String? ?? '',
      );

  /// The id, or null for an entry that has not been written yet.
  final int? id;

  final CrashKind kind;

  /// What went wrong, in one line. A screen reads this; the stack is for the
  /// expanded row.
  final String message;

  final String at;

  /// The stack, trimmed to [maxStackLines] lines: the top of the trace is the
  /// useful part, and a 400-frame stack is a wall of framework noise.
  final String? stack;

  /// Where in the app it happened — the router's location, so the trail starts
  /// at a screen a person can name.
  final String? route;

  /// The display name of whoever was signed in, denormalised for the same
  /// reason the audit log denormalises its actor: a name that may be scrubbed
  /// from the staff table must not drag the failure log with it.
  final String? actorName;

  /// What the app was doing — the operation whose failure this is, when the
  /// failure was caught in one. Free text, because the list of operations is
  /// the list of things a shop does.
  final String? action;

  final List<String> breadcrumbs;

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'kind': kind.wire,
        'message': message,
        'stack': _trimStack(stack),
        'route': route,
        'actor_name': actorName,
        'action': action,
        'breadcrumbs': breadcrumbs.join('\n'),
        'created_at': at,
      };

  /// Cuts a stack to the frames that matter.
  ///
  /// Kept here rather than in the recorder so the rule survives a copy-paste:
  /// a 60-line frame of `dart:async` and framework plumbing tells a developer
  /// nothing, and the frames above it are the ones that name the shop's own
  /// code.
  static String? _trimStack(String? stack) {
    if (stack == null || stack.isEmpty) return null;
    final List<String> lines = stack.split('\n');
    if (lines.length <= maxStackLines) return stack;
    return '${lines.take(maxStackLines).join('\n')}\n…';
  }

  /// The top frames worth keeping. Three screens of a phone, no scrolling
  /// needed to reach the line that matters.
  static const int maxStackLines = 12;

  /// The largest entry a recorder may write.
  ///
  /// A message beyond this is JSON from a response body or a wall of text a
  /// parser produced; either way the first kilobyte is the diagnosis and the
  /// rest is noise a phone should not store.
  static const int maxMessageChars = 1024;
}

/// How much of the failure log to read.
class CrashLogQuery {
  const CrashLogQuery({this.limit = 100, this.kinds, this.since});

  final int limit;

  /// Only these kinds, when a caller wants just the crashes.
  final Set<CrashKind>? kinds;

  /// Only what happened after this instant.
  final String? since;
}
