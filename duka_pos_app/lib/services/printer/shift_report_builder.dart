import 'receipt_builder.dart';
import '../../screens/reports_shifts.dart';
import '../../utils/money.dart';

/// Pure, fixed-width layout for an immutable local Z report.
List<ReceiptLine> buildShiftReportLines(
  ShiftReportSnapshot report,
) {
  final lines = <ReceiptLine>[
    const ReceiptText('Z REPORT',
        alignment: ReceiptAlignment.center, bold: true),
    ReceiptColumns('Report No.', '${report.reportNumber}'),
    ReceiptColumns('Closed', report.endedAt),
    const ReceiptRule(),
    ReceiptColumns('Sales', '${report.saleCount}'),
    ReceiptColumns('Gross', formatMoney(report.gross)),
    ReceiptColumns('Profit', formatMoney(report.profit)),
    ReceiptColumns('Taxable', formatMoney(report.taxable)),
    ReceiptColumns('VAT', formatMoney(report.vat)),
    ReceiptRule(),
    ReceiptColumns('Expected cash', formatMoney(report.expectedCash)),
    ReceiptColumns('Counted cash', formatMoney(report.countedCash)),
    ReceiptColumns('Variance', formatMoney(report.variance)),
  ];
  if (report.paymentMix.isNotEmpty) {
    lines.add(const ReceiptText('Payment mix', bold: true));
    for (final entry in report.paymentMix.entries) {
      lines.add(
          ReceiptColumns(entry.key, formatMoney(Money.fromMinor(entry.value))));
    }
  }
  lines.add(const ReceiptRule());
  lines.add(ReceiptText(
    report.kraActivated
        ? 'KRA comparison: activated'
        : 'KRA comparison: not activated',
    alignment: ReceiptAlignment.center,
  ));
  lines.add(const ReceiptFeed(2));
  return lines;
}
