// The diagnostics screen: what it does with the failure log.
//
// The value of this screen is not that it shows a list — it is what happens
// at the edges: an empty log that says "nothing is wrong" rather than an
// empty list that looks like a bug, a card that expands to reveal the trail
// that makes a crash tractable, a report that reaches the clipboard with the
// answers a developer will ask for, and a log that survives being cleared.
//
// All of it is driven through `DiagnosticsPanel`, a value-driven widget, so
// none of these tests needs a database, a shop, or a network.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/crash_log.dart';
import 'package:duka_pos/screens/diagnostics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

late AppLocalizations l10n;

CrashLogEntry entry({
  String message = 'Sync failed: no route to host',
  CrashKind kind = CrashKind.error,
  String route = '/sell',
  String actor = 'Amina',
  String action = 'sync',
  List<String> trail = const <String>['opened app', 'opened sell'],
  String? stack = '#0 syncProducts',
}) =>
    CrashLogEntry(
      kind: kind,
      message: message,
      route: route,
      actorName: actor,
      action: action,
      breadcrumbs: trail,
      stack: stack,
      at: '2026-10-10T09:00:00.000',
    );

/// The panel as a `home`, so the harness supplies the theme, the locales and
/// the MediaQuery rather than a second MaterialApp doing it differently.
Widget panelHome({
  List<CrashLogEntry> entries = const <CrashLogEntry>[],
  bool loading = false,
  Future<void> Function()? onClear,
  Future<void> Function()? onCopyReport,
  Future<void> Function()? onRefresh,
  String? message,
}) =>
    Scaffold(
      body: DiagnosticsPanel(
        entries: entries,
        loading: loading,
        retainedRows: 200,
        message: message,
        onClear: onClear ?? () async {},
        onCopyReport: onCopyReport ?? () async {},
        onRefresh: onRefresh ?? () async {},
      ),
    );

void main() {
  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  group('an empty log', () {
    testWidgets('says nothing is wrong, rather than showing an empty list',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: panelHome());

      // The empty state is a statement ("nothing has gone wrong"), not a blank
      // space that reads as a bug.
      expect(find.text(l10n.diagnosticsEmptyTitle), findsOneWidget);
      expect(find.text(l10n.diagnosticsEmptyMessage), findsOneWidget);
      expect(find.text(l10n.diagnosticsCopyReport), findsOneWidget);
      // Nothing to copy from an empty log, so the action is offered disabled
      // rather than being hidden: a button that vanishes is a button that
      // looks like the feature does not exist.
      final OutlinedButton copy = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, l10n.diagnosticsCopyReport),
      );
      expect(copy.enabled, isFalse);
    });

    testWidgets('offers a refresh from the empty state', (tester) async {
      tester.useDevice(Device.small);
      var refreshes = 0;
      await tester.pumpApp(
        home: panelHome(onRefresh: () async => refreshes += 1),
      );
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionRefresh));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
    });
  });

  group('a log that has something in it', () {
    testWidgets('shows the count and the cap together', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: panelHome(entries: <CrashLogEntry>[entry()]));

      // "1 failure kept — the last 2 weeks, newer than 200 rows are not kept":
      // the cap is on screen so a shop can tell a trimmed log from a gap.
      expect(find.text(l10n.diagnosticsRecentCount(200, 1, 2)), findsOneWidget);
    });

    testWidgets(
        'reconstructs the failure: route, actor, and what was happening',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: panelHome(entries: <CrashLogEntry>[entry()]));

      // The one line that turns a crash into a diagnosis.
      expect(
        find.text(l10n.diagnosticsEntryContext('sync', 'Amina', '/sell')),
        findsOneWidget,
      );
      tester.expectNoOverflow('diagnostics with one crash');
    });

    testWidgets('keeps the trail and the stack until the card is opened',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: panelHome(entries: <CrashLogEntry>[entry()]));

      // Collapsed, because a stack trace is five screens high and a list of
      // failures is not a list of stack traces.
      expect(find.text(l10n.diagnosticsTrailTitle), findsNothing);
      expect(find.text('#0 syncProducts'), findsNothing);

      await tester.tap(
          find.text(l10n.diagnosticsEntryContext('sync', 'Amina', '/sell')));
      await tester.pumpAndSettle();

      // The trail is a sentence, not three rows.
      expect(
        find.text(l10n.diagnosticsTrailTitle),
        findsOneWidget,
      );
      expect(find.text('opened app › opened sell'), findsOneWidget);
      expect(find.text('#0 syncProducts'), findsOneWidget);
    });

    testWidgets('collapses again on a second tap', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: panelHome(entries: <CrashLogEntry>[entry()]));
      await tester.tap(
          find.text(l10n.diagnosticsEntryContext('sync', 'Amina', '/sell')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.text(l10n.diagnosticsEntryContext('sync', 'Amina', '/sell')));
      await tester.pumpAndSettle();
      expect(find.text('#0 syncProducts'), findsNothing);
    });

    testWidgets('reads an entry with no trail, no route and no stack',
        (tester) async {
      // A row written by an older version of the app must still read; a card
      // that renders "on null · null · null" is worse than no card.
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: panelHome(
          entries: <CrashLogEntry>[
            CrashLogEntry(
              kind: CrashKind.warning,
              message: 'Queued while offline',
              at: '2026-10-10T09:00:00.000',
            ),
          ],
        ),
      );

      expect(
        find.text(
          l10n.diagnosticsEntryContext(
            l10n.diagnosticsActionUnknown,
            l10n.diagnosticsActorUnknown,
            l10n.diagnosticsRouteUnknown,
          ),
        ),
        findsOneWidget,
      );
      tester.expectNoOverflow('diagnostics with a sparse entry');
    });

    testWidgets('uses a different shape per kind, not only a different colour',
        (tester) async {
      // Non-colour redundancy: a colour-blind reader must still tell a crash
      // from a notice.
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: panelHome(
          entries: <CrashLogEntry>[
            entry(message: 'a crash', kind: CrashKind.crash),
            entry(message: 'a warning', kind: CrashKind.warning),
          ],
        ),
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });

  group('the two actions', () {
    testWidgets('copy is delegated: the panel has no clipboard of its own',
        (tester) async {
      // The panel reports an intent; what the report contains is the caller's
      // business, which is why the screen owns the text and the clipboard.
      tester.useDevice(Device.small);
      var copies = 0;
      await tester.pumpApp(
        home: panelHome(
          entries: <CrashLogEntry>[entry()],
          onCopyReport: () async => copies += 1,
        ),
      );
      await tester
          .tap(find.widgetWithText(OutlinedButton, l10n.diagnosticsCopyReport));
      await tester.pumpAndSettle();
      expect(copies, 1);
    });

    testWidgets('clear is offered, and the caller decides what it means',
        (tester) async {
      tester.useDevice(Device.small);
      var cleared = 0;
      await tester.pumpApp(
        home: panelHome(
            entries: <CrashLogEntry>[entry()],
            onClear: () async => cleared += 1),
      );
      await tester
          .tap(find.widgetWithText(OutlinedButton, l10n.diagnosticsClear));
      await tester.pumpAndSettle();
      expect(cleared, 1);
    });
  });

  group('the panel at the extremes of the matrix', () {
    for (final Device device in Device.all) {
      testWidgets('fits on ${device.name} at 2.0x text', (tester) async {
        tester.useDevice(device);
        await tester.pumpApp(
          home: panelHome(
            entries: <CrashLogEntry>[
              entry(
                message:
                    'Sync failed: no route to host while pushing inventory',
                trail: const <String>[
                  'opened app',
                  'opened inventory',
                  'imported 40 rows',
                  'opened sync',
                ],
              ),
            ],
          ),
          textScaler: TextScaler.linear(2.0),
        );

        // With the card open, so the trail, the context line and the buttons
        // are all on screen at the largest text scale the app supports.
        await tester.tap(
          find.text(l10n.diagnosticsEntryContext('sync', 'Amina', '/sell')),
        );
        await tester.pumpAndSettle();

        tester.expectNoOverflow(
            'diagnostics collapsed at 2.0x on ${device.name}');
      });
    }
  });

  group('the screen wires the log through', () {
    testWidgets('clears through a confirmation, then empties', (tester) async {
      tester.useDevice(Device.small);
      var loads = 0;
      var clears = 0;
      List<CrashLogEntry> log = <CrashLogEntry>[entry()];

      await tester.pumpApp(
        home: DiagnosticsScreen(
          loadEntries: () async {
            loads += 1;
            return log;
          },
          onClearLog: () async {
            clears += 1;
            log = <CrashLogEntry>[];
          },
          environment: const <String, String>{'platform': 'android'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.diagnosticsRecentCount(200, 1, 2)), findsOneWidget);

      // A confirmation first: the log is the diagnosis, and losing it is not
      // recoverable from the phone.
      await tester
          .tap(find.widgetWithText(OutlinedButton, l10n.diagnosticsClear));
      await tester.pumpAndSettle();
      expect(find.text(l10n.diagnosticsClearConfirmTitle), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, l10n.actionConfirm));
      await tester.pumpAndSettle();

      expect(clears, 1);
      // Reloaded, so the shop sees the log it now has rather than the one it
      // used to have.
      expect(loads, 2);
      expect(find.text(l10n.diagnosticsCleared), findsOneWidget);
      expect(find.text(l10n.diagnosticsEmptyTitle), findsOneWidget);
    });

    testWidgets('dismissing the confirmation leaves the log alone',
        (tester) async {
      tester.useDevice(Device.small);
      var clears = 0;

      await tester.pumpApp(
        home: DiagnosticsScreen(
          loadEntries: () async => <CrashLogEntry>[entry()],
          onClearLog: () async => clears += 1,
          environment: const <String, String>{'platform': 'android'},
        ),
      );
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(OutlinedButton, l10n.diagnosticsClear));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l10n.actionCancel));
      await tester.pumpAndSettle();

      expect(clears, 0);
      expect(find.text(l10n.diagnosticsClearConfirmTitle), findsNothing);
      expect(find.text(l10n.diagnosticsRecentCount(200, 1, 2)), findsOneWidget);
    });

    testWidgets('puts the environment in the report, not at the bottom',
        (tester) async {
      // The first question back from a developer is always "which build".
      tester.useDevice(Device.small);
      final List<MethodCall> log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        log.add(call);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpApp(
        home: DiagnosticsScreen(
          loadEntries: () async => <CrashLogEntry>[entry()],
          onClearLog: () async {},
          environment: const <String, String>{
            'platform': 'android',
            'version': 'Tiramisu',
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(OutlinedButton, l10n.diagnosticsCopyReport));
      await tester.pumpAndSettle();

      expect(log.map((call) => call.method), contains('Clipboard.setData'));
    });
  });
}
