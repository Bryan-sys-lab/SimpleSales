import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:duka_pos/routing/app_router.dart';
import 'package:duka_pos/routing/system_back_handler.dart';

/// The app's real dispatch path: a route's `PopScope` (installed by
/// `_fadeThrough`) inside the router's subtree.
///
/// This is the regression test for the crash on the phone, and the proof that
/// the guard is reachable at all — the version that sat above the router was
/// inert, which is how `popRoute()`'s empty-configuration `Bad state: No
/// element` reached a real shop.
GoRouter _router() => GoRouter(
      navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'root'),
      initialLocation: '/welcome',
      routes: <RouteBase>[
        GoRoute(
          path: '/welcome',
          pageBuilder: (BuildContext context, GoRouterState state) =>
              fadeThroughForTesting(
            state,
            const Scaffold(body: Text('welcome')),
          ),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (BuildContext context, GoRouterState state) =>
              fadeThroughForTesting(
            state,
            const Scaffold(body: Text('profile')),
          ),
        ),
      ],
    );

void main() {
  // The handler is the app's one instance and owns a timer. Without this the
  // leftover arm from one test keeps the next one's tree from being torn down.
  tearDown(() => systemBackHandler.dispose());

  testWidgets(
      "the guard a route builds answers Back, and the router's own "
      'popRoute never runs', (tester) async {
    final GoRouter router = _router();
    setSystemBackHint(() {});
    // Point the module's router reference at this one, exactly as
    // `buildAppRouter` does when the app builds.
    appRouterForTesting = router;

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    router.push('/profile');
    await tester.pump();
    expect(router.state.uri.toString(), '/profile');

    await tester.binding.handlePopRoute();
    await tester.pump();

    // Guarded: back returned to the route beneath, through the handler's guarded
    // pop, rather than reaching the framework path that throws on an empty
    // configuration.
    expect(router.state.uri.toString(), '/welcome');
  });

  testWidgets('back at a branch root arms the exit rather than crashing',
      (tester) async {
    final GoRouter router = _router();
    int hints = 0;
    setSystemBackHint(() => hints++);
    appRouterForTesting = router;

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    // Nothing beneath the welcome screen: this is the state that used to empty
    // the root navigator and produce both the blank screen and the crash.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(hints, 1, reason: 'the first press arms the exit');
    expect(router.state.uri.toString(), '/welcome', reason: 'and pops nothing');

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(hints, 1, reason: 'the second press is the confirmation');
  });
  test('a guarded pop is a no-op, never a throw', () {
    // The guard's whole contract, and the part that is pure: the two reads
    // go_router disagrees on — a non-empty match list on the one hand, and a
    // pop that finds nothing to pop on the other — both have to land here as a
    // refusal rather than as a crash. `Bad state: No element` out of
    // `_findCurrentNavigators` is the bug; `GoError("There is nothing to pop")`
    // is its mirror image, and both reach a shop through the same double press.
    final GoRouter router = _router();
    setSystemBackHint(() {});
    appRouterForTesting = router;

    expect(SystemBackHandler.popIfAnythingToPop(router), isFalse,
        reason: 'a router at its only route has nothing to pop');
  });
}
