import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../widgets/backup_reminder_banner.dart';

const double _fashionCatalogueMaxWidth = 1200;

/// Fashion catalogue: parent products (styles), not individual variants.
///
/// Each row: product name, category, total stock across variants, price
/// range, variant count. Tapping opens the variant detail view.
class FashionCatalogueScreen extends StatefulWidget {
  const FashionCatalogueScreen({super.key});

  @override
  State<FashionCatalogueScreen> createState() => _FashionCatalogueScreenState();
}

class _FashionCatalogueScreenState extends State<FashionCatalogueScreen> {
  List<Product> _products = const [];
  bool _loading = true;
  String _searchQuery = '';

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
      if (!mounted) return;
      setState(() {
        _products = products.where((p) => p.trackVariants).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<Product> get _filteredProducts {
    final query = _searchQuery.trim().toLowerCase();
    return _products.where((p) {
      return query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          p.category.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final products = _filteredProducts;

    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _fashionCatalogueMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () => performBackup(context)),
            SizedBox(height: spacing.section),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.fashionCatalogueTitle,
                        style: AppTypography.of(context).headlineSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        l10n.fashionCatalogueSubtitle,
                        style: AppTypography.of(context)
                            .bodyMedium
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => context.push(Routes.fashionProductForm),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.fashionCatalogueAddStyle),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            Padding(
              padding: EdgeInsetsDirectional.only(bottom: spacing.sm),
              child: TextField(
                decoration: InputDecoration(
                  labelText: l10n.fashionCatalogueSearch,
                  hintText: l10n.fashionCatalogueSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  constraints: BoxConstraints(
                    minHeight: AppSpacing.of(context).textFieldHeight,
                  ),
                ),
                onChanged: (value) =>
                    setState(() => _searchQuery = value),
              ),
            ),
            Expanded(
              child: _loading || products.isEmpty
                  ? _FashionCatalogueEmpty(
                      isEmpty: products.isEmpty && !_loading,
                      onAddStyle: () => context.push(Routes.fashionProductForm),
                    )
                  : ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, i) => Divider(
                        height: 1,
                        indent: spacing.md,
                        color: colors.outline,
                      ),
                      itemBuilder: (_, i) {
                        final p = products[i];
                        return Semantics(
                          label:
                              '${p.name} · ${p.category} · ${p.stockQty.toInt()} in stock',
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: colors.surfaceSunken,
                                borderRadius: AppShapes.of(context)
                                    .controlRadius,
                              ),
                              child: Icon(
                                Icons.checkroom_outlined,
                                size: 18,
                                color: colors.onSurfaceMuted,
                              ),
                            ),
                            title: Text(
                              p.name,
                              style: AppTypography.of(context).bodyMedium,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  '${p.category} · ${_variantCountLabel(p)}',
                                  style: AppTypography.of(context)
                                      .labelSmall
                                      ?.copyWith(color: colors.onSurfaceMuted),
                                ),
                                SizedBox(height: spacing.xs),
                                Text(
                                  _stockLabel(p),
                                  style: AppTypography.of(context)
                                      .labelSmall
                                      ?.copyWith(
                                        color: _stockTone(
                                            p, colors).onContainer(colors),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                            trailing: StatusChip(
                              tone: _stockTone(p, colors),
                              text: _stockStatus(p),
                              dense: true,
                            ),
                            onTap: () => context.push(
                              Routes.fashionProduct(p.id ?? 0),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  StatusTone _stockTone(Product p, AppColors colors) {
    if (p.stockQty <= 0) return StatusTone.danger;
    if (p.isLow) return StatusTone.warning;
    return StatusTone.success;
  }

  String _stockStatus(Product p) {
    if (p.stockQty <= 0) return 'Out';
    if (p.isLow) return 'Low';
    return 'In stock';
  }

  String _variantCountLabel(Product p) {
    return p.trackVariants ? 'Variants' : 'Single';
  }

  String _stockLabel(Product p) {
    return '${p.stockQty.toInt()} in stock';
  }
}

class _FashionCatalogueEmpty extends StatelessWidget {
  const _FashionCatalogueEmpty({required this.isEmpty, required this.onAddStyle});

  final bool isEmpty;
  final VoidCallback onAddStyle;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(height: spacing.lg),
        Container(
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: AppShapes.of(context).controlRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                isEmpty ? l10n.fashionCatalogueNoStyles : l10n.fashionCatalogueLoading,
                style: type.bodyMedium,
              ),
              SizedBox(height: spacing.xs),
              Text(
                isEmpty
                    ? l10n.fashionCatalogueNoStylesSubtitle
                    : l10n.fashionCatalogueLoadingSubtitle,
                style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        FilledButton.icon(
          onPressed: onAddStyle,
          icon: const Icon(Icons.add),
          label: Text(l10n.fashionCatalogueAddStyle),
        ),
      ],
    );
  }
}
