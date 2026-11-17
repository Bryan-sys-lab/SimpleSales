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
import 'analytics_screen.dart';
import 'analytics_shared.dart';

/// The open profile analytics screen.
///
/// Open-profile analytics emphasizes revenue, net profit, cash position,
/// pooled costs and receivables while reusing the shared analytics engine.
class OpenAnalyticsScreen extends StatelessWidget {
  const OpenAnalyticsScreen({
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
        // Open leads with commerce figures: revenue, net profit, cash
        // position, pooled costs, and receivables.
        _OpenOpeningKpis(
          totals: snapshot.totals,
          lowStockCount: snapshot.lowStock.length,
          outOfStockCount: snapshot.outOfStock.length,
          pooledCosts: snapshot.pooledCosts,
          receivables: snapshot.receivables,
          cashPosition: snapshot.cashPosition,
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

/// Revenue, net profit, cash position, pooled costs, and receivables —
/// the figures an Open business owner opens analytics for.
class _OpenOpeningKpis extends StatelessWidget {
  const _OpenOpeningKpis({
    required this.totals,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.pooledCosts,
    required this.receivables,
    required this.cashPosition,
  });

  final DailyTotals totals;
  final int lowStockCount;
  final int outOfStockCount;
  final Money pooledCosts;
  final Money receivables;
  final Money cashPosition;

  @override
  Widget build(BuildContext context) {
    final totals = this.totals;
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final type = AppTypography.of(context);
    final profit = totals.profit.minorUnits > 0
        ? (
            l10n.openDashboardProfit,
            formatMoney(totals.profit.abs),
            StatusTone.success
          )
        : totals.profit.minorUnits < 0
            ? (
                l10n.openDashboardNotInProfitYet,
                formatMoney(totals.profit.abs),
                StatusTone.danger
              )
            : (
                l10n.openDashboardBreakEven,
                formatMoney(Money.zero),
                StatusTone.neutral
              );

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.openAnalyticsFinancialPerformance,
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
                  label: profit.$1,
                  value: profit.$2,
                  tone: profit.$3,
                  icon: Icons.attach_money_outlined,
                ),
                _OpeningKpiTile(
                  label: l10n.openAnalyticsCashPosition,
                  value: formatMoney(cashPosition),
                  icon: Icons.account_balance_wallet_outlined,
                ),
                _OpeningKpiTile(
                  label: l10n.openAnalyticsPooledCosts,
                  value: formatMoney(pooledCosts),
                  icon: Icons.account_balance_outlined,
                ),
                _OpeningKpiTile(
                  label: l10n.openAnalyticsReceivables,
                  value: formatMoney(receivables),
                  icon: Icons.schedule_outlined,
                  tone: StatusTone.warning,
                ),
              ];
              if (row) {
                return IntrinsicHeight(
                    child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = 0; i < tiles.length; i++) ...<Widget>[
                      if (i > 0) SizedBox(width: spacing.lg),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                ));
              }
              return Wrap(
                spacing: spacing.lg,
                runSpacing: spacing.lg,
                children:
                    tiles.map((t) => SizedBox(width: 150, child: t)).toList(),
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
