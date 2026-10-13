import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/home_shell.dart';
import '../routing/routes.dart';
import '../services/analytics.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../services/workspace_service.dart';
import '../services/live_refresh_mixin.dart';
import '../services/live_channel_service.dart';
import '../services/session_refresh_mixin.dart';
import '../ui/components/states.dart';
import '../ui/components/surface.dart';
import '../widgets/chart.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import 'analytics_tables.dart';

/// The windows the owner thinks in.
///
/// Named as lengths rather than as two dates: "last 7 days" is what someone
/// asks for at the counter, and it includes today. Keeping them as an enum
/// means the query, the label and the bar chart can never disagree about which
/// period is on screen.
enum AnalyticsRange {
  today('Today', 1),
  week('7 days', 7),
  month('30 days', 30),
  quarter('90 days', 90);

  const AnalyticsRange(this.label, this.days);

  final String label;

  /// Days of history the window covers, today included.
  final int days;

  /// Midnight today, and the start of the day [days] ago.
  ///
  /// `salesByDay`/`topProducts` take `since` inclusive, so a seven-day window
  /// starts six days back — seven days *including today*, which is what the
  /// label claims.
  DateTime get since {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: days - 1));
  }

  /// The window of equal length immediately before this one, as
  /// `[previousSince, until)`.
  ///
  /// Derived from [since] rather than from a second `DateTime.now()`, so the
  /// comparison window can never drift across midnight relative to the one it is
  /// being compared with — the two windows are adjacent by construction, which
  /// is the only way "up 12% on the week before" means anything.
  DateTime get previousSince => since.subtract(Duration(days: days));

  /// Exclusive end of the previous window, which is this window's start.
  DateTime get previousUntil => since;
}

/// Which column the product table is ordered by.
enum ProductSort {
  name('Product'),
  units('Units'),
  revenue('Revenue'),
  profit('Profit'),
  margin('Margin');

  const ProductSort(this.label);
  final String label;
}

/// Everything one load of this screen resolved to.
///
/// Built once, in [_AnalyticsScreenState._load], so that `build()` does no
/// formatting, no sorting and no aggregation: every string a user reads and
/// every `PosLinePoint` is already made by the time the widget tree is asked for
/// it.
@immutable
class AnalyticsSnapshot {
  const AnalyticsSnapshot({
    required this.totals,
    required this.previousTotals,
    required this.days,
    required this.products,
    required this.payments,
    required this.outOfStock,
    required this.lowStock,
  });

  /// What an empty range aggregates to, so the first frame renders real zeros
  /// instead of branching on a null.
  static const AnalyticsSnapshot empty = AnalyticsSnapshot(
    totals: DailyTotals.empty,
    previousTotals: DailyTotals.empty,
    days: <DateBucket>[],
    products: <ProductSalesRow>[],
    payments: <PaymentMixRow>[],
    outOfStock: <Product>[],
    lowStock: <Product>[],
  );

  final DailyTotals totals;
  final DailyTotals previousTotals;
  final List<DateBucket> days;
  final List<ProductSalesRow> products;
  final List<PaymentMixRow> payments;
  final List<Product> outOfStock;
  final List<Product> lowStock;

  bool get isEmpty =>
      !totals.hasSales &&
      products.isEmpty &&
      payments.isEmpty &&
      outOfStock.isEmpty &&
      lowStock.isEmpty;
}

/// Exactly one of these is on screen.
///
/// A sealed class rather than an `isLoading`/`error`/`data` trio: the three
/// flags can disagree with each other, and every one of the three combinations
/// they allow is a screen nobody designed. The loading case carries the
/// *previous* snapshot so a pull-to-refresh or a range change keeps the figures
/// on screen rather than blanking the shop's takings for the length of a query.
sealed class AnalyticsView {
  const AnalyticsView();
}

final class AnalyticsLoading extends AnalyticsView {
  const AnalyticsLoading(this.previous);
  final AnalyticsSnapshot previous;
}

final class AnalyticsFailure extends AnalyticsView {
  const AnalyticsFailure(this.message);
  final String message;
}

final class AnalyticsContent extends AnalyticsView {
  const AnalyticsContent(this.snapshot);
  final AnalyticsSnapshot snapshot;
}

/// The shop's trading over a chosen window.
///
/// Manager and owner only (the shell adds the destination for `canManageStock`):
/// the figures here are the whole shop's, including every cashier's takings and
/// every product's margin, which is not a cashier's to read. A cashier's own
/// numbers are on their dashboard, scoped by `staff_id`.
///
/// Nothing on this screen sums anything in Dart — each figure is one
/// aggregate query answered by SQLite, so a ninety-day window costs the same
/// as a one-day one.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with LiveRefresh<AnalyticsScreen>, SessionRefresh<AnalyticsScreen> {
  /// Whether to offer the all-shops view.
  ///
  /// Read from the local shop registry rather than the backend: the answer is
  /// "how many shops are on THIS device", which is a question the phone can
  /// already answer without a round trip — and an owner who has added a second
  /// shop deserves to see the link offline.
  bool _canShowPortfolio = false;

  AnalyticsRange _range = AnalyticsRange.week;
  ProductSort _sort = ProductSort.revenue;
  bool _ascending = false;

  AnalyticsView _view = const AnalyticsLoading(AnalyticsSnapshot.empty);

  /// The display order of the product table. Held rather than derived in
  /// `build()` so a rebuild is never also a sort.
  List<ProductSalesRow> _sortedProducts = const <ProductSalesRow>[];

  /// The chart's bars, merged and pre-formatted at load time.
  List<PosLinePoint> _salesPoints = const <PosLinePoint>[];

  /// Every figure here is a roll-up, so any reason applies.
  @override
  Set<LiveReason> get liveReasons => const <LiveReason>{};

  @override
  bool get liveIsVisible => TickerMode.valuesOf(context).enabled;

  @override
  Future<void> reloadFromLive() => _load();

  /// The session that was reading these figures has ended: the figures on
  /// screen were read for it, so they go. The shop's takings are not a
  /// session's to keep — a shell that outlives a sign-out must not offer them
  /// to whoever signs in next — and the empty snapshot is what makes the
  /// skeleton the only honest thing to draw while the new session's read is
  /// in flight.
  @override
  void clearForSession() {
    _view = const AnalyticsLoading(AnalyticsSnapshot.empty);
    _sortedProducts = const <ProductSalesRow>[];
    _salesPoints = const <PosLinePoint>[];
  }

  @override
  Future<void> reloadFromSession() => _load();

  @override
  void initState() {
    super.initState();
    _loadShopCount();
    _load();
  }

  Future<void> _loadShopCount() async {
    final int count = (await WorkspaceServiceShops.localShops()).length;
    if (!mounted) return;
    setState(() => _canShowPortfolio = count > 1);
  }

  Future<void> _load() async {
    final DatabaseHelper db = DatabaseHelper.instance;
    // The previous window rides along in the same batch: it is one more
    // aggregate query, and fetching it with the current one means the comparison
    // is answered by a single consistent read of the ledger rather than two
    // queries that could straddle a sale landing between them.
    final AnalyticsRange range = _range;
    final DateTime since = range.since;
    try {
      final List<Object> results = await Future.wait(<Future<Object>>[
        db.salesTotalsFor(since: since),
        db.salesByDay(since: since),
        db.topProducts(since: since, limit: 20),
        db.salesByPaymentMethod(since: since),
        db.getProducts(),
        db.salesTotalsFor(since: range.previousSince, until: since),
      ]);
      if (!mounted) return;
      final List<Product> products = results[4] as List<Product>;
      setState(() {
        _sortedProducts = _order(
          results[2] as List<ProductSalesRow>,
          _sort,
          _ascending,
        );
        _salesPoints = _salesChartPoints(results[1] as List<DateBucket>);
        _view = AnalyticsContent(
          AnalyticsSnapshot(
            totals: results[0] as DailyTotals,
            previousTotals: results[5] as DailyTotals,
            days: results[1] as List<DateBucket>,
            products: results[2] as List<ProductSalesRow>,
            payments: results[3] as List<PaymentMixRow>,
            // Two lists, not one: "out of stock" and "running low" are different
            // urgencies, and one list that quietly contains both is read as the
            // milder of the two.
            outOfStock: products.where((Product p) => p.stockQty <= 0).toList()
              ..sort((Product a, Product b) => a.name.compareTo(b.name)),
            lowStock: products
                .where((Product p) => p.stockQty > 0 && p.isLow)
                .toList()
              ..sort(
                  (Product a, Product b) => a.stockQty.compareTo(b.stockQty)),
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _view = AnalyticsFailure('Couldn’t load analytics.');
      });
    }
  }

  void _setRange(AnalyticsRange range) {
    if (range == _range) return;
    HapticTheme.of(context).fire(HapticEvent.select);
    setState(() {
      _range = range;
      // Previous content stays on screen under the skeleton. A range change is a
      // question, not a reset: blanking the takings to answer it reads as the
      // shop having sold nothing.
      _view = AnalyticsLoading(
        _view is AnalyticsContent
            ? (_view as AnalyticsContent).snapshot
            : AnalyticsSnapshot.empty,
      );
    });
    _load();
  }

  void _sortBy(ProductSort column) {
    HapticTheme.of(context).fire(HapticEvent.select);
    final List<ProductSalesRow> rows = _view is AnalyticsContent
        ? (_view as AnalyticsContent).snapshot.products
        : const <ProductSalesRow>[];
    setState(() {
      // Tapping the active column reverses it; a new column starts descending,
      // because the first thing anyone looks at in a top-sellers list is the
      // top of it.
      if (_sort == column) {
        _ascending = !_ascending;
      } else {
        _sort = column;
        _ascending = column == ProductSort.name;
      }
      _sortedProducts = _order(rows, _sort, _ascending);
    });
  }

  /// The order the table is displayed in, derived from the column the header
  /// says is sorted — so the arrow and the rows can never disagree.
  static List<ProductSalesRow> _order(
    List<ProductSalesRow> rows,
    ProductSort sort,
    bool ascending,
  ) {
    int compare(ProductSalesRow a, ProductSalesRow b) => switch (sort) {
          ProductSort.name =>
            a.productName.toLowerCase().compareTo(b.productName.toLowerCase()),
          ProductSort.units => a.units.compareTo(b.units),
          ProductSort.revenue => a.revenueMinor.compareTo(b.revenueMinor),
          ProductSort.profit => a.profitMinor.compareTo(b.profitMinor),
          ProductSort.margin => a.marginPct.compareTo(b.marginPct),
        };
    final List<ProductSalesRow> sorted = <ProductSalesRow>[...rows]
      ..sort(compare);
    return ascending ? sorted : sorted.reversed.toList();
  }

  /// 90 points is unreadable at any phone width; merging consecutive days keeps
  /// every shilling on the line while making the axis legible.
  static List<PosLinePoint> _salesChartPoints(List<DateBucket> days) {
    return <PosLinePoint>[
      for (final DateBucket day in mergeDateBuckets(days, 14))
        PosLinePoint(
          label: day.label,
          value: day.salesMinor,
          valueLabel: formatMoney(day.sales),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return switch (_view) {
      AnalyticsLoading(previous: final AnalyticsSnapshot previous) =>
        _AnalyticsScaffold(
          range: _range,
          onRangeChanged: _setRange,
          snapshot: previous,
          onRetry: _load,
          loading: true,
        ),
      AnalyticsFailure(message: final String message) => _AnalyticsScaffold(
          range: _range,
          onRangeChanged: _setRange,
          snapshot: AnalyticsSnapshot.empty,
          onRetry: _load,
          errorMessage: message,
        ),
      AnalyticsContent(snapshot: final AnalyticsSnapshot snapshot) =>
        _AnalyticsScaffold(
          range: _range,
          onRangeChanged: _setRange,
          snapshot: snapshot,
          onRetry: _load,
          onSortBy: _sortBy,
          sort: _sort,
          ascending: _ascending,
          sortedProducts: _sortedProducts,
          salesPoints: _salesPoints,
          chartSemantics: describeDailyBuckets(
            AppLocalizations.of(context).analyticsChartTitleSalesByDay,
            snapshot.days,
          ),
          chartEmphasis: snapshot.totals.hasSales
              ? '${formatMoney(snapshot.totals.total)} over ${_range.label.toLowerCase()}'
              : null,
          bottomInset: spacing.xl,
          onOpenPortfolio: () => context.push(Routes.portfolio),
          showPortfolioLink: _canShowPortfolio,
        ),
    };
  }
}

/// The page: the range control, then whichever of the four sections the snapshot
/// can fill.
///
/// [AdaptivePage] supplies the canvas and the safe-area inset; this adds the
/// pull-to-refresh and the vertical rhythm between sections.
class _AnalyticsScaffold extends StatelessWidget {
  const _AnalyticsScaffold({
    required this.range,
    required this.onRangeChanged,
    required this.snapshot,
    required this.onRetry,
    this.loading = false,
    this.errorMessage,
    this.onSortBy,
    this.sort = ProductSort.revenue,
    this.ascending = false,
    this.sortedProducts = const <ProductSalesRow>[],
    this.salesPoints = const <PosLinePoint>[],
    this.chartSemantics,
    this.chartEmphasis,
    this.bottomInset = 0,
    this.onOpenPortfolio,
    this.showPortfolioLink = false,
  });

  final AnalyticsRange range;
  final ValueChanged<AnalyticsRange> onRangeChanged;
  final AnalyticsSnapshot snapshot;
  final Future<void> Function() onRetry;
  final bool loading;

  /// Non-null means the load failed and there is nothing behind it.
  final String? errorMessage;

  final ValueChanged<ProductSort>? onSortBy;
  final ProductSort sort;
  final bool ascending;
  final List<ProductSalesRow> sortedProducts;
  final List<PosLinePoint> salesPoints;
  final String? chartSemantics;
  final String? chartEmphasis;
  final double bottomInset;

  /// Opens the all-shops view.
  final VoidCallback? onOpenPortfolio;

  /// Whether to offer it. An owner running one duka has no use for "All shops",
  /// and an affordance that answers a question they never asked is noise on the
  /// screen they use every day.
  final bool showPortfolioLink;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AnalyticsSnapshot shown =
        errorMessage != null ? AnalyticsSnapshot.empty : snapshot;

    return AdaptivePage(
      // A five-column table is legitimately wider than the prose cap, so the
      // window's own width is the limit here rather than 680.
      maxContentWidth: double.infinity,
      padding: EdgeInsets.zero,
      child: RefreshIndicator(
        onRefresh: onRetry,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsetsDirectional.only(
            start: spacing.md,
            end: spacing.md,
            top: spacing.md,
            bottom: spacing.xl + bottomInset,
          ),
          children: <Widget>[
            _RangeBar(range: range, onChanged: onRangeChanged),
            if (showPortfolioLink && onOpenPortfolio != null) ...<Widget>[
              SizedBox(height: spacing.md),
              SettingsNavRow(
                icon: Icons.insights_outlined,
                title: AppLocalizations.of(context).portfolioOpenAction,
                subtitle: AppLocalizations.of(context).portfolioOpenSubtitle,
                onTap: onOpenPortfolio,
              ),
            ],
            SizedBox(height: spacing.lg),
            if (loading)
              const SkeletonList(itemCount: 4)
            else if (errorMessage != null)
              _AnalyticsError(message: errorMessage!, onRetry: onRetry)
            else
              ..._content(context, shown),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, AnalyticsSnapshot shown) {
    final AppSpacing spacing = AppSpacing.of(context);
    return <Widget>[
      _RangeKpis(totals: shown.totals, range: range),
      SizedBox(height: spacing.md),
      _GrowthLine(
        current: shown.totals,
        previous: shown.previousTotals,
        range: range,
      ),
      SizedBox(height: spacing.lg),
      SurfaceCard(
        padding: EdgeInsetsDirectional.only(
          start: spacing.md,
          end: spacing.md,
          top: spacing.md,
          bottom: spacing.sm,
        ),
        // A line, not a column of dates. The question this chart answers is
        // "is the week trending up or down" — a direction, which a line renders
        // directly and fourteen bars ask the reader to derive.
        child: PosLineChart(
          title: AppLocalizations.of(context).analyticsChartTitleSalesByDay,
          emphasis: chartEmphasis,
          semanticsLabel: chartSemantics,
          height: 168,
          points: salesPoints,
        ),
      ),
      SizedBox(height: spacing.lg),
      ProductTableCard(
        rows: sortedProducts,
        sort: sort,
        ascending: ascending,
        onSort: onSortBy,
      ),
      SizedBox(height: spacing.lg),
      PaymentMixCard(rows: shown.payments, totals: shown.totals),
      SizedBox(height: spacing.lg),
      StockSection(outOfStock: shown.outOfStock, lowStock: shown.lowStock),
    ];
  }
}

/// The range control.
///
/// Four windows, all equally likely, so one tap each: a segmented control
/// rather than a dropdown. [SegmentedChoice] scrolls horizontally at large text
/// scales instead of squeezing, and names the group for a screen reader, which
/// would otherwise hear a row of unrelated buttons.
class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.range, required this.onChanged});

  final AnalyticsRange range;
  final ValueChanged<AnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedChoice<AnalyticsRange>(
      value: range,
      onChanged: onChanged,
      semanticLabel: 'Reporting period',
      options: <SegmentedOption<AnalyticsRange>>[
        for (final AnalyticsRange option in AnalyticsRange.values)
          SegmentedOption<AnalyticsRange>(value: option, label: option.label),
      ],
    );
  }
}

/// The range's headline figures.
///
/// Four [StatTile]s, whose value style is already tabular, in a [Wrap] rather
/// than a [Row]: a value that wraps at 200% text scale makes a taller tile
/// rather than a clipped number, and the second row simply reflows.
class _RangeKpis extends StatelessWidget {
  const _RangeKpis({required this.totals, required this.range});

  final DailyTotals totals;
  final AnalyticsRange range;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = (constraints.maxWidth - spacing.md) / 2;
        return Wrap(
          spacing: spacing.md,
          runSpacing: spacing.md,
          children: <Widget>[
            for (final Widget tile in _tiles(AppLocalizations.of(context)))
              SizedBox(
                width: width,
                child: SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: tile,
                ),
              ),
          ],
        );
      },
    );
  }

  /// The catalogue is passed in: this is called from `build`, which has the
  /// context, and reaching for a field here would mean a second lookup per tile
  /// row for no benefit.
  List<Widget> _tiles(AppLocalizations l10n) {
    return <Widget>[
      StatTile(
        label: l10n.analyticsSalesLabel,
        value: formatMoney(totals.total),
        caption: range.label,
        emphasis: StatEmphasis.strong,
      ),
      StatTile(
        label: l10n.analyticsProfitLabel,
        value: formatMoney(totals.profit),
        caption: totals.hasSales
            ? l10n.analyticsMarginCaption(totals.marginPct.toStringAsFixed(0))
            : null,
      ),
      // The transaction COUNT is the caption, not the value: the value is money,
      // and a tile whose big number is "7" beside a money tile beside it is
      // read as KSh 7.
      StatTile(
        label: l10n.analyticsTransactionsLabel,
        value: l10n.analyticsTransactionCaption(totals.transactions),
        emphasis: StatEmphasis.strong,
      ),
      StatTile(
        label: l10n.analyticsAvgBasketLabel,
        value: formatMoney(totals.averageBasket),
        caption: l10n.analyticsAvgBasketCaption,
      ),
    ];
  }
}

/// Takings against the window before, as a signed word and a figure.
///
/// Colour is the LAST channel here and never the only one. The direction is
/// carried by three independent signals — an arrow glyph whose silhouette
/// differs per direction, the word "Up"/"Down"/"Level", and the sign on the
/// figure — so the comparison survives greyscale, `invertColors` and every
/// screen reader. A red/green pair alone would fail all three.
class _GrowthLine extends StatelessWidget {
  const _GrowthLine({
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
    // A shop with nothing in the earlier window has no percentage to quote, so
    // the line says what actually happened rather than inventing a ratio.
    final String word = isUp ? 'Up' : (isDown ? 'Down' : 'Level');
    final IconData glyph = isUp
        ? Icons.arrow_upward
        : (isDown ? Icons.arrow_downward : Icons.horizontal_rule);
    final Color tone = isUp
        ? colors.success
        : (isDown ? colors.danger : colors.onSurfaceVariant);

    final String figure = hasComparison
        ? '${isUp ? '+' : (isDown ? '−' : '')}${percent.abs().toStringAsFixed(0)}%'
        : (isUp ? 'nothing to compare' : 'no change');

    final TextStyle figureStyle = AppTypography.money(
      context,
      size: 13,
      weight: FontWeight.w700,
    ).copyWith(color: tone);

    final String comparison = previous.hasSales || current.hasSales
        ? AppLocalizations.of(context).analyticsAgainstDaysBefore(range.days)
        : 'no sales yet in this period';

    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(glyph, size: 18, color: tone, semanticLabel: word),
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

/// The load failed and there is nothing behind it.
///
/// Offers the one action that can fix it, and says which range it will retry —
/// an error with no stated next action is a dead end.
class _AnalyticsError extends StatelessWidget {
  const _AnalyticsError({required this.message, required this.onRetry});

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
              child: TextButton(
                onPressed: () => onRetry(),
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reorder stock from the report, rather than telling the owner where to go.
class OpenInventoryAction extends StatelessWidget {
  const OpenInventoryAction({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Semantics(
      button: true,
      label: 'Open Inventory to reorder',
      child: ExcludeSemantics(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () =>
                context.read<HomeShellTabs>().goTo(AppDestination.inventory),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Reorder in Inventory'),
            style: TextButton.styleFrom(
              foregroundColor: colors.accent,
              minimumSize: const Size(0, 44),
            ),
          ),
        ),
      ),
    );
  }
}
