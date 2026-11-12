import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../profile/profile_product_forms.dart';
import '../profile/profile_terminology.dart';
import '../profile/shop_profile.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../services/live_refresh_mixin.dart';
import '../services/live_channel_service.dart';
import '../services/session_refresh_mixin.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import '../widgets/backup_reminder_banner.dart';

const double _openDashboardMaxWidth = 1200;

/// The Open profile dashboard.
///
/// Job-centred rather than product-centred: revenue, net profit, cash position
/// and receivables lead — then active jobs, jobs awaiting payment, overdue
/// jobs, cost groups and recent activity. Quick actions sit beside the figures
/// so the four questions an Open owner asks are answered on one screen:
///
///   What money came in?  What profit did we make?
///   What is tied up in work?  What is still owed?
class OpenDashboardScreen extends StatefulWidget {
  const OpenDashboardScreen({super.key});

  @override
  State<OpenDashboardScreen> createState() => _OpenDashboardScreenState();
}

class _OpenDashboardScreenState extends State<OpenDashboardScreen>
    with LiveRefresh<OpenDashboardScreen>, SessionRefresh<OpenDashboardScreen> {
  int _revenueMinor = 0;
  int _netProfitMinor = 0;
  int _cashPositionMinor = 0;
  int _receivablesMinor = 0;
  int _activeJobs = 0;
  int _jobsAwaitingPayment = 0;
  int _overdueJobs = 0;
  int _costGroups = 0;
  List<({int id, String title})> _recentJobs = const [];
  List<Map<String, dynamic>> _jobs = const [];
  String? _error;

  @override
  Set<LiveReason> get liveReasons => const <LiveReason>{};

  @override
  bool get liveIsVisible => TickerMode.valuesOf(context).enabled;

  @override
  Future<void> reloadFromLive() => _load();

  @override
  void clearForSession() {
    _revenueMinor = 0;
    _netProfitMinor = 0;
    _cashPositionMinor = 0;
    _receivablesMinor = 0;
    _activeJobs = 0;
    _jobsAwaitingPayment = 0;
    _overdueJobs = 0;
    _costGroups = 0;
    _recentJobs = const [];
    _error = null;
  }

  @override
  Future<void> reloadFromSession() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = DatabaseHelper.instance;
      final jobs = await db.getOpenJobs();
      final pools = await db.getCostPools();
      final credit = await db.creditSummary();

      // Revenue comes only from completed jobs (job_completion financial events),
      // not from deposits collected on open jobs.
      final events = await db.getFinancialEvents();
      int revenue = 0;
      int cashIn = 0;
      int cashOut = 0;
      for (final e in events) {
        if (e.eventType == 'job_completion') {
          revenue += e.revenueMinor;
        }
        cashIn += e.cashInMinor;
        cashOut += e.cashOutMinor;
      }

      int costs = 0;
      int active = 0;
      int awaiting = 0;
      int overdue = 0;
      final now = DateTime.now();
      for (final job in jobs) {
        final jobId = (job['id'] as num).toInt();
        final jc = await db.getJobCosts(jobId);
        costs += jc.fold<int>(0, (s, c) => s + ((c['amount_minor'] as num?)?.toInt() ?? 0));
        final status = (job['status'] as String?) ?? 'draft';
        if (status != 'completed' && status != 'closed' && status != 'cancelled') {
          active++;
        }
        if (status == 'awaiting_payment') awaiting++;
        final due = job['due_at'];
        if (due is String) {
          final dt = DateTime.tryParse(due);
          if (dt != null && dt.isBefore(now) && status != 'completed' && status != 'closed') {
            overdue++;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _revenueMinor = revenue;
        _netProfitMinor = revenue - costs;
        _cashPositionMinor = cashIn - cashOut;
        _receivablesMinor = credit.totalOwedMinor;
        _activeJobs = active;
        _jobsAwaitingPayment = awaiting;
        _overdueJobs = overdue;
        _costGroups = pools.length;
        _recentJobs = jobs.take(3).map((j) => (id: (j['id'] as num).toInt(), title: (j['title'] as String?) ?? '')).toList();
        _jobs = jobs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }


  Future<void> _pickJob(void Function(int jobId) onPicked) async {
    if (_jobs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).openDashboardNoJobs)),
      );
      return;
    }
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppLocalizations.of(context).openDashboardSelectJob),
        children: _jobs.map((j) {
          final id = (j['id'] as num).toInt();
          final title = (j['title'] as String?) ?? 'Untitled';
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(id),
            child: Text(title),
          );
        }).toList(),
      ),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    final appState = context.watch<AppState>();
    final String addItemLabel = 'Add ${appState.shopProfile.terminologyLocalized(l10n).product}';

    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _openDashboardMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () => performBackup(context)),
            SizedBox(height: spacing.section),
            _OpenBusinessHeader(
              shopName: appState.owner?.shopName ?? SimplePosBrand.appName,
              eyebrow: timeOfDayWord(l10n),
              subtitle: l10n.openDashboardGreeting,
            ),
            SizedBox(height: spacing.xl),
            if (_error != null)
              SurfaceCard(
                padding: EdgeInsets.all(spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Unable to load dashboard data',
                      style: AppTypography.of(context).bodyMedium?.copyWith(
                        color: AppColors.of(context).danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: spacing.sm),
                    Text(
                      _error!,
                      style: AppTypography.of(context).bodySmall?.copyWith(
                        color: AppColors.of(context).onSurfaceMuted,
                      ),
                    ),
                    SizedBox(height: spacing.lg),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else
              _OpenFinancialHero(
                revenue: Money.fromMinor(_revenueMinor),
                netProfit: Money.fromMinor(_netProfitMinor),
                cashPosition: Money.fromMinor(_cashPositionMinor),
                receivables: Money.fromMinor(_receivablesMinor),
                scopeLabel: appState.isOwnerSession
                    ? l10n.openDashboardScopeShop
                    : l10n.openDashboardScopeOwn,
              ),
            SizedBox(height: spacing.xl),
            _OpenOperationalOverview(
              activeJobs: _activeJobs,
              jobsAwaitingPayment: _jobsAwaitingPayment,
              overdueJobs: _overdueJobs,
              costGroups: _costGroups,
              onOpenJobs: () => context.push(Routes.openJobs),
              onOpenReceivables: () => context.push(Routes.openReceivables),
              onOpenCostGroups: () => context.push(Routes.openCostGroups),
            ),
            SizedBox(height: spacing.xl),
            _OpenQuickActions(
              onNewJob: () => context.push(Routes.openJobNew),
              onRecordPayment: () => _pickJob((id) => context.push(Routes.openJobDetail(id))),
              onRecordSale: () => context.push(Routes.sell),
              onAddJobCost: () => _pickJob((id) => context.push(Routes.openJobAddCost(id))),
              onNewCostGroup: () => context.push(Routes.openCostGroupNew),
              onAddItem: () => _openAddItem(context),
              onOwnerFinance: () => _recordOwnerTransaction(),
              addItemLabel: addItemLabel,
              canManageJobs: appState.hasPermission(PermissionKey.manageJobs),
              canReceivePayments:
                  appState.hasPermission(PermissionKey.receiveJobPayment),
              canRecordSales:
                  appState.isOwnerSession ||
                      appState.role == ShopRole.manager,
            ),
            SizedBox(height: spacing.xl),
            _OpenRecentActivity(
              title: l10n.openDashboardRecentActivity,
              recent: _recentJobs,
              onOpenJob: () => context.push(Routes.openJobs),
            ),
            SizedBox(height: spacing.section),
          ],
        ),
      ),
    );
  }

  /// Records an owner transaction (capital/drawing/loan). Gated to owner session.
  Future<void> _recordOwnerTransaction() async {
    final appState = context.read<AppState>();
    if (!appState.isOwnerSession) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Owner-only operation')),
      );
      return;
    }
    final typeCtrl = StringBuffer('capital_in');
    final amountCtrl = TextEditingController();
    final referenceCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Owner Finance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: typeCtrl.toString(),
              decoration: const InputDecoration(labelText: 'Transaction type'),
              items: <String>['capital_in', 'drawing', 'loan_received', 'loan_repayment']
                  .map((t) => DropdownMenuItem<String>(
                        value: t,
                        child: Text(t.replaceAll('_', ' ').toUpperCase()),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                typeCtrl.clear();
                typeCtrl.write(v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (KES)'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: referenceCtrl,
              decoration: const InputDecoration(labelText: 'Reference (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) return;
              Navigator.pop(ctx, <String, String>{
                'type': typeCtrl.toString(),
                'amount': amountCtrl.text.trim(),
                'reference': referenceCtrl.text.trim(),
                'note': noteCtrl.text.trim(),
              });
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
    amountCtrl.dispose();
    referenceCtrl.dispose();
    noteCtrl.dispose();
    if (result == null || !mounted) return;
    final amount = double.tryParse(result['amount'] ?? '');
    if (amount == null || amount <= 0) return;
    try {
      await DatabaseHelper.instance.recordOwnerTransaction(
        uuid: 'own-${DateTime.now().microsecondsSinceEpoch}',
        transactionType: result['type']!,
        amount: Money.fromMajor(amount),
        staffName: appState.currentStaffName ?? 'Owner',
        staffId: appState.currentStaffId,
        note: (result['note'] ?? '').isEmpty ? null : result['note'],
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Owner transaction failed: $e')),
        );
      }
    }
  }

  /// Opens the Open-profile add-item dialog. This is the visible entry point
  /// for the profile-defined product creation capability, gated on the profile
  /// tracking stock (now enabled for Open). Persists via upsertProduct.
  Future<void> _openAddItem(BuildContext context) async {
    final result = await ProfileProductForms.showForm(
      context: context,
      profile: ShopProfile.open,
    );
    if (!context.mounted || result == null) return;
    final unit = ProductUnit.parse(result['unit'] as String?);
    final cost = (result['cost'] as num?)?.toDouble() ?? 0;
    final price = (result['price'] as num?)?.toDouble() ?? 0;
    final stock = (result['stock'] as num?)?.toDouble() ?? 0;
    final optionalStock = result['optional_stock'] as bool? ?? false;
    final product = Product(
      name: result['name'] as String,
      category: (result['category'] as String? ?? 'Item or service'),
      costPrice: Money.fromMajor(cost),
      sellPrice: Money.fromMajor(price),
      stockQty: stock,
      reorderLevel: optionalStock ? 5 : 0,
      unit: unit,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await DatabaseHelper.instance.upsertProduct(product);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product.name} saved')),
    );
  }
}

/// Shop header: name, time-of-day greeting, signed-in staff role.
class _OpenBusinessHeader extends StatelessWidget {
  const _OpenBusinessHeader({
    required this.shopName,
    required this.eyebrow,
    required this.subtitle,
  });

  final String shopName;
  final String eyebrow;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Semantics(
      header: true,
      child: Text(
        '$eyebrow · $shopName — $subtitle',
        style: type.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: colors.onSurface,
        ),
        softWrap: true,
      ),
    );
  }
}

/// Top financial overview: Revenue, Net profit, Cash position, Receivables.
class _OpenFinancialHero extends StatelessWidget {
  const _OpenFinancialHero({
    required this.revenue,
    required this.netProfit,
    required this.cashPosition,
    required this.receivables,
    required this.scopeLabel,
  });

  final Money revenue;
  final Money netProfit;
  final Money cashPosition;
  final Money receivables;
  final String scopeLabel;

  (String label, String value, StatusTone tone) _signed(
    Money value, {
    required String goodLabel,
    required String badLabel,
    required String zeroLabel,
    required StatusTone goodTone,
    required StatusTone badTone,
  }) {
    if (value.minorUnits > 0) {
      return (goodLabel, formatMoney(value.abs), goodTone);
    }
    if (value.minorUnits < 0) {
      return (badLabel, formatMoney(value.abs), badTone);
    }
    return (zeroLabel, formatMoney(Money.zero), StatusTone.neutral);
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);

    final net = _signed(
      netProfit,
      goodLabel: l10n.openDashboardProfit,
      badLabel: l10n.openDashboardNotInProfitYet,
      zeroLabel: l10n.openDashboardBreakEven,
      goodTone: StatusTone.success,
      badTone: StatusTone.danger,
    );
    final cash = _signed(
      cashPosition,
      goodLabel: l10n.openDashboardSurplus,
      badLabel: l10n.openDashboardShortfall,
      zeroLabel: l10n.openDashboardBreakEven,
      goodTone: StatusTone.success,
      badTone: StatusTone.danger,
    );
    final rec = _signed(
      receivables,
      goodLabel: l10n.openDashboardOwedToYou,
      badLabel: l10n.openDashboardYouOwe,
      zeroLabel: l10n.openDashboardBreakEven,
      goodTone: StatusTone.warning,
      badTone: StatusTone.danger,
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Container(
            color: AppColors.of(context).surfaceSunken,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  colors.canvas.withValues(alpha: 0.55),
                  colors.canvas.withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        Padding(
          padding: PageGutter.card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.openDashboardFinancialOverview,
                          style: type.labelMedium?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: spacing.xs),
                        Text(
                          scopeLabel,
                          style: type.labelSmall?.copyWith(
                            color: colors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _OpenMoneyTile(
                      label: l10n.openDashboardRevenue,
                      value: formatMoney(revenue),
                      tone: StatusTone.success,
                      icon: Icons.trending_up_outlined,
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: _OpenMoneyTile(
                      label: net.$1,
                      value: net.$2,
                      tone: net.$3,
                      icon: Icons.attach_money_outlined,
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: _OpenMoneyTile(
                      label: cash.$1,
                      value: cash.$2,
                      tone: cash.$3,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: _OpenMoneyTile(
                      label: rec.$1,
                      value: rec.$2,
                      tone: rec.$3,
                      icon: Icons.schedule_outlined,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OpenMoneyTile extends StatelessWidget {
  const _OpenMoneyTile({
    required this.label,
    required this.value,
    required this.tone,
    required this.icon,
  });

  final String label;
  final String value;
  final StatusTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: EdgeInsets.all(spacing.xs),
          decoration: BoxDecoration(
            color: tone.container(colors).withValues(alpha: 0.9),
            borderRadius: AppShapes.of(context).controlRadius,
          ),
          child: Icon(
            icon,
            size: 18,
            color: tone.onContainer(colors),
          ),
        ),
        SizedBox(height: spacing.lg),
        Text(
          value,
          style: AppTypography.money(
            context,
            size: 20,
            weight: FontWeight.w800,
          ).copyWith(color: colors.onSurface),
        ),
        SizedBox(height: spacing.xs),
        Text(
          label,
          style: type.labelMedium?.copyWith(color: colors.onSurface),
        ),
      ],
    );
  }
}

/// Operational overview: active jobs, jobs awaiting payment, overdue jobs, cost groups.
class _OpenOperationalOverview extends StatelessWidget {
  const _OpenOperationalOverview({
    required this.activeJobs,
    required this.jobsAwaitingPayment,
    required this.overdueJobs,
    required this.costGroups,
    required this.onOpenJobs,
    required this.onOpenReceivables,
    required this.onOpenCostGroups,
  });

  final int activeJobs;
  final int jobsAwaitingPayment;
  final int overdueJobs;
  final int costGroups;
  final VoidCallback onOpenJobs;
  final VoidCallback onOpenReceivables;
  final VoidCallback onOpenCostGroups;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final type = AppTypography.of(context);

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.openDashboardOperationalOverview,
            style: type.labelMedium?.copyWith(
              color: colors.onSurfaceMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: spacing.lg),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool row = constraints.maxWidth >= 760;
              final List<Widget> tiles = <Widget>[
                _CountTile(
                  label: l10n.openDashboardActiveJobs,
                  count: activeJobs,
                  tone: activeJobs > 0 ? StatusTone.warning : StatusTone.success,
                  icon: Icons.work_outline,
                  onTap: onOpenJobs,
                ),
                _CountTile(
                  label: l10n.openDashboardJobsAwaitingPayment,
                  count: jobsAwaitingPayment,
                  tone: jobsAwaitingPayment > 0
                      ? StatusTone.warning
                      : StatusTone.success,
                  icon: Icons.schedule_outlined,
                  onTap: onOpenReceivables,
                ),
                _CountTile(
                  label: l10n.openDashboardOverdueJobs,
                  count: overdueJobs,
                  tone: overdueJobs > 0
                      ? StatusTone.danger
                      : StatusTone.success,
                  icon: Icons.error_outline,
                  onTap: onOpenReceivables,
                ),
                _CountTile(
                  label: l10n.openDashboardCostGroups,
                  count: costGroups,
                  tone: StatusTone.neutral,
                  icon: Icons.account_balance_wallet_outlined,
                  onTap: onOpenCostGroups,
                ),
              ];
              if (row) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = 0; i < tiles.length; i++) ...<Widget>[
                      if (i > 0) SizedBox(width: spacing.lg),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: spacing.lg,
                runSpacing: spacing.lg,
                children: tiles.map((t) => SizedBox(width: ((constraints.maxWidth - spacing.lg) / 2).clamp(120.0, double.infinity), child: t)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.count,
    required this.tone,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int count;
  final StatusTone tone;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: spacing.sm,
            runSpacing: spacing.xs,
            children: <Widget>[
              Container(
                padding: EdgeInsets.all(spacing.xs),
                decoration: BoxDecoration(
                  color: tone.container(colors),
                  borderRadius: AppShapes.of(context).controlRadius,
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: tone.onContainer(colors),
                ),
              ),
              StatusChip(tone: tone, text: tone.label, dense: true),
            ],
          ),
          SizedBox(height: spacing.lg),
          Text(
            '$count',
            style: AppTypography.money(
              context,
              size: 20,
              weight: FontWeight.w800,
            ),
          ),
          SizedBox(height: spacing.xs),
          Text(
            label,
            style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

/// Quick actions: New job, Record sale, Record payment, Add job cost, New cost
/// group — as a 2x2 grid of tiles with icon + label + subtitle, mirroring
/// the mockup.
class _OpenQuickActions extends StatelessWidget {
  const _OpenQuickActions({
    required this.onNewJob,
    required this.onRecordPayment,
    required this.onRecordSale,
    required this.onAddJobCost,
    required this.onNewCostGroup,
    required this.onAddItem,
    required this.onOwnerFinance,
    required this.addItemLabel,
    required this.canManageJobs,
    required this.canReceivePayments,
    required this.canRecordSales,
  });

  final VoidCallback onNewJob;
  final VoidCallback onRecordPayment;
  final VoidCallback onRecordSale;
  final VoidCallback onAddJobCost;
  final VoidCallback onNewCostGroup;
  final VoidCallback onAddItem;
  final VoidCallback onOwnerFinance;
  final String addItemLabel;
  final bool canManageJobs;
  final bool canReceivePayments;
  final bool canRecordSales;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    final List<Widget> tiles = <Widget>[
      _OpenQuickTile(
        icon: Icons.add_task,
        label: 'New job',
        subtitle: 'Create a job',
        onTap: onNewJob,
        primary: true,
      ),
      if (canRecordSales)
        _OpenQuickTile(
          icon: Icons.point_of_sale_outlined,
          label: 'Record sale',
          subtitle: 'Quick sale',
          onTap: onRecordSale,
        ),
      _OpenQuickTile(
        icon: Icons.add_circle_outline,
        label: addItemLabel,
        subtitle: 'New catalogue item',
        onTap: onAddItem,
      ),
      if (canReceivePayments)
        _OpenQuickTile(
          icon: Icons.payment_outlined,
          label: 'Record payment',
          subtitle: 'Receive payment',
          onTap: onRecordPayment,
        ),
      if (canManageJobs)
        _OpenQuickTile(
          icon: Icons.add_circle_outline,
          label: 'Add job cost',
          subtitle: 'Log a cost',
          onTap: onAddJobCost,
        ),
      _OpenQuickTile(
        icon: Icons.account_balance_wallet_outlined,
        label: 'New cost group',
        subtitle: 'Pooled costs',
        onTap: onNewCostGroup,
      ),
      _OpenQuickTile(
        icon: Icons.attach_money,
        label: 'Owner finance',
        subtitle: 'Capital, drawing, loan',
        onTap: onOwnerFinance,
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool twoColumns = constraints.maxWidth >= 320;
        if (twoColumns) {
          return Wrap(
            spacing: spacing.md,
            runSpacing: spacing.md,
            children: <Widget>[
              for (final tile in tiles)
                SizedBox(
                  width: (constraints.maxWidth - spacing.md) / 2,
                  child: tile,
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < tiles.length; i++) ...<Widget>[
              if (i > 0) SizedBox(height: spacing.md),
              tiles[i],
            ],
          ],
        );
      },
    );
  }
}

/// One quick-action tile for the open dashboard.
class _OpenQuickTile extends StatelessWidget {
  const _OpenQuickTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      button: true,
      label: '$label, $subtitle',
      child: SurfaceCard(
        padding: EdgeInsets.all(spacing.md),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: EdgeInsets.all(spacing.xs),
              decoration: BoxDecoration(
                color: primary
                    ? colors.accentContainer
                    : colors.surfaceSunken,
                borderRadius: AppShapes.of(context).controlRadius,
              ),
              child: Icon(
                icon,
                size: 20,
                color: primary ? colors.accent : colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: spacing.md),
            Text(
              label,
              style: type.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: primary ? colors.accent : colors.onSurface,
              ),
            ),
            SizedBox(height: 2),
            Text(
              subtitle,
              style: type.bodySmall?.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recent activity: a compact list of recent payments, job updates, costs and quick sales.
class _OpenRecentActivity extends StatelessWidget {
  const _OpenRecentActivity({
    required this.title,
    required this.recent,
    required this.onOpenJob,
  });

  final String title;
  final List<({int id, String title})> recent;
  final VoidCallback onOpenJob;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: onOpenJob,
              child: Text(l10n.openDashboardViewAll),
            ),
          ],
        ),
        SizedBox(height: spacing.sm),
        if (recent.isEmpty)
          Text(
            'No recent activity yet.',
            style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recent.length,
            itemBuilder: (_, i) {
              final entry = recent[i];
              return Padding(
                padding: EdgeInsets.only(bottom: spacing.sm),
                child: InkWell(
                  onTap: () => context.push(Routes.openJobDetail(entry.id)),
                  child: Row(
                    children: <Widget>[
                    Container(
                      padding: EdgeInsets.all(spacing.xs),
                      decoration: BoxDecoration(
                        color: colors.surfaceSunken,
                        borderRadius: AppShapes.of(context).controlRadius,
                      ),
                      child: Icon(
                        Icons.access_time_outlined,
                        size: 16,
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                    SizedBox(width: spacing.md),
                    Expanded(
                      child: Text(
                        entry.title,
                        style: type.bodyMedium,
                      ),
                    ),
                  ],
                ),
                ),
              );
            },
          ),
      ],
    );
  }
}

String timeOfDayWord(AppLocalizations l10n) {
  final hour = DateTime.now().hour;
  if (hour < 12) return l10n.openDashboardGoodMorning;
  if (hour < 17) return l10n.openDashboardGoodAfternoon;
  return l10n.openDashboardGoodEvening;
}

/// A minimal model so RefreshIndicator has an onRefresh target.
class OpenDashboardModel extends ChangeNotifier {
  Future<void> load() async {
    notifyListeners();
  }
}
