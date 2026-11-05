import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/financial_event.dart';
import '../models/models.dart';
import '../routing/routes.dart';
import '../services/analytics.dart';
import '../services/app_state.dart';
import '../profile/profile_navigation.dart';
import '../profile/shop_profile.dart';
import '../services/shift_analytics.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../services/workspace_service.dart';
import '../services/live_refresh_mixin.dart';
import '../services/live_channel_service.dart';
import '../services/session_refresh_mixin.dart';
import '../services/roles.dart';
import '../services/backend_service.dart';
import '../ui/components/screen_title.dart';
import '../ui/components/states.dart';
import '../ui/components/surface.dart';
import '../widgets/chart.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import 'analytics_shared.dart';
import 'analytics_tables.dart';
import 'duka_analytics_screen.dart';
import 'fashion_analytics_screen.dart';
import 'open_analytics_screen.dart';
import 'product_drilldown_sheet.dart';

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
  quarter('90 days', 90),
  year('1 year', 365);

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
    this.expiring = const <Product>[],
    this.expired = const <Product>[],
    this.slowMovers = const <SlowMoverRow>[],
    this.costCoverage = CostCoverage.empty,
    required this.stockValue,
    this.shifts = const ShiftAnalytics.empty(),
    this.drinks = DrinksAnalyticsSnapshot.empty,
    this.statement,
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
    expiring: <Product>[],
    expired: <Product>[],
    slowMovers: <SlowMoverRow>[],
    costCoverage: CostCoverage.empty,
    stockValue: Money.zero,
    shifts: ShiftAnalytics.empty(),
    drinks: DrinksAnalyticsSnapshot.empty,
    statement: null,
  );

  final DailyTotals totals;
  final DailyTotals previousTotals;
  final List<DateBucket> days;
  final List<ProductSalesRow> products;
  final List<PaymentMixRow> payments;
  final List<Product> outOfStock;
  final List<Product> lowStock;
  final List<Product> expiring;
  final List<Product> expired;
  final List<SlowMoverRow> slowMovers;
  final CostCoverage costCoverage;
  final Money stockValue;

  /// The shifts over the window, and what the drawers did.
  final ShiftAnalytics shifts;

  /// Drinks-only operational metrics projected from the shared ledger.
  final DrinksAnalyticsSnapshot drinks;

  /// The canonical statement is management-scoped. Cashiers see their own
  /// sales KPIs, but must not receive a whole-shop liability or cash balance.
  final FinancialStatement? statement;

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
    final AppState appState = context.read<AppState>();
    // The previous window rides along in the same batch: it is one more
    // aggregate query, and fetching it with the current one means the comparison
    // is answered by a single consistent read of the ledger rather than two
    // queries that could straddle a sale landing between them.
    final AnalyticsRange range = _range;
    final DateTime since = range.since;
    // WHOSE figures these are.
    //
    // Null for the owner and the manager: they read the whole shop. For a
    // cashier it is their own staff id, and every aggregate below is asked
    // with it, so the screen shows the takings of the counter they were
    // standing at and nothing else.
    //
    // It used to be a whole-shop screen that cashiers could not open at all,
    // which answered the question "how am I doing?" with "you may not look".
    // Their own numbers are theirs to read.
    final int? staffId = context.read<AppState>().analyticsStaffId;
    try {
      final List<Object> results = await Future.wait(<Future<Object>>[
        db.salesTotalsFor(since: since, staffId: staffId),
        db.salesByDay(since: since, staffId: staffId),
        db.topProducts(since: since, limit: 20, staffId: staffId),
        db.salesByPaymentMethod(since: since, staffId: staffId),
        db.getProducts(),
        db.getExpiringProducts(),
        db.getExpiredProducts(),
        db.getSlowMovingProducts(since: since, until: DateTime.now()),
        db.salesTotalsFor(
          since: range.previousSince,
          until: since,
          staffId: staffId,
        ),
        loadShiftAnalytics(from: since, to: DateTime.now(), staffId: staffId),
        appState.shopProfile.navigation.showDrinkService
            ? db.drinksAnalytics(since: since, staffId: staffId)
            : Future<DrinksAnalyticsSnapshot>.value(
                DrinksAnalyticsSnapshot.empty),
      ]);
      final FinancialStatement? statement = staffId == null
          ? await db.getFinancialStatement(
              fromUtc: since.toUtc(),
              untilUtc: DateTime.now().toUtc(),
            )
          : null;
      if (!mounted) return;
      final List<Product> products = results[4] as List<Product>;
      final Money stockValue = Money.fromMinor(
        products.where((p) => p.active).fold<int>(
          0,
          (sum, p) => sum + (p.stockQty * p.costPrice.minorUnits).round(),
        ),
      );
      final List<Product> expiring = results[5] as List<Product>;
      final List<Product> expired = results[6] as List<Product>;
      final List<SlowMoverRow> slowMovers = results[7] as List<SlowMoverRow>;
      List<ProductSalesRow> productRows = results[2] as List<ProductSalesRow>;
      CostCoverage costCoverage = costCoverageFor(productRows, products);
      DailyTotals totals = results[0] as DailyTotals;
      DailyTotals previousTotals = results[8] as DailyTotals;
      List<PaymentMixRow> payments = results[3] as List<PaymentMixRow>;
      List<DateBucket> chartDays = results[1] as List<DateBucket>;
      // Once this till has no pending sales, the verified backend aggregate is
      // authoritative: it includes sales from every till in the tenant. While
      // this device still has an offline queue, keep its local figures so a
      // just-recorded sale is never hidden while waiting for upload.
      final pendingOperational = await db.unsyncedOperationalCounts();
      final bool canUseRemote = remoteAnalyticsIsAuthoritative(
        staffId: staffId,
        identityVerified: await BackendService.isIdentityVerified,
        pendingOperational: pendingOperational,
      );
      if (canUseRemote) {
        try {
          final remote = await BackendService.remoteSalesSummary(
            from: since,
            to: DateTime.now(),
          );
          totals = remote.totals;
          payments = remote.payments;
          if (remote.days.isNotEmpty) chartDays = remote.days;
          final previous = await BackendService.remoteSalesSummary(
            from: range.previousSince,
            to: since,
          );
          previousTotals = previous.totals;
        } catch (_) {
          // Local zeroes are still honest while offline or unverified.
        }
      }
      if (canUseRemote) {
        try {
          final remoteProducts = await BackendService.remoteProductReport(
            from: since,
            to: DateTime.now(),
          );
          if (remoteProducts.products.isNotEmpty || productRows.isEmpty) {
            productRows = remoteProducts.products;
          }
          if (remoteProducts.costCoverage != null) {
            costCoverage = remoteProducts.costCoverage!;
          }
        } catch (_) {
          // Product rows remain empty while offline.
        }
      }
      setState(() {
        _sortedProducts = _order(
          productRows,
          _sort,
          _ascending,
        );
        _salesPoints = _salesChartPoints(chartDays);
        _view = AnalyticsContent(
          AnalyticsSnapshot(
            totals: totals,
            previousTotals: previousTotals,
            days: chartDays,
            products: productRows,
            payments: payments,
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
            costCoverage: costCoverage,
            stockValue: stockValue,
            expiring: expiring,
            expired: expired,
            slowMovers: slowMovers,
            shifts: results[9] as ShiftAnalytics,
            drinks: results[10] as DrinksAnalyticsSnapshot,
            statement: statement,
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
    final AppState state = context.watch<AppState>();
    final l10n = AppLocalizations.of(context);

    return switch (_view) {
      AnalyticsLoading(previous: final AnalyticsSnapshot previous) =>
          AnalyticsScaffold(
        range: _range,
        onRangeChanged: _setRange,
        snapshot: previous,
        onRetry: _load,
        loading: true,
        drinks: null,
      ),
      AnalyticsFailure(message: final String message) => AnalyticsScaffold(
        range: _range,
        onRangeChanged: _setRange,
        snapshot: AnalyticsSnapshot.empty,
        onRetry: _load,
        errorMessage: message,
        drinks: null,
      ),
      AnalyticsContent(snapshot: final AnalyticsSnapshot snapshot) =>
          switch (state.shopProfile) {
        ShopProfile.drinks => DrinksAnalyticsScreen(
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
            l10n.analyticsChartTitleSalesByDay,
            snapshot.days,
          ),
          chartEmphasis: snapshot.totals.hasSales
              ? '${formatMoney(snapshot.totals.total)} over ${_range.label.toLowerCase()}'
              : null,
          statement: snapshot.statement,
          bottomInset: spacing.xl,
          onOpenPortfolio: () => context.push(Routes.portfolio),
          showPortfolioLink: _canShowPortfolio && state.isAdmin,
          onProductTap: state.isOwnerSession || state.role == ShopRole.manager
              ? (row) => showProductDrilldownSheet(
                    context,
                    row: row,
                    since: _range.since,
                  )
              : null,
          drinks: state.shopProfile.navigation.showDrinkService
              ? snapshot.drinks
              : null,
        ),
        ShopProfile.duka => DukaAnalyticsScreen(
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
            l10n.analyticsChartTitleSalesByDay,
            snapshot.days,
          ),
          chartEmphasis: snapshot.totals.hasSales
              ? '${formatMoney(snapshot.totals.total)} over ${_range.label.toLowerCase()}'
              : null,
          statement: snapshot.statement,
          bottomInset: spacing.xl,
          onOpenPortfolio: () => context.push(Routes.portfolio),
          showPortfolioLink: _canShowPortfolio && state.isAdmin,
          onProductTap: state.isOwnerSession || state.role == ShopRole.manager
              ? (row) => showProductDrilldownSheet(
                    context,
                    row: row,
                    since: _range.since,
                  )
              : null,
        ),
        ShopProfile.fashion => FashionAnalyticsScreen(
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
            l10n.analyticsChartTitleSalesByDay,
            snapshot.days,
          ),
          chartEmphasis: snapshot.totals.hasSales
              ? '${formatMoney(snapshot.totals.total)} over ${_range.label.toLowerCase()}'
              : null,
          statement: snapshot.statement,
          bottomInset: spacing.xl,
          onOpenPortfolio: () => context.push(Routes.portfolio),
          showPortfolioLink: _canShowPortfolio && state.isAdmin,
          onProductTap: state.isOwnerSession || state.role == ShopRole.manager
              ? (row) => showProductDrilldownSheet(
                    context,
                    row: row,
                    since: _range.since,
                  )
              : null,
        ),
        ShopProfile.open => OpenAnalyticsScreen(
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
            l10n.analyticsChartTitleSalesByDay,
            snapshot.days,
          ),
          chartEmphasis: snapshot.totals.hasSales
              ? '${formatMoney(snapshot.totals.total)} over ${_range.label.toLowerCase()}'
              : null,
          statement: snapshot.statement,
          bottomInset: spacing.xl,
          onOpenPortfolio: () => context.push(Routes.portfolio),
          showPortfolioLink: _canShowPortfolio && state.isAdmin,
          onProductTap: state.isOwnerSession || state.role == ShopRole.manager
              ? (row) => showProductDrilldownSheet(
                    context,
                    row: row,
                    since: _range.since,
                  )
              : null,
        ),
      },
    };
  }
}

/// Drinks' own analytics view: beverage performance leads, shared financial
/// sections follow. Built from the same snapshot every profile reads, but
/// composed so a drinks shop sees its business first.
class DrinksAnalyticsScreen extends StatelessWidget {
  const DrinksAnalyticsScreen({
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
    this.drinks,
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
  final DrinksAnalyticsSnapshot? drinks;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    final bool hasSales = snapshot.totals.hasSales;
    var section = 0;
    Widget reveal(Widget child) => Reveal(index: section++, child: child);

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
      title: l10n.analyticsDrinksTitle,
      statement: statement,
      drinks: drinks,
      // Children built here so drinks leads: beverage card first, then the
      // shared financial sections.
      children: <Widget>[
        if (drinks != null) ...<Widget>[
          reveal(DrinksAnalyticsCard(snapshot: drinks!)),
          SizedBox(height: spacing.lg),
        ],
        reveal(SurfaceCard(
          padding: EdgeInsets.all(spacing.lg),
          child: TakingsHero(
            totals: snapshot.totals,
            previous: snapshot.previousTotals,
            range: range,
          ),
        )),
        SizedBox(height: spacing.lg),
        if (!hasSales)
          Padding(
            padding: EdgeInsetsDirectional.only(bottom: spacing.md),
            child: Text(
              l10n.analyticsNothingTaken,
              style: AppTypography.of(context)
                  .bodyMedium
                  ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
            ),
          ),
        reveal(KpiGrid(
          totals: snapshot.totals,
          previous: snapshot.previousTotals,
          days: range.days,
        )),
        SizedBox(height: spacing.lg),
        reveal(PaymentMixCard(rows: snapshot.payments, totals: snapshot.totals)),
        SizedBox(height: spacing.lg),
        reveal(StockSection(
            outOfStock: snapshot.outOfStock, lowStock: snapshot.lowStock)),
        SizedBox(height: spacing.lg),
        reveal(VatSummaryCard(totals: snapshot.totals)),
        SizedBox(height: spacing.lg),
        if (statement != null) ...<Widget>[
          reveal(FinancialStatementCard(statement: statement!)),
          SizedBox(height: spacing.lg),
        ],
        if (snapshot.costCoverage.hasMissingCosts) ...<Widget>[
          reveal(CostCoverageCard(coverage: snapshot.costCoverage)),
          SizedBox(height: spacing.lg),
        ],
        reveal(SurfaceCard(
          padding: EdgeInsetsDirectional.only(
            start: spacing.md,
            end: spacing.md,
            top: spacing.md,
            bottom: spacing.sm,
          ),
          child: PosLineChart(
            title: l10n.analyticsChartTitleSalesByDay,
            emphasis: chartEmphasis,
            semanticsLabel: chartSemantics,
            height: 168,
            points: salesPoints,
          ),
        )),
        SizedBox(height: spacing.lg),
        reveal(ProductTableCard(
          rows: sortedProducts,
          sort: sort,
          ascending: ascending,
          onSort: onSortBy,
          onProductTap: onProductTap,
        )),
        SizedBox(height: spacing.lg),
        if (snapshot.expiring.isNotEmpty) ...<Widget>[
          reveal(ExpiringCard(products: snapshot.expiring)),
          SizedBox(height: spacing.lg),
        ],
        if (snapshot.expired.isNotEmpty) ...<Widget>[
          reveal(ExpiredCard(products: snapshot.expired)),
          SizedBox(height: spacing.lg),
        ],
        if (snapshot.slowMovers.isNotEmpty) ...<Widget>[
          reveal(SlowMoversCard(rows: snapshot.slowMovers)),
          SizedBox(height: spacing.lg),
        ],
        reveal(ShiftAnalyticsCard(shifts: snapshot.shifts)),
      ],
    );
  }
}

/// The page: the range control, then whichever of the four sections the snapshot
/// can fill.
///
/// [AdaptivePage] supplies the canvas and the safe-area inset; this adds the
/// pull-to-refresh and the vertical rhythm between sections.
class AnalyticsScaffold extends StatelessWidget {
  const AnalyticsScaffold({super.key,
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
    this.onProductTap,
    this.showPortfolioLink = false,
    this.title,
    this.statement,
    this.drinks,
    this.children,
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
  final ValueChanged<ProductSalesRow>? onProductTap;

  /// Whether to offer it. An owner running one duka has no use for "All shops",
  /// and an affordance that answers a question they never asked is noise on the
  /// screen they use every day.
  final bool showPortfolioLink;

  /// The screen's own name, which depends on whose figures it is showing.
  final String? title;
  final FinancialStatement? statement;
  final DrinksAnalyticsSnapshot? drinks;

  /// Pre-built children, used when a profile owns its own section order
  /// (drinks leads with beverage performance). When null, [_content] builds
  /// the shared order.
  final List<Widget>? children;

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
            // The screen names itself on the canvas: a large left-aligned title
            // under the shell's brand bar, not a coloured app bar that spends
            // the app's only accent on chrome.
            ScreenTitle(
              title: title ?? AppLocalizations.of(context).navAnalytics,
              // The range filter lives beside the title, not on its own row.
              trailing: RangeBar(range: range, onChanged: onRangeChanged),
              // The list already insets its content by `md`; the title's own
              // default inset would push it off the gutter the cards sit on.
              padding: EdgeInsetsDirectional.only(bottom: spacing.md),
            ),
            if (showPortfolioLink && onOpenPortfolio != null) ...<Widget>[
              SizedBox(height: spacing.md),
              SettingsNavRow(
                icon: Icons.insights_outlined,
                title: AppLocalizations.of(context).portfolioOpenAction,
                onTap: onOpenPortfolio,
              ),
            ],
            SizedBox(height: spacing.lg),
            if (loading)
              const SkeletonList(itemCount: 4)
            else if (errorMessage != null)
              AnalyticsError(message: errorMessage!, onRetry: onRetry)
            else
              ...(children ?? standardAnalyticsSections(
                context: context,
                shown: shown,
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
                l10n: AppLocalizations.of(context),
                colors: AppColors.of(context),
              )),
          ],
        ),
      ),
    );
  }

  /// The page's sections, in reading order, each one revealed as it arrives.
  ///
  /// ## WHY A HERO AND NOT FOUR BOXES
  ///
  /// The screen used to open with four equally weighted cards: takings,
  /// profit, transactions, basket. Equal weight is no hierarchy — the eye has
  /// nowhere to land, and the one figure the owner opened the app for was the
  /// same size as the one they only glance at. So the takings are the single
  /// display-size number on the screen, the comparison sits immediately under
  /// it in words, and the other three become quiet rows in one card: present,
  /// comparable, and visibly secondary.
  ///
  /// ## WHY THE STAGGER
  ///
  /// Sections arrive 40ms apart, eight pixels up, over 220ms on an ease-out
  /// curve — a cascade rather than a page that snaps. It runs ONCE, on the
  /// first paint of a snapshot: re-revealing on every rebuild would make
  /// changing the range feel like a page reload. Under reduced motion every
  /// offset and duration collapses to zero and the sections simply appear.
}

/// Drinks' operational emphasis, rendered from the shared analytics snapshot.
/// The card stays inside the common analytics page; a non-Drinks profile never
/// receives it from the profile capability layer.
class DrinksAnalyticsCard extends StatelessWidget {
  const DrinksAnalyticsCard({super.key, required this.snapshot});

  final DrinksAnalyticsSnapshot snapshot;

  String _litres(double value) {
    final decimals = value >= 100
        ? 0
        : value >= 10
            ? 1
            : 2;
    return '${value.toStringAsFixed(decimals)} L';
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);
    final kpis = <Kpi>[
      Kpi(
        label: l10n.drinksAnalyticsLitresSold,
        value: _litres(snapshot.litresSold),
        caption: l10n.drinksAnalyticsMeasuredLines,
        icon: Icons.local_drink_outlined,
      ),
      Kpi(
        label: l10n.drinksAnalyticsPourSales,
        value: formatMoney(snapshot.pourSales),
        caption:
            '${l10n.drinksAnalyticsMeasuredLines} · ${snapshot.pourCostPercent.toStringAsFixed(0)}% cost',
        icon: Icons.point_of_sale_outlined,
      ),
      Kpi(
        label: l10n.drinksAnalyticsOpenTabs,
        value: '${snapshot.openTabs}',
        icon: Icons.receipt_long_outlined,
      ),
      Kpi(
        label: l10n.drinksAnalyticsTankBalance,
        value: _litres(snapshot.litresRemaining),
        caption: l10n.drinksAnalyticsTitle,
        icon: Icons.propane_tank_outlined,
      ),
      Kpi(
        label: l10n.drinksAnalyticsWaste,
        value: _litres(snapshot.wasteLitres),
        caption: formatMoney(snapshot.wasteValue),
        icon: Icons.delete_sweep_outlined,
      ),
      Kpi(
        label: l10n.drinksAnalyticsDipVariance,
        value: _litres(snapshot.dipVarianceLitres.abs()),
        caption: snapshot.dipVarianceLitres < 0
            ? l10n.drinksAnalyticsDipBelow
            : l10n.drinksAnalyticsDipAbove,
        icon: Icons.water_drop_outlined,
      ),
    ];

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.local_bar_outlined, color: colors.onSurfaceMuted),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text(
                  l10n.drinksAnalyticsTitle,
                  style: type.titleMedium,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 4 : 2;
              final width =
                  (constraints.maxWidth - spacing.md * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing.md,
                runSpacing: spacing.md,
                children: <Widget>[
                  for (final kpi in kpis)
                    SizedBox(width: width, child: KpiCard(kpi: kpi)),
                ],
              );
            },
          ),
          SizedBox(height: spacing.md),
          if (snapshot.tanks.isEmpty)
            Text(
              l10n.drinksAnalyticsNoTankData,
              style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
            )
          else
            for (final tank in snapshot.tanks)
              Padding(
                padding: EdgeInsets.only(bottom: spacing.xs),
                child: Semantics(
                  label: '${tank.name}, ${_litres(tank.litresRemaining)}',
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(tank.name)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            _litres(tank.litresRemaining),
                            style: type.labelLarge,
                          ),
                          Text(
                            '${(tank.fillPercent * 100).toStringAsFixed(0)}% full',
                            style: type.bodySmall,
                          ),
                          Text(
                            'Cost: ${formatMoney(tank.costInvested)}',
                            style: type.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// The management statement is intentionally built from [FinancialStatement],
/// not from the sales dashboard totals. The two answer different questions:
/// profit includes non-sale events, while cash flow includes movements that do
/// not belong in profit.
class FinancialStatementCard extends StatelessWidget {
  const FinancialStatementCard({required this.statement, super.key});

  final FinancialStatement statement;

  static String _signedMoney(int minor) {
    final String sign = minor < 0 ? '−' : '+';
    return '$sign${formatMoney(Money.fromMinor(minor.abs()))}';
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final List<_StatementMetric> metrics = <_StatementMetric>[
      _StatementMetric(
          'Net profit',
          formatMoney(Money.fromMinor(statement.netProfitMinor)),
          Icons.trending_up),
      _StatementMetric(
          'Cash flow',
          _signedMoney(statement.totals.netCashFlowMinor),
          Icons.account_balance_wallet_outlined),
      _StatementMetric('Receivables',
          _signedMoney(statement.receivableDeltaMinor), Icons.people_outline),
      _StatementMetric('Payables', _signedMoney(statement.payableDeltaMinor),
          Icons.request_quote_outlined),
      _StatementMetric(
          'Customer deposits',
          _signedMoney(statement.customerDepositDeltaMinor),
          Icons.savings_outlined),
      _StatementMetric(
          'Inventory movement',
          '${statement.inventoryDeltaMilliunits / 1000}',
          Icons.inventory_2_outlined),
    ];
    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Reconciled financial statement', style: type.titleLarge),
          SizedBox(height: spacing.xs),
          Text(
            statement.openingCashIsKnown
                ? 'Opening cash is known for this period.'
                : 'Closing cash is calculated from recorded movements; opening cash is not anchored.',
            style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
          ),
          SizedBox(height: spacing.md),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final int columns = constraints.maxWidth >= 720 ? 3 : 2;
              final double width =
                  (constraints.maxWidth - spacing.sm * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing.sm,
                runSpacing: spacing.md,
                children: <Widget>[
                  for (final _StatementMetric metric in metrics)
                    SizedBox(
                      width: width,
                      child: Row(
                        children: <Widget>[
                          Icon(metric.icon,
                              size: 18, color: colors.onSurfaceMuted),
                          SizedBox(width: spacing.xs),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(metric.label, style: type.bodySmall),
                                Text(metric.value, style: type.titleMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          SizedBox(height: spacing.md),
          Text(
            'Opening ${formatMoney(Money.fromMinor(statement.openingCashMinor))} · '
            'closing ${formatMoney(Money.fromMinor(statement.closingCashMinor))}',
            style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

class _StatementMetric {
  const _StatementMetric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}
