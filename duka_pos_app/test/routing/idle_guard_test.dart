// The idle guard, and the shopkeeper it used to sign out.
//
// The bug: a four-minute window reset only by pointer events. A till signed out
// someone who was mid-conversation with a customer, answered the phone, or was
// scanning a basket — because none of those are pointer events, and a scanner in
// particular types into a text field without ever touching the screen. The
// session went, and the interrupted work went with it.
//
// The window is a parameter so a test drives it with a real clock rather than
// waiting fifteen minutes for the bug to come back.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:duka_pos/routing/idle_guard.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/live_channel_service.dart';

void main() {
  late AppState state;
  late LiveChannelService channel;

  setUp(() {
    state = AppState();
    state.signIn('Amina', asOwner: false);
    channel = LiveChannelService();
  });

  Widget host(Widget child, Duration timeout) => MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<LiveChannelService>.value(value: channel),
        ],
        child: MaterialApp(
          home: IdleGuard(timeout: timeout, child: child),
        ),
      );

  testWidgets('a till untouched for the window signs itself out',
      (WidgetTester tester) async {
    await tester
        .pumpWidget(host(const SizedBox(), const Duration(minutes: 15)));

    expect(state.isSignedIn, isTrue);
    await tester.pump(const Duration(minutes: 14, seconds: 59));
    expect(state.isSignedIn, isTrue, reason: 'still inside the window');
    await tester.pump(const Duration(seconds: 2));
    expect(state.isSignedIn, isFalse,
        reason: 'past it, the till is unattended');
  });

  testWidgets('a tap resets the clock, so an active till never signs out',
      (WidgetTester tester) async {
    await tester.pumpWidget(host(
      GestureDetector(
        onTap: () {},
        child: const SizedBox(width: 100, height: 100),
      ),
      const Duration(minutes: 15),
    ));

    await tester.pump(const Duration(minutes: 10));
    await tester.tap(find.byType(GestureDetector));
    await tester.pump(const Duration(minutes: 10));
    await tester.pump(const Duration(minutes: 4, seconds: 59));

    expect(state.isSignedIn, isTrue,
        reason: 'ten minutes of work, a tap, ten more: no sign-out');
  });

  testWidgets('a sale recorded on the shop keeps the till signed in',
      (WidgetTester tester) async {
    // The scanner case: a barcode scanner types into a text field and produces
    // no pointer events at all, so the sale it rings up is the only signal the
    // shop is being used. Without it the till signs out mid-sale.
    await tester
        .pumpWidget(host(const SizedBox(), const Duration(minutes: 15)));

    await tester.pump(const Duration(minutes: 10));
    // What every recorded write on the shop does: publishes on the channel.
    channel.notifyListeners();
    await tester.pump(const Duration(minutes: 10));
    await tester.pump(const Duration(minutes: 4, seconds: 59));

    expect(state.isSignedIn, isTrue,
        reason: 'a till ringing up sales is not unattended');
  });

  testWidgets('returning to the foreground is not idleness',
      (WidgetTester tester) async {
    await tester
        .pumpWidget(host(const SizedBox(), const Duration(minutes: 15)));

    // A phone call, a pocketed screen: four minutes with the app not
    // foreground, and the user comes back to their work still signed in.
    await tester.pump(const Duration(minutes: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(minutes: 14, seconds: 59));

    expect(state.isSignedIn, isTrue,
        reason: 'the interruption was the phone, not the shop');
  });

  testWidgets('a guard behind the window stops caring',
      (WidgetTester tester) async {
    // The timer is per-guard, so two tills on one device do not sign each other
    // out, and a disposed guard cannot fire into a dead tree.
    await tester
        .pumpWidget(host(const SizedBox(), const Duration(minutes: 15)));
    await tester
        .pumpWidget(host(const SizedBox(), const Duration(minutes: 15)));

    await tester.pump(const Duration(minutes: 16));

    expect(state.isSignedIn, isFalse);
  });
}
