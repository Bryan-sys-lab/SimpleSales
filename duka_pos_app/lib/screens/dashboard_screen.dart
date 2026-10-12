import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/home_shell.dart';
import '../routing/routes.dart';
import '../services/analytics.dart';
import '../app_brand.dart';
import '../services/app_state.dart';
import '../services/live_channel_service.dart';
import '../services/live_refresh_mixin.dart';
import '../services/etims/etims_service.dart';
import '../services/excel_service.dart';
import '../theme/app_haptics.dart';
import '../theme/app_spacing.dart';
import '../ui/components/controls.dart';
import '../ui/components/states.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';
import 'dashboard_attention.dart';
import 'dashboard_sections.dart';

/// What a seller needs before they need anything else.
///
/// Ordered by what a shift actually goes wrong in: what will stop me selling
/// (the attention list, first), what have I made (the KPIs and the hour chart),
/// what should I reorder (low stock), and last the stock that is merely
/// interesting. Everything on this screen is read in the seconds between
/// customers, so it answers questions rather than reporting activity.
///
/// Every figure is scoped by `staff_id`, never by name: a cashier sees their
/// own takings and a manager or owner sees the shop's. See
/// `staffIdForCashier` for why the id is the only defensible filter.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// One of exactly three outcomes, resolved in one switch.
///
/// Deliberately not a `bool loading` next to a `String? error` next to a
/// `List<Product>`: those three can disagree, and every screen that has them
/// eventually renders a spinner over a stale list, or an error over content that
/// loaded fine. A sealed value cannot hold two answers at once.
sealed class _DashboardState {
  const _DashboardState();
}

/// Nothing has arrived yet. The first load only: a REFRESH keeps the previous
/// content on screen, because a cashier pulling to refresh mid-queue does not
/// need their figures to vanish.
final class _DashboardLoading extends _DashboardState {
  const _DashboardLoading();
}

/// The load failed. No figures, no chart, no list.
final class _DashboardFailed extends _DashboardState {
  const _DashboardFailed();
}

/// Everything the screen shows, as one value.
final class _DashboardReady extends _DashboardState {
  const _DashboardReady({
    required this.totals,
    required this.hasEverSold,
    required this.hours,
    required this.topProducts,
    required this.lowStock,
    required this.lowStockCount,
    required this.attention,
    required this.scopeLabel,
    required this.greeting,
    required this.openShift,
    required this.expectedTill,
  });

  final DailyTotals totals;

  /// Whether the ledger has *ever* held a sale. A zero-sales day and a till
  /// that has never sold anything need different words, and one screen that
  /// says "Sales today KSh 0" for both cannot tell them apart.
  final bool hasEverSold;

  final List<TimeBucket> hours;
  final List<ProductSalesRow> topProducts;
  final List<Product> lowStock;
  final int lowStockCount;
  final AttentionSummary attention;

  /// "the shop" or the cashier's own name — says out loud whose takings these
  /// are, because the number itself cannot.
  final String scopeLabel;

  /// Who is signed in and what they are looking at, resolved here rather than in
  /// a `build` that would otherwise call the clock on every frame.
  final String greeting;

  /// The signed-in person's open shift, and what the drawer should hold in it.
  ///
  /// Loaded with the rest rather than read when the card is built, because the
  /// card needs a number — the expected cash — that only the database can
  /// produce, and building it inline would mean a query per rebuild.
  final Shift? openShift;
  final Money expectedTill;
}

class _DashboardScreenState extends State<DashboardScreen>
    with LiveRefresh<DashboardScreen> {
  _DashboardState? _state;
  bool _loading = false;

  @override
  Set<LiveReason> get liveReasons => const <LiveReason>{
        LiveReason.sales,
        LiveReason.stock,
        LiveReason.products,
      };

  @override
  bool get liveIsVisible => TickerMode.valuesOf(context).enabled;

  @override
  Future<void> reloadFromLive() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    final AppState appState = context.read<AppState>();
    setState(() {
      _state ??= const _DashboardLoading();
      _loading = true;
    });

    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final bool ownOnly = !appState.canManageStock;
      final int? staffId = ownOnly
          ? staffIdForCashier(
              await db.getStaff(activeOnly: false), appState.currentStaffName)
          : null;

      final DateTime now = DateTime.now();
      final DateTime dayStart = DateTime(now.year, now.month, now.day);
      final DateTime tomorrow = dayStart.add(const Duration(days: 1));

      final List<Product> products = await db.getProducts();
      final DailyTotals totalsToday =
          await db.salesTotalsFor(since: dayStart, staffId: staffId);
      final DailyTotals totalsAll = await db.salesTotalsFor(staffId: staffId);

      if (!mounted) return;
      if (products.isEmpty && !totalsAll.hasSales) {
        final Shift? shift = appState.currentStaffId == null
            ? null
            : await db.getOpenShift(appState.currentStaffId!);
        final String scopeLabel =
            ownOnly ? (appState.currentStaffName ?? 'you') : 'the shop';
        setState(() {
          _state = _DashboardReady(
            totals: totalsToday,
            hasEverSold: totalsAll.hasSales,
            hours: const <TimeBucket>[],
            topProducts: const <ProductSalesRow>[],
            lowStock: const <Product>[],
            lowStockCount: 0,
            attention: const AttentionSummary(
              pendingEtims: 0,
              rejectedEtims: 0,
              openImportProblems: 0,
              unverifiedPayments: 0,
            ),
            scopeLabel: scopeLabel,
            greeting: _greeting(
              AppLocalizations.of(context),
              shopName: appState.owner?.shopName ?? SimplePosBrand.appName,
              staffName: appState.currentStaffName,
              role: appState.currentRole,
              scopeLabel: scopeLabel,
            ),
            openShift: shift,
            expectedTill: Money.zero,
          );
        });
        if (shift == null) return;
        final Money expected = await db.expectedTillBalance(shift);
        if (!mounted) return;
        final _DashboardReady? ready = _state as _DashboardReady?;
        if (ready == null || ready.openShift?.id != shift.id) return;
        setState(() => _state = _DashboardReady(
              totals: ready.totals,
              hasEverSold: ready.hasEverSold,
              hours: ready.hours,
              topProducts: ready.topProducts,
              lowStock: ready.lowStock,
              lowStockCount: ready.lowStockCount,
              attention: ready.attention,
              scopeLabel: ready.scopeLabel,
              greeting: ready.greeting,
              openShift: ready.openShift,
              expectedTill: expected,
            ));
        return;
      }

      final List<Object?> results = await Future.wait<Object?>([
        db.salesByHour(day: dayStart, staffId: staffId),
        db.topProducts(
            since: dayStart, until: tomorrow, staffId: staffId, limit: 5),
        db.countLowStockProducts(),
        db.attentionSummary(),
        appState.currentStaffId == null
            ? Future<Shift?>.value(null)
            : db.getOpenShift(appState.currentStaffId!),
      ]);

      final List<Product> low = (await db.getProducts())
          .where((Product product) => product.isLow)
          .toList()
        ..sort((Product a, Product b) {
          final int byEmpty =
              (a.stockQty <= 0 ? 0 : 1).compareTo(b.stockQty <= 0 ? 0 : 1);
          return byEmpty != 0 ? byEmpty : a.stockQty.compareTo(b.stockQty);
        });

      final Shift? shift = results[4] as Shift?;
      final String scopeLabel =
          ownOnly ? (appState.currentStaffName ?? 'you') : 'the shop';

      if (!mounted) return;
      setState(() {
        _state = _DashboardReady(
          totals: totalsToday,
          hasEverSold: totalsAll.hasSales,
          hours: results[0] as List<TimeBucket>,
          topProducts: results[1] as List<ProductSalesRow>,
          lowStockCount: results[2] as int,
          attention: results[3] as AttentionSummary,
          lowStock: low,
          scopeLabel: scopeLabel,
          greeting: _greeting(
            AppLocalizations.of(context),
            shopName: appState.owner?.shopName ?? SimplePosBrand.appName,
            staffName: appState.currentStaffName,
            role: appState.currentRole,
            scopeLabel: scopeLabel,
          ),
          openShift: shift,
          expectedTill: Money.zero,
        );
      });

      if (shift == null) return;
      final Money expected = await db.expectedTillBalance(shift);
      if (!mounted) return;
      final _DashboardReady? ready = _state as _DashboardReady?;
      if (ready == null || ready.openShift?.id != shift.id) return;
      setState(() => _state = _DashboardReady(
            totals: ready.totals,
            hasEverSold: ready.hasEverSold,
            hours: ready.hours,
            topProducts: ready.topProducts,
            lowStock: ready.lowStock,
            lowStockCount: ready.lowStockCount,
            attention: ready.attention,
            scopeLabel: ready.scopeLabel,
            greeting: ready.greeting,
            openShift: ready.openShift,
            expectedTill: expected,
          ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state ??= const _DashboardFailed();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// "Good morning, Wanjiku · Cashier · showing the shop".
  ///
  /// Resolved once per load rather than per build: it reads the clock, and a
  /// greeting that changes because a rebuild happened at 17:00 is a bug report.
  static String _greeting(
    AppLocalizations l10n, {
    required String shopName,
    required String? staffName,
    required String role,
    required String scopeLabel,
  }) {
    final int hour = DateTime.now().hour;
    final String greeting = hour < 12
        ? l10n.dashboardGreetingMorning
        : hour < 17
            ? l10n.dashboardGreetingAfternoon
            : l10n.dashboardGreetingEvening;
    final String name = staffName ?? '';
    // An admin is the OWNER, not a manager, and the dashboard says so: this is
    // the line that tells someone whether the till they are holding is theirs.
    final String roleLabel = switch (role) {
      'admin' => l10n.shellRoleOwner,
      'manager' => l10n.settingsRoleManager,
      _ => l10n.settingsRoleCashier,
    };
    return name.isEmpty
        ? l10n.dashboardGreetingAnonymous(greeting, scopeLabel)
        : l10n.dashboardGreetingNamed(greeting, name, roleLabel, scopeLabel);
  }

  Future<void> _openShift() async {
    await context.push(Routes.shift);
    // The shift may have been opened or closed on that screen, and the card's
    // number is a figure from the ledger rather than a UI value.
    if (mounted) await _load();
  }

  void _openSell() {
    context.read<HomeShellTabs>().goTo(AppDestination.sell);
  }

  void _openInventory() {
    // A cashier has no Inventory destination; `HomeShellTabs.goTo` is a no-op
    // for one this role does not have, so there is nothing to guard here.
    context.read<HomeShellTabs>().goTo(AppDestination.inventory);
  }

  /// Puts the shop's TIN and eTIMS device id in front of the owner.
  ///
  /// The tax settings screen rather than the Settings tab: a rejected receipt
  /// has exactly one fix, and it is three fields down a screen the tab does not
  /// even open. Pushed over the shell so Back returns to the dashboard the
  /// problem was found on.
  void _openEtimsSettings() {
    context.push(Routes.taxSettings);
  }

  /// Opens one product in the stock list, scrolled to and marked.
  ///
  /// The identity travels in the PATH, not in `extra`: a link shared from the
  /// dashboard has to reconstruct this screen on a cold start.
  void _openProduct(Product product) {
    final int? id = product.id;
    if (id == null) return;
    context.push(Routes.product(AppLocalizations.of(context).dashboardId(id)));
  }

  Future<void> _backupNow() async {
    final file = await ExcelService().exportEncryptedInventory();
    await ExcelService().shareFile(file);
  }

  /// Retries the KRA upload queue, then re-reads the counts.
  ///
  /// The action is the one the situation actually needs: these receipts are
  /// waiting because the till was offline, and a queue that only reports its
  /// own size every morning is an outage nobody can end.
  Future<void> _retryEtims() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final EtimsFlushResult result = await EtimsService().flushPending();
      if (!mounted) return;
      HapticTheme.of(context).fire(HapticEvent.commit);
      showAppSnackBar(context, message: EtimsService.describeResult(result));
      await _load();
    } catch (_) {
      if (!mounted) return;
      HapticTheme.of(context).fire(HapticEvent.reject);
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'Could not reach KRA. The receipts stay queued and will go up on the next connection.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      null || _DashboardLoading() => const _DashboardSkeleton(),
      _DashboardFailed() => ErrorStateView(
          message: 'Could not load today’s dashboard data.',
          detail: 'The till keeps working. Pull to try again, or check the '
              'database in Settings.',
          onRetry: _load,
        ),
      _DashboardReady() => _DashboardContent(
          data: _state! as _DashboardReady,
          onRefresh: _load,
          onBackupNow: _backupNow,
          onOpenShift: _openShift,
          onOpenSell: _openSell,
          onOpenInventory: _openInventory,
          onOpenEtimsSettings: _openEtimsSettings,
          onOpenProduct: _openProduct,
          onRetryEtims: _retryEtims,
        ),
    };
  }
}

/// The first paint, before anything has been read.
///
/// A skeleton of the screen's own shapes rather than a centred spinner: rows
/// where the attention list will be, tiles where the figures will be. A spinner
/// over an empty box means everything moves when the data lands.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return AdaptivePage(
      maxContentWidth: _kDashboardMaxWidth,
      padding: EdgeInsets.all(spacing.xl),
      child: const SkeletonList(itemCount: 5, linesPerItem: 2),
    );
  }
}

/// The widest the dashboard grows. A manager on a desktop monitor gets two
/// columns of panels, not one 1600px-wide row of numbers nobody can scan.
const double _kDashboardMaxWidth = 1200;

/// At and above this content width the panels split into a main column and a
/// side column. Below it they stack in reading order.
const double _kTwoColumnBreakpoint = 840;

/// The screen's body, in reading order.
///
/// On a phone, one column:
///
///   header · what needs attention · today's figures · shift · sales by hour ·
///   top products · reorder
///
/// On a tablet or desktop the same content is split so nothing is further than
/// one glance away: the MAIN column (what happened — the hour chart and the top
/// sellers) beside a SIDE column (what to do — the shift and the reorder list).
class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.data,
    required this.onRefresh,
    required this.onBackupNow,
    required this.onOpenShift,
    required this.onOpenSell,
    required this.onOpenInventory,
    required this.onOpenEtimsSettings,
    required this.onOpenProduct,
    required this.onRetryEtims,
  });

  final _DashboardReady data;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onBackupNow;
  final Future<void> Function() onOpenShift;
  final VoidCallback onOpenSell;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenEtimsSettings;
  final ValueChanged<Product> onOpenProduct;
  final Future<void> Function() onRetryEtims;

  /// [items] with the nulls dropped and [gap] put between what is left, so a
  /// section that is absent today leaves no double gap behind it.
  static List<Widget> _spaced(List<Widget?> items, double gap) {
    final List<Widget> present = items.whereType<Widget>().toList();
    return <Widget>[
      for (int i = 0; i < present.length; i++) ...<Widget>[
        if (i > 0) SizedBox(height: gap),
        present[i],
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppState appState = context.watch<AppState>();
    final double gap = spacing.xl;

    final bool hasSales = data.totals.hasSales;

    final Widget? attention = data.attention.isEmpty
        ? null
        : DashboardAttentionCard(
            summary: data.attention,
            canFixEtims: appState.isAdmin,
            onRetryEtims: onRetryEtims,
            onOpenEtimsSettings: onOpenEtimsSettings,
          );

    final Widget shift = DashboardShiftCard(
      shift: data.openShift,
      expected: data.expectedTill,
      onOpen: onOpenShift,
    );

    final Widget sales = hasSales
        ? DashboardHourlySales(buckets: data.hours)
        : DashboardNoSalesCard(hasEverSold: data.hasEverSold);

    final Widget? topProducts =
        hasSales ? DashboardTopProducts(rows: data.topProducts) : null;

    final Widget reorder = DashboardLowStockList(
      products: data.lowStock,
      totalCount: data.lowStockCount,
      canOpen: appState.canManageStock,
      onOpenProduct: onOpenProduct,
      onViewAll: onOpenInventory,
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _kDashboardMaxWidth,
        padding: EdgeInsets.all(spacing.xl),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool twoColumns =
                constraints.maxWidth >= _kTwoColumnBreakpoint;

            final List<Widget> panels = twoColumns
                ? <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _spaced(
                              <Widget?>[sales, topProducts],
                              gap,
                            ),
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _spaced(
                              <Widget?>[shift, reorder],
                              gap,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ]
                : _spaced(
                    <Widget?>[shift, sales, topProducts, reorder],
                    gap,
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                BackupReminderBanner(onBackupNow: onBackupNow),
                ..._spaced(
                  <Widget?>[
                    DashboardHeader(
                      shopName: appState.owner?.shopName ?? 'SimpleSales',
                      subtitle: data.greeting,
                      onSell: onOpenSell,
                    ),
                    // First after the header because it is the only thing that
                    // stops a sale, and a section that is usually empty and
                    // occasionally urgent is read far more seriously than one
                    // that is always on screen.
                    attention,
                    DashboardKpis(
                      totals: data.totals,
                      scopeLabel: data.scopeLabel,
                    ),
                  ],
                  gap,
                ),
                SizedBox(height: gap),
                ...panels,
              ],
            );
          },
        ),
      ),
    );
  }
}
