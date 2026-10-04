import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/analytics.dart';
import '../services/app_state.dart';
import '../services/etims/etims_service.dart';
import '../services/excel_service.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';
import '../widgets/chart.dart';
import 'home_shell.dart';
import 'shift_screen.dart';

/// What a seller needs before they need anything else.
///
/// Ordered by what a shift actually goes wrong in: what will stop me selling
/// (the attention list), what have I made (the KPIs and the hour chart), what
/// should I reorder (low stock), and last the stock that is merely interesting.
/// Everything on this screen is read in the seconds between customers, so it
/// answers questions rather than reporting activity.
///
/// Every figure is scoped by `staff_id`, never by name: a cashier sees their
/// own takings and a manager or owner sees the shop's. See
/// `staffIdForCashier` for why the id is the only defensible filter.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;

  DailyTotals _today = DailyTotals.empty;

  /// Whether the ledger has *ever* held a sale. A zero-sales day and a till
  /// that has never sold anything need different words, and one screen that
  /// says "Sales today KSh 0" for both cannot tell them apart.
  bool _hasEverSold = false;

  List<TimeBucket> _hours = const [];
  List<ProductSalesRow> _topProducts = const [];
  List<Product> _lowStock = const [];
  int _lowStockCount = 0;
  AttentionSummary _attention = AttentionSummary.empty;

  /// "the shop" or the cashier's own name — says out loud whose takings these
  /// are, because the number itself cannot.
  String _scopeLabel = 'the shop';

  /// The signed-in person's open shift, and what the drawer should hold in it.
  ///
  /// Loaded here rather than read when the card is built, because the card needs
  /// a number — the expected cash — that only the database can produce, and
  /// building it inline would mean a query per rebuild.
  Shift? _openShift;
  Money _expectedTill = Money.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final appState = context.read<AppState>();
    final ownOnly = !appState.canManageStock;
    final staffId = ownOnly
        ? staffIdForCashier(
            await db.getStaff(activeOnly: false), appState.currentStaffName)
        : null;

    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final tomorrow = dayStart.add(const Duration(days: 1));

      // One round trip for the whole screen rather than a cascade of
      // dependent ones: these seven aggregates do not depend on each other.
      final results = await Future.wait([
        db.salesTotalsFor(since: dayStart, staffId: staffId),
        db.salesTotalsFor(staffId: staffId),
        db.salesByHour(day: dayStart, staffId: staffId),
        db.topProducts(
            since: dayStart, until: tomorrow, staffId: staffId, limit: 5),
        db.countLowStockProducts(),
        db.attentionSummary(),
        db.getProducts(),
        appState.currentStaffId == null
            ? Future.value(null)
            : db.getOpenShift(appState.currentStaffId!),
      ]);

      final low = (results[6] as List<Product>).where((p) => p.isLow).toList()
        // Out-of-stock first: it is the only entry here that stops a sale.
        ..sort((a, b) {
          final byEmpty =
              (a.stockQty <= 0 ? 0 : 1).compareTo(b.stockQty <= 0 ? 0 : 1);
          return byEmpty != 0 ? byEmpty : a.stockQty.compareTo(b.stockQty);
        });

      if (!mounted) return;
      setState(() {
        _today = results[0] as DailyTotals;
        _hasEverSold = (results[1] as DailyTotals).hasSales;
        _hours = results[2] as List<TimeBucket>;
        _topProducts = results[3] as List<ProductSalesRow>;
        _lowStockCount = results[4] as int;
        _attention = results[5] as AttentionSummary;
        _lowStock = low;
        _scopeLabel =
            ownOnly ? (appState.currentStaffName ?? 'you') : 'the shop';
        _openShift = results[7] as Shift?;
        _loading = false;
        _error = null;
      });
      // Outside the setState so the expected figure does not arrive a frame
      // later than the shift that produces it.
      final shift = _openShift;
      if (shift != null) {
        final expected = await db.expectedTillBalance(shift);
        if (!mounted) return;
        setState(() => _expectedTill = expected);
      } else {
        _expectedTill = Money.zero;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t load today’s dashboard data.';
      });
    }
  }

  void _goToShift() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ShiftScreen()),
    );
    // The shift may have been opened or closed on that screen, and the card's
    // number is a figure from the ledger rather than a UI value.
    if (mounted) await _load();
  }

  void _goToInventory() {
    final tabs = context.read<HomeShellTabs>();
    // A cashier has no Inventory tab; HomeShellTabs.goTo ignores a destination
    // this role does not have, so there is nothing to guard here.
    tabs.goTo(HomeTab.inventory);
  }

  /// Retries the KRA upload queue, then re-reads the counts.
  ///
  /// The action is the one the situation actually needs: these receipts are
  /// waiting because the till was offline, and a queue that only reports its
  /// own size every morning is an outage nobody can end.
  Future<void> _retryEtims() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await EtimsService().flushPending();
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(EtimsService.describeResult(result))));
      await _load();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Could not reach KRA. The receipts stay queued and will go up on the next connection.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ]),
      ));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(DukaSpacing.lg),
        children: [
          BackupReminderBanner(onBackupNow: () async {
            final file = await ExcelService().exportEncryptedInventory();
            await ExcelService().shareFile(file);
          }),
          _Greeting(
            shopName: context.read<AppState>().owner?.shopName ?? 'Duka POS',
            staffName: context.read<AppState>().currentStaffName,
            role: context.read<AppState>().currentRole,
            scopeLabel: _scopeLabel,
          ),
          const SizedBox(height: DukaSpacing.lg),
          _ShiftCard(
            shift: _openShift,
            expected: _expectedTill,
            onOpen: _goToShift,
          ),
          const SizedBox(height: DukaSpacing.lg),
          _KpiGrid(
            totals: _today,
            scopeLabel: _scopeLabel,
          ),
          const SizedBox(height: DukaSpacing.md),
          _LowStockTile(
            count: _lowStockCount,
            onTap: _goToInventory,
          ),
          if (!_attention.isEmpty) ...[
            const SizedBox(height: DukaSpacing.xl),
            _AttentionSection(
              summary: _attention,
              canOpenSettings: context.read<AppState>().isAdmin,
              onRetryEtims: _retryEtims,
              onOpenSettings: () =>
                  context.read<HomeShellTabs>().goTo(HomeTab.settings),
            ),
          ],
          const SizedBox(height: DukaSpacing.xl),
          if (!_today.hasSales)
            _NoSalesToday(hasEverSold: _hasEverSold)
          else ...[
            _HourlySalesChart(buckets: _hours),
            const SizedBox(height: DukaSpacing.xl),
            _TopProductsChart(rows: _topProducts),
          ],
          const SizedBox(height: DukaSpacing.xl),
          _LowStockList(
            products: _lowStock,
            totalCount: _lowStockCount,
            onViewAll: _goToInventory,
          ),
        ],
      ),
    );
  }
}

/// Shop name, who is signed in, and whose numbers they are looking at.
class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.shopName,
    required this.staffName,
    required this.role,
    required this.scopeLabel,
  });

  final String shopName;
  final String? staffName;
  final String role;
  final String scopeLabel;

  static String _partOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _roleLabel(String role) => switch (role) {
        'admin' => 'Owner',
        'manager' => 'Manager',
        _ => 'Cashier',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = staffName ?? '';
    final roleLabel = _roleLabel(role);
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(shopName, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            name.isEmpty
                ? '$_partOfDay() · showing $scopeLabel'
                : '$_partOfDay(), $name · $roleLabel · showing $scopeLabel',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The four figures a seller checks between customers.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.totals, required this.scopeLabel});

  final DailyTotals totals;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Two columns at any width. A three- or four-across grid fits a 400px
      // phone and overflows a 320px one, which is a size real budget phones
      // still use at the counter.
      const spacing = DukaSpacing.md;
      final tileWidth = (constraints.maxWidth - spacing) / 2;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          SizedBox(
            width: tileWidth,
            child: _KpiTile(
              label: 'Sales today',
              value: formatMoney(totals.total),
              semanticsValue: 'for $scopeLabel',
            ),
          ),
          SizedBox(
            width: tileWidth,
            child: _KpiTile(
              label: 'Profit today',
              value: formatMoney(totals.profit),
              caption: totals.hasSales
                  ? '${totals.marginPct.toStringAsFixed(0)}% margin'
                  : null,
            ),
          ),
          SizedBox(
            width: tileWidth,
            child: _KpiTile(
              label: 'Transactions',
              value: '${totals.transactions}',
              caption: '${_plural(totals.transactions, 'sale')} today',
            ),
          ),
          SizedBox(
            width: tileWidth,
            child: _KpiTile(
              label: 'Avg basket',
              value: formatMoney(totals.averageBasket),
              caption: totals.hasSales ? 'per customer' : null,
            ),
          ),
        ],
      );
    });
  }

  static String _plural(int count, String word) =>
      count == 1 ? '$count $word' : '$count ${word}s';
}

/// One figure. The value is the loud part, the label says what it is, and a
/// screen reader gets both plus any caption — a bold number on its own is not
/// an accessible label.
class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    this.caption,
    this.semanticsValue,
  });

  final String label;
  final String value;
  final String? caption;
  final String? semanticsValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = [label, value, if (caption != null) caption!];
    if (semanticsValue != null) parts.add(semanticsValue!);
    return Semantics(
      label: parts.join(', '),
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(DukaSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Wraps rather than shrinks. Scaling a number down to fit is how
              // a large figure ends up rendered a point smaller than a small
              // one, and a sale of KSh 1,204,500 has to be able to say so.
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.bodySmall),
              if (caption != null)
                Text(caption!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Low stock as a full-width row rather than a fifth KPI tile.
///
/// It is the only figure here with a next step, and it is the one a seller
/// acts on — so it gets the whole row, an icon, and the affordance of
/// something tappable.
class _LowStockTile extends StatelessWidget {
  const _LowStockTile({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warn = count > 0;
    final message = warn
        ? '$count ${count == 1 ? 'product is' : 'products are'} at or below the reorder level'
        : 'Everything is above its reorder level';
    return Semantics(
      button: true,
      label: 'Low stock. $message. Open inventory.',
      excludeSemantics: true,
      child: Card(
        color: warn ? DukaColors.surfaceWarm : DukaColors.surface,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(DukaSpacing.md),
            child: Row(
              children: [
                Icon(
                  warn
                      ? Icons.production_quantity_limits
                      : Icons.check_circle_outline,
                  color: warn ? DukaColors.danger : DukaColors.success,
                ),
                const SizedBox(width: DukaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Low stock', style: theme.textTheme.titleMedium),
                      Text(message, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: DukaColors.mutedInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The four things that derail a shift, with a way out of each.
///
/// Shown only when something is actually outstanding — a section that is
/// usually empty and occasionally urgent is read far more seriously than one
/// that is always on screen. Each row names the consequence as well as the
/// count, because "3" means nothing and "3 receipts KRA has not issued" means
/// an unfiled tax invoice for money already taken.
/// The signed-in person's shift, or the prompt to open one.
///
/// On the dashboard rather than behind a tab because a shift is the thing a
/// cashier has to do before they can reconcile, and a screen they have to go
/// looking for is a screen they will forget. The two states are given different
/// words on purpose: "no shift open" is a missing first step, not an error.
class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.shift,
    required this.expected,
    required this.onOpen,
  });

  final Shift? shift;
  final Money expected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = shift;
    return Card(
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: current == null
              ? Row(
                  children: [
                    Icon(Icons.play_circle_outline,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('No shift open',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          SizedBox(height: 2),
                          Text('Tap to count the cash you start with'),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                  ],
                )
              : Semantics(
                  label:
                      'Shift open since ${current.startTime}. ${formatMoney(expected)} expected in the drawer.',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Shift open',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${formatMoney(expected)} expected in the drawer',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: theme.colorScheme.outline),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _AttentionSection extends StatelessWidget {
  const _AttentionSection({
    required this.summary,
    required this.canOpenSettings,
    required this.onRetryEtims,
    required this.onOpenSettings,
  });

  final AttentionSummary summary;
  final bool canOpenSettings;
  final VoidCallback onRetryEtims;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text('Needs your attention',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: DukaSpacing.sm),
        Card(
          child: Column(
            children: [
              if (summary.pendingEtims > 0)
                _AttentionRow(
                  icon: Icons.receipt_long_outlined,
                  tone: _AttentionTone.warning,
                  title:
                      '${summary.pendingEtims} receipt${_s(summary.pendingEtims)} waiting for KRA',
                  detail:
                      'Money taken, invoice not yet issued. They upload on their own once there is a connection.',
                  actionLabel: 'Retry now',
                  onAction: onRetryEtims,
                ),
              if (summary.rejectedEtims > 0)
                _AttentionRow(
                  icon: Icons.gpp_bad_outlined,
                  tone: _AttentionTone.danger,
                  title:
                      '${summary.rejectedEtims} receipt${_s(summary.rejectedEtims)} rejected by KRA',
                  detail: canOpenSettings
                      ? 'Retrying will fail until the shop\u2019s TIN or device ID is corrected.'
                      : 'These will not retry successfully until the owner corrects the shop\u2019s KRA setup.',
                  actionLabel: canOpenSettings ? 'Open settings' : null,
                  onAction: canOpenSettings ? onOpenSettings : null,
                ),
              if (summary.unverifiedPayments > 0)
                _AttentionRow(
                  icon: Icons.phone_android_outlined,
                  tone: _AttentionTone.warning,
                  title:
                      '${summary.unverifiedPayments} mobile money payment${_s(summary.unverifiedPayments)} unconfirmed',
                  detail:
                      'Taken offline and never matched to a provider receipt. Reconcile them against your PayHero statement.',
                ),
              if (summary.openImportProblems > 0)
                _AttentionRow(
                  icon: Icons.upload_file_outlined,
                  tone: _AttentionTone.warning,
                  title:
                      '${summary.openImportProblems} imported row${_s(summary.openImportProblems)} need attention',
                  detail:
                      'Rows a spreadsheet could not be turned into products. Fix the source file and import again.',
                  actionLabel: 'Review rows',
                  onAction: () => _showImportProblems(context),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _s(int count) => count == 1 ? '' : 's';

  /// The rows themselves, so "3 need attention" is answerable without leaving
  /// the dashboard.
  static Future<void> _showImportProblems(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final rows = await DatabaseHelper.instance.getImportProblems(limit: 20);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rows that need attention'),
        content: rows.isEmpty
            ? const Text('Nothing outstanding.')
            : ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 420, maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final row in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(row.label),
                        subtitle: Text(row.problem),
                        trailing: TextButton(
                          onPressed: () async {
                            final id = row.id;
                            if (id == null) return;
                            await DatabaseHelper.instance
                                .resolveImportProblem(id);
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            messenger.showSnackBar(const SnackBar(
                                content: Text('Marked as dealt with.')));
                          },
                          child: const Text('Done'),
                        ),
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'))
        ],
      ),
    );
  }
}

/// How serious a row is. Carried as an icon and a colour together, never a
/// colour alone.
enum _AttentionTone { warning, danger }

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final _AttentionTone tone;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour =
        tone == _AttentionTone.danger ? DukaColors.danger : DukaColors.warning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          DukaSpacing.md, DukaSpacing.md, DukaSpacing.sm, DukaSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colour),
          const SizedBox(width: DukaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (onAction != null && actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Takings hour by hour, so the owner can see when to put a second person on
/// the counter.
class _HourlySalesChart extends StatelessWidget {
  const _HourlySalesChart({required this.buckets});

  final List<TimeBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final peak = busiestHour(buckets);
    return SimplePosChart(
      title: 'Sales by hour today',
      emphasis: peak == null
          ? null
          : 'Busiest around ${peak.hourLabel} — ${formatMoney(peak.sales)}',
      semanticsLabel: 'Sales by hour today. '
          '${peak == null ? 'No sales recorded.' : 'Busiest hour ${peak.hourLabel}, ${formatMoney(peak.sales)} across ${peak.transactions} ${peak.transactions == 1 ? 'sale' : 'sales'}.'}',
      bars: [
        for (final bucket in buckets)
          PosChartBar(
            label: bucket.hourLabel,
            value: bucket.salesMinor,
            valueLabel: formatMoney(bucket.sales),
          ),
      ],
    );
  }
}

/// What is actually moving, as horizontal bars — a product name needs the whole
/// left column to itself, which a vertical bar cannot give it.
class _TopProductsChart extends StatelessWidget {
  const _TopProductsChart({required this.rows});

  final List<ProductSalesRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Semantics(
        header: true,
        child: Text('Top products today',
            style: Theme.of(context).textTheme.titleMedium),
      );
    }
    return SimplePosChart(
      title: 'Top products today',
      semanticsLabel: describeTopProducts(rows),
      axis: PosChartAxis.horizontal,
      bars: [
        for (final row in rows)
          PosChartBar(
            label: row.productName,
            value: row.revenueMinor,
            valueLabel: formatMoney(row.revenue),
          ),
      ],
    );
  }
}

/// Nothing sold yet, said as its own thing.
///
/// The old dashboard rendered a row of zeroes, which reads identically to "we
/// sold nothing" and to "this till has never sold anything" — two very
/// different mornings for the person reading it.
class _NoSalesToday extends StatelessWidget {
  const _NoSalesToday({required this.hasEverSold});

  final bool hasEverSold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DukaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_empty, color: DukaColors.mutedInk),
                const SizedBox(width: DukaSpacing.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      hasEverSold
                          ? 'No sales yet today'
                          : 'No sales recorded yet',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DukaSpacing.sm),
            Text(
              hasEverSold
                  ? 'Nothing has been rung through since the till opened. Sales appear here the moment the first one is.'
                  : 'This till has no sales in its ledger yet. The first sale you ring through will start the record.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// The stock that will stop a sale, capped, with a way to see the rest.
class _LowStockList extends StatelessWidget {
  const _LowStockList({
    required this.products,
    required this.totalCount,
    required this.onViewAll,
  });

  final List<Product> products;
  final int totalCount;
  final VoidCallback onViewAll;

  /// What the list shows before offering a link. Eight fills a tall phone
  /// without pushing the charts off the first screen.
  static const int shown = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = products.take(shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text('Low stock', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: DukaSpacing.sm),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: DukaSpacing.sm),
            child: Text('All stocked up.'),
          )
        else
          Card(
            child: Column(
              children: [
                for (final product in visible) _LowStockRow(product: product),
              ],
            ),
          ),
        if (totalCount > visible.length) ...[
          const SizedBox(height: DukaSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onViewAll,
              icon: const Icon(Icons.list_alt_outlined),
              label: Text('View all $totalCount in inventory'),
            ),
          ),
        ],
      ],
    );
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final out = product.stockQty <= 0;
    final stock = product.stockQty == product.stockQty.roundToDouble()
        ? product.stockQty.toStringAsFixed(0)
        : product.stockQty.toStringAsFixed(1);
    return ListTile(
      title: Text(product.name, style: theme.textTheme.bodyLarge),
      subtitle: Text('Reorder at ${product.reorderLevel}',
          style: theme.textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The word carries the state, not just the colour: "Out" beside a red
          // 0 is legible to someone who cannot see the red.
          if (out)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: DukaSpacing.sm),
              child: Text(
                'Out',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: DukaColors.danger),
              ),
            ),
          Text(
            '$stock left',
            style: TextStyle(
              color: out ? DukaColors.danger : DukaColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
