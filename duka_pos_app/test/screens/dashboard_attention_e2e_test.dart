// End-to-end style widget tests for the dashboard attention card: the one
// screen a till opens to see what needs fixing, and the (X) button that lets
// the owner dismiss a category they have read.
//
// These pump the real card through the app's harness (themes, localizations,
// device surface) and drive a real tap on the cancel (X) button.
import 'package:duka_pos/screens/dashboard_attention.dart';
import 'package:duka_pos/services/analytics.dart';
import '../support/harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a [DashboardAttentionCard] inside a tiny stateful owner so that
/// tapping the (X) button really dismisses (setState rebuilds the card with
/// the updated `dismissed` set — exactly as the dashboard screen does).
class _DismissableCard extends StatefulWidget {
  const _DismissableCard({
    required this.summary,
    required this.canFixEtims,
  });

  final AttentionSummary summary;
  final bool canFixEtims;

  @override
  State<_DismissableCard> createState() => _DismissableCardState();
}

class _DismissableCardState extends State<_DismissableCard> {
  final dismissed = <String>{};

  @override
  Widget build(BuildContext context) {
    return DashboardAttentionCard(
      summary: widget.summary,
      canFixEtims: widget.canFixEtims,
      onRetryEtims: () {},
      onOpenEtimsSettings: () {},
      dismissed: dismissed,
      onDismiss: (id) => setState(() => dismissed.add(id)),
    );
  }
}

void main() {
  group('DashboardAttentionCard', () {
    AttentionSummary summaryWith(int rejectedEtims,
            {int pendingEtims = 0,
            int unverifiedPayments = 0,
            int openImportProblems = 0}) =>
        AttentionSummary(
          pendingEtims: pendingEtims,
          rejectedEtims: rejectedEtims,
          openImportProblems: openImportProblems,
          unverifiedPayments: unverifiedPayments,
        );

    testWidgets('renders each open problem as its own row', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _DismissableCard(
          summary: summaryWith(2, pendingEtims: 1, unverifiedPayments: 3),
          canFixEtims: false,
        ),
      );

      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('KRA refused 2 receipts'), findsOneWidget);
      expect(find.text('Waiting on KRA for 1 receipt'), findsOneWidget);
      expect(find.text('3 payments not confirmed'), findsOneWidget);
    });

    testWidgets('hides every row once its category is dismissed',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _DismissableCard(
          summary: summaryWith(1),
          canFixEtims: false,
        ),
      );
      await tester.pump();

      final l10n = await loadL10n();
      // Dismiss the only category through its (X) button.
      await tester.tap(find.byTooltip(l10n.attentionDismissAction).first);
      await tester.pump();

      // The header stays, but the row is gone.
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('KRA refused 1 receipt'), findsNothing);
    });

    testWidgets(
        'the cancel (X) button dismisses one category while '
        'leaving the others', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _DismissableCard(
          summary: summaryWith(1, pendingEtims: 1),
          canFixEtims: false,
        ),
      );
      await tester.pump();

      final l10n = await loadL10n();
      await tester.tap(find.byTooltip(l10n.attentionDismissAction).first);
      await tester.pump();

      expect(find.text('KRA refused 1 receipt'), findsNothing);
      expect(find.text('Waiting on KRA for 1 receipt'), findsOneWidget);
    });

    testWidgets('respects the 44px tap target floor for every action',
        (tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: _DismissableCard(
          summary: summaryWith(1),
          canFixEtims: true,
        ),
      );

      tester.expectTapTargetsMeetMinimum(find.byType(DashboardAttentionCard));
      tester.expectNoOverflow('attention card on $Device.compact');
    });
  });
}
