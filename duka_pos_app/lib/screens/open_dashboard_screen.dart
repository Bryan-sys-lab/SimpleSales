import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
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
class OpenDashboardScreen extends StatelessWidget {
  const OpenDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    final appState = context.watch<AppState>();

    return RefreshIndicator(
      onRefresh: () => context.read<OpenDashboardModel>().load(),
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _openDashboardMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () async {}),
            SizedBox(height: spacing.section),
            _OpenBusinessHeader(
              shopName: appState.owner?.shopName ?? SimplePosBrand.appName,
              eyebrow: timeOfDayWord(l10n),
              subtitle: l10n.openDashboardGreeting,
            ),
            SizedBox(height: spacing.xl),
            _OpenFinancialHero(
              revenue: Money.fromMinor(125000),
              netProfit: Money.fromMinor(42000),
              cashPosition: Money.fromMinor(31000),
              receivables: Money.fromMinor(18500),
              scopeLabel: appState.isOwnerSession
                  ? l10n.openDashboardScopeShop
                  : l10n.openDashboardScopeOwn,
            ),
            SizedBox(height: spacing.xl),
            _OpenOperationalOverview(
              activeJobs: 3,
              jobsAwaitingPayment: 2,
              overdueJobs: 1,
              costGroups: 4,
              onOpenJobs: () => context.push(Routes.openJobs),
              onOpenReceivables: () => context.push(Routes.openReceivables),
              onOpenCostGroups: () => context.push(Routes.openCostGroups),
            ),
            SizedBox(height: spacing.xl),
            _OpenQuickActions(
              onNewJob: () => context.push(Routes.openJobNew),
              onRecordPayment: () => context.push(Routes.openRecordPayment),
              onRecordSale: () => context.push(Routes.openSell),
              onAddJobCost: () => context.push(Routes.openAddJobCost),
              onNewCostGroup: () => context.push(Routes.openNewCostGroup),
              canManageJobs: appState.canManageStock,
              canReceivePayments:
                  appState.hasPermission(PermissionKey.receiveStock),
              canRecordSales:
                  appState.isOwnerSession ||
                      appState.role == ShopRole.manager,
            ),
            SizedBox(height: spacing.xl),
            _OpenRecentActivity(
              title: l10n.openDashboardRecentActivity,
              onOpenJob: () => context.push(Routes.openJobs),
            ),
            SizedBox(height: spacing.section),
          ],
        ),
      ),
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
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    eyebrow,
                    style: type.labelMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    shopName,
                    style: type.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.sm),
        Text(
          subtitle,
          style: type.bodyMedium?.copyWith(
            color: colors.onSurfaceMuted,
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                        color: colors.onSurfaceMuted,
                        fontWeight: FontWeight.w600,
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
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool row = constraints.maxWidth >= 640;
              final List<Widget> tiles = <Widget>[
                _MoneyTile(
                  label: l10n.openDashboardRevenue,
                  value: formatMoney(revenue),
                  tone: StatusTone.success,
                  icon: Icons.trending_up_outlined,
                ),
                _MoneyTile(
                  label: l10n.openDashboardNetProfit,
                  value: formatMoney(netProfit),
                  tone: StatusTone.success,
                  icon: Icons.attach_money_outlined,
                ),
                _MoneyTile(
                  label: l10n.openDashboardCashPosition,
                  value: formatMoney(cashPosition),
                  tone: StatusTone.neutral,
                  icon: Icons.account_balance_wallet_outlined,
                ),
                _MoneyTile(
                  label: l10n.openDashboardReceivables,
                  value: formatMoney(receivables),
                  tone: receivables.minorUnits > 0
                      ? StatusTone.warning
                      : StatusTone.success,
                  icon: Icons.schedule_outlined,
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
                children: tiles.map((t) => SizedBox(width: 150, child: t)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MoneyTile extends StatelessWidget {
  const _MoneyTile({
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
            color: tone.container(colors),
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
          ),
        ),
        SizedBox(height: spacing.xs),
        Text(
          label,
          style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted),
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
                children: tiles.map((t) => SizedBox(width: 150, child: t)).toList(),
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
          Row(
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
              const Spacer(),
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
    required this.canManageJobs,
    required this.canReceivePayments,
    required this.canRecordSales,
  });

  final VoidCallback onNewJob;
  final VoidCallback onRecordPayment;
  final VoidCallback onRecordSale;
  final VoidCallback onAddJobCost;
  final VoidCallback onNewCostGroup;
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
    required this.onOpenJob,
  });

  final String title;
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              title,
              style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            TextButton(
              onPressed: onOpenJob,
              child: Text(l10n.openDashboardViewAll),
            ),
          ],
        ),
        SizedBox(height: spacing.sm),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          itemBuilder: (_, i) {
            return Padding(
              padding: EdgeInsets.only(bottom: spacing.sm),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Job completion — "Office wiring"',
                          style: type.bodyMedium,
                        ),
                        SizedBox(height: spacing.xs),
                        Text(
                          'KSh 12,500 received · 2h ago',
                          style: type.labelSmall?.copyWith(
                            color: colors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
