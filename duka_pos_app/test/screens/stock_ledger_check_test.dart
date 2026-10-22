// The stock ledger check on the Diagnostics screen.
//
// The check is the one place a shop can ask "does the number on the shelf
// agree with the history of how it got there?" — so its edges matter more
// than its happy path:
//
//   1. A check that found nothing must SAY it found nothing. Silence is
//      indistinguishable from a check that never ran.
//   2. A difference must name the product and BOTH numbers. One of them is a
//      lie, and the owner cannot tell which without the other.
//   3. The fix is the owner's alone. A manager may SEE the difference — it is
//      information they need — but writing the correction is not theirs to do.
//
// The widget is driven through its own inputs, so none of these needs a
// database, a shop, or a network.

import 'dart:async';

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/stock_movement.dart';
import 'package:duka_pos/screens/diagnostics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

late AppLocalizations l10n;

LedgerDifference difference({
  int productId = 4,
  String productName = 'Cola 350ml',
  double counted = 20,
  double ledger = 24,
}) =>
    LedgerDifference(
      productId: productId,
      productName: productName,
      counted: counted,
      ledger: ledger,
    );

Widget checkHome({
  List<LedgerDifference> differences = const <LedgerDifference>[],
  bool canRepair = true,
  Future<bool> Function(LedgerDifference)? repair,
}) =>
    Scaffold(
      body: StockLedgerCheck(
        loadDifferences: () async => differences,
        repair: repair ?? (LedgerDifference _) async => true,
        canRepair: canRepair,
      ),
    );

void main() {
  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  group('the stock ledger check', () {
    testWidgets('a healthy ledger says so, in words',
        (WidgetTester tester) async {
      await tester.pumpApp(home: checkHome());

      expect(find.text(l10n.diagnosticsLedgerHealthy), findsOneWidget);
      expect(find.text(l10n.diagnosticsLedgerDifferences(1)), findsNothing,
          reason: 'a clean ledger must not also claim something disagrees');
    });

    testWidgets('a difference names the product and both numbers',
        (WidgetTester tester) async {
      await tester.pumpApp(
          home: checkHome(differences: <LedgerDifference>[difference()]));

      await tester.pumpAndSettle();

      expect(
        find.text(
            l10n.diagnosticsLedgerDifferenceRow('20', '24', 'Cola 350ml')),
        findsOneWidget,
      );
      expect(find.text(l10n.diagnosticsLedgerDifferences(1)), findsOneWidget);
    });

    testWidgets('a difference offers the fix to the owner',
        (WidgetTester tester) async {
      var repaired = false;
      await tester.pumpApp(
        home: checkHome(
          differences: <LedgerDifference>[difference()],
          repair: (LedgerDifference d) async {
            repaired = true;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.diagnosticsLedgerRepairAction));
      await tester.pumpAndSettle();

      expect(repaired, isTrue);
      expect(find.text(l10n.diagnosticsLedgerRepaired('Cola 350ml')),
          findsOneWidget);
    });

    testWidgets('a difference offers NO fix to anyone else',
        (WidgetTester tester) async {
      await tester.pumpApp(
        home: checkHome(
          differences: <LedgerDifference>[difference()],
          canRepair: false,
        ),
      );
      await tester.pumpAndSettle();

      // The difference is still VISIBLE — a manager needs to know the books
      // disagree — but the button that changes the books is not theirs.
      expect(
          find.text(
              l10n.diagnosticsLedgerDifferenceRow('20', '24', 'Cola 350ml')),
          findsOneWidget);
      expect(find.text(l10n.diagnosticsLedgerRepairAction), findsNothing);
    });

    testWidgets('a failed correction is reported, not swallowed',
        (WidgetTester tester) async {
      await tester.pumpApp(
        home: checkHome(
          differences: <LedgerDifference>[difference()],
          repair: (LedgerDifference _) async => false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.diagnosticsLedgerRepairAction));
      await tester.pumpAndSettle();

      expect(find.text(l10n.diagnosticsLedgerRepairFailed('Cola 350ml')),
          findsOneWidget);
    });

    testWidgets('the check says it is checking, before it answers',
        (WidgetTester tester) async {
      // A loader that never answers, so the "checking" state is a state the
      // test can actually see. With a loader that returns at once the check
      // answers in the first frame, and there is nothing to assert.
      final Completer<List<LedgerDifference>> pending =
          Completer<List<LedgerDifference>>();
      await tester.pumpApp(
        home: Scaffold(
          body: StockLedgerCheck(
            loadDifferences: () => pending.future,
            repair: (LedgerDifference _) async => true,
          ),
        ),
      );

      expect(find.text(l10n.diagnosticsLedgerChecking), findsOneWidget);
      expect(find.text(l10n.diagnosticsLedgerHealthy), findsNothing,
          reason: 'a check that has not answered must not claim a result');
    });
  });
}
