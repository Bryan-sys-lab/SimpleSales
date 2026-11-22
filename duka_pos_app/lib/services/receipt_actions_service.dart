import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../services/printer/printer_config.dart';
import '../services/printer/receipt_printer.dart';
import '../services/printer/receipt_builder.dart';
import 'receipt_pdf_service.dart';
import 'receipt_share_service.dart';
import '../utils/money.dart';

/// Shared receipt actions entry point. Delegates to existing services.
class ReceiptActionsService {
  ReceiptActionsService._();
  static final ReceiptActionsService instance = ReceiptActionsService._();

  Future<void> shareTextReceipt(BuildContext context, int saleId) async {
    final sale = await DatabaseHelper.instance.getSaleById(saleId);
    if (sale == null || !context.mounted) return;
    await shareSaleText(context, sale: sale);
  }

  /// Shares the immutable sale snapshot. Callers may already have the sale
  /// loaded (sale details and completion sheets do), so they do not need to
  /// perform a second read that could race a refresh.
  Future<void> shareSaleText(
    BuildContext context, {
    required Sale sale,
    String? shopName,
  }) async {
    if (!context.mounted) return;
    final recipientMasked = await askReceiptRecipient(context);
    if (!context.mounted) return;
    final state = context.read<AppState>();
    final resolvedShopName = shopName ?? state.owner?.shopName ?? 'Duka POS';
    String? link;
    final snapshot = <String, dynamic>{
      'shop_name': resolvedShopName,
      'receipt_id': sale.id,
      'staff_name': sale.staffName,
      'created_at': sale.createdAt,
      'payment_method': sale.paymentMethod,
      'total_minor': sale.total.minorUnits,
      'items': [
        for (final item in sale.items)
          {
            'name': item.productName,
            'qty': item.qty,
            'total_minor': item.total.minorUnits,
          },
      ],
    };
    try {
      final response = await BackendService.createReceiptLink(snapshot);
      final relative = response?['url'] as String?;
      if (relative != null) {
        link = BackendService.backendUrl.replaceFirst(RegExp(r'/api$'), '') +
            relative;
        if (sale.id != null) {
          await DatabaseHelper.instance.recordReceiptShare(
            uuid: 'receipt-share-${DateTime.now().microsecondsSinceEpoch}',
            saleId: sale.id!,
            token: response?['token'] as String?,
            url: link,
            recipientMasked: recipientMasked,
            expiresAt: response?['expires_at']?.toString(),
          );
        }
      } else if (sale.id != null) {
        await DatabaseHelper.instance.recordReceiptShare(
          uuid: 'receipt-share-${DateTime.now().microsecondsSinceEpoch}',
          saleId: sale.id!,
          recipientMasked: recipientMasked,
        );
      }
    } on Object catch (_) {
      if (sale.id != null) {
        await DatabaseHelper.instance.recordReceiptShare(
          uuid: 'receipt-share-${DateTime.now().microsecondsSinceEpoch}',
          saleId: sale.id!,
          recipientMasked: recipientMasked,
        );
      }
    }
    final lines = <String>[
      if (resolvedShopName.isNotEmpty) resolvedShopName,
      'Receipt ${sale.id ?? ''}'.trim(),
      for (final item in sale.items)
        '${item.productName} × ${item.qty}  ${formatMoney(item.total)}',
      'Total: ${formatMoney(sale.total)}',
      'Paid by ${sale.paymentMethod}',
      if (link != null) link,
    ];
    await SharePlus.instance.share(ShareParams(
      text: lines.join('\n'),
      subject: 'Receipt from $resolvedShopName',
    ));
  }

  Future<void> sharePdfReceipt(BuildContext context, int saleId) async {
    final sale = await DatabaseHelper.instance.getSaleById(saleId);
    if (sale == null || !context.mounted) return;
    await shareSalePdf(context, sale: sale);
  }

  Future<void> shareSalePdf(
    BuildContext context, {
    required Sale sale,
    String? shopName,
  }) async {
    if (!context.mounted) return;
    final file = await const ReceiptPdfService().write(
      sale: sale,
      shopName:
          shopName ?? context.read<AppState>().owner?.shopName ?? 'Duka POS',
    );
    if (!context.mounted) return;
    await SharePlus.instance.share(ShareParams(
      files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Receipt ${sale.id ?? ''}'.trim(),
    ));
  }

  Future<PrintResult> printReceipt(BuildContext context, int saleId) async {
    if (!context.mounted) {
      return const PrintResult(PrintOutcome.failed);
    }
    final state = context.read<AppState>();
    final receiptLanguage = Localizations.localeOf(context).languageCode == 'sw'
        ? ReceiptLanguage.swahili
        : ReceiptLanguage.english;
    final config = await PrinterConfig.load();
    final row = await DatabaseHelper.instance.getSaleRowById(saleId);
    final vatRate = row == null
        ? await DatabaseHelper.instance.getVatRatePercent()
        : await DatabaseHelper.instance.vatRateForSale(row);
    final prefs = await SharedPreferences.getInstance();
    return ReceiptPrinter().printSale(
      saleId: saleId,
      shopName: state.owner?.shopName ?? 'Duka POS',
      staffRole: state.isOwnerSession ? 'Owner' : state.currentRole,
      config: config,
      vatRatePercent: vatRate,
      pricesIncludeVat: prefs.getBool('prices_include_vat') ?? true,
      receiptLanguage: receiptLanguage,
    );
  }
}
