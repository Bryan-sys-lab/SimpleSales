import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/financial_event.dart';
import '../services/analytics.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../utils/money.dart';
import '../widgets/chart.dart';
import 'analytics_shared.dart';
import 'analytics_screen.dart';

/// The fashion profile analytics screen.
///
/// Variant-focused rather than product-focused: revenue, net profit, cash
/// position, stock value, layby balance and variant-level performance lead.
/// Then standard financial sections follow. Fashion turns on size/colour
/// combinations, so variants are visible throughout.
class FashionAnalyticsScreen extends StatelessWidget {
  const FashionAnalyticsScreen({
    required this.range,
    required this.onRangeChanged,
    required this.snapshot,
    required this.onRetry,
    this.onSortBy,
    this.sort = ProductSort.revenue,
    this.ascending = false,
    required this.sortedProducts,
    required this.salesPoints,
    required this.chartSemantics,
    this.chartEmphasis,
    this.statement,
    this.bottomInset = 0,
    this.onOpenPortfolio,
    this.onProductTap,
    this.showPortfolioLink = false,
    super.key,
  });

  final AnalyticsRange range;
  final ValueChanged<AnalyticsRange> onRangeChanged;
  final AnalyticsSnapshot snapshot;
  final Future<void> Function() onRetry;
  final void Function(ProductSort)? onSortBy;
  final ProductSort sort;
  final bool ascending;
  final List<ProductSalesRow> sortedProducts;
  final List<PosLinePoint> salesPoints;
  final String? chartSemantics;
  final String? chartEmphasis;
  final FinancialStatement? statement;
  final double bottomInset;
  final VoidCallback? onOpenPortfolio;
  final void Function(ProductSalesRow)? onProductTap;
  final bool showPortfolioLink;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);

    return AnalyticsScaffold(
      range: range,
      onRangeChanged: onRangeChanged,
      snapshot: snapshot,
      onRetry: onRetry,
      onSortBy: onSortBy,
      sort: sort,
      ascending: ascending,
      sortedProducts: sortedProducts,
      salesPoints: salesPoints,
      chartSemantics: chartSemantics,
      chartEmphasis: chartEmphasis,
      bottomInset: bottomInset,
      onOpenPortfolio: onOpenPortfolio,
      onProductTap: onProductTap,
      showPortfolioLink: showPortfolioLink,
      title: l10n.navAnalytics,
      statement: statement,
      children: <Widget>[
        // Fashion leads with variant-relevant figures: revenue, net profit,
        // cash position, stock value, low-stock variants, layby balance.
        _FashionOpeningKpis(
          totals: snapshot.totals,
          stockValue: snapshot.stockValue,
          lowStockCount: snapshot.lowStock.length,
          outOfStockCount: snapshot.outOfStock.length,
        ),
        SizedBox(height: spacing.lg),
        ...standardAnalyticsSections(
          context: context,
          shown: snapshot,
          range: range,
          chartSemantics: chartSemantics,
          chartEmphasis: chartEmphasis,
          statement: statement,
          salesPoints: salesPoints,
          sortedProducts: sortedProducts,
          sort: sort,
          ascending: ascending,
          onSortBy: onSortBy,
          onProductTap: onProductTap,
          spacing: spacing,
          l10n: l10n,
          colors: colors,
        ),
      ],
    );
  }
}

/// Revenue, net profit, cash position, stock value, low-stock variants,
/// out-of-stock variants — the figures a fashion owner opens analytics for.
class _FashionOpeningKpis extends StatelessWidget {
  const _FashionOpeningKpis({
    required this.totals,
    required this.stockValue,
    required this.lowStockCount,
    required this.outOfStockCount,
  });

  final DailyTotals totals;
  final Money stockValue;
  final int lowStockCount;
  final int outOfStockCount;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final type = AppTypography.of(context);

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.fashionAnalyticsFinancialPerformance,
            style: type.labelMedium?.copyWith(
              color: colors.onSurfaceMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: spacing.xs),
          Text(
            formatMoney(totals.total),
            style: AppTypography.money(
              context,
              size: 40,
              weight: FontWeight.w800,
            ),
          ),
          SizedBox(height: spacing.lg),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool row = constraints.maxWidth >= 640;
              final List<Widget> tiles = <Widget>[
                _OpeningKpiTile(
                  label: l10n.fashionAnalyticsNetProfit,
                  value: formatMoney(totals.profit),
                  icon: Icons.attach_money_outlined,
                ),
                _OpeningKpiTile(
                  label: l10n.fashionAnalyticsStockValue,
                  value: formatMoney(stockValue),
                  icon: Icons.inventory_2_outlined,
                ),
                _OpeningKpiTile(
                  label: l10n.fashionAnalyticsLowStockVariants,
                  value: '$lowStockCount',
                  tone: lowStockCount > 0 ? StatusTone.warning : null,
                  icon: Icons.warning_amber_outlined,
                ),
                _OpeningKpiTile(
                  label: l10n.fashionAnalyticsOutOfStock,
                  value: '$outOfStockCount',
                  tone: outOfStockCount > 0 ? StatusTone.danger : null,
                  icon: Icons.cancel_outlined,
                ),
              ];
              if (row) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = 0; i < tiles.length; i++) ...<Widget>[
                      if (i > 0) SizedBox(width: spacing.lg),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: spacing.lg,
                runSpacing: spacing.lg,
                children: tiles.map((t) => SizedBox(width: 150, child: t)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OpeningKpiTile extends StatelessWidget {
  const _OpeningKpiTile({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final effectiveTone = tone ?? StatusTone.neutral;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              padding: EdgeInsets.all(spacing.xs),
              decoration: BoxDecoration(
                color: effectiveTone.container(colors),
                borderRadius: AppShapes.of(context).controlRadius,
              ),
              child: Icon(
                icon,
                size: 18,
                color: effectiveTone.onContainer(colors),
              ),
            ),
            const Spacer(),
            if (tone != null)
              StatusChip(
                tone: effectiveTone,
                text: effectiveTone.label,
                dense: true,
              ),
          ],
        ),
        SizedBox(height: spacing.lg),
        Text(
          value,
          style: AppTypography.money(
            context,
            size: 20,
            weight: FontWeight.w800,
          ),
        ),
        SizedBox(height: spacing.xs),
        Text(
          label,
          style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted),
        ),
      ],
    );
  }
}
