import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import '../services/roles.dart';
import '../services/live_channel_service.dart';
import '../services/live_refresh_mixin.dart';
import '../services/session_refresh_mixin.dart';
import '../services/etims/etims_service.dart';
import '../services/excel_service.dart';
import '../theme/app_haptics.dart';
import '../theme/app_spacing.dart';
import '../ui/components/controls.dart';
import '../ui/components/operation_result.dart';
import '../ui/components/states.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';
import 'dashboard_attention.dart';
import 'dashboard_sections.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

sealed class _DashboardState {
  const _DashboardState();
}

final class _DashboardLoading extends _DashboardState {
  const _DashboardLoading();
}

final class _DashboardFailed extends _DashboardState {
  const _DashboardFailed();
}

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
    this.creditOwedMinor = 0,
    this.creditCustomerCount = 0,
  });

  final DailyTotals totals;

  final bool hasEverSold;

  final List<TimeBucket> hours;
  final List<ProductSalesRow> topProducts;
  final List<Product> lowStock;
  final int lowStockCount;
  final AttentionSummary attention;

  final String scopeLabel;

  final String greeting;

  final Shift? openShift;
  final Money expectedTill;
  final int creditOwedMinor;
  final int creditCustomerCount;
}

class _DashboardScreenState extends State<DashboardScreen>
    with LiveRefresh<DashboardScreen>, SessionRefresh<DashboardScreen> {
  _DashboardState? _state;

  int _loadSerial = 0;

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
  void clearForSession() {
    _state = null;
  }

  @override
  Future<void> reloadFromSession() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final int serial = ++_loadSerial;
    final AppState appState = context.read<AppState>();
    // The localisations are read ONCE, up front, and carried through the
    // awaits below: a `BuildContext` does not survive an await, and reading it
    // afterwards is how a screen ends up building a string in a language that
    // is no longer the one on the device.
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Which session this load answers. A load reads the session in pieces
    // across several awaits — the role up front, the name and the id later —
    // so a sign-out or sign-in landing mid-load would otherwise be answered
    // with one session's scope and another session's greeting.
    final int session = appState.sessionGeneration;
    setState(() {
      _state ??= const _DashboardLoading();
    });

    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      // Stock access and sales visibility are separate permissions. A cashier
      // may be granted stock-receiving without being granted the whole shop's
      // financial view.
      final bool ownOnly = !appState.seesAllSales;
      // A cashier's own figures only. An id that cannot be resolved scopes to
      // NOBODY: the name lookup returns nothing for a name that matches no
      // roster row or two of them, and null means "no filter" to every scoped
      // query — which would show this cashier the whole shop's takings as
      // their own. Over-reporting someone's day is the worse of the two
      // errors, so the unresolved case reads as nothing sold. See `ownStaffId`
      // for the resolution order and the closed failure.
      final int? staffId = ownOnly
          ? ownStaffId(
              // The session's own id first: `signInAsStaff` carries the local
              // staff row's id, and that is the id `sales.staff_id` holds. The
              // name lookup is only the fallback for a restored session with
              // no id, and it fails CLOSED either way — see `ownStaffId`.
              sessionStaffId: appState.currentStaffId,
              staff: await db.getStaff(activeOnly: false),
              staffName: appState.currentStaffName,
            )
          : null;

      final DateTime now = DateTime.now();
      final DateTime dayStart = DateTime(now.year, now.month, now.day);
      final DateTime tomorrow = dayStart.add(const Duration(days: 1));

      final List<Product> products = await db.getProducts();
      final DailyTotals totalsToday =
          await db.salesTotalsFor(since: dayStart, staffId: staffId);
      final DailyTotals totalsAll = await db.salesTotalsFor(staffId: staffId);
      final creditSummary = ownOnly
          ? (totalOwedMinor: 0, customerCount: 0)
          : await db.creditSummary();

      if (!_current(serial, session, appState)) return;
      if (products.isEmpty && !totalsAll.hasSales) {
        final Shift? shift = appState.currentStaffId == null
            ? null
            : await db.getOpenShift(appState.currentStaffId!);
        // Re-checked: the greeting below reads the session again, and the read
        // that follows it is enough time for an idle sign-out to land.
        if (!_current(serial, session, appState)) return;
        final String scopeLabel = _scopeLabel(l10n, ownOnly: ownOnly);
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
              l10n,
              staffName: appState.currentStaffName ?? '',
            ),
            openShift: shift,
            expectedTill: Money.zero,
            creditOwedMinor: creditSummary.totalOwedMinor,
            creditCustomerCount: creditSummary.customerCount,
          );
        });
        if (shift == null) return;
        final Money expected = await db.expectedTillBalance(shift);
        if (!_current(serial, session, appState)) return;
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
              creditOwedMinor: ready.creditOwedMinor,
              creditCustomerCount: ready.creditCustomerCount,
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

      // Every session read from here on — the scope label and the greeting —
      // is behind the guard, so a sign-out that landed during the batch above
      // cannot flavour the figures it finally leaves on screen.
      if (!_current(serial, session, appState)) return;
      final String scopeLabel =
          ownOnly ? (appState.currentStaffName ?? 'you') : 'the shop';

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
            l10n,
            staffName: appState.currentStaffName ?? '',
          ),
          openShift: shift,
          expectedTill: Money.zero,
          creditOwedMinor: creditSummary.totalOwedMinor,
          creditCustomerCount: creditSummary.customerCount,
        );
      });

      if (shift == null) return;
      final Money expected = await db.expectedTillBalance(shift);
      if (!_current(serial, session, appState)) return;
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
            creditOwedMinor: ready.creditOwedMinor,
            creditCustomerCount: ready.creditCustomerCount,
          ));
    } catch (_) {
      if (!_current(serial, session, appState)) return;
      setState(() {
        _state ??= const _DashboardFailed();
      });
    }
  }

  /// Whether the load numbered [serial], started for session [session], is
  /// still the one this screen is waiting for.
  ///
  /// Two ways a load can be overtaken, and both drop its result: a newer load
  /// started (which will deliver), or the session changed underneath it — in
  /// which case what it read is a mix of two sessions' scope and greeting and

  bool _current(int serial, int session, AppState appState) =>
      mounted && serial == _loadSerial && appState.sessionGeneration == session;

  /// The welcome line.
  ///
  /// A SENTENCE, and only a sentence: "Good morning, Wanjiru."
  ///
  /// It used to be "Good morning, Wanjiru · Cashier · you" — the greeting, the
  /// name, the role and the scope, run together with dots. That is a database
  /// row printed as a welcome, and it read as robotic because it was one: a
  /// comma-spliced list of four facts, two of which ("Cashier") were the same
  /// information the shell's bar already carried, and one of which ("you") was
  /// a pronoun with nothing to refer to.
  ///
  /// The three facts now live where each of them belongs. The NAME is here,
  /// because a greeting that does not say who it is for is not a greeting. The
  /// ROLE is in the shell's bar, beside the sign-out. The SCOPE is on the
  /// figure it qualifies — "Sales today · the whole shop" — because it is a
  /// statement about whose takings are on screen, not about the person
  /// reading them.
  static String _greeting(
    AppLocalizations l10n, {
    required String staffName,
  }) {
    final int hour = DateTime.now().hour;
    final String greeting = hour < 12
        ? l10n.dashboardGreetingMorning
        : hour < 17
            ? l10n.dashboardGreetingAfternoon
            : l10n.dashboardGreetingEvening;
    final String name = staffName.trim();
    return name.isEmpty
        ? l10n.dashboardGreetingAnonymous(greeting)
        : l10n.dashboardGreetingNamed(greeting, name);
  }

  /// Whose takings the screen is showing.
  ///
  /// A cashier sees their OWN; an owner or a manager sees the whole shop. The
  /// words are a phrase that finishes "Sales today · …", and they are
  /// localised — they used to be the English literals "the shop" and the
  /// staff's own name, in an app that localises everything else.
  static String _scopeLabel(
    AppLocalizations l10n, {
    required bool ownOnly,
  }) =>
      ownOnly ? l10n.dashboardScopeOwn : l10n.dashboardScopeShop;

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

  void _openEtimsSettings() {
    context.push(Routes.taxSettings);
  }

  void _openProduct(Product product) {
    final int? id = product.id;
    if (id == null) return;
    context.push(Routes.product(AppLocalizations.of(context).dashboardId(id)));
  }

  /// Backs up now, and says what happened.
  ///
  /// The owner pressed this because they were worried, and a backup that
  /// quietly failed leaves them MORE worried, not less. So both outcomes are a
  /// screen: what was made, or why there was not one.
  Future<void> _backupNow() async {
    final l10n = AppLocalizations.of(context);
    try {
      final file = await ExcelService().exportEncryptedInventory();
      await ExcelService().shareFile(file);
      if (!mounted) return;
      showOperationSuccess(
        context,
        title: l10n.settingsBackupDoneTitle,
        message: l10n.settingsBackupDone,
        detailIcon: Icons.backup_outlined,
      );
    } on Object {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsBackupFailedTitle,
        message: l10n.settingsBackupFailed,
        icon: Icons.backup_outlined,
        onRetry: _backupNow,
      );
    }
  }

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

  /// Puts the receipts KRA refused back in the queue and tries again.
  ///
  /// The owner has just fixed the cause — a wrong TIN, a buyer PIN — and the
  /// invoices still have to be filed. This is the action that makes a refusal
  /// a thing to resolve rather than a thing to stare at.
  Future<void> _retryRejectedEtims() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final EtimsFlushResult result = await EtimsService().retryRejected();
      if (!mounted) return;
      HapticTheme.of(context).fire(HapticEvent.commit);
      showAppSnackBar(context, message: EtimsService.describeResult(result));
      await _load();
    } catch (_) {
      if (!mounted) return;
      HapticTheme.of(context).fire(HapticEvent.reject);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.attentionKraRetryFailed),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      null || _DashboardLoading() => const _DashboardSkeleton(),
      _DashboardFailed() => ErrorStateView(
          message: AppLocalizations.of(context).dashboardCouldNotLoad,
          detail: AppLocalizations.of(context).dashboardStillWorksDetail,
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
          onRetryRejectedEtims: _retryRejectedEtims,
        ),
    };
  }
}

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

const double _kDashboardMaxWidth = 1200;

const double _kTwoColumnBreakpoint = 840;

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
    required this.onRetryRejectedEtims,
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
  final Future<void> Function() onRetryRejectedEtims;

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
            // Only the people who can fix the cause may put the refused
            // receipts back: a cashier tapping "Try again" on a shop whose TIN
            // is still wrong gets the same refusal and a lot less patience.
            onRetryRejectedEtims:
                appState.isAdmin ? onRetryRejectedEtims : null,
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

    final bool canManageCredit =
        appState.isOwnerSession || appState.role == ShopRole.manager;
    final Widget? credit = canManageCredit
        ? DashboardCreditCard(
            owedMinor: data.creditOwedMinor,
            customerCount: data.creditCustomerCount,
            onOpen: () => context.push(Routes.customers),
          )
        : null;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _kDashboardMaxWidth,
        // The page's gutter, from the shared helper: a phone gets a smaller
        // one, because 16dp of page padding plus 16dp of card padding plus a
        // border is 33dp of nothing before the first word.
        padding: PageGutter.of(context),
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
                              <Widget?>[shift, credit, reorder],
                              gap,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ]
                : _spaced(
                    <Widget?>[shift, credit, sales, topProducts, reorder],
                    gap,
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                BackupReminderBanner(onBackupNow: onBackupNow),
                SizedBox(height: spacing.section),
                ..._spaced(
                  <Widget?>[
                    DashboardHeader(
                      shopName:
                          appState.owner?.shopName ?? SimplePosBrand.appName,
                      subtitle: data.greeting,
                      onSell: onOpenSell,
                    ),
                    // First after the header because it is the only thing that
                    // stops a sale, and a section that is usually empty and
                    // occasionally urgent is read far more seriously than one
                    // that is always on screen. Traversal priority goes to the
                    // attention list before every figure on screen.
                    if (attention != null)
                      Semantics(
                        sortKey: const OrdinalSortKey(0),
                        child: attention,
                      ),
                    DashboardKpis(
                      totals: data.totals,
                      scopeLabel: data.scopeLabel,
                      // A count of transactions is a question — which ones, and
                      // by whom — so the card opens the list that answers it.
                      onTransactions: () => context.push(Routes.transactions),
                    ),
                    credit,
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
