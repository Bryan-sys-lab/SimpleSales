// Shared analytics widgets used by every profile's analytics screen.
//
// Each profile (drinks, duka, fashion, open) gets its own screen file, but the
// common section widgets — takings hero, KPI grid, payment mix, stock,
// VAT summary, revenue chart, product table — live here so there is one
// component language across profiles.

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/financial_event.dart';
import '../models/models.dart';
import '../services/analytics.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/surface.dart';
import '../utils/money.dart';
import '../widgets/chart.dart';
import 'analytics_screen.dart';
import 'analytics_tables.dart';

/// The headline figure: the one display-size number on the screen.
class TakingsHero extends StatelessWidget {
  const TakingsHero({super.key,
    required this.totals,
    required this.previous,
    required this.range,
  });

  final DailyTotals totals;
  final DailyTotals previous;
  final AnalyticsRange range;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.analyticsSalesLabel,
                  style: AppTypography.of(context)
                      .labelLarge
                      ?.copyWith(color: colors.onSurfaceMuted),
                ),
              ),
              Text(
                range.label,
                style: AppTypography.of(context).labelMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          Text(
            formatMoney(totals.total),
            style: AppTypography.money(
                  context,
                  size: 40,
                  weight: FontWeight.w700,
                )
                .copyWith(color: colors.onSurface, height: 1.05),
          ),
          SizedBox(height: spacing.sm),
          GrowthLine(current: totals, previous: previous, range: range),
        ],
      ),
    );
  }
}

/// Takings against the window before, as a signed word and a figure.
///
/// Colour is the LAST channel here and never the only one. The direction is
/// carried by three independent signals — an arrow glyph whose silhouette
/// differs per direction, the word "Up"/"Down"/"Level", and the sign on the
/// figure — so the comparison survives greyscale, `invertColors` and every
/// screen reader. A red/green pair alone would fail all three.
class GrowthLine extends StatelessWidget {
  const GrowthLine({super.key,
    required this.current,
    required this.previous,
    required this.range,
  });

  final DailyTotals current;
  final DailyTotals previous;
  final AnalyticsRange range;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    final int delta = current.totalMinor - previous.totalMinor;
    final bool hasComparison = previous.totalMinor > 0;
    final double percent =
        hasComparison ? (delta / previous.totalMinor) * 100 : 0;

    final bool isUp = delta > 0;
    final bool isDown = delta < 0;
    final l10n = AppLocalizations.of(context);
    final String word = isUp ? 'Up' : (isDown ? 'Down' : 'Level');
    final IconData glyph = isUp
        ? Icons.arrow_upward
        : (isDown ? Icons.arrow_downward : Icons.horizontal_rule);
    final Color tone = isUp
        ? colors.success
        : (isDown ? colors.danger : colors.onSurfaceVariant);

    final String figure = hasComparison
        ? '${isUp ? '+' : (isDown ? '−' : '')}${percent.abs().toStringAsFixed(0)}%'
        : (isUp ? l10n.analyticsNothingToCompare : l10n.analyticsNoChange);

    final TextStyle figureStyle = AppTypography.money(
      context,
      size: 13,
      weight: FontWeight.w700,
    ).copyWith(color: tone);

    final String comparison = previous.hasSales || current.hasSales
        ? l10n.analyticsAgainstDaysBefore(range.days)
        : l10n.analyticsNothingTaken;

    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(glyph, size: 14, color: tone, semanticLabel: word),
          SizedBox(width: spacing.sm),
          Text(
            word,
            style: AppTypography.of(context).labelLarge?.copyWith(color: tone),
          ),
          SizedBox(width: spacing.sm),
          Text(figure, style: figureStyle),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              comparison,
              style: AppTypography.of(context).bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The range control.
///
/// Four windows, all equally likely, so one tap each: a segmented control
/// rather than a dropdown. [SegmentedChoice] scrolls horizontally at large text
/// scales instead of squeezing, and names the group for a screen reader, which
/// would otherwise hear a row of unrelated buttons.
class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.range, required this.onChanged});

  final AnalyticsRange range;
  final ValueChanged<AnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedChoice<AnalyticsRange>(
      value: range,
      onChanged: onChanged,
      semanticLabel: AppLocalizations.of(context).analyticsReportingPeriod,
      options: <SegmentedOption<AnalyticsRange>>[
        for (final AnalyticsRange option in AnalyticsRange.values)
          SegmentedOption<AnalyticsRange>(value: option, label: option.label),
      ],
    );
  }
}

/// The figures that support the headline, as KPI cards.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key,
    required this.totals,
    required this.previous,
    required this.days,
  });

  final DailyTotals totals;
  final DailyTotals previous;
  final int days;

  String? _countChange(AppLocalizations l10n) {
    final int before = previous.transactions;
    final int now = totals.transactions;
    if (before <= 0 || now == before) return null;
    final double percent = ((now - before) / before) * 100;
    final String sign = percent > 0 ? '+' : '−';
    return '$sign${percent.abs().toStringAsFixed(0)}% '
        '${l10n.analyticsAgainstDaysBefore(days)}';
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);

    final List<Kpi> kpis = <Kpi>[
      Kpi(
        label: l10n.analyticsProfitLabel,
        value: formatMoney(totals.profit),
        caption: totals.hasSales
            ? l10n.analyticsMarginCaption(totals.marginPct.toStringAsFixed(0))
            : null,
        icon: Icons.trending_up,
      ),
      Kpi(
        label: l10n.analyticsNetProfitLabel,
        value: formatMoney(totals.netProfit),
        caption: '${l10n.analyticsNetProfitCaption} · '
            '${formatMoney(Money.fromMinor(totals.expensesMinor))}',
        icon: Icons.account_balance_outlined,
      ),
      Kpi(
        label: l10n.analyticsMarginLabel,
        value:
            totals.hasSales ? '${totals.marginPct.toStringAsFixed(0)}%' : '—',
        caption: l10n.analyticsAvgBasketCaption,
        icon: Icons.percent,
      ),
      Kpi(
        label: l10n.analyticsTransactionsLabel,
        value: l10n.analyticsTransactionCaption(totals.transactions),
        caption: _countChange(l10n),
        icon: Icons.receipt_long_outlined,
        showCaptionWhenEmpty: false,
      ),
      Kpi(
        label: l10n.analyticsAvgBasketLabel,
        value: formatMoney(totals.averageBasket),
        caption: l10n.analyticsAvgBasketCaption,
        icon: Icons.shopping_basket_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 720 ? 4 : 2;
        final double width =
            (constraints.maxWidth - spacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing.md,
          runSpacing: spacing.md,
          children: <Widget>[
            for (final Kpi kpi in kpis)
              SizedBox(
                width: width,
                child: KpiCard(kpi: kpi),
              ),
          ],
        );
      },
    );
  }
}

/// One figure on the dashboard: its label, its value, and what qualifies it.
class Kpi {
  const Kpi({
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.showCaptionWhenEmpty = true,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? caption;

  /// Whether the caption is worth showing when the figure is zero.
  final bool showCaptionWhenEmpty;
}

/// One KPI card: label, value, optional caption.
class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.kpi});

  final Kpi kpi;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final String? caption =
        kpi.showCaptionWhenEmpty || kpi.value != '0' ? kpi.caption : null;

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(kpi.icon, size: 16, color: colors.onSurfaceMuted),
              SizedBox(width: spacing.xs),
              Expanded(
                child: Text(
                  kpi.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.labelMedium?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Text(
            kpi.value,
            maxLines: 2,
            style: AppTypography.money(context, size: 22)
                .copyWith(color: colors.onSurface, height: 1.1),
          ),
          if (caption != null) ...<Widget>[
            SizedBox(height: spacing.xs),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// VAT reconciliation card.
class VatSummaryCard extends StatelessWidget {
  const VatSummaryCard({super.key, required this.totals});

  final DailyTotals totals;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Semantics(
        container: true,
        label: 'VAT captured ${formatMoney(Money.fromMinor(totals.vatMinor))}. '
            'Taxable sales ${formatMoney(Money.fromMinor(totals.taxableMinor))}.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VAT reconciliation', style: type.titleSmall),
            SizedBox(height: spacing.xs),
            Text(
              'Captured from each sale line for this period; this is not a KRA filing.',
              style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
            ),
            SizedBox(height: spacing.sm),
            Wrap(
              spacing: spacing.lg,
              runSpacing: spacing.xs,
              children: [
                VatMetric(label: 'Taxable sales', minor: totals.taxableMinor),
                VatMetric(label: 'VAT captured', minor: totals.vatMinor),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One VAT metric row.
class VatMetric extends StatelessWidget {
  const VatMetric({super.key, required this.label, required this.minor});

  final String label;
  final int minor;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.of(context).bodySmall),
            Text(formatMoney(Money.fromMinor(minor)),
                style: AppTypography.money(context, size: 18)),
          ],
        ),
      );
}

/// A section that fades and rises into place once, on its first paint.
///
/// [index] staggers the sections: the delay grows by forty milliseconds per
/// section, which is short enough that the page never feels like it is loading
/// itself in front of the reader. The end state is the layout's own state —
/// under reduced motion every offset and duration collapses to zero and the
/// sections simply appear.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  double _reveal = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) setState(() => _reveal = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: AlwaysStoppedAnimation(_reveal),
      curve: Curves.easeOut,
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Cost coverage warning card.
class CostCoverageCard extends StatelessWidget {
  const CostCoverageCard({super.key, required this.coverage});

  final CostCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final names = coverage.missingCostProductNames.take(3).join(', ');
    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Semantics(
        container: true,
        label:
            'Cost coverage ${coverage.percentage.toStringAsFixed(0)} percent. '
            '${coverage.missingCostProductNames.length} products have no cost recorded.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_outlined,
                    size: 18, color: colors.warning),
                SizedBox(width: spacing.xs),
                Expanded(child: Text('Cost coverage', style: type.titleSmall)),
                Text('${coverage.percentage.toStringAsFixed(0)}%',
                    style: AppTypography.money(context, size: 22)),
              ],
            ),
            SizedBox(height: spacing.xs),
            Text(
              'Profit is incomplete until every selling product has a cost.',
              style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
            ),
            SizedBox(height: spacing.xs),
            Text(
              names.isEmpty ? 'No missing costs.' : 'Missing: $names',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: type.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Expiry attention card.
class ExpiringCard extends StatelessWidget {
  const ExpiringCard({super.key, required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final colors = AppColors.of(context);
    final names = products.take(5).map((product) => product.name).join(', ');
    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Semantics(
        container: true,
        label:
            '${products.length} products have stock expiring within seven days.',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.schedule_outlined, color: colors.warning),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Expiry attention',
                      style: AppTypography.of(context).titleSmall),
                  SizedBox(height: spacing.xs),
                  Text(
                    '${products.length} product${products.length == 1 ? '' : 's'} have dated stock expiring within 7 days.',
                    style: AppTypography.of(context).bodySmall,
                  ),
                  SizedBox(height: spacing.xs),
                  Text('Review: $names',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expired stock card.
class ExpiredCard extends StatelessWidget {
  const ExpiredCard({super.key, required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final colors = AppColors.of(context);
    final names = products.take(5).map((product) => product.name).join(', ');
    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Semantics(
        container: true,
        label: '${products.length} products have expired stock.',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.delete_outline, color: colors.danger),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Expired stock',
                      style: AppTypography.of(context).titleSmall),
                  SizedBox(height: spacing.xs),
                  Text(
                    '${products.length} product${products.length == 1 ? '' : 's'} have expired.',
                    style: AppTypography.of(context).bodySmall,
                  ),
                  SizedBox(height: spacing.xs),
                  Text('Remove: $names',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slow movers card.
class SlowMoversCard extends StatelessWidget {
  const SlowMoversCard({super.key, required this.rows});

  final List<SlowMoverRow> rows;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final type = AppTypography.of(context);
    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Slow movers', style: type.titleSmall),
          SizedBox(height: spacing.xs),
          Text('Products with the fewest units sold in this period.',
              style: type.bodySmall),
          SizedBox(height: spacing.sm),
          for (final row in rows)
            Padding(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Row(
                children: [
                  Expanded(child: Text(row.product.name)),
                  Text('${row.unitsPerDay.toStringAsFixed(1)}/day',
                      style: type.labelMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Load failure view with a retry action.
class AnalyticsError extends StatelessWidget {
  const AnalyticsError({super.key, required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.dangerContainer,
          borderRadius: AppShapes.of(context).controlRadius,
          border: Border.all(color: colors.danger),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.cloud_off_outlined, size: 18, color: colors.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: AppTypography.of(context).bodyMedium?.copyWith(
                          color: colors.danger,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child:             TextButton(
                onPressed: () => onRetry(),
                child: Text(AppLocalizations.of(context).actionTryAgain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The standard section ordering for non-Drinks profiles: takings first, then
/// supporting figures, payment mix, stock, VAT, revenue chart, product table,
/// expiring/expired/slow movers, and shifts.
///
/// Drinks overrides this order to lead with beverage performance.
List<Widget> standardAnalyticsSections({
  required BuildContext context,
  required AnalyticsSnapshot shown,
  required AnalyticsRange range,
  required String? chartSemantics,
  required String? chartEmphasis,
  required FinancialStatement? statement,
  required List<PosLinePoint> salesPoints,
  required List<ProductSalesRow> sortedProducts,
  required ProductSort sort,
  required bool ascending,
  required void Function(ProductSort)? onSortBy,
  required void Function(ProductSalesRow)? onProductTap,
  required AppSpacing spacing,
  required AppLocalizations l10n,
  required AppColors colors,
}) {
  final double spacingLg = spacing.lg;
  final double spacingMd = spacing.md;
  final double spacingSm = spacing.sm;
  var section = 0;
  Widget reveal(Widget child) => Reveal(index: section++, child: child);

  return <Widget>[
    // The headline is a CARD like the rest of the figures, with the amount
    // inside it as the one display-size number on the screen.
    reveal(SurfaceCard(
      padding: EdgeInsets.all(spacingLg),
      child: TakingsHero(
        totals: shown.totals,
        previous: shown.previousTotals,
        range: range,
      ),
    )),
    SizedBox(height: spacingLg),
    if (!shown.totals.hasSales)
      Padding(
        padding: EdgeInsetsDirectional.only(bottom: spacingMd),
        child: Text(
          l10n.analyticsNothingTaken,
          style: AppTypography.of(context)
              .bodyMedium
              ?.copyWith(color: colors.onSurfaceMuted),
        ),
      ),
    reveal(KpiGrid(
      totals: shown.totals,
      previous: shown.previousTotals,
      days: range.days,
    )),
    SizedBox(height: spacingLg),
    reveal(PaymentMixCard(rows: shown.payments, totals: shown.totals)),
    SizedBox(height: spacingLg),
    reveal(StockSection(outOfStock: shown.outOfStock, lowStock: shown.lowStock)),
    SizedBox(height: spacingLg),
    reveal(VatSummaryCard(totals: shown.totals)),
    SizedBox(height: spacingLg),
    if (statement != null) ...<Widget>[
      reveal(FinancialStatementCard(statement: statement)),
      SizedBox(height: spacingLg),
    ],
    if (shown.costCoverage.hasMissingCosts) ...<Widget>[
      reveal(CostCoverageCard(coverage: shown.costCoverage)),
      SizedBox(height: spacingLg),
    ],
    reveal(SurfaceCard(
      padding: EdgeInsetsDirectional.only(
        start: spacingMd,
        end: spacingMd,
        top: spacingMd,
        bottom: spacingSm,
      ),
      child: PosLineChart(
        title: l10n.analyticsChartTitleSalesByDay,
        emphasis: chartEmphasis,
        semanticsLabel: chartSemantics,
        height: 168,
        points: salesPoints,
      ),
    )),
    SizedBox(height: spacingLg),
    reveal(ProductTableCard(
      rows: sortedProducts,
      sort: sort,
      ascending: ascending,
      onSort: onSortBy,
      onProductTap: onProductTap,
    )),
    SizedBox(height: spacingLg),
    if (shown.expiring.isNotEmpty) ...<Widget>[
      reveal(ExpiringCard(products: shown.expiring)),
      SizedBox(height: spacingLg),
    ],
    if (shown.expired.isNotEmpty) ...<Widget>[
      reveal(ExpiredCard(products: shown.expired)),
      SizedBox(height: spacingLg),
    ],
    if (shown.slowMovers.isNotEmpty) ...<Widget>[
      reveal(SlowMoversCard(rows: shown.slowMovers)),
      SizedBox(height: spacingLg),
    ],
    // The shifts, and what the drawers did over the window.
    reveal(ShiftAnalyticsCard(shifts: shown.shifts)),
  ];
}
