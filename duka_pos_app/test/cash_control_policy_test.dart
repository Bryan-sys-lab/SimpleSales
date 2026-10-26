import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/services/cash_control_policy.dart';

void main() {
  test('cashier payout approval starts above the configured limit', () {
    expect(
      expenseApprovalRequired(amountMinor: 500000, limitMinor: 500000),
      isFalse,
    );
    expect(
      expenseApprovalRequired(amountMinor: 500001, limitMinor: 500000),
      isTrue,
    );
  });
}
