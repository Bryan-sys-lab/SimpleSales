// The body of the dashboard: the figures, the shift, and the lists a manager
// actually reads.
//
// Three conventions run through this file, and all three exist because a till is
// looked at from arm's length by someone serving a customer:
//
//   * Every figure is set in TABULAR figures. A row of totals that shifts
//     sideways as the digits change cannot be compared down the column, which is
//     the only reason to put a column there.
//   * Emphasis is SIZE, not colour. The sales figure is the biggest thing on the
//     screen; its tinted card is decoration on top of that, so the hierarchy
//     survives greyscale.
//   * Lists are one panel with a hairline between rows, never a card per item. A
//     table of twenty low-stock lines rendered as twenty cards is a wall of
//     borders with no scannable alignment.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/analytics.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../utils/datetime_format.dart';
import '../utils/money.dart';
import '../widgets/chart.dart';

// ---------------------------------------------------------------------------
// The panel every section sits in.
// ---------------------------------------------------------------------------

/// A titled card: a header row, a hairline, then the content.
///
/// One component for every section so the dashboard reads as a grid of equals
/// rather than a stack of differently-dressed boxes. The header is a fixed
/// minimum height — the same as a tap target — so a panel with an action in its
/// header and a panel without one line up when they sit side by side.
class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    required this.title,
    required this.child,
    this.trailing,
    this.padChild = true,
    super.key,
  });

  final String title;
  final Widget child;

  /// A status chip or a "See all" button, on the title's line.
  final Widget? trailing;

  /// Off for a list that draws its own rows edge to edge.
  final bool padChild;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    return SurfaceCard(
      padding: EdgeInsets.zero,
      clipContent: true,
      // A transparent Material INSIDE the card, so a tappable row's ripple is
      // painted above the card's opaque fill. Without it the nearest Material
      // is the Scaffold's, which sits behind the card and hides the ink.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: spacing.minTapTarget),
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: spacing.xl,
                  end: spacing.md,
                  top: spacing.sm,
                  bottom: spacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: AppTypography.of(context).titleMedium,
                        ),
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colors.outline),
            if (padChild)
              Padding(padding: EdgeInsets.all(spacing.xl), child: child)
            else
              child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today's figures.
// ---------------------------------------------------------------------------

class _Kpi {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.hero = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;

  /// The one figure the shop is judged on. Bigger, and tinted.
  final bool hero;
}

/// Today's four figures, in a row on a wide window and a 2 x 2 grid on a phone.
///
/// Sales is the emphasised one: it is larger and sits on the accent container.
/// The cards in a row are stretched to the tallest, so a card with a caption and
/// one without still share a top and a bottom edge.
class DashboardKpis extends StatelessWidget {
  const DashboardKpis({
    required this.totals,
    required this.scopeLabel,
    super.key,
  });

  final DailyTotals totals;
  final String scopeLabel;

  /// Below this the four cards go two by two.
  static const double _rowBreakpoint = 720;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    final List<_Kpi> kpis = <_Kpi>[
      _Kpi(
        icon: Icons.payments_outlined,
        label: l10n.dashboardSalesLabel,
        value: formatMoney(Money.fromMinor(totals.totalMinor)),
        caption: l10n.dashboardSalesToday(scopeLabel),
        hero: true,
      ),
      _Kpi(
        icon: Icons.trending_up_outlined,
        label: l10n.dashboardProfitLabel,
        value: formatMoney(Money.fromMinor(totals.profitMinor)),
      ),
      _Kpi(
        icon: Icons.receipt_long_outlined,
        label: 'Transactions',
        value: '${totals.transactions}',
      ),
      _Kpi(
        icon: Icons.shopping_basket_outlined,
        label: l10n.dashboardAverageSaleLabel,
        value: formatMoney(Money.fromMinor(totals.averageMinor)),
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool row = constraints.maxWidth >= _rowBreakpoint;
        final double gap = spacing.lg;

        Widget card(int i) => _KpiCard(kpi: kpis[i], compact: !row);

        if (row) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(flex: 3, child: card(0)),
                for (int i = 1; i < kpis.length; i++) ...<Widget>[
                  SizedBox(width: gap),
                  Expanded(flex: 2, child: card(i)),
                ],
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: card(0)),
                  SizedBox(width: gap),
                  Expanded(child: card(1)),
                ],
              ),
            ),
            SizedBox(height: gap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: card(2)),
                  SizedBox(width: gap),
                  Expanded(child: card(3)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi, required this.compact});

  final _Kpi kpi;

  /// Phone-width cards are ~160dp across, so the figure steps down a size
  /// rather than wrapping a currency symbol onto its own line.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    final bool hero = kpi.hero;
    final Color ink = hero ? colors.onAccentContainer : colors.onSurface;
    final Color quiet = hero ? colors.onAccentContainer : colors.onSurfaceMuted;
    final double size = hero ? (compact ? 22 : 28) : (compact ? 18 : 22);

    return Semantics(
      container: true,
      label: kpi.caption == null
          ? '${kpi.label}: ${kpi.value}'
          : '${kpi.label}: ${kpi.value}. ${kpi.caption}',
      child: ExcludeSemantics(
        child: SurfaceCard(
          color: hero ? colors.accentContainer : null,
          padding: EdgeInsets.all(spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      kpi.label,
                      style: type.labelMedium?.copyWith(color: quiet),
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  Icon(kpi.icon, size: 18, color: quiet),
                ],
              ),
              SizedBox(height: spacing.lg),
              // Not shrunk to fit and not truncated: a figure that wraps at 200%
              // text scale grows its card, because a clipped total is a wrong
              // total.
              Text(
                kpi.value,
                style: AppTypography.money(
                  context,
                  size: size,
                  weight: hero ? FontWeight.w800 : FontWeight.w700,
                ).copyWith(color: ink),
              ),
              if (kpi.caption != null) ...<Widget>[
                SizedBox(height: spacing.sm),
                Text(
                  kpi.caption!,
                  style: type.bodySmall?.copyWith(color: quiet),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The shift.
// ---------------------------------------------------------------------------

/// The open shift, and what the drawer should hold.
///
/// The expected figure is stated as a NUMBER, because the count the cashier will
/// do is compared against it. A card that only said "shift open since 08:12"
/// gives them nothing to reconcile against.
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
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Shift? open = shift;

    if (open == null) {
      return DashboardPanel(
        title: 'Till shift',
        // Two channels, never colour alone: the word, and the outlined shape a
        // neutral chip has that a filled one does not.
        trailing: const StatusChip(tone: StatusTone.neutral, text: 'No shift'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.dashboardNoShiftMessage,
              style: type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
            ),
            SizedBox(height: spacing.xl),
            FilledButton(
              onPressed: onOpen,
              child: Text(l10n.dashboardOpenShiftAction),
            ),
          ],
        ),
      );
    }

    // The stored value is an ISO instant; this is the owner's wording of it.
    final String since = formatInstant(open.startTime, locale: l10n.localeName);

    return DashboardPanel(
      title: 'Till shift',
      // Three channels: the glyph's shape, the word "Open", and the accent. A
      // cashier who cannot separate amber from green still hears the state.
      trailing: const StatusChip(tone: StatusTone.success, text: 'Open'),
      padChild: false,
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: l10n.dashboardOpenShiftSpoken(formatMoney(expected), since),
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: EdgeInsets.all(spacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.dashboardStaffNameSince(open.staffName, since),
                  style: type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
                ),
                SizedBox(height: spacing.xl),
                Text(
                  l10n.dashboardExpectedInDrawer,
                  style: type.labelMedium?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
                SizedBox(height: spacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        formatMoney(expected),
                        // The figure the count is measured against, so it is
                        // the emphasised one.
                        style: AppTypography.money(
                          context,
                          size: 24,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                    // Auto-mirrors under RTL.
                    Icon(Icons.chevron_right, color: colors.onSurfaceMuted),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sales.
// ---------------------------------------------------------------------------

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
    final AppLocalizations l10n = AppLocalizations.of(context);

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.xxl),
      child: Column(
        children: <Widget>[
          Icon(
            hasEverSold ? Icons.nightlight_outlined : Icons.storefront_outlined,
            size: 32,
            color: colors.onSurfaceMuted,
          ),
          SizedBox(height: spacing.lg),
          Text(
            hasEverSold
                ? l10n.dashboardNoSalesTitle
                : l10n.dashboardNoSalesMessage,
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
    final AppLocalizations l10n = AppLocalizations.of(context);

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

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.xl),
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
              label: _hourLabel(bucket.hour, l10n),
              value: bucket.salesMinor,
              valueLabel: formatMoney(
                Money.fromMinor(bucket.salesMinor),
              ),
            ),
        ],
      ),
    );
  }

  /// `14` -> `2:00 pm`, in the locale's own clock convention.
  ///
  /// `intl` rather than three hand-written cases, because a 12-hour locale is not
  /// the only difference: `DateFormat.jm` knows which locales put the meridiem
  /// first, which use a dot, and which have no AM/PM at all.
  static String _hourLabel(int hour, AppLocalizations l10n) =>
      DateFormat.jm(l10n.localeName).format(DateTime(2000, 1, 1, hour));
}

/// What actually sold, most first.
///
/// Each row carries a bar scaled to the best seller, so the SHAPE of the day —
/// one product carrying it, or five evenly — is visible without reading a number.
class DashboardTopProducts extends StatelessWidget {
  const DashboardTopProducts({required this.rows, super.key});

  final List<ProductSalesRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    int best = 0;
    for (final ProductSalesRow row in rows) {
      if (row.revenueMinor > best) best = row.revenueMinor;
    }

    return DashboardPanel(
      title: 'Top products',
      padChild: false,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++)
            _TopProductRow(
              rank: i + 1,
              row: rows[i],
              share: best == 0 ? 0.0 : rows[i].revenueMinor / best,
              showDivider: i != rows.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TopProductRow extends StatelessWidget {
  const _TopProductRow({
    required this.rank,
    required this.row,
    required this.share,
    required this.showDivider,
  });

  final int rank;
  final ProductSalesRow row;

  /// 0..1, revenue relative to the best seller shown.
  final double share;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    final String revenue = formatMoney(Money.fromMinor(row.revenueMinor));
    final double units = row.units;
    // "3", not "3.0" — a fraction is only worth showing when stock is fractional.
    final String sold = units == units.roundToDouble()
        ? '${units.round()} sold'
        : '${units.toStringAsFixed(1)} sold';

    return Semantics(
      container: true,
      label: '${row.productName}, $sold, $revenue',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.xl,
                vertical: spacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: spacing.xxl,
                        child: Text(
                          '$rank',
                          style: type.labelMedium?.copyWith(
                            color: colors.onSurfaceMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(row.productName, style: type.bodyMedium),
                      ),
                      SizedBox(width: spacing.md),
                      Text(
                        revenue,
                        style: AppTypography.money(
                          context,
                          size: 14,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.md),
                  Row(
                    children: <Widget>[
                      SizedBox(width: spacing.xxl),
                      Expanded(child: _ShareBar(fraction: share)),
                      SizedBox(width: spacing.md),
                      Text(sold, style: type.labelSmall),
                    ],
                  ),
                ],
              ),
            ),
            if (showDivider) Divider(height: 1, color: colors.outline),
          ],
        ),
      ),
    );
  }
}

/// A thin proportional bar: a track, and a fill to [fraction] of it.
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.fraction});

  final double fraction;

  static const double _height = 6;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppShapes shapes = AppShapes.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // A floor so a product with a sliver of the best seller's revenue still
        // draws a bar rather than vanishing into the track.
        final double filled =
            constraints.maxWidth * fraction.clamp(0.04, 1.0).toDouble();
        return ClipRRect(
          borderRadius: shapes.chipRadius,
          child: Stack(
            children: <Widget>[
              Container(
                height: _height,
                width: constraints.maxWidth,
                color: colors.surfaceSunken,
              ),
              Container(
                height: _height,
                width: filled,
                color: colors.accent,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Stock.
// ---------------------------------------------------------------------------

/// The low-stock list, capped.
///
/// Capped at five with a "see all" affordance rather than scrolled: the point of
/// this block on a home screen is the SHAPE of the problem (a handful urgent
/// versus forty), not the full list.
///
/// [canOpen] is whether this session may act on stock at all. A cashier sees what
/// is running low — it changes what they tell a customer — but the rows are
/// plain text for them: tapping one used to bounce off the role guard back to the
/// dashboard, which reads as a broken button.
class DashboardLowStockList extends StatelessWidget {
  const DashboardLowStockList({
    required this.products,
    required this.totalCount,
    required this.canOpen,
    required this.onOpenProduct,
    required this.onViewAll,
    super.key,
  });

  final List<Product> products;
  final int totalCount;
  final bool canOpen;
  final ValueChanged<Product> onOpenProduct;
  final VoidCallback onViewAll;

  static const int _cap = 5;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    if (products.isEmpty) {
      return DashboardPanel(
        title: l10n.dashboardReorderSection,
        trailing: const StatusChip(tone: StatusTone.success, text: 'All clear'),
        child: Row(
          children: <Widget>[
            Icon(Icons.inventory_2_outlined, color: colors.onSurfaceMuted),
            SizedBox(width: spacing.lg),
            Expanded(
              child: Text(
                'Nothing is at or below its reorder level.',
                style: AppTypography.of(context).bodyMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    final List<Product> shown = products.take(_cap).toList(growable: false);

    return DashboardPanel(
      title: l10n.dashboardReorderSection,
      trailing: canOpen
          ? TextButton(
              onPressed: onViewAll,
              child: Text(l10n.dashboardSee(totalCount)),
            )
          : Padding(
              padding: EdgeInsetsDirectional.only(end: spacing.md),
              child: CountBadge(
                count: totalCount,
                noun: l10n.dashboardLowStockNoun(totalCount),
                tone: totalCount <= 5 ? StatusTone.warning : StatusTone.danger,
              ),
            ),
      padChild: false,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < shown.length; i++)
            KeyValueRow(
              label: shown[i].name,
              // A "0.0" for a product sold in whole units is noise.
              value: '${shown[i].stockQty.round()} in stock',
              trailing: shown[i].stockQty <= 0
                  ? const StatusChip(
                      tone: StatusTone.danger,
                      text: 'Out',
                      dense: true,
                    )
                  : const StatusChip(
                      tone: StatusTone.warning,
                      text: 'Low',
                      dense: true,
                    ),
              // The identity handed back is the row itself, and the caller
              // re-reads the id from it. A closure that captured an id at
              // render time opens the wrong product if the list re-sorts
              // between the tap and the handler running.
              onTap: canOpen ? () => onOpenProduct(shown[i]) : null,
              showDivider: i != shown.length - 1,
            ),
        ],
      ),
    );
  }
}
