import 'package:duka_pos/models/financial_event.dart';
import 'package:duka_pos/screens/analytics_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('keeps profit, cash flow and obligations distinct',
      (WidgetTester tester) async {
    const FinancialStatement statement = FinancialStatement(
      totals: FinancialEventTotals(
        revenueMinor: 10000,
        cashInMinor: 7000,
        cashOutMinor: 2000,
        cogsMinor: 4000,
        operatingExpenseMinor: 1000,
        receivableDeltaMinor: 3000,
        payableDeltaMinor: 1500,
        customerDepositDeltaMinor: 500,
        inventoryDeltaMilliunits: 2500,
      ),
      openingCashMinor: 12000,
      openingCashIsKnown: false,
    );

    await tester.pumpApp(home: FinancialStatementCard(statement: statement));

    expect(find.text('Reconciled financial statement'), findsOneWidget);
    expect(find.text('Net profit'), findsOneWidget);
    expect(find.text('Cash flow'), findsOneWidget);
    expect(find.text('Receivables'), findsOneWidget);
    expect(find.text('Payables'), findsOneWidget);
    expect(find.textContaining('opening cash is not anchored'), findsOneWidget);
  });
}
