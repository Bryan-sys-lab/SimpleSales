import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/analytics.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../services/roles.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../widgets/chart.dart';
import '../widgets/sale_details_sheet.dart';
import '../ui/components/product_photo.dart';
import '../utils/money.dart';

/// Product analytics detail.  It is intentionally a sheet rather than a new
/// route: the period remains owned by Analytics and the owner can return to the
/// ranked list without losing the sort or scroll position.
Future<void> showProductDrilldownSheet(
  BuildContext context, {
  required ProductSalesRow row,
  required DateTime since,
  DateTime? until,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ProductDrilldownSheet(
      row: row,
      since: since,
      until: until,
    ),
  );
}

class _ProductDrilldownSheet extends StatelessWidget {
  const _ProductDrilldownSheet({
    required this.row,
    required this.since,
    this.until,
  });

  final ProductSalesRow row;
  final DateTime since;
  final DateTime? until;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: FutureBuilder<ProductDrilldownSnapshot>(
          future: _read(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return const SizedBox(
                height: 180,
                child: Center(child: Text('Could not load product analytics.')),
              );
            }
            final data = snapshot.data!;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (data.catalogueProduct?.imagePath != null) ...[
                        ProductPhoto(
                          imagePath: data.catalogueProduct!.imagePath,
                          size: 64,
                        ),
                        SizedBox(width: spacing.md),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data.product.productName,
                                style: AppTypography.of(context).headlineSmall),
                            if (data.catalogueProduct != null)
                              Text(
                                '${data.catalogueProduct!.category} · '
                                '${_status(data.catalogueProduct!)}',
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (data.catalogueProduct != null) ...[
                    SizedBox(height: spacing.sm),
                    Wrap(
                      spacing: spacing.lg,
                      runSpacing: spacing.xs,
                      children: [
                        _Metric('Sell price',
                            formatMoney(data.catalogueProduct!.sellPrice)),
                        _Metric('Cost',
                            formatMoney(data.catalogueProduct!.costPrice)),
                        _Metric(
                            'On hand', _units(data.catalogueProduct!.stockQty)),
                      ],
                    ),
                  ],
                  SizedBox(height: spacing.xs),
                  Text('Product detail for the selected period'),
                  SizedBox(height: spacing.lg),
                  Wrap(
                    spacing: spacing.lg,
                    runSpacing: spacing.md,
                    children: [
                      _Metric('Units', _units(data.product.units)),
                      _Metric('Sales', formatMoney(data.product.revenue)),
                      _Metric('Profit', formatMoney(data.product.profit)),
                      _Metric('Margin', data.product.marginLabel),
                      _Metric('Transactions', '${data.totals.transactions}'),
                    ],
                  ),
                  if (data.daily.isNotEmpty) ...[
                    SizedBox(height: spacing.lg),
                    PosLineChart(
                      title: 'Sales trend',
                      height: 160,
                      points: [
                        for (final day in data.daily)
                          PosLinePoint(
                            label: day.label,
                            value: day.salesMinor,
                            valueLabel: formatMoney(day.sales),
                          ),
                      ],
                      semanticsLabel: 'Product sales trend by day',
                    ),
                  ],
                  SizedBox(height: spacing.lg),
                  Text('Who sells it',
                      style: AppTypography.of(context).titleMedium),
                  for (final staff in data.staff)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(staff.name),
                      subtitle: Text('${staff.transactions} transactions'),
                      trailing: Text(
                          formatMoney(Money.fromMinor(staff.revenueMinor))),
                    ),
                  SizedBox(height: spacing.md),
                  Text('How customers pay',
                      style: AppTypography.of(context).titleMedium),
                  for (final payment in data.payments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(payment.label()),
                      subtitle: Text('${payment.transactions} transactions'),
                      trailing: Text(formatMoney(payment.sales)),
                    ),
                  if (data.hourly.isNotEmpty) ...[
                    SizedBox(height: spacing.md),
                    Text('When it sells',
                        style: AppTypography.of(context).titleMedium),
                    for (final hour in data.hourly)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title:
                            Text('${hour.hour.toString().padLeft(2, '0')}:00'),
                        subtitle: Text(
                            '${_units(hour.units)} units · ${hour.transactions} transactions'),
                        trailing: Text(formatMoney(hour.sales)),
                      ),
                  ],
                  if (data.boughtTogether.isNotEmpty) ...[
                    SizedBox(height: spacing.md),
                    Text('Bought together',
                        style: AppTypography.of(context).titleMedium),
                    for (final companion in data.boughtTogether)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(companion.productName),
                        subtitle: Text(
                            '${companion.baskets} shared baskets · ${_units(companion.units)} units'),
                      ),
                  ],
                  if (data.stockTimeline.isNotEmpty) ...[
                    SizedBox(height: spacing.md),
                    Text('Stock timeline',
                        style: AppTypography.of(context).titleMedium),
                    for (final movement in data.stockTimeline)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(movement.type.wire),
                        subtitle: Text(
                            '${movement.createdAt} · balance ${_units(movement.balanceAfter)}'),
                        trailing: Text(
                          '${movement.qtyDelta >= 0 ? '+' : ''}${_units(movement.qtyDelta)}',
                        ),
                      ),
                  ],
                  if (data.priceHistory.isNotEmpty) ...[
                    SizedBox(height: spacing.md),
                    Text('Price and cost history',
                        style: AppTypography.of(context).titleMedium),
                    for (final point in data.priceHistory)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${formatMoney(Money.fromMinor(point.sellPriceMinor))} sell · '
                          '${formatMoney(Money.fromMinor(point.costPriceMinor))} cost',
                        ),
                        subtitle: Text(
                            '${point.recordedAt}${point.reason == null ? '' : ' · ${point.reason}'}'),
                      ),
                  ],
                  if (data.records.isNotEmpty) ...[
                    SizedBox(height: spacing.md),
                    Text('Transactions containing this product',
                        style: AppTypography.of(context).titleMedium),
                    for (final record in data.records)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => _openRecord(context, record),
                        title: Text(formatMoney(record.productSales)),
                        subtitle: Text(
                            '${record.createdAt} · ${record.staffName} · ${record.paymentMethod}'),
                        trailing: Text('Sale ${formatMoney(record.saleTotal)}'),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static String _status(Product product) {
    if (!product.active) return 'Inactive';
    if (product.stockQty <= 0) return 'Out of stock';
    if (product.isLow) return 'Low stock';
    return 'Selling';
  }

  Future<void> _openRecord(
    BuildContext context,
    ProductTransactionRow record,
  ) async {
    // Local drill-down rows carry the SQLite sale id. A remote UUID is still a
    // useful record, so ask the verified backend for the authoritative receipt.
    final localId = int.tryParse(record.saleId);
    if (localId == null) {
      if (!context.mounted) return;
      try {
        final remote = await BackendService.remoteSaleDetails(record.saleId);
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Product sale'),
            content: SingleChildScrollView(
              child: Text(_remoteSaleText(remote, record)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load this remote sale.')),
        );
      }
      return;
    }
    final sale = await DatabaseHelper.instance.getSaleById(localId);
    if (!context.mounted) return;
    if (sale == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This sale is no longer on this till.')),
      );
      return;
    }
    final state = context.read<AppState>();
    await showSaleDetails(
      context,
      sale: sale,
      canSeeSellers: state.canManageStock,
      canProcessReturn: state.hasPermission(PermissionKey.processReturn),
      shopName: state.owner?.shopName ?? '',
    );
  }

  static String _remoteSaleText(
      Map<String, dynamic> sale, ProductTransactionRow fallback) {
    final lines = <String>[
      '${sale['createdAt'] ?? fallback.createdAt} · ${sale['staffName'] ?? fallback.staffName}',
      'Total ${formatMoney(Money.fromMinor((sale['total'] as num?)?.toInt() ?? fallback.saleTotalMinor))}',
    ];
    final items = sale['items'];
    if (items is List) {
      for (final raw in items.whereType<Map>()) {
        lines.add('${raw['productName'] ?? 'Item'} × ${raw['qty'] ?? 0} · '
            '${formatMoney(Money.fromMinor((raw['unitPrice'] as num?)?.toInt() ?? 0))}');
      }
    }
    final tenders = sale['tenders'];
    if (tenders is List && tenders.isNotEmpty) {
      lines.add('Payments');
      for (final raw in tenders.whereType<Map>()) {
        lines.add('• ${raw['method'] ?? 'payment'}: '
            '${formatMoney(Money.fromMinor((raw['amount'] as num?)?.toInt() ?? 0))}');
      }
    }
    return lines.join('\n');
  }

  Future<ProductDrilldownSnapshot> _read() async {
    // Local analytics remains the offline and cashier path. Remote detail is
    // authoritative only after identity verification and once this till has
    // no pending sales that the server cannot yet include.
    final canUseRemote = row.remoteId != null &&
        await BackendService.isIdentityVerified &&
        (await DatabaseHelper.instance.getUnsyncedSales(limit: 1)).isEmpty;
    if (canUseRemote) {
      try {
        final remote = await BackendService.remoteProductReport(
          from: since,
          to: until ?? DateTime.now(),
          productId: row.remoteId,
        );
        if (remote.drilldown != null) return remote.drilldown!;
      } catch (_) {
        // A temporary network or permission failure should not hide the
        // product's local drill-down.
      }
    }
    return DatabaseHelper.instance.productDrilldown(
      productId: row.productId,
      since: since,
      until: until,
    );
  }

  static String _units(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.of(context).bodySmall),
            Text(value, style: AppTypography.of(context).titleLarge),
          ],
        ),
      );
}
