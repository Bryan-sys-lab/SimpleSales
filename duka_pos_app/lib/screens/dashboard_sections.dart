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
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;

  /// The one figure the shop is judged on. Bigger, and tinted.
  final bool hero;

  /// Set when the card is a door: a count of transactions is the figure a
  /// manager opens the list of.
  final VoidCallback? onTap;
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
    this.onTransactions,
    super.key,
  });

  final DailyTotals totals;
  final String scopeLabel;

  /// Where the transactions card goes. Null for a caller that cannot navigate
  /// — a preview, or a role the list is not offered to.
  final VoidCallback? onTransactions;

  /// Below this the four cards go two by two.
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
      ),
      _Kpi(
        icon: Icons.trending_up_outlined,
        label: l10n.dashboardProfitLabel,
        value: formatMoney(Money.fromMinor(totals.profitMinor)),
      ),
      _Kpi(
        icon: Icons.receipt_long_outlined,
        label: l10n.dashboardTransactionsLabel,
        value: '${totals.transactions}',
        // A door, not a figure: the count is the question "who sold these?" and
        // the list is the answer. Without a target the card stays inert.
        onTap: onTransactions,
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

/// Sales by hour.
///
/// The chart is a real element with a heading and a semantics label, not a
/// painted decoration: a screen-reader user gets "Sales by hour. Busiest at 6pm
/// with KSh 12,400" rather than silence where a picture should be.
/// The hourly sales line chart, and the shape of the day.
///
/// StateFUL rather than stateless, and the reason is the cache below: it is a
/// value derived from `buckets` that is expensive to compute (a locale
/// formatter per bucket) and that must survive a rebuild. A `StatelessWidget`
/// cannot hold it, and building it in `build()` is what the previous version
/// did — the ~30-object allocation on every dashboard rebuild the cache exists
/// to remove.
/// Whether two bucket lists hold the same content.
///
/// Compares by value rather than identity because the caller rebuilds the list
/// on every data load: `identity` would report an unchanged day as changed, and
/// a cache that never hits is a cache that does nothing.
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
  /// Memoised points. Null until the first call to [_points].
  List<PosLinePoint>? _cachedPoints;

  /// The points for the chart, formatted once.
  ///
  /// EVERY bucket in the window is included, including the hours that sold
  /// nothing. The x axis is index-based — `_LineChartPainter._x` spaces points
  /// evenly across the width — so dropping the empty hours would move every
  /// later point left and flatten a day that sold at 9am and 5pm into one
  /// adjacent pair, which is exactly the false "continuous sales" reading the
  /// line chart exists to avoid. A zero hour plots at the baseline instead.
  ///
  /// Invalidated when the buckets themselves change, so a fresh day's data is
  /// reformatted rather than shown with yesterday's labels — which is the
  /// failure mode of any cache keyed on nothing.
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
    return SurfaceCard(
      padding: EdgeInsets.all(spacing.xl),
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
                  Icon(
                    Icons.nightlight_outlined,
                    size: 32,
                    color: AppColors.of(context).onSurfaceMuted,
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

  /// `14` -> `2:00 pm`, in the locale's own clock convention. The full form,
  /// for the peak-hour badge a shop reads as a sentence.
  ///
  /// `intl` rather than three hand-written cases, because a 12-hour locale is not
  /// the only difference: `DateFormat.jm` knows which locales put the meridiem
  /// first, which use a dot, and which have no AM/PM at all.
  static String _hourLabel(int hour, AppLocalizations l10n) =>
      DateFormat.jm(l10n.localeName).format(DateTime(2000, 1, 1, hour));

  /// `14` -> `2pm`, for the axis.
  ///
  /// The full form belongs in a sentence; across a phone's width, twenty-four of
  /// them are the row of collisions this replaces. The ":00" every hour carries
  /// no information — an hour is an hour — and dropping it is what lets the axis
  /// sit at a readable interval instead of being thinned until it disappears.
  /// The locale convention survives: the meridiem, the digit order, the dot,
  /// and a 24-hour locale's shape are all still there.
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
          Icon(
            Icons.trending_up,
            size: 14,
            color: colors.accent,
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
              child: Icon(
                Icons.check_circle_outline,
                color: colors.success,
                size: 24,
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

    final bool isOut = product.stockQty <= 0;
    final StatusTone tone = isOut ? StatusTone.danger : StatusTone.warning;

    return InkWell(
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
              child: Icon(
                tone.icon,
                size: 20,
                color: tone.onContainer(colors),
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
                    // This was `maxLines: 1` with an ellipsis, which shows
                    // "Tusker Lager 500ml Returnab…" — a name cut at the point
                    // where the product is least recognisable. The repo's own
                    // stated policy for this exact case lives a file over, in
                    // analytics_tables.dart: "Nothing is dropped and nothing
                    // is truncated: a product name wraps instead of being
                    // ellipsised, because a truncated product name in a report
                    // is a defect, not a design." The dashboard is where an
                    // owner acts on low stock, so it needs to be readable here
                    // most of all.
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
    );
  }
}
