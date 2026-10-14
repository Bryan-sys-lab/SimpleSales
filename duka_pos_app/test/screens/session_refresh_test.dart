// What a screen does when the session changes under it.
//
// The bug these pin down: logging out blanked the session in `AppState` and
// nothing else, so every screen kept whatever it had already read. On a normal
// sign-out the router disposes the shell and the screens die with it — by
// accident. The moment a shell outlives a session (an idle timeout, a PIN pad
// shown as an overlay, a future navigation change), the next person at the
// till reads the previous person's figures.
//
// So the contract under test is the one `SessionRefresh` promises, exercised on
// a screen with no I/O of its own: CLEAR first, reload second, once per session
// change, and never on entry (the entry load is `initState`'s job).
//
// The database is deliberately absent. `testWidgets` runs in a fake-async zone
// where sqflite's background-isolate queries never complete, so a screen that
// awaits one here would hang until the harness killed the file — which is why
// the real screens' DB behaviour is covered in `session_scope_test.dart` and
// `analytics_test.dart` instead.

import 'dart:async';
import 'dart:io';

import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/session_refresh_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// A screen that holds one session's data and records what happened to it.
///
/// The event log is the assertion: `cleared` must precede `reloaded`, because a
/// screen that reloaded without clearing would hold the previous person's
/// figures on screen for the length of the read — which is the leak.
class _FakeScreen extends StatefulWidget {
  const _FakeScreen();

  @override
  State<_FakeScreen> createState() => _FakeScreenState();
}

class _FakeScreenState extends State<_FakeScreen>
    with SessionRefresh<_FakeScreen> {
  final List<String> events = <String>[];
  String? shown;

  @override
  void initState() {
    super.initState();
    // After the first frame, the way a real screen's own entry load lands.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    shown = context.read<AppState>().currentStaffName ?? 'nobody';
    events.add('loaded');
    if (mounted) setState(() {});
  }

  @override
  void clearForSession() {
    shown = null;
    events.add('cleared');
  }

  @override
  Future<void> reloadFromSession() async {
    shown = context.read<AppState>().currentStaffName ?? 'nobody';
    events.add('reloaded');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Material(
        child: Text(shown ?? 'CLEARED'),
      );
}

void main() {
  late AppState state;

  setUp(() {
    state = AppState();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<AppState>.value(value: state),
        ],
        child: const MaterialApp(home: _FakeScreen()),
      ),
    );
    // One frame for the entry load's post-frame callback, one for the rebuild
    // it schedules.
    await tester.pump();
    await tester.pump();
  }

  Future<_FakeScreenState> screenState(WidgetTester tester) async {
    await tester.pump();
    return tester.state<_FakeScreenState>(find.byType(_FakeScreen));
  }

  testWidgets('entering a session loads once and does not reload',
      (WidgetTester tester) async {
    await pumpScreen(tester);
    final _FakeScreenState screen = await screenState(tester);

    // The entry load is `initState`'s job. A mixin that reloaded on entry
    // would double every screen's first read — and would fire before its own
    // data could possibly be stale.
    expect(screen.events, <String>['loaded']);
    expect(find.text('nobody'), findsOneWidget);
  });

  testWidgets('signing out clears what the screen held, then reloads',
      (WidgetTester tester) async {
    state.signIn('Amina', asOwner: false);
    await pumpScreen(tester);
    _FakeScreenState screen = await screenState(tester);
    expect(find.text('Amina'), findsOneWidget);

    state.signOut();
    await tester.pump();
    await tester.pump();
    screen = await screenState(tester);

    // Cleared BEFORE reloaded: the ordering is the whole guarantee. A reload
    // without a clear would paint Amina's data under the signed-out session.
    expect(screen.events, <String>['loaded', 'cleared', 'reloaded']);
    // And the screen now reads the session that exists: nobody.
    expect(find.text('nobody'), findsOneWidget);
    expect(find.text('Amina'), findsNothing);
  });

  testWidgets('the next person in gets the screen, not the last person’s',
      (WidgetTester tester) async {
    // The reported bug in one test: the owner works, signs out; a cashier
    // signs in. Without the session signal the screen still holds the owner's
    // read — greeting, figures, shift card — under the cashier's name.
    //
    // The raw `signIn` path, because an owner session's `signInAsOwner` needs
    // the shop's row from a database this file deliberately has none of.
    state.signIn('Test Owner', asOwner: true);
    await pumpScreen(tester);
    _FakeScreenState screen = await screenState(tester);
    expect(find.text('Test Owner'), findsOneWidget);

    state.signOut();
    await tester.pump();
    await tester.pump();
    state.signInAsStaff(Staff(id: 7, name: 'Amina', pinHash: 'x'));
    await tester.pump();
    await tester.pump();
    screen = await screenState(tester);

    // Cleared and re-read for the cashier: the screen never shows the owner's
    // data under the cashier's session, not even between the two.
    expect(
      screen.events,
      <String>['loaded', 'cleared', 'reloaded', 'cleared', 'reloaded'],
    );
    expect(find.text('Amina'), findsOneWidget);
    expect(find.text('Test Owner'), findsNothing);
    expect(find.text('nobody'), findsNothing);
  });

  testWidgets('two session changes in one frame are one reload',
      (WidgetTester tester) async {
    state.signIn('Amina', asOwner: false);
    await pumpScreen(tester);
    _FakeScreenState screen = await screenState(tester);

    // A sign-out followed immediately by a sign-in — the idle timeout that
    // lands while someone else is already typing a PIN, say. The screen must
    // not clear-and-reload twice: the first reload would be for a session
    // that no longer exists by the time it ran.
    state.signOut();
    state.signIn('Joseph', asOwner: false);
    await tester.pump();
    await tester.pump();
    screen = await screenState(tester);

    expect(
      screen.events.where((String e) => e == 'reloaded').length,
      1,
      reason: 'one session change should cost one reload, got ${screen.events}',
    );
    expect(find.text('Joseph'), findsOneWidget);
  });

  testWidgets('a session change nobody asked for changes nothing',
      (WidgetTester tester) async {
    await pumpScreen(tester);
    _FakeScreenState screen = await screenState(tester);

    // `refresh()` is the notification the non-session state fires most often.
    state.refresh();
    await tester.pump();
    await tester.pump();

    expect(screen.events, <String>['loaded']);
  });

  group('the screens that hold a session’s data', () {
    // A structural guard, the way manifest_test.dart guards the manifest: the
    // invariant this whole change exists for is INVISIBLE to a unit test,
    // because the failure is a screen that never got wired up. Every screen
    // that holds a session's data must both watch the session and clear what
    // it holds.
    const Map<String, String> screens = <String, String>{
      'dashboard_screen.dart': 'the figures, the greeting and the shift card',
      'inventory_screen.dart': 'the product list',
      'analytics_screen.dart': 'the shop’s aggregated figures',
      'sell_screen.dart': 'the cart, which is the previous cashier’s sale',
      'settings_screen.dart': 'the roster and its PIN-reset buttons',
      'reports_screen.dart': 'the ledger rows',
      'activity_screen.dart': 'the audit log',
      'portfolio_screen.dart': 'the cross-shop KPIs',
      'shift_screen.dart': 'the shift ledger and its expected figure',
    };

    test('each one mixes in SessionRefresh, and clears as well as reloads', () {
      for (final MapEntry<String, String> screen in screens.entries) {
        final String source =
            File('lib/screens/${screen.key}').readAsStringSync();
        final String what = '${screen.key} holds ${screen.value}';

        expect(
          source,
          contains('SessionRefresh<'),
          reason: '$what but does not watch the session. '
              'Mix SessionRefresh into its State.',
        );
        expect(
          source,
          contains('void clearForSession()'),
          reason: '$what and watches the session, but never clears what it '
              'holds — a shell that outlives a session would keep showing it.',
        );
        expect(
          source,
          contains('Future<void> reloadFromSession()'),
          reason: '$what and watches the session, but never reloads — the '
              'next person in would read the previous person’s data.',
        );
      }
    });
  });
}
