// The app's one answer to the system Back button.
//
// It exists in its own file because the behaviour it replaces took the app
// down, and because the state it holds (armed/disarmed for "press back again"
// to exit) is static mutable state that must be reachable from a test.
//
// The crash it fixes, from the phone's own failure log:
//
//   #0 _Array.last
//   #1 GoRouterDelegate._findCurrentNavigators  (delegate.dart:123)
//   #2 GoRouterDelegate.popRoute                (delegate.dart:57)
//
// `Bad state: No element`, thrown while the user was backing out of a sheet and
// a dialog. The cause is that go_router's two halves disagree about one state:
// `GoRouter.canPop()` answers "yes" whenever the ROOT navigator can pop, and
// only then consults the route configuration, while `GoRouter.pop()` reads
// `currentConfiguration.matches.last` with no emptiness guard. A configuration
// emptied by the pop just served — the navigator's last page was popped and the
// match list went with it — therefore reports `canPop() == true` and then throws
// out of `pop()`. The user felt both halves of that: a blank screen where the
// emptied navigator had nothing to draw, and the crash on the next press.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// How long "press back again to exit" stays armed.
///
/// Long enough for the deliberate second press, short enough that a press
/// several minutes later never exits the till by accident — a POS is on all day
/// and lives inside a pocket with a back button in it.
const Duration _exitArmWindow = Duration(seconds: 2);

/// Handles Back, and never crashes doing it.
///
/// One instance per app, mounted by the `PopScope` above the router. The
/// instance is disposable because it owns a timer; the handler is a plain object
/// rather than a `static` on a widget so a test can arm it, fire it, and read
/// what happened without pumping a tree.
class SystemBackHandler {
  SystemBackHandler(this._hint);

  /// Shows "press back again to exit". Called through a callback rather than
  /// holding a `BuildContext`, because the context that armed the window is not
  /// the context that disarms it.
  final void Function() _hint;

  bool _armed = false;
  Timer? _armTimer;

  /// The app's answer to a Back press that nothing else consumed.
  ///
  /// [didPop] is the `PopScope`'s own result and is ignored beyond its
  /// meaning: if the framework already popped something, there is nothing here
  /// to do.
  void handle(GoRouter router, {bool didPop = false}) {
    if (didPop) return;
    if (_armed) {
      _disarm();
      // Leaving the till deliberately, from a screen that has nothing to pop.
      SystemNavigator.pop();
      return;
    }
    if (_popIfAnythingToPop(router)) return;

    _arm();
  }

  void _arm() {
    _armed = true;
    _hint();
    _armTimer?.cancel();
    _armTimer = Timer(_exitArmWindow, () => _armed = false);
  }

  void _disarm() {
    _armed = false;
    _armTimer?.cancel();
    _armTimer = null;
  }

  void dispose() {
    _armTimer?.cancel();
    _armed = false;
  }

  /// Pops the current route, but only when there is provably one to pop.
  ///
  /// The guard is the point. [router.state] performs the same
  /// `currentConfiguration.matches.last` read `pop()` performs and throws the
  /// same `StateError` when the list is empty, so it answers "is there a route
  /// configuration at all" exactly. `router.canPop()` cannot answer it: it looks
  /// at the root navigator first and returns true on a configuration that has
  /// already been emptied.
  ///
  /// The pop itself is then guarded too, because `GoRouter.pop()` throws
  /// `GoError` when every navigator it finds is already at its root — the
  /// mirror image of the first failure, and reachable from the same double
  /// press. A refused pop is not a crash: it means there was nothing to go back
  /// to, which is the one case that should offer the exit.
  @visibleForTesting
  static bool popIfAnythingToPop(GoRouter router) =>
      _popIfAnythingToPop(router);

  static bool _popIfAnythingToPop(GoRouter router) {
    if (!_hasRouteConfiguration(router)) return false;
    try {
      if (!router.canPop()) return false;
      router.pop();
      return true;
    } on GoError {
      // "There is nothing to pop" — see above.
      return false;
    } on StateError {
      // The configuration moved between the two reads; a Back press is not
      // worth more than a no-op.
      return false;
    }
  }

  static bool _hasRouteConfiguration(GoRouter router) {
    try {
      router.state;
      return true;
    } on StateError {
      return false;
    }
  }
}
