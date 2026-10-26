import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import '../utils/money.dart';

/// Writes a receipt snapshot locally. It never needs the backend, so a seller
/// can hand over a PDF while the till is offline.
class ReceiptPdfService {
  const ReceiptPdfService();

  Future<File> write({
    required Sale sale,
    required String shopName,
  }) async {
    final document = pw.Document(title: 'Receipt ${sale.id ?? ''}');
    final issued = DateTime.tryParse(sale.createdAt)?.toLocal();
    document.addPage(
      pw.Page(
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(shopName,
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('Receipt ${sale.id ?? ''}'),
            if (issued != null)
              pw.Text(DateFormat('d MMM yyyy, HH:mm').format(issued)),
            pw.SizedBox(height: 16),
            for (final item in sale.items)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: <pw.Widget>[
                  pw.Expanded(
                      child: pw.Text('${item.productName} × ${item.qty}')),
                  pw.Text(formatMoney(item.total)),
                ],
              ),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                pw.Text('Total',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(formatMoney(sale.total),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text('Paid by ${sale.paymentMethod}'),
          ],
        ),
      ),
    );
    final directory = await getApplicationDocumentsDirectory();
    final exportDirectory = Directory('${directory.path}/receipts');
    await exportDirectory.create(recursive: true);
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    final file = File('${exportDirectory.path}/receipt-$stamp.pdf');
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }
}
