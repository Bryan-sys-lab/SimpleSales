// The rest of the dashboard: the shift, the figures, and the two lists a manager
// actually reads.
//
// Two conventions run through this file, and both exist because a till is looked
// at from arm's length by someone serving a customer:
//
//   * Every figure is a `MoneyText` or a `StatTile`, which means TABULAR figures.
//     A row of totals that shifts sideways as the digits change cannot be
//     compared down the column, which is the only reason to put a column there.
//   * Nothing here is a card-per-item. A table of twenty low-stock lines rendered
//     as twenty cards is a wall of borders with no scannable alignment, so the
//     lists use a hairline between rows and a single container around them.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/analytics.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../utils/money.dart';
import '../widgets/chart.dart';

/// The open shift, and what the drawer should hold.
///
/// The expected figure is stated as a NUMBER with the word "expected" beside it,
/// because the count the cashier will do is compared against it. A shift card
/// that only said "shift open since 08:12" gives them nothing to reconcile
/// against.
class DashboardShiftCard extends StatelessWidget {
  const DashboardShiftCard({
    required this.shift,
    required this.expected,
    required this.onOpen,
    super.key,
  });

  final Shift? shift;
  final Money expected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final Shift? open = shift;

    if (open == null) {
      return SurfaceCard(
        child: Row(
          children: <Widget>[
            Icon(
              Icons.point_of_sale_outlined,
              color: AppColors.of(context).onSurfaceMuted,
            ),
            SizedBox(width: spacing.md),
            Expanded(
              child: Text(
                AppLocalizations.of(context).dashboardNoShiftMessage,
                style: type.bodyMedium,
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: spacing.minTapTarget),
              child: FilledButton(
                onPressed: onOpen,
                child:
                    Text(AppLocalizations.of(context).dashboardOpenShiftAction),
              ),
            ),
          ],
        ),
      );
    }

    return SurfaceCard(
      onTap: onOpen,
      semanticLabel: AppLocalizations.of(context).dashboardOpenShiftSpoken(
        open.startTime,
        formatMoney(expected),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Three channels: the glyph's shape, the word "Open", and the
              // accent colour. A cashier who cannot separate the amber from the
              // green still hears the state.
              const StatusChip(tone: StatusTone.success, text: 'Open'),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)
                      .dashboardStaffNameSince(open.staffName, open.startTime),
                  style: type.titleSmall,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: AppLocalizations.of(context).dashboardExpectedInDrawer,
                  value: formatMoney(expected),
                  // The figure the count is measured against, so it is the
                  // emphasised one rather than the float they typed.
                  emphasis: StatEmphasis.strong,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Today's figures.
///
/// Four tiles, in a grid whose column count comes from the WINDOW. Sales is the
/// emphasised one: it is the number the shop is judged on, and emphasis here is a
/// size difference rather than a colour, so it survives greyscale.
class DashboardKpis extends StatelessWidget {
  const DashboardKpis({
    required this.totals,
    required this.scopeLabel,
    super.key,
  });

  final DailyTotals totals;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
            label:
                AppLocalizations.of(context).dashboardSalesToday(scopeLabel)),
        SurfaceCard(
          padding: EdgeInsets.all(spacing.xs),
          child: Column(
            children: <Widget>[
              StatTile(
                label: AppLocalizations.of(context).dashboardSalesLabel,
                value: formatMoney(
                  Money.fromMinor(totals.totalMinor),
                ),
                emphasis: StatEmphasis.strong,
                caption: AppLocalizations.of(context)
                    .dashboardTransactionCaption(totals.transactions),
              ),
              Divider(height: 1, color: AppColors.of(context).outline),
              _Pair(
                label: AppLocalizations.of(context).dashboardProfitLabel,
                value: formatMoney(
                  Money.fromMinor(totals.profitMinor),
                ),
              ),
              Divider(height: 1, color: AppColors.of(context).outline),
              _Pair(
                label: AppLocalizations.of(context).dashboardAverageSaleLabel,
                value: formatMoney(
                  Money.fromMinor(totals.averageMinor),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(AppSpacing.of(context).xs),
      child: KeyValueRow(label: label, value: value),
    );
  }
}

/// "12 items need reordering" as a single tappable card.
///
/// One card rather than a list of twelve, because the ACTION is the same for all
/// twelve: go to Inventory, which is already filtered to what is low.
class DashboardLowStockCard extends StatelessWidget {
  const DashboardLowStockCard({
    required this.count,
    required this.onOpen,
    super.key,
  });

  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    final AppSpacing spacing = AppSpacing.of(context);
    final bool isLowCount = count <= 5;

    return SurfaceCard(
      onTap: onOpen,
      semanticLabel:
          AppLocalizations.of(context).dashboardLowStockSpoken(count),
      child: Row(
        children: <Widget>[
          CountBadge(
            count: count,
            noun: AppLocalizations.of(context).dashboardLowStockNoun(count),
            tone: isLowCount ? StatusTone.warning : StatusTone.danger,
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Text(
              isLowCount
                  ? AppLocalizations.of(context).dashboardLowStockFewMessage
                  : AppLocalizations.of(context).dashboardLowStockManyMessage,
              style: AppTypography.of(context).bodyMedium,
            ),
          ),
          Icon(
            Icons.chevron_right,
            // Auto-mirrors under RTL: `chevron_right` is declared with
            // `matchTextDirection: true`.
            color: AppColors.of(context).onSurfaceMuted,
          ),
        ],
      ),
    );
  }
}

/// A day with no sales at all.
///
/// Distinct from a day with no sales YET: a till that has never sold needs the
/// words "no sales recorded yet", and a till that sold yesterday but has not
/// today needs "nothing sold today". One screen saying "Sales today KSh 0" for
/// both cannot tell them apart, and the first is a setup problem.
class DashboardNoSalesCard extends StatelessWidget {
  const DashboardNoSalesCard({required this.hasEverSold, super.key});

  final bool hasEverSold;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    return SurfaceCard(
      child: Column(
        children: <Widget>[
          Icon(
            hasEverSold ? Icons.nightlight_outlined : Icons.storefront_outlined,
            color: colors.onSurfaceMuted,
          ),
          SizedBox(height: spacing.md),
          Text(
            hasEverSold
                ? AppLocalizations.of(context).dashboardNoSalesTitle
                : AppLocalizations.of(context).dashboardNoSalesMessage,
            textAlign: TextAlign.center,
            style: AppTypography.of(context).titleMedium,
          ),
          SizedBox(height: spacing.sm),
          Text(
            hasEverSold
                ? 'That is normal if you have not opened.'
                : 'Sales will appear here as soon as the first sale goes '
                    'through the till.',
            textAlign: TextAlign.center,
            style: AppTypography.of(context).bodyMedium?.copyWith(
                  color: colors.onSurfaceMuted,
                ),
          ),
        ],
      ),
    );
  }
}

/// Sales by hour.
///
/// The chart is a real element with a heading and a semantics label, not a
/// painted decoration: a screen-reader user gets "Sales by hour. Busiest at 6pm
/// with KSh 12,400" rather than silence where a picture should be.
class DashboardHourlySales extends StatelessWidget {
  const DashboardHourlySales({required this.buckets, super.key});

  final List<TimeBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    // The busiest hour, computed here rather than in the loading code, because it
    // is a PRESENTATION fact about this list — the same buckets rendered on the
    // analytics screen may not want it.
    TimeBucket? peak;
    for (final TimeBucket bucket in buckets) {
      if (bucket.salesMinor > 0 &&
          (peak == null || bucket.salesMinor > peak.salesMinor)) {
        peak = bucket;
      }
    }

    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(label: l10n.dashboardSalesByHour),
        SurfaceCard(
          child: SimplePosChart(
            title: l10n.dashboardSalesByHour,
            semanticsLabel: peak == null
                ? l10n.dashboardSalesByHourEmpty
                : l10n.dashboardPeakHourSpoken(
                    _hourLabel(peak.hour, l10n),
                    formatMoney(Money.fromMinor(peak.salesMinor)),
                  ),
            emphasis: peak == null
                ? null
                : l10n.dashboardBusiestHour(_hourLabel(peak.hour, l10n)),
            axis: PosChartAxis.vertical,
            bars: <PosChartBar>[
              for (final TimeBucket bucket in buckets)
                PosChartBar(
                  label: _hourLabel(bucket.hour, AppLocalizations.of(context)),
                  value: bucket.salesMinor,
                  valueLabel: formatMoney(
                    Money.fromMinor(bucket.salesMinor),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: spacing.xs),
      ],
    );
  }

  /// `14` -> `2:00 pm`, in the locale's own clock convention.
  ///
  /// `intl` rather than three hand-written cases, because a 12-hour locale is not
  /// the only difference: `DateFormat.jm` knows which locales put the meridiem
  /// first, which use a dot, and which have no AM/PM at all. Hand-rolling it is
  /// how an app ends up with a chart labelled in American time in a market that
  /// writes `14h`.
  static String _hourLabel(int hour, AppLocalizations l10n) =>
      DateFormat.jm(l10n.localeName).format(DateTime(2000, 1, 1, hour));
}

/// What actually sold, most first.
class DashboardTopProducts extends StatelessWidget {
  const DashboardTopProducts({required this.rows, super.key});

  final List<ProductSalesRow> rows;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(label: 'Top products'),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < rows.length; i++)
                KeyValueRow(
                  label: rows[i].productName,
                  value: formatMoney(
                    Money.fromMinor(rows[i].revenueMinor),
                  ),
                  // Unit count beside the money, because a product with KSh 900
                  // of revenue from one sale and one from nine look identical
                  // otherwise.
                  trailing: Text(
                    '${rows[i].units}',
                    style: AppTypography.of(context).labelSmall,
                  ),
                  showDivider: i != rows.length - 1,
                ),
            ],
          ),
        ),
        SizedBox(height: spacing.xs),
      ],
    );
  }
}

/// The low-stock list, capped.
///
/// Capped at five with a "see all" affordance rather than scrolled: the point of
/// this block on a home screen is the SHAPE of the problem (a handful urgent
/// versus forty), not the full list. The full list is one tap away and already
/// filtered.
class DashboardLowStockList extends StatelessWidget {
  const DashboardLowStockList({
    required this.products,
    required this.totalCount,
    required this.onOpenProduct,
    required this.onViewAll,
    super.key,
  });

  final List<Product> products;
  final int totalCount;
  final ValueChanged<Product> onOpenProduct;
  final VoidCallback onViewAll;

  static const int _cap = 5;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    final AppSpacing spacing = AppSpacing.of(context);
    final List<Product> shown = products.take(_cap).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          label: AppLocalizations.of(context).dashboardReorderSection,
          trailing: TextButton(
            onPressed: onViewAll,
            child: Text(AppLocalizations.of(context).dashboardSee(totalCount)),
          ),
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < shown.length; i++)
                KeyValueRow(
                  label: shown[i].name,
                  // A "0.0" for a product sold in whole units is noise; the unit
                  // column is only worth showing when the stock is fractional.
                  value: '${shown[i].stockQty.round()} in stock',
                  trailing: shown[i].isLow
                      ? const StatusChip(
                          tone: StatusTone.warning,
                          text: 'Low',
                          dense: true,
                        )
                      : null,
                  // The identity handed back is the row itself, and the caller
                  // re-reads the id from it. A closure that captured an id at
                  // render time opens the wrong product if the list re-sorts
                  // between the tap and the handler running.
                  onTap: () => onOpenProduct(shown[i]),
                  showDivider: i != shown.length - 1,
                ),
            ],
          ),
        ),
        SizedBox(height: spacing.xs),
      ],
    );
  }
}
