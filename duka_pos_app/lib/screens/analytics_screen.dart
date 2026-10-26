import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/financial_event.dart';
import '../models/models.dart';
import '../routing/home_shell.dart';
import '../routing/routes.dart';
import '../services/analytics.dart';
import '../services/app_state.dart';
import '../profile/profile_navigation.dart';
import '../services/shift_analytics.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_motion.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../services/workspace_service.dart';
import '../services/live_refresh_mixin.dart';
import '../services/live_channel_service.dart';
import '../services/session_refresh_mixin.dart';
import '../services/roles.dart';
import 'cash_control_sheets.dart';
import '../services/backend_service.dart';
import '../ui/components/screen_title.dart';
import '../ui/components/states.dart';
import '../ui/components/surface.dart';
import '../widgets/chart.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import 'analytics_tables.dart';
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
    // Whose figures this is. The owner and the manager read the whole shop;
    // a cashier reads their own counter, and the screen says so, because a
    // screen called "Analytics" that quietly means "your own takings" is a
    // screen nobody trusts.
    final AppState state = context.watch<AppState>();
    final bool ownScope = !state.seesAllSales;

    return switch (_view) {
      AnalyticsLoading(previous: final AnalyticsSnapshot previous) =>
        _AnalyticsScaffold(
          range: _range,
          onRangeChanged: _setRange,
          snapshot: previous,
          onRetry: _load,
          loading: true,
          drinks: null,
        ),
      AnalyticsFailure(message: final String message) => _AnalyticsScaffold(
          range: _range,
          onRangeChanged: _setRange,
          snapshot: AnalyticsSnapshot.empty,
          onRetry: _load,
          errorMessage: message,
          drinks: null,
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
          statement: snapshot.statement,
          bottomInset: spacing.xl,
          onOpenPortfolio: () => context.push(Routes.portfolio),
          // The all-shops view reads across every shop on the device, which
          // is the owner's business and nobody else's.
          showPortfolioLink: _canShowPortfolio && state.isAdmin,
          onProductTap: state.isOwnerSession || state.role == ShopRole.manager
              ? (row) => showProductDrilldownSheet(
                    context,
                    row: row,
                    since: _range.since,
                  )
              : null,
          title: ownScope
              ? AppLocalizations.of(context).analyticsYourSalesTitle
              : AppLocalizations.of(context).navAnalytics,
          drinks: state.shopProfile.navigation.showDrinkService
              ? snapshot.drinks
              : null,
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
    this.onProductTap,
    this.showPortfolioLink = false,
    this.title,
    this.statement,
    this.drinks,
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
              // The list already insets its content by `md`; the title's own
              // default inset would push it off the gutter the cards sit on.
              padding: EdgeInsetsDirectional.only(bottom: spacing.md),
            ),
            _RangeBar(range: range, onChanged: onRangeChanged),
            if (context
                .read<AppState>()
                .hasPermission(PermissionKey.recordExpense)) ...<Widget>[
              SizedBox(height: spacing.md),
              SettingsNavRow(
                icon: Icons.receipt_long_outlined,
                title: AppLocalizations.of(context).expensePayOutAction,
                onTap: () async {
                  final AppState state = context.read<AppState>();
                  final bool saved = await showExpenseSheet(
                    context,
                    staffName:
                        state.currentStaffName ?? state.owner?.name ?? 'Owner',
                    staffId: state.currentStaffId,
                  );
                  if (saved) await onRetry();
                },
              ),
            ],
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
              _AnalyticsError(message: errorMessage!, onRetry: onRetry)
            else
              ..._content(context, shown),
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
  List<Widget> _content(BuildContext context, AnalyticsSnapshot shown) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    var section = 0;
    Widget reveal(Widget child) => _Reveal(index: section++, child: child);

    return <Widget>[
      // The headline is a CARD like the rest of the figures, with the amount
      // inside it as the one display-size number on the screen. A dashboard
      // whose top row is one bare number and four boxes reads as two designs
      // stacked; one card system, with the biggest number in the first card,
      // is a hierarchy rather than an inconsistency.
      reveal(SurfaceCard(
        padding: EdgeInsets.all(spacing.lg),
        child: _TakingsHero(
          totals: shown.totals,
          previous: shown.previousTotals,
          range: range,
        ),
      )),
      SizedBox(height: spacing.lg),
      if (!shown.totals.hasSales)
        Padding(
          padding: EdgeInsetsDirectional.only(bottom: spacing.md),
          child: Text(
            l10n.analyticsNothingTaken,
            style: AppTypography.of(context)
                .bodyMedium
                ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
          ),
        ),
      reveal(_KpiGrid(
        totals: shown.totals,
        previous: shown.previousTotals,
        days: range.days,
      )),
      SizedBox(height: spacing.lg),
      if (drinks != null) ...<Widget>[
        reveal(_DrinksAnalyticsCard(snapshot: drinks!)),
        SizedBox(height: spacing.lg),
      ],
      if (statement != null) ...<Widget>[
        reveal(FinancialStatementCard(statement: statement!)),
        SizedBox(height: spacing.lg),
      ],
      reveal(_VatSummaryCard(totals: shown.totals)),
      SizedBox(height: spacing.lg),
      if (shown.costCoverage.hasMissingCosts) ...<Widget>[
        reveal(_CostCoverageCard(coverage: shown.costCoverage)),
        SizedBox(height: spacing.lg),
      ],
      reveal(SurfaceCard(
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
      reveal(PaymentMixCard(rows: shown.payments, totals: shown.totals)),
      SizedBox(height: spacing.lg),
      if (shown.expiring.isNotEmpty) ...<Widget>[
        reveal(_ExpiringCard(products: shown.expiring)),
        SizedBox(height: spacing.lg),
      ],
      if (shown.expired.isNotEmpty) ...<Widget>[
        reveal(_ExpiredCard(products: shown.expired)),
        SizedBox(height: spacing.lg),
      ],
      if (shown.slowMovers.isNotEmpty) ...<Widget>[
        reveal(_SlowMoversCard(rows: shown.slowMovers)),
        SizedBox(height: spacing.lg),
      ],
      // The shifts, and what the drawers did over the window.
      //
      // Between the payment mix and the stock: both are about the shop's
      // money and the shift figures are the ones that say whether the money
      // in the drawer is the money the ledger expects.
      reveal(ShiftAnalyticsCard(shifts: shown.shifts)),
      SizedBox(height: spacing.lg),
      reveal(
          StockSection(outOfStock: shown.outOfStock, lowStock: shown.lowStock)),
    ];
  }
}

/// Drinks' operational emphasis, rendered from the shared analytics snapshot.
/// The card stays inside the common analytics page; a non-Drinks profile never
/// receives it from the profile capability layer.
class _DrinksAnalyticsCard extends StatelessWidget {
  const _DrinksAnalyticsCard({required this.snapshot});

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
    final kpis = <_Kpi>[
      _Kpi(
        label: l10n.drinksAnalyticsLitresSold,
        value: _litres(snapshot.litresSold),
        caption: l10n.drinksAnalyticsMeasuredLines,
        icon: Icons.local_drink_outlined,
      ),
      _Kpi(
        label: l10n.drinksAnalyticsPourSales,
        value: formatMoney(snapshot.pourSales),
        caption:
            '${l10n.drinksAnalyticsMeasuredLines} · ${snapshot.pourCostPercent.toStringAsFixed(0)}% cost',
        icon: Icons.point_of_sale_outlined,
      ),
      _Kpi(
        label: l10n.drinksAnalyticsOpenTabs,
        value: '${snapshot.openTabs}',
        icon: Icons.receipt_long_outlined,
      ),
      _Kpi(
        label: l10n.drinksAnalyticsTankBalance,
        value: _litres(snapshot.litresRemaining),
        caption: l10n.drinksAnalyticsTitle,
        icon: Icons.propane_tank_outlined,
      ),
      _Kpi(
        label: l10n.drinksAnalyticsWaste,
        value: _litres(snapshot.wasteLitres),
        caption: formatMoney(snapshot.wasteValue),
        icon: Icons.delete_sweep_outlined,
      ),
      _Kpi(
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
                    SizedBox(width: width, child: _KpiCard(kpi: kpi)),
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
                      Text(
                        _litres(tank.litresRemaining),
                        style: type.labelLarge,
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

class _ExpiringCard extends StatelessWidget {
  const _ExpiringCard({required this.products});

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

class _ExpiredCard extends StatelessWidget {
  const _ExpiredCard({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final names = products.take(5).map((product) => product.name).join(', ');
    return SurfaceCard(
      padding: EdgeInsets.all(AppSpacing.of(context).md),
      child: Semantics(
        container: true,
        label: '${products.length} products have expired stock.',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_outlined,
                color: AppColors.of(context).danger),
            SizedBox(width: AppSpacing.of(context).sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Expired stock',
                      style: AppTypography.of(context).titleSmall),
                  SizedBox(height: AppSpacing.of(context).xs),
                  Text(
                      'Write off expired stock from Inventory before it can be sold.'),
                  SizedBox(height: AppSpacing.of(context).xs),
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

class _SlowMoversCard extends StatelessWidget {
  const _SlowMoversCard({required this.rows});

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

class _CostCoverageCard extends StatelessWidget {
  const _CostCoverageCard({required this.coverage});

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

class _VatSummaryCard extends StatelessWidget {
  const _VatSummaryCard({required this.totals});

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
                _VatMetric('Taxable sales', totals.taxableMinor),
                _VatMetric('VAT captured', totals.vatMinor),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VatMetric extends StatelessWidget {
  const _VatMetric(this.label, this.minor);

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
/// under reduced motion the widget is the child, untouched.
class _Reveal extends StatefulWidget {
  const _Reveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> {
  bool _shown = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Deferred by a frame so the first build is the "before" state; without it
    // the animation has nothing to travel from.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _started) return;
      _started = true;
      Future<void>.delayed(
        Duration(milliseconds: 40 * widget.index),
        () {
          if (mounted) setState(() => _shown = true);
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppMotion motion = AppMotion.of(context);
    // The duration and curve both collapse under reduced motion, so the widget
    // still reaches its end state — it just does not travel to it.
    final Duration duration = AppMotion.resolve(context, motion.normal);
    if (duration == Duration.zero) return widget.child;
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: duration,
      curve: AppMotion.resolveCurve(context, motion.enter),
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.02),
        duration: duration,
        curve: AppMotion.resolveCurve(context, motion.enter),
        child: widget.child,
      ),
    );
  }
}

/// The period's takings: the one display-size figure, and how it compares.
class _TakingsHero extends StatelessWidget {
  const _TakingsHero({
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
              // The window is a caption on the figure, not a control: the
              // control is the segmented bar directly above it.
              Text(
                range.label,
                style: AppTypography.of(context).labelMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          // Money at display size, tabular so the digits do not jitter as the
          // range changes. Nothing else on this screen is this large.
          Text(
            formatMoney(totals.total),
            style:
                AppTypography.money(context, size: 40, weight: FontWeight.w700)
                    .copyWith(color: colors.onSurface, height: 1.05),
          ),
          SizedBox(height: spacing.sm),
          _GrowthLine(current: totals, previous: previous, range: range),
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
class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.range, required this.onChanged});

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
///
/// ## WHY CARDS AND NOT ROWS
///
/// Four numbers in one vertical list read as a receipt: you scan down, and the
/// eye has to re-find the left edge for every label. A grid of cards gives each
/// figure its own frame and its own place, which is what makes a dashboard
/// scannable from across a counter — you look AT a card, not along a list.
///
/// ## WHY THE GRID REFLOWS INSTEAD OF SHRINKING
///
/// The width is computed from the space available, not from the device, so the
/// same code gives two columns on a phone and four on a tablet. A card whose
/// value has to ellipsis is a card that has failed; the grid moves a column to
/// the next row instead, and at 200% text that is the difference between a
/// readable dashboard and a set of clipped numbers.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.totals,
    required this.previous,
    required this.days,
  });

  final DailyTotals totals;

  /// The window before, so the sales count can say which way it moved.
  final DailyTotals previous;

  /// The window's length, for the comparison sentence.
  final int days;

  /// The sales count against the previous window, as "+12%" or "−8%".
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

    final List<_Kpi> kpis = <_Kpi>[
      _Kpi(
        label: l10n.analyticsProfitLabel,
        value: formatMoney(totals.profit),
        caption: totals.hasSales
            ? l10n.analyticsMarginCaption(totals.marginPct.toStringAsFixed(0))
            : null,
        icon: Icons.trending_up,
      ),
      _Kpi(
        label: l10n.analyticsNetProfitLabel,
        value: formatMoney(totals.netProfit),
        caption: '${l10n.analyticsNetProfitCaption} · '
            '${formatMoney(Money.fromMinor(totals.expensesMinor))}',
        icon: Icons.account_balance_outlined,
      ),
      _Kpi(
        label: l10n.analyticsMarginLabel,
        value:
            totals.hasSales ? '${totals.marginPct.toStringAsFixed(0)}%' : '—',
        caption: l10n.analyticsAvgBasketCaption,
        icon: Icons.percent,
      ),
      _Kpi(
        label: l10n.analyticsTransactionsLabel,
        value: l10n.analyticsTransactionCaption(totals.transactions),
        // How the count moved, as a signed percentage. Null when there is no
        // earlier window to compare with: a "0%" beside a zero is a claim
        // about a direction that did not happen.
        caption: _countChange(l10n),
        icon: Icons.receipt_long_outlined,
        showCaptionWhenEmpty: false,
      ),
      _Kpi(
        label: l10n.analyticsAvgBasketLabel,
        value: formatMoney(totals.averageBasket),
        caption: l10n.analyticsAvgBasketCaption,
        icon: Icons.shopping_basket_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Two columns up to a tablet, four beyond it. The minimum card is wide
        // enough for a four-figure shilling amount at normal text.
        final int columns = constraints.maxWidth >= 720 ? 4 : 2;
        final double width =
            (constraints.maxWidth - spacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing.md,
          runSpacing: spacing.md,
          children: <Widget>[
            for (final _Kpi kpi in kpis)
              SizedBox(
                width: width,
                child: _KpiCard(kpi: kpi),
              ),
          ],
        );
      },
    );
  }
}

/// One figure on the dashboard: its label, its value, and what qualifies it.
class _Kpi {
  const _Kpi({
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

  /// Whether the caption is worth showing when the figure is zero. "per sale"
  /// under a zero basket is noise; a margin caption is not.
  final bool showCaptionWhenEmpty;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});

  final _Kpi kpi;

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
          // Tabular figures so four cards form a column of digits that does
          // not jitter when the range changes.
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
    final l10n = AppLocalizations.of(context);
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
          // The same glyph, size and tone a `StatTile` delta uses: a rise is an
          // up arrow in the success tone, a fall a down arrow in the danger
          // tone, and the word beside it says which in words as well.
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
                child: Text(AppLocalizations.of(context).actionTryAgain),
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      // The screen-reader name is said too, so it carries the same plain words
      // as the label rather than a third phrasing nobody reads.
      label: l10n.analyticsReorderInInventory,
      child: ExcludeSemantics(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () =>
                context.read<HomeShellTabs>().goTo(AppDestination.inventory),
            icon: const Icon(Icons.inventory_2_outlined),
            label: Text(l10n.analyticsReorderInInventory),
            style: TextButton.styleFrom(
              foregroundColor: colors.accent,
              minimumSize: Size(
                0,
                AppSpacing.of(context).primaryButtonHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
