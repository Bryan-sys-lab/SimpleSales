import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../utils/money.dart';

/// Product detail: everything an owner or cashier needs to know about one
/// product, on a single scrollable page.
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
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: AppSpacing.of(context).xl,
              end: AppSpacing.of(context).xl,
              top: spacing.sm,
              bottom: spacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            product.name,
                            style: type.headlineSmall,
                          ),
                          SizedBox(height: spacing.xs),
                          Text(
                            product.category.isNotEmpty
                                ? product.category
                                : 'All products',
                            style: type.bodySmall?.copyWith(
                              color: colors.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(
                      tone: tone,
                      text: isOut
                          ? l10n.inventoryOutOfStock
                          : isLow
                              ? l10n.inventoryLowStock
                              : l10n.inventoryInStock,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsetsDirectional.only(
                start: AppSpacing.of(context).xl,
                end: AppSpacing.of(context).xl,
                top: spacing.sm,
                bottom: spacing.lg,
              ),
              children: <Widget>[
                _DetailSection(
                  title: l10n.inventoryProductDetail,
                  children: <Widget>[
                    _DetailRow(
                      label: 'Stock count',
                      value: _stockCountLabel(product.stockQty),
                      unit: product.unit.suffix,
                    ),
                    _DetailRow(
                      label: l10n.inventoryCostPrice,
                      value: formatMoney(product.costPrice),
                    ),
                    _DetailRow(
                      label: l10n.inventorySellingPrice,
                      value: formatMoney(product.sellPrice),
                    ),
                    _DetailRow(
                      label: l10n.inventoryReorderLevel,
                      value: '${product.reorderLevel.toInt()}',
                    ),
                    _DetailRow(
                      label: l10n.inventoryStockValue,
                      value: formatMoney(stockValue),
                    ),
                  ],
                ),
                SizedBox(height: spacing.lg),
                _DetailSection(
                  title: l10n.inventorySalesPerformance,
                  children: <Widget>[
                    _DetailRow(
                      label: 'Units sold',
                      value: '—',
                      subtitle: l10n.inventoryNoMovement,
                    ),
                    _DetailRow(
                      label: l10n.inventoryRevenue,
                      value: formatMoney(Money.zero),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: AppSpacing.of(context).xl,
                end: AppSpacing.of(context).xl,
                top: spacing.sm,
                bottom: spacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (canEdit)
                    _ActionButton(
                      label: 'Edit product',
                      icon: Icons.edit_outlined,
                      onPressed: () => _openEditor(context),
                    ),
                  if (canReceive)
                    _ActionButton(
                      label: 'Receive stock',
                      icon: Icons.local_shipping_outlined,
                      onPressed: () => _receiveStock(context),
                    ),
                  if (canAdjust)
                    _ActionButton(
                      label: 'Adjust stock',
                      icon: Icons.update_outlined,
                      onPressed: () => _adjustStock(context),
                    ),
                  _ActionButton(
                    label: 'View sales',
                    icon: Icons.receipt_outlined,
                    onPressed: () => _viewSales(context),
                  ),
                  if (canAdjust)
                    _ActionButton(
                      label: 'Repack',
                      icon: Icons.inventory_2_outlined,
                      onPressed: () => _repack(context),
                    ),
                ],
              ),
            ),
          ),
        ],
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

  void _repack(BuildContext context) {
    context.pop();
  }

  String _stockCountLabel(double value) =>
      value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(1);
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(bottom: spacing.xs),
          child: Text(
            title,
            style: type.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ...children,
        SizedBox(height: spacing.lg),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.unit,
    this.subtitle,
  });

  final String label;
  final String value;
  final String? unit;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppColors colors = AppColors.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: type.bodyMedium?.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      value,
                      style: type.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
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
                if (subtitle != null) ...<Widget>[
                  SizedBox(height: spacing.xs),
                  Text(
                    subtitle!,
                    style: type.labelSmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: spacing.sm),
        ),
      ),
    );
  }
}
