// One session-change rule for every screen that shows a session's data.
//
// Logging out used to clear the session and nothing else: `AppState` blanked
// the name, the id and the role, and each screen kept whatever it had already
// read. On a normal sign-out the router swaps the shell out and the screens
// are disposed, so their snapshots die with the session — by accident, not by
// design. Nothing in any screen knows a session ended, so the moment the
// shell SURVIVES one (an idle timeout, a PIN pad shown as an overlay, a future
// navigation change), the next person at the till is looking at the previous
// person's dashboard, inventory and analytics.
//
// So the rule lives here once, the way the live-change rule does:
//
//   * [AppState.sessionGeneration] is the single signal that a session began
//     or ended. It is a counter, not a flag, because signing out and back in
//     as the SAME person is still a new session.
//   * a screen CLEARS first and reloads second. Clearing first is the whole
//     point: the previous session's figures must never be on screen under the
//     new session's greeting, not even for the length of a query.
//   * the first change a screen sees is its own entry, so `initState` remains
//     the only load on mount and a re-parent is not a reload.
library;

import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';

/// Adds session-change reloading to a `State`.
///
/// A screen implements [clearForSession] and [reloadFromSession]. The mixin
/// owns the subscription to [AppState] and the "is this a new session" test.
///
/// Combine freely with `LiveRefresh`: one answers "the data changed", the other
/// answers "the reader did", and a screen that shows live figures needs both.
mixin SessionRefresh<T extends StatefulWidget> on State<T> {
  /// The session this screen was last loaded for. Null until the first
  /// `didChangeDependencies`, which is after `initState` — the mount load.
  int? _loadedSession;

  /// Whether a session change is already queued for the next frame.
  ///
  /// Without it, two changes inside one frame — a sign-out followed by a
  /// sign-in, say — would clear and reload twice, and the first reload's
  /// read could land on top of the second session's.
  bool _sessionUpdateQueued = false;

  /// Drops everything the screen holds for the session that just ended.
  ///
  /// Called synchronously, inside `setState`, before [reloadFromSession]: a
  /// screen that only reloaded would keep the old figures on screen for the
  /// length of the query, which is exactly the leak this mixin exists to stop.
  /// A screen whose content is genuinely session-independent may leave this
  /// empty, and say so.
  void clearForSession() {}

  /// Re-reads whatever the screen shows, for the session now signed in.
  ///
  /// Called once per session change, after [clearForSession]. Like
  /// `LiveRefresh.reloadFromLive`, it must be safe to call at any time.
  Future<void> reloadFromSession();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // WATCH, not read: this subscription is what delivers the change. Without
    // it the screen never rebuilds on a sign-in and `didChangeDependencies`
    // is never called again after the first build.
    final int generation = context.watch<AppState>().sessionGeneration;

    final int? loaded = _loadedSession;
    if (loaded == null) {
      // Entering: `initState` has already loaded for the session that is
      // current, so there is nothing to reload.
      _loadedSession = generation;
      return;
    }
    // Recorded HERE, before the deferred work, because a second change in the
    // same frame (a sign-out followed by a sign-in) must not schedule a second
    // clear-and-reload: by the time the frame lands, only the latest session
    // exists and only it deserves the read.
    if (generation == loaded || _sessionUpdateQueued) return;
    _loadedSession = generation;
    _sessionUpdateQueued = true;

    // Deferred for the same reason `LiveRefresh` defers: a dependency change
    // arrives mid-build, and work that setStates from here would rebuild
    // during a build. In the ordinary case the router has already navigated
    // away by the time the frame lands, so this is usually a no-op — it is
    // the case where the shell SURVIVES the sign-out that it exists for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sessionUpdateQueued = false;
      if (!mounted) return;
      setState(clearForSession);
      unawaited(reloadFromSession());
    });
  }
}
