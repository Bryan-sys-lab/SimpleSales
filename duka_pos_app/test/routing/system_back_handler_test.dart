// The back button, and the crash it used to cause.
//
// The phone's own failure log names the frame:
//
//   #0 _Array.last
//   #1 GoRouterDelegate._findCurrentNavigators  (delegate.dart:123)
//   #2 GoRouterDelegate.popRoute                (delegate.dart:57)
//
// `Bad state: No element`. The app's handler called `router.canPop()` — which
// looks at the ROOT navigator BEFORE the route configuration, so it answers
// true on a configuration that has already been emptied — and then
// `router.pop()`, which reads `currentConfiguration.matches.last` with no
// emptiness guard. The user got both halves: a blank screen where the emptied
// navigator had nothing left to draw, and the crash on the next press.
//
// These tests drive the handler against real routers in the two states that
// disagree, which is the only way to pin a bug whose precondition is a
// library's internal inconsistency.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:duka_pos/routing/system_back_handler.dart';

/// A router whose routes are two plain pages, so "can pop" and "cannot pop"
/// are both reachable without a shell or a session.
GoRouter _router(String initial) => GoRouter(
      initialLocation: initial,
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/detail',
          builder: (_, __) => const Scaffold(body: Text('detail')),
        ),
      ],
    );

void main() {
  // A testWidgets harness (not a bare `test`) because `GoRouter.state` needs a
  // router mounted with a configuration. The pumps are timed rather than
  // settled: there is nothing here that animates, and a settle that never
  // settles is a test that never ends.
  Future<void> pump(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> mount(WidgetTester tester, GoRouter router) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  testWidgets('back pops a pushed route, exactly as the router would have',
      (WidgetTester tester) async {
    final GoRouter router = _router('/');
    await mount(tester, router);
    router.push('/detail');
    await pump(tester);
    expect(router.state.uri.toString(), '/detail');

    final SystemBackHandler handler = SystemBackHandler(() {});
    handler.handle(router);
    await pump(tester);

    expect(router.state.uri.toString(), '/',
        reason: 'back must return to the screen the user came from');
    handler.dispose();
  });

  testWidgets(
      'back at a root shows the exit hint once, and exits on the '
      'second press', (WidgetTester tester) async {
    final GoRouter router = _router('/');
    await mount(tester, router);
    await pump(tester);

    int hints = 0;
    final SystemBackHandler handler = SystemBackHandler(() => hints++);

    handler.handle(router);
    await pump(tester);
    expect(hints, 1, reason: 'the first press arms the exit');
    expect(router.state.uri.toString(), '/', reason: 'and pops nothing');

    handler.handle(router);
    await pump(tester);
    expect(hints, 1,
        reason: 'the second press is the confirmation, not a hint');
    handler.dispose();
  });

  testWidgets('the hint disarms itself, so a later press does not exit',
      (WidgetTester tester) async {
    final GoRouter router = _router('/');
    await mount(tester, router);
    await pump(tester);

    int hints = 0;
    final SystemBackHandler handler = SystemBackHandler(() => hints++);

    handler.handle(router);
    await pump(tester);
    expect(hints, 1);

    // Past the arm window, which is exactly the case a till must survive: a
    // back button inside a pocket, pressed a minute later.
    await tester.pump(const Duration(seconds: 3));
    handler.handle(router);
    await pump(tester);

    expect(hints, 2, reason: 'a press after the window is a new first press');
    handler.dispose();
  });

  testWidgets('a back the framework already consumed is not answered again',
      (WidgetTester tester) async {
    final GoRouter router = _router('/');
    await mount(tester, router);
    await pump(tester);

    int hints = 0;
    final SystemBackHandler handler = SystemBackHandler(() => hints++);

    handler.handle(router, didPop: true);
    await pump(tester);

    expect(hints, 0, reason: 'nothing should be armed for a handled pop');
    handler.dispose();
  });

  testWidgets('a router with nothing behind it is popped only once',
      (WidgetTester tester) async {
    // The mirror image of the crash: `GoRouter.pop()` throws `GoError("There is
    // nothing to pop")` when every navigator it finds is at its root. A refused
    // pop is the exit case, not a crash.
    final GoRouter router = _router('/');
    await mount(tester, router);
    await pump(tester);

    int hints = 0;
    final SystemBackHandler handler = SystemBackHandler(() => hints++);

    handler.handle(router);
    await pump(tester);
    handler.handle(router);
    await pump(tester);

    expect(hints, 1);
    handler.dispose();
  });

  group('the guard itself', () {
    testWidgets('a router sitting at its only route is left alone',
        (WidgetTester tester) async {
      final GoRouter router = _router('/');
      await mount(tester, router);
      await pump(tester);

      // `canPop()` alone would already answer false here, so this is the easy
      // half. The half that matters — a configuration emptied by the pop just
      // served — is a window inside go_router's own delegate: nothing outside
      // it can hold the router in that state, which is exactly why the guard
      // has to ask the question rather than trusting the navigator's answer.
      expect(SystemBackHandler.popIfAnythingToPop(router), isFalse);
    });
  });
}
