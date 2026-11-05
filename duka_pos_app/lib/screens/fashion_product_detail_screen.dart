import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../ui/components/surface.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';

const double _fashionProductDetailMaxWidth = 900;

/// One fashion product's variants table.
///
/// Variant rows: colour, size, stock, status, sell price, cost price, reorder.
/// Each variant is independently tracked — size M may be out while size L is fine.
class FashionProductDetailScreen extends StatefulWidget {
  const FashionProductDetailScreen({super.key, required this.productId});

  final int productId;

  @override
  State<FashionProductDetailScreen> createState() =>
      _FashionProductDetailScreenState();
}

class _FashionProductDetailScreenState
    extends State<FashionProductDetailScreen> {
  Product? _product;
  List<ProductVariant> _variants = const [];
  bool _loading = true;

  DatabaseHelper get _db => DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final products = await _db.getProducts(activeOnly: true);
      final product = products.firstWhere(
        (p) => p.id == widget.productId,
        orElse: () => throw StateError('Product not found'),
      );
      final variants = await _db.getVariants(widget.productId);
      if (!mounted) return;
      setState(() {
        _product = product;
        _variants = variants;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final appState = context.read<AppState>();

    if (_loading) {
      return AdaptivePage(
        maxContentWidth: _fashionProductDetailMaxWidth,
        padding: PageGutter.of(context),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_product == null) {
      return AdaptivePage(
        maxContentWidth: _fashionProductDetailMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () async {}),
            SizedBox(height: spacing.section),
            Text(
              l10n.fashionProductDetailNotFound,
              style: AppTypography.of(context).headlineSmall,
            ),
          ],
        ),
      );
    }

    final p = _product!;
    final totalStock = _variants.fold<double>(
      0,
      (sum, v) => sum + v.availableStockQty,
    );
    final lowVariantCount = _variants.where((v) => v.isLow).length;

    final bool canManageStock = appState.canManageStock;

    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _fashionProductDetailMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () async {}),
            SizedBox(height: spacing.section),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        p.name,
                        style: AppTypography.of(context).headlineSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        p.category.isNotEmpty ? p.category : 'Uncategorised',
                        style: AppTypography.of(context)
                            .bodyMedium
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _VariantStat(
                      label: l10n.fashionProductDetailTotalStock,
                      value: totalStock.toInt().toString(),
                    ),
                    SizedBox(height: spacing.xs),
                    _VariantStat(
                      label: l10n.fashionProductDetailLowStock,
                      value: '$lowVariantCount',
                      tone: lowVariantCount > 0 ? StatusTone.warning : null,
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: spacing.xl),
            // Variants table
            _VariantSection(
              title: l10n.fashionProductDetailVariants,
              children: _variants.isEmpty
                  ? <Widget>[
                      Padding(
                        padding: EdgeInsets.all(spacing.md),
                        child: Text(
                          l10n.fashionProductDetailNoVariants,
                          style: AppTypography.of(context)
                              .labelSmall
                              ?.copyWith(color: colors.onSurfaceMuted),
                        ),
                      ),
                    ]
                  : _variants.map((v) => _VariantRowDetail(
                      variant: v,
                      canEdit: canManageStock,
                    )).toList(),
            ),
            SizedBox(height: spacing.xl),
            // Actions
            if (canManageStock)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _editProduct(context),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l10n.fashionProductDetailEditStyle),
                ),
              ),
            SizedBox(height: spacing.section),
          ],
        ),
      ),
    );
  }

  void _editProduct(BuildContext context) {
    context.push(Routes.fashionProductForm);
  }
}

class _VariantStat extends StatelessWidget {
  const _VariantStat({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (tone != null) ...<Widget>[
          Container(
            padding: EdgeInsets.all(spacing.xs),
            decoration: BoxDecoration(
              color: tone!.container(colors),
              borderRadius: AppShapes.of(context).controlRadius,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 16,
              color: tone!.onContainer(colors),
            ),
          ),
          SizedBox(height: spacing.xs),
        ],
        Text(
          value,
          style: AppTypography.money(
            context,
            size: 16,
            weight: FontWeight.w800,
          ),
        ),
        SizedBox(height: spacing.xs),
        Text(
          label,
          style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
        ),
      ],
    );
  }
}

class _VariantSection extends StatelessWidget {
  const _VariantSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: spacing.sm),
        ...children,
        SizedBox(height: spacing.lg),
      ],
    );
  }
}

/// One variant row in the product detail table: colour, size, stock, status, prices.
class _VariantRowDetail extends StatelessWidget {
  const _VariantRowDetail({required this.variant, required this.canEdit});

  final ProductVariant variant;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final isLow = variant.availableStockQty <= 0;
    final tone = isLow ? StatusTone.danger : variant.isLow ? StatusTone.warning : StatusTone.success;

    return SurfaceCard(
      padding: EdgeInsets.symmetric(horizontal: spacing.md, vertical: spacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  variant.label,
                  style: type.bodyMedium,
                ),
                SizedBox(height: spacing.xs),
                Text(
                  variant.sku.isNotEmpty ? variant.sku : 'No SKU',
                  style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${variant.availableStockQty.toInt()}',
                  style: type.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: tone == StatusTone.danger ? colors.danger : colors.onSurface,
                  ),
                ),
                SizedBox(height: spacing.xs),
                Text(
                  'Reorder at ${variant.reorderLevel}',
                  style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  formatMoney(variant.sellPrice),
                  style: type.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: spacing.xs),
                Text(
                  formatMoney(variant.costPrice),
                  style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          StatusChip(
            tone: tone,
            text: tone.label,
            dense: true,
          ),
        ],
      ),
    );
  }
}
