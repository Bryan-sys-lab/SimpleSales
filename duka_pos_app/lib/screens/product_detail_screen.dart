import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';

/// Product detail: everything an owner or cashier needs to know about one
/// product, on a single scrollable page.
///
/// Redesigned to match the SimpleSales duka profile mockup: centered product
/// art badge, name + category subtitle, stock/selling/buying/stock-value
/// stats grid, stock activity list, and receive/adjust action buttons.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({required this.product, super.key});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);
    final appState = context.watch<AppState>();

    final bool canAdjust =
        appState.isOwnerSession ||
        appState.hasPermission(PermissionKey.adjustStock);
    final bool canReceive =
        appState.isOwnerSession ||
        appState.hasPermission(PermissionKey.receiveStock);
    final bool canEdit =
        appState.isOwnerSession ||
        appState.hasPermission(PermissionKey.manageSuppliers);

    final Money stockValue = Money.fromMinor(
      (product.stockQty * product.costPrice.minorUnits).round(),
    );

    final bool isOut = product.stockQty <= 0;
    final bool isLow = !isOut && product.isLow;

    final StatusTone tone = isOut
        ? StatusTone.danger
        : isLow
            ? StatusTone.warning
            : StatusTone.success;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inventoryProductDetail),
        actions: <Widget>[
          if (canEdit)
            TextButton.icon(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
        ],
      ),
      body: AdaptivePage(
        scrollable: true,
        maxContentWidth: 900,
        padding: EdgeInsetsDirectional.only(
          start: spacing.md,
          end: spacing.md,
          top: spacing.md,
          bottom: spacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(height: spacing.sm),

            // Centered product identity: large circular art badge, name bold,
            // muted category subtitle. Mirrors the mockup's product header.
            SurfaceCard(
              padding: EdgeInsets.all(spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors.surfaceSunken,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 36,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: spacing.md),
                  Text(
                    product.name,
                    style: type.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    product.category.isNotEmpty
                        ? product.category
                        : 'All products',
                    style: type.bodySmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: spacing.sm),
                  StatusChip(
                    tone: tone,
                    text: isOut
                        ? l10n.inventoryOutOfStock
                        : isLow
                            ? l10n.inventoryLowStock
                            : l10n.inventoryInStock,
                    dense: true,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.lg),

            // Four stats in a 2x2 grid: available stock, selling price, buying
            // cost, stock value.
            SurfaceCard(
              padding: EdgeInsets.all(spacing.lg),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool row = constraints.maxWidth >= 640;
                  final List<Widget> tiles = <Widget>[
                    _DukaStatCard(
                      label: 'Available stock',
                      value: _stockCountLabel(product.stockQty),
                      unit: product.unit.suffix,
                      icon: Icons.warehouse_outlined,
                    ),
                    _DukaStatCard(
                      label: l10n.inventorySellingPrice,
                      value: formatMoney(product.sellPrice),
                      icon: Icons.sell_outlined,
                    ),
                    _DukaStatCard(
                      label: l10n.inventoryCostPrice,
                      value: formatMoney(product.costPrice),
                      icon: Icons.shopping_cart_outlined,
                    ),
                    _DukaStatCard(
                      label: l10n.inventoryStockValue,
                      value: formatMoney(stockValue),
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ];
                  if (row) {
                    return IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              for (int i = 0; i < 2; i++) ...<Widget>[
                                if (i > 0) SizedBox(width: spacing.lg),
                                Expanded(child: tiles[i]),
                              ],
                            ],
                          ),
                          SizedBox(height: spacing.lg),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              for (int i = 2; i < 4; i++) ...<Widget>[
                                if (i > 2) SizedBox(width: spacing.lg),
                                Expanded(child: tiles[i]),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int i = 0; i < tiles.length; i++) ...<Widget>[
                        if (i > 0) SizedBox(height: spacing.lg),
                        tiles[i],
                      ],
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: spacing.lg),

            // Stock activity section.
            SurfaceCard(
              padding: EdgeInsetsDirectional.only(
                start: spacing.lg,
                end: spacing.lg,
                top: spacing.lg,
                bottom: spacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Stock activity',
                    style: type.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  _DukaActivityRow(
                    icon: Icons.local_shipping_outlined,
                    label: 'Stock received',
                    detail: 'Today · Supplier delivery',
                    value: formatMoney(stockValue),
                  ),
                  _DukaActivityRow(
                    icon: Icons.sell_outlined,
                    label: 'Sale',
                    detail: 'Today · KSh 450',
                    value: '2.5 ${product.unit.suffix}',
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.lg),

            // Action buttons: receive stock, adjust stock.
            if (canReceive)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _receiveStock(context),
                  icon: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: const Text('Receive stock'),
                ),
              ),
            if (canReceive) SizedBox(height: spacing.md),
            if (canAdjust)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _adjustStock(context),
                  icon: const Icon(Icons.tune_outlined, size: 18),
                  label: const Text('Adjust stock'),
                ),
              ),
            if (canAdjust) SizedBox(height: spacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _viewSales(context),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('View sales'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditor(BuildContext context) {
    context.pop();
  }

  void _receiveStock(BuildContext context) {
    context.pop();
  }

  void _adjustStock(BuildContext context) {
    context.pop();
  }

  void _viewSales(BuildContext context) {
    context.pop();
  }

  String _stockCountLabel(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

/// One stat card: label above bold value, optional unit, icon badge.
class _DukaStatCard extends StatelessWidget {
  const _DukaStatCard({
    required this.label,
    required this.value,
    this.unit,
    required this.icon,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              padding: EdgeInsets.all(spacing.xs),
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: AppShapes.of(context).controlRadius,
              ),
              child: Icon(
                icon,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.lg),
        Text(
          label,
          style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted),
        ),
        SizedBox(height: spacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              value,
              style: AppTypography.money(
                context,
                size: 20,
                weight: FontWeight.w800,
              ),
            ),
            if (unit != null) ...<Widget>[
              SizedBox(width: spacing.xs),
              Text(
                unit!,
                style: type.labelSmall?.copyWith(
                  color: colors.onSurfaceMuted,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// One activity row: icon circle, label/detail, value trailing.
class _DukaActivityRow extends StatelessWidget {
  const _DukaActivityRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String detail;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: type.bodyMedium),
                SizedBox(height: 2),
                Text(
                  detail,
                  style: type.bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: spacing.sm),
          Text(
            value,
            style: AppTypography.money(context, size: 14),
          ),
        ],
      ),
    );
  }
}
