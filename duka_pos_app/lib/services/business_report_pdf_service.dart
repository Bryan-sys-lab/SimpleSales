import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/database_helper.dart';
import '../models/audit_log.dart';
import '../services/analytics.dart';
import '../utils/money.dart';

/// Builds the owner's business report entirely from the local ledger.
///
/// This is deliberately a file writer, not a cloud report client: an owner can
/// export while offline, and the PDF is a point-in-time local artifact that
/// includes the figures and the audit events used to explain them.
class BusinessReportPdfService {
  BusinessReportPdfService({DatabaseHelper? database})
      : _database = database ?? DatabaseHelper.instance;

  final DatabaseHelper _database;

  Future<File> export({
    required DateTime since,
    DateTime? until,
    String shopName = 'SimpleSales',
  }) async {
    final DateTime end = until ?? DateTime.now();
    final results = await Future.wait<Object>([
      _database.salesTotalsFor(since: since, until: end),
      _database.salesByDay(since: since, until: end),
      _database.topProducts(since: since, until: end, limit: 12),
      _database.salesByPaymentMethod(since: since, until: end),
      _database.auditLog(AuditLogQuery(
        since: since.toIso8601String(),
        until: end.toIso8601String(),
        // The report is the owner's local audit export. Use the same bounded
        // retention window as the database instead of silently omitting all
        // but the latest 30 actions from a one-year report.
        limit: DatabaseHelper.auditRetainRows,
      )),
    ]);
    final totals = results[0] as DailyTotals;
    final days = results[1] as List<DateBucket>;
    final products = results[2] as List<ProductSalesRow>;
    final payments = results[3] as List<PaymentMixRow>;
    final audit = results[4] as List<AuditLogEntry>;

    final document = pw.Document(title: '$shopName business report');
    final dateFormat = DateFormat('d MMM yyyy');
    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: pw.EdgeInsets.all(32),
          theme: pw.ThemeData(defaultTextStyle: pw.TextStyle(fontSize: 9)),
        ),
        header: (_) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(shopName,
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('Business report'),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}'),
        ),
        build: (_) => <pw.Widget>[
          pw.SizedBox(height: 12),
          pw.Text('${dateFormat.format(since)} – ${dateFormat.format(end)}'),
          pw.SizedBox(height: 18),
          pw.Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <pw.Widget>[
              _metric('Sales', formatMoney(totals.total)),
              _metric('Profit', formatMoney(totals.profit)),
              _metric('Expenses',
                  formatMoney(Money.fromMinor(totals.expensesMinor))),
              _metric('Net profit', formatMoney(totals.netProfit)),
              _metric('Transactions', '${totals.transactions}'),
              _metric('Average sale', formatMoney(totals.averageBasket)),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text('Sales trend', style: _heading),
          pw.SizedBox(height: 8),
          // A year of daily rows is exact data but not a readable PDF chart;
          // merge consecutive buckets without dropping any sales.
          _barChart(mergeDateBuckets(days, 31)),
          pw.SizedBox(height: 20),
          pw.Text('Top products', style: _heading),
          _table(<String>[
            'Product',
            'Units',
            'Sales',
            'Profit'
          ], <List<String>>[
            for (final row in products)
              <String>[
                row.productName,
                row.units
                    .toStringAsFixed(row.units == row.units.round() ? 0 : 1),
                formatMoney(row.revenue),
                formatMoney(row.profit),
              ],
          ]),
          pw.SizedBox(height: 18),
          pw.Text('Payment mix', style: _heading),
          _table(<String>[
            'Method',
            'Transactions',
            'Sales'
          ], <List<String>>[
            for (final row in payments)
              <String>[
                row.method,
                '${row.transactions}',
                formatMoney(row.sales)
              ],
          ]),
          pw.SizedBox(height: 18),
          pw.Text('Audit trail', style: _heading),
          _table(<String>[
            'When',
            'Actor',
            'Action',
            'Detail'
          ], <List<String>>[
            for (final row in audit)
              <String>[
                DateFormat('d MMM HH:mm')
                    .format(DateTime.tryParse(row.createdAt) ?? since),
                row.actorName,
                row.action.wire,
                row.detail ?? '',
              ],
          ]),
        ],
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final exportDirectory = Directory('${directory.path}/reports');
    await exportDirectory.create(recursive: true);
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    final file = File('${exportDirectory.path}/business-report-$stamp.pdf');
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }

  static final pw.TextStyle _heading =
      pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);

  static pw.Widget _metric(String label, String value) => pw.Container(
        width: 120,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(label, style: pw.TextStyle(color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  static pw.Widget _barChart(List<DateBucket> days) {
    final max = days.fold<double>(
        0,
        (value, day) =>
            value > day.salesMinor ? value : day.salesMinor.toDouble());
    if (days.isEmpty || max <= 0) {
      return pw.Text('No sales recorded in this period.');
    }
    return pw.SizedBox(
      height: 130,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: <pw.Widget>[
          for (final day in days)
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: <pw.Widget>[
                    pw.Container(
                      height: 88 * day.salesMinor / max,
                      color: PdfColors.blueGrey700,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(day.label, style: pw.TextStyle(fontSize: 6)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _table(List<String> headers, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellPadding: const pw.EdgeInsets.all(5),
        border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
      );
}
