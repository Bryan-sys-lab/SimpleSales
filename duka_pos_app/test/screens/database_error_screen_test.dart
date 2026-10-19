// The recovery screen: what a shop owner can DO when the app cannot open its
// data.
//
// The bug this file exists to prevent: the screen said what had happened and
// then stopped. It was a dead end with a paragraph on it — the owner was told
// their data could not be opened, and given no way to find out whether that
// was still true, no way to try again, and no way to get the diagnostics to
// whoever could help.
//
// The condition is often temporary. A full disk is freed, a restored backup
// lands, a working directory changes under an update. A screen that can only
// report a failure has given up on the one thing it could still have done.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/database_error_screen.dart';
import 'package:duka_pos/services/failure_recorder.dart';

import '../support/harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  testWidgets('offers a way forward, not just a description',
      (WidgetTester tester) async {
    await tester.pumpApp(home: const DatabaseErrorScreen());

    expect(find.text(l10n.databaseErrorTitle), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, l10n.databaseErrorRetryAction),
      findsOneWidget,
      reason: 'a screen that cannot open its data must let the owner try again',
    );
    expect(
      find.widgetWithText(OutlinedButton, l10n.databaseErrorShareAction),
      findsOneWidget,
      reason: 'the diagnostics are on the phone and support needs them',
    );
  });

  testWidgets('the diagnostics carry the trail to support',
      (WidgetTester tester) async {
    // The clipboard is a platform channel, and the test engine has no
    // implementation of `Clipboard.getData` to read it back — so the channel
    // is mocked and the TEXT is what is asserted. Asking the engine for the
    // clipboard in a widget test hangs.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    failureRecorder.trail.jot('opened the till');
    failureRecorder.trail.jot('broke the database');

    await tester.pumpApp(home: const DatabaseErrorScreen());
    await tester.tap(
      find.widgetWithText(OutlinedButton, l10n.databaseErrorShareAction),
    );
    await tester.pump();

    expect(copied, isNotNull);
    expect(copied, contains('SimpleSales failure report'));
    expect(copied, contains('broke the database'));
  });

  testWidgets('a retry that fails says so, out loud',
      (WidgetTester tester) async {
    // The database cannot open in a plain widget test — there is no platform
    // channel behind it — so the retry fails, which is the case worth seeing:
    // the owner must not be left staring at a button that did nothing.
    await tester.pumpApp(home: const DatabaseErrorScreen());

    await tester.tap(
      find.widgetWithText(FilledButton, l10n.databaseErrorRetryAction),
    );
    // The retry opens a database that cannot open, and the open does not
    // answer — so the retry's own timeout is what ends it. The clock is
    // advanced past that timeout to reach the answer.
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();

    expect(find.text(l10n.databaseErrorRetryFailed), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the screen fits a small phone at large text',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);

    await tester.pumpApp(
      home: const DatabaseErrorScreen(),
      textScaler: TextScaler.linear(2.0),
    );
    await tester.pump();

    tester.expectNoOverflow('the recovery screen on a 320dp phone at 2x text');
  });
}
