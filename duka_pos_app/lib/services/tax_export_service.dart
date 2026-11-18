import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../db/database_helper.dart';

/// Exports the local VAT return for a period as a CSV file.
///
/// This is a MANUAL export for the owner to file with KRA. It is not a filing
/// and carries no legal weight on its own. Values are in minor units (cents).
class TaxExportService {
  static Future<String> exportVatReturnCsv({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(total), 0) AS gross_minor,
        COALESCE(SUM(taxable_minor), 0) AS taxable_minor,
        COALESCE(SUM(vat_minor), 0) AS vat_minor,
        COUNT(*) AS sale_count,
        payment_method
      FROM sales
      WHERE created_at >= ? AND created_at < ? AND voided = 0
      GROUP BY payment_method
    ''', [from.toIso8601String(), to.toIso8601String()]);

    int gross = 0, taxable = 0, vat = 0, count = 0;
    final paymentMix = <String, Map<String, int>>{};
    for (final r in rows) {
      final g = (r['gross_minor'] as num?)?.toInt() ?? 0;
      final t = (r['taxable_minor'] as num?)?.toInt() ?? 0;
      final v = (r['vat_minor'] as num?)?.toInt() ?? 0;
      final c = (r['sale_count'] as num?)?.toInt() ?? 0;
      gross += g; taxable += t; vat += v; count += c;
      final method = (r['payment_method'] as String?) ?? 'cash';
      paymentMix[method] = {'gross': g, 'count': c};
    }

    final buf = StringBuffer();
    buf.writeln('VAT Return Export (LOCAL FIGURES - NOT A FILING)');
    buf.writeln('Period,${from.toIso8601String().split('T').first} to ${to.toIso8601String().split('T').first}');
    buf.writeln('Double-check all figures before filing with KRA.');
    buf.writeln('');
    buf.writeln('Field,Value (minor units)');
    buf.writeln('Gross sales,$gross');
    buf.writeln('Taxable sales,$taxable');
    buf.writeln('VAT collected,$vat');
    buf.writeln('Sale count,$count');
    buf.writeln('');
    buf.writeln('Payment method,Gross (minor),Count');
    for (final e in paymentMix.entries) {
      buf.writeln('${e.key},${e.value['gross']},${e.value['count']}');
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/vat-return-${from.toIso8601String().split('T').first}.csv');
    await file.writeAsString(buf.toString());
    return file.path;
  }
}
