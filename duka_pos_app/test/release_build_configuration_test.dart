// A release build with no server address still starts.
//
// ## WHAT THIS PINS
//
// A release build that was never given a backend URL, or an OIDC issuer, used
// to REFUSE TO OPEN. The app showed a dead-end screen and the till could not
// sell, so the person shipping the build could never see it, and the shop
// could never try it before the backend work landed.
//
// The build now starts. The till sells, the stock moves, the reports are
// right, and the one screen that talks about the build says which parts will
// not work until the addresses are supplied.
//
// Two things can undo that, and both are pinned here:
//
//   * Someone re-adds a gate in `main()` — so the startup path is read and
//     checked, the same way `release_workflow_test.dart` reads and RUNS the
//     release workflow's shell.
//   * The notice is shown on a build that is perfectly fine, or hidden on one
//     that is not — so the notice is rendered, both ways.

import 'dart:io';

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/services/build_configuration.dart';
import 'package:duka_pos/ui/components/build_configuration_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  group('the startup path', () {
    // The source of `main()` is read, because the decision it makes — start
    // the app, or refuse — happens before any widget exists and there is no
    // other way to ask the question.
    //
    // The rule checked here is narrow and exact: between the point where the
    // build's configuration is read and the point where the app is run, there
    // must be no `return`. A `return` in that window is a gate: the app stops
    // before it starts, and the phone shows nothing but the gate's screen.
    test('an incomplete build does not stop the app from starting', () {
      final String source = File('lib/main.dart').readAsStringSync();

      final int checked = source.indexOf('BuildConfiguration.problem');
      expect(
        checked,
        isNot(-1),
        reason: 'main() must still LOOK at the build\'s configuration — the '
            'notice in Diagnostics depends on it',
      );

      final int started = source.indexOf('runApp(const DukaPosApp()');
      expect(
        started,
        isNot(-1),
        reason: 'main() must run the app',
      );
      expect(
        started,
        greaterThan(checked),
        reason: 'the app is run after the configuration is read',
      );

      // The window between the check and the run: no early exit.
      final String window = source.substring(checked, started);
      expect(
        window.contains('return;'),
        isFalse,
        reason: 'nothing may return between reading the build\'s '
            'configuration and running the app — that is a gate, and the gate '
            'is what this test exists to keep out:\n$window',
      );
    });

    test('the app no longer has a screen that replaces it', () {
      final String source = File('lib/main.dart').readAsStringSync();
      expect(
        source.contains('ConfigurationErrorScreen'),
        isFalse,
        reason: 'the dead-end configuration screen is gone; the notice in '
            'Diagnostics says the same thing without stopping the till',
      );
      expect(
        File('lib/screens/configuration_error_screen.dart').existsSync(),
        isFalse,
        reason: 'the dead-end configuration screen is gone',
      );
    });

    test('the services no longer throw on a missing address', () {
      // The old rule was a throw, called from an `assertConfigured` that
      // existed only to stop the app. Both of those are gone; what is left is
      // a question, and a question is safe to ask.
      for (final String path in <String>[
        'lib/services/backend_service.dart',
        'lib/services/oidc_service.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        expect(
          source.contains('assertConfigured'),
          isFalse,
          reason: '$path must not carry a throwing configuration check: a '
              'missing address is a local-only build, not a broken one',
        );
      }
    });
  });

  group('the configuration notice', () {
    testWidgets('it says what is missing and what still works', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        home: const Scaffold(
          body: BuildConfigurationNotice(
            problem: 'BACKEND_URL was never set.',
          ),
        ),
      );

      expect(find.text('This build is not configured'), findsOneWidget);
      expect(
        find.textContaining('Selling, stock and reports work as usual'),
        findsOneWidget,
      );
      expect(find.textContaining('BACKEND_URL was never set.'), findsOneWidget);
      // The technical detail is on screen AND copyable, because this screen
      // is read by whoever builds the release.
      expect(find.text('Copy the details'), findsOneWidget);
    });

    testWidgets('copying puts the detail on the clipboard', (
      WidgetTester tester,
    ) async {
      final List<String> copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text'] as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpApp(
        home: const Scaffold(
          body: BuildConfigurationNotice(
            problem: 'OIDC_ISSUER_URL was never set.',
          ),
        ),
      );

      await tester.tap(find.text('Copy the details'));
      await tester.pump();

      expect(copied, <String>['OIDC_ISSUER_URL was never set.']);
    });

    testWidgets('it fits a small phone at twice the text size', (
      WidgetTester tester,
    ) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        textScaler: const TextScaler.linear(2.0),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: BuildConfigurationNotice(
              problem: 'BACKEND_URL was never set, so this build points at '
                  'https://localhost:3000/api. Rebuild with '
                  '--dart-define=BACKEND_URL=https://your-backend/api',
            ),
          ),
        ),
      );
      tester.expectNoOverflow('the build configuration notice');
    });
  });

  group('a build that is fine', () {
    test('a debug build is never incomplete', () {
      // The rule is about RELEASE builds: localhost is exactly where the
      // development server lives, so a debug build is never "unconfigured".
      expect(BuildConfiguration.problem, isNull);
      expect(BuildConfiguration.isIncomplete, isFalse);
    });

    test('the strings for the notice exist in the catalogue', () async {
      final AppLocalizations l10n = await loadL10n();
      expect(l10n.configurationErrorTitle, isNotEmpty);
      expect(l10n.configurationNoticeBody, isNotEmpty);
      expect(l10n.configurationErrorAdvice, isNotEmpty);
      expect(l10n.configurationErrorDetail('x'), contains('x'));
    });
  });
}
