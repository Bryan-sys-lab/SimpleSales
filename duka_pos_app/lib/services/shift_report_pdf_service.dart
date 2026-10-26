import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import '../screens/reports_shifts.dart';
import '../utils/money.dart';

/// Writes a closed shift's immutable Z snapshot locally.
class ShiftReportPdfService {
  const ShiftReportPdfService();

  Future<File> export({
    required ShiftReportSnapshot report,
    String shopName = 'SimpleSales',
  }) async {
    final document =
        pw.Document(title: '$shopName Z report ${report.reportNumber}');
    document.addPage(pw.Page(
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(shopName,
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('Z report #${report.reportNumber}'),
          pw.Text(report.endedAt),
          pw.SizedBox(height: 16),
          for (final row in <List<String>>[
            <String>['Sales', '${report.saleCount}'],
            <String>['Gross', formatMoney(report.gross)],
            <String>['Profit', formatMoney(report.profit)],
            <String>['Taxable sales', formatMoney(report.taxable)],
            <String>['VAT', formatMoney(report.vat)],
            <String>['Expected cash', formatMoney(report.expectedCash)],
            <String>['Counted cash', formatMoney(report.countedCash)],
            <String>['Variance', formatMoney(report.variance)],
          ])
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: <pw.Widget>[pw.Text(row[0]), pw.Text(row[1])]),
          pw.SizedBox(height: 16),
          pw.Text(report.kraActivated
              ? 'KRA comparison: activated'
              : 'KRA comparison: not activated; this is a local report.'),
          pw.SizedBox(height: 8),
          pw.Text(
              'Generated locally ${DateFormat('d MMM yyyy, HH:mm').format(DateTime.now())}'),
        ],
      ),
    ));
    final directory = await getApplicationDocumentsDirectory();
    final exportDirectory = Directory('${directory.path}/reports');
    await exportDirectory.create(recursive: true);
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    final file = File(
        '${exportDirectory.path}/z-report-${report.reportNumber}-$stamp.pdf');
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }
}
