/// Cash-control rules kept pure so the limit boundary is testable without UI.
bool expenseApprovalRequired({
  required int amountMinor,
  required int limitMinor,
}) =>
    amountMinor > limitMinor;
