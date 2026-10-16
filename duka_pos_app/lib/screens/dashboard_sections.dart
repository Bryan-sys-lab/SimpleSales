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
//
// Traversal order is authored, not inherited: the shift card and the sales
// figure outrank the top-products list even though they sit lower on screen, so
// each panel carries an OrdinalSortKey a linear scanner can trust.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import '../ui/brand/simple_pos_mark.dart';
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
///
/// [sortKey] authors traversal priority independent of layout: a panel that
// matters more (the shift, the sales figure) is reached first by a linear
/// scanner even when it is not the first panel on screen.
class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    required this.title,
    required this.child,
    this.trailing,
    this.padChild = true,
    this.sortKey,
    super.key,
  });

  final String title;
  final Widget child;

  /// A status chip or a "See all" button, on the title's line.
  final Widget? trailing;

  final bool padChild;

  final double? sortKey;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    final Widget card = SurfaceCard(
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

    if (sortKey == null) return card;

    return Semantics(
      sortKey: OrdinalSortKey(sortKey!),
      child: card,
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
    this.onTap,
    this.sortKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;

  final bool hero;

  final VoidCallback? onTap;

  final double? sortKey;
}

class DashboardKpis extends StatelessWidget {
  const DashboardKpis({
    required this.totals,
    required this.scopeLabel,
    this.onTransactions,
    super.key,
  });

  final DailyTotals totals;
  final String scopeLabel;

  final VoidCallback? onTransactions;

  static const double _rowBreakpoint = 720;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    final List<_Kpi> kpis = <_Kpi>[
      _Kpi(
        icon: Icons.point_of_sale_outlined,
        label: l10n.dashboardSalesLabel,
        value: formatMoney(Money.fromMinor(totals.totalMinor)),
        caption: l10n.dashboardSalesToday(scopeLabel),
        hero: true,
        sortKey: 0,
      ),
      _Kpi(
        icon: Icons.trending_up_outlined,
        label: l10n.dashboardProfitLabel,
        value: formatMoney(Money.fromMinor(totals.profitMinor)),
        sortKey: 1,
      ),
      _Kpi(
        icon: Icons.receipt_long_outlined,
        label: l10n.dashboardTransactionsLabel,
        value: '${totals.transactions}',
        // A door, not a figure: the count is the question "who sold these?" and
        // the list is the answer. Without a target the card stays inert.
        onTap: onTransactions,
        sortKey: 2,
      ),
      _Kpi(
        icon: Icons.shopping_basket_outlined,
        label: l10n.dashboardAverageSaleLabel,
        value: formatMoney(Money.fromMinor(totals.averageMinor)),
        sortKey: 3,
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

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    final bool hero = kpi.hero;
    final Color ink = hero ? colors.onAccentContainer : colors.onSurface;
    final Color quiet = hero ? colors.onAccentContainer : colors.onSurfaceMuted;
    final double size = hero ? (compact ? 22 : 32) : (compact ? 18 : 24);
    final bool isDoor = kpi.onTap != null;

    // A card that opens something says so, twice: once to a screen reader, and
    // once as a chevron for everyone else. A count with no way in is a figure
    // the reader then has to go hunting for.
    return Semantics(
      container: true,
      button: isDoor,
      label: kpi.caption == null
          ? '${kpi.label}: ${kpi.value}'
          : '${kpi.label}: ${kpi.value}. ${kpi.caption}',
      child: ExcludeSemantics(
        child: SurfaceCard(
          color: hero ? colors.accentContainer : null,
          padding: EdgeInsets.all(spacing.xl),
          onTap: kpi.onTap,
          child: Stack(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        padding: EdgeInsets.all(spacing.xs),
                        decoration: BoxDecoration(
                          color: hero
                              ? colors.accent.withValues(alpha: 0.15)
                              : colors.surfaceSunken,
                          borderRadius: AppShapes.of(context).controlRadius,
                        ),
                        child: Icon(
                          kpi.icon,
                          size: hero ? 22 : 18,
                          color: hero ? colors.accent : quiet,
                        ),
                      ),
                      SizedBox(width: spacing.md),
                      Expanded(
                        child: Text(
                          kpi.label,
                          style: type.labelMedium?.copyWith(color: quiet),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
              // The affordance for a door: no icon colour change, one chevron
              // in the corner — the label already says what the card is and the
              // figure is why you would open it.
              //
              // `PositionedDirectional` puts it on the true leading edge, which
              // is the whole of the RTL work: a direction-aware ICON would have
              // to pick between two glyphs, and a chevron that points the way
              // the layout reads is the same picture either way round here.
              if (isDoor)
                PositionedDirectional(
                  top: spacing.xs,
                  end: spacing.xs,
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: quiet,
                  ),
                ),
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
      return Semantics(
        sortKey: OrdinalSortKey(0),
        child: DashboardPanel(
          title: 'Till shift',
          // Two channels, never colour alone: the word, and the outlined shape a
          // neutral chip has that a filled one does not.
          trailing:
              const StatusChip(tone: StatusTone.neutral, text: 'No shift'),
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
        ),
      );
    }

    // The stored value is an ISO instant; this is the owner's wording of it.
    final String since = formatInstant(open.startTime, locale: l10n.localeName);

    return Semantics(
      sortKey: const OrdinalSortKey(0),
      button: true,
      label: l10n.dashboardOpenShiftSpoken(formatMoney(expected), since),
      child: DashboardPanel(
        title: 'Till shift',
        // Brand mark first: the till's identity sits beside the shift it runs.
        trailing: _ShiftBrand(),
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
                    style:
                        type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
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
      ),
    );
  }
}

class _ShiftBrand extends StatelessWidget {
  const _ShiftBrand();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'SimpleSales',
      child: ExcludeSemantics(
        child: const SimplePosMark(
          size: 22,
          variant: SimplePosMarkVariant.full,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sales.
// ---------------------------------------------------------------------------

class DashboardNoSalesCard extends StatelessWidget {
  const DashboardNoSalesCard({required this.hasEverSold, super.key});

  final bool hasEverSold;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DashboardPanel(
      sortKey: 1,
      title: l10n.dashboardNoSalesTitle,
      child: Column(
        children: <Widget>[
          Semantics(
            image: true,
            label: l10n.dashboardNoSalesTitle,
            child: ExcludeSemantics(
              child: Icon(
                hasEverSold
                    ? Icons.nightlight_outlined
                    : Icons.storefront_outlined,
                size: 32,
                color: colors.onSurfaceMuted,
              ),
            ),
          ),
          SizedBox(height: spacing.lg),
          Text(
            l10n.dashboardNoSalesTitle,
            textAlign: TextAlign.center,
            style: AppTypography.of(context).titleMedium,
          ),
          SizedBox(height: spacing.sm),
          Text(
            // The two body strings are the two halves of the same empty state:
            // one for "you have sold before, just not yet today", one for "you
            // have never sold". A hardcoded pair once stood here, and the two
            // keys that were supposed to carry it went unreferenced.
            hasEverSold
                ? l10n.dashboardNoSalesTodayBody
                : l10n.dashboardNoSalesFirstBody,
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

bool _bucketsEqual(List<TimeBucket> a, List<TimeBucket> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].hour != b[i].hour || a[i].salesMinor != b[i].salesMinor) {
      return false;
    }
  }
  return true;
}

class DashboardHourlySales extends StatefulWidget {
  const DashboardHourlySales({required this.buckets, super.key});

  final List<TimeBucket> buckets;

  @override
  State<DashboardHourlySales> createState() => _DashboardHourlySalesState();
}

class _DashboardHourlySalesState extends State<DashboardHourlySales> {
  List<PosLinePoint>? _cachedPoints;

  List<PosLinePoint> _points(AppLocalizations l10n) {
    _cachedPoints ??= <PosLinePoint>[
      for (final TimeBucket bucket in widget.buckets)
        PosLinePoint(
          label: _axisHourLabel(bucket.hour, l10n),
          value: bucket.salesMinor,
          valueLabel: formatMoney(Money.fromMinor(bucket.salesMinor)),
        ),
    ];
    return _cachedPoints!;
  }

  @override
  void didUpdateWidget(covariant DashboardHourlySales oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_bucketsEqual(oldWidget.buckets, widget.buckets)) {
      _cachedPoints = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    // The busiest hour, computed here rather than in the loading code, because it
    // is a PRESENTATION fact about this list — the same buckets rendered on the
    // analytics screen may not want it.
    TimeBucket? peak;
    for (final TimeBucket bucket in widget.buckets) {
      if (bucket.salesMinor > 0 &&
          (peak == null || bucket.salesMinor > peak.salesMinor)) {
        peak = bucket;
      }
    }

    // "There is a peak" and "there are sales today" are the SAME fact, asked
    // once and used in both branches, rather than re-asked of the buckets a
    // second time and hoped to agree.
    final bool hasData = peak != null;

    // Formatted once per widget instance, not once per build. See [_points].
    final List<PosLinePoint> points = _points(l10n);
    return DashboardPanel(
      sortKey: 1,
      title: l10n.dashboardSalesByHour,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.dashboardSalesByHour,
                  style: AppTypography.of(context).titleMedium,
                ),
              ),
              if (hasData) ...[
                SizedBox(width: spacing.md),
                _PeakHourBadge(
                  hour: _hourLabel(peak.hour, l10n),
                  amount: formatMoney(Money.fromMinor(peak.salesMinor)),
                ),
              ],
            ],
          ),
          SizedBox(height: spacing.lg),
          if (!hasData)
            Center(
                child: Padding(
              padding: EdgeInsets.symmetric(vertical: spacing.xxl),
              child: Column(
                children: [
                  Semantics(
                    image: true,
                    label: l10n.dashboardNoSalesTitle,
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.nightlight_outlined,
                        size: 32,
                        color: AppColors.of(context).onSurfaceMuted,
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.md),
                  Text(
                    l10n.dashboardNoSalesTitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.of(context).titleMedium,
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                    l10n.dashboardNoSalesFirstBody,
                    textAlign: TextAlign.center,
                    style: AppTypography.of(context).bodyMedium?.copyWith(
                          color: AppColors.of(context).onSurfaceMuted,
                        ),
                  ),
                ],
              ),
            ))
          else
            // One bar per hour, and the money figure only when a bar is tapped.
            //
            // Bars, because an hourly total is a MAGNITUDE at a moment, not a
            // trajectory through one: "which hour was best" is a comparison of
            // lengths, which a bar answers at a glance and a line only after
            // being traced. The figure is hidden until a tap, because a painted
            // peak value over a picture of the answer is the one label most
            // likely to collide with the hour beneath it — and it is the answer
            // to a question the shop has not asked yet.
            //
            // No force-unwrap: `hasData` is DERIVED from `peak != null`, so
            // flow analysis already knows the peak exists in this branch.
            PosBarChart(
              title: '',
              semanticsLabel: l10n.dashboardPeakHourSpoken(
                formatMoney(Money.fromMinor(peak.salesMinor)),
                _hourLabel(peak.hour, l10n),
              ),
              height: 132,
              points: points,
            ),
        ],
      ),
    );
  }

  static String _hourLabel(int hour, AppLocalizations l10n) =>
      DateFormat.jm(l10n.localeName).format(DateTime(2000, 1, 1, hour));

  static String _axisHourLabel(int hour, AppLocalizations l10n) {
    final full = _hourLabel(hour, l10n);
    return full.replaceAll(':00 ', ' ').replaceAll(':00', '').trim();
  }
}

class _PeakHourBadge extends StatelessWidget {
  const _PeakHourBadge({required this.hour, required this.amount});

  final String hour;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final type = AppTypography.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.accentContainer,
        borderRadius: AppShapes.of(context).chipRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Peak hour $hour, $amount',
            child: ExcludeSemantics(
              child: Icon(
                Icons.trending_up,
                size: 14,
                color: colors.accent,
              ),
            ),
          ),
          SizedBox(width: spacing.xs),
          Text(
            '$hour · $amount',
            style: type.labelSmall?.copyWith(
              color: colors.onAccentContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

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
      sortKey: 2,
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
      button: true,
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
        sortKey: 3,
        title: l10n.dashboardReorderSection,
        trailing: StatusChip(
          tone: StatusTone.success,
          text: l10n.dashboardAllClear,
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: EdgeInsets.all(spacing.sm),
              decoration: BoxDecoration(
                color: colors.successContainer,
                borderRadius: AppShapes.of(context).controlRadius,
              ),
              child: Semantics(
                label: l10n.dashboardAllClear,
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.check_circle_outline,
                    color: colors.success,
                    size: 24,
                  ),
                ),
              ),
            ),
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
      sortKey: 3,
      title: l10n.dashboardReorderSection,
      trailing: canOpen
          ? TextButton.icon(
              onPressed: onViewAll,
              icon: Icon(Icons.chevron_right, size: 18),
              label: Text(l10n.dashboardSee(totalCount)),
            )
          : CountBadge(
              count: totalCount,
              noun: l10n.dashboardLowStockNoun(totalCount),
              tone: totalCount <= 5 ? StatusTone.warning : StatusTone.danger,
            ),
      padChild: false,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < shown.length; i++)
            _LowStockRow(
              product: shown[i],
              canOpen: canOpen,
              onTap: canOpen ? () => onOpenProduct(shown[i]) : null,
              showDivider: i != shown.length - 1,
            ),
        ],
      ),
    );
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({
    required this.product,
    required this.canOpen,
    required this.onTap,
    required this.showDivider,
  });

  final Product product;
  final bool canOpen;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);

    final bool isOut = product.stockQty <= 0;
    final StatusTone tone = isOut ? StatusTone.danger : StatusTone.warning;

    return Semantics(
      container: true,
      button: canOpen,
      label: '${product.name}, ${formatMoney(product.sellPrice)}, '
          '${product.stockQty.round()} in stock, ${isOut ? l10n.inventoryOutOfStock : l10n.inventoryLowStock}',
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.xl,
            vertical: spacing.md,
          ),
          child: Row(
            children: <Widget>[
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: tone.container(colors),
                  borderRadius: AppShapes.of(context).controlRadius,
                ),
                child: Semantics(
                  label: tone.label,
                  child: ExcludeSemantics(
                    child: Icon(
                      tone.icon,
                      size: 20,
                      color: tone.onContainer(colors),
                    ),
                  ),
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      product.name,
                      style: type.bodyMedium,
                      // Wraps rather than ellipsises.
                      //
                      // The row's `Semantics` label carries the full name, so
                      // this is a visual budget rather than a truncation of
                      // the data.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      '${product.stockQty.round()} in stock',
                      style: type.bodySmall?.copyWith(
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.md),
              StatusChip(
                tone: tone,
                text: isOut ? 'Out of stock' : 'Low stock',
                dense: true,
              ),
              if (canOpen) ...[
                SizedBox(width: spacing.sm),
                Icon(
                  Icons.chevron_right,
                  color: colors.onSurfaceMuted,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
