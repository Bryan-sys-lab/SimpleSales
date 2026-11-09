import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';

const double _openCostGroupsMaxWidth = 1200;

/// Cost groups list for the Open profile.
///
/// Each row: group name, total invested, allocated/consumed, remaining
/// unallocated, number of linked jobs. Tap opens cost group detail.
class OpenCostGroupsScreen extends StatefulWidget {
  const OpenCostGroupsScreen({super.key});

  @override
  State<OpenCostGroupsScreen> createState() => _OpenCostGroupsScreenState();
}

class _OpenCostGroupsScreenState extends State<OpenCostGroupsScreen> {
  List<Map<String, dynamic>> _pools = const [];
  bool _loading = true;

  DatabaseHelper get _db => DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pools = await _db.getCostPools();
      if (!mounted) return;
      setState(() {
        _pools = pools;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final pools = _pools;

    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _openCostGroupsMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () => performBackup(context)),
            SizedBox(height: spacing.section),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.openCostGroupsTitle,
                        style: AppTypography.of(context).headlineSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        l10n.openCostGroupsSubtitle,
                        style: AppTypography.of(context)
                            .bodyMedium
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => context.push(Routes.openCostGroupNew),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.openCostGroupsNewGroup),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            Expanded(
              child: _loading || pools.isEmpty
                  ? _OpenCostGroupsEmpty(
                      isEmpty: pools.isEmpty && !_loading,
                      onNewGroup: () => context.push(Routes.openCostGroupNew),
                    )
                  : ListView.separated(
                      itemCount: pools.length,
                      separatorBuilder: (_, i) => Divider(
                        height: 1,
                        indent: spacing.md,
                        color: colors.outline,
                      ),
                      itemBuilder: (_, i) {
                        final pool = pools[i];
                        final invested = Money.fromMinor(
                          (pool['invested_minor'] as num?)?.toInt() ?? 0,
                        );
                        final recovered = Money.fromMinor(
                          (pool['recovered_minor'] as num?)?.toInt() ?? 0,
                        );
                        final remaining = Money.fromMinor(
                          invested.minorUnits - recovered.minorUnits,
                        );

                        return Semantics(
                          label:
                              '${pool['name']} · Invested ${formatMoney(invested)} · Recovered ${formatMoney(recovered)} · Remaining ${formatMoney(remaining)}',
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: colors.surfaceSunken,
                                borderRadius: AppShapes.of(context)
                                    .controlRadius,
                              ),
                              child: Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 18,
                                color: colors.onSurfaceMuted,
                              ),
                            ),
                            title: Text(
                              pool['name'] as String,
                              style: AppTypography.of(context).bodyMedium,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  '${l10n.openCostGroupsInvested} ${formatMoney(invested)} · ${l10n.openCostGroupsRecovered} ${formatMoney(recovered)}',
                                  style: AppTypography.of(context)
                                      .labelSmall
                                      ?.copyWith(color: colors.onSurfaceMuted),
                                ),
                                SizedBox(height: spacing.xs),
                                Text(
                                  '${l10n.openCostGroupsRemaining} ${formatMoney(remaining)}',
                                  style: AppTypography.of(context)
                                      .labelSmall
                                      ?.copyWith(
                                        color: remaining.minorUnits > 0
                                            ? colors.warning
                                            : colors.onSurfaceMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                            trailing: StatusChip(
                              tone: remaining.minorUnits > 0
                                  ? StatusTone.warning
                                  : StatusTone.success,
                              text: remaining.minorUnits > 0
                                  ? l10n.openCostGroupsHasRemaining
                                  : l10n.openCostGroupsFullyAllocated,
                              dense: true,
                            ),
                            onTap: () => context.push(
                              '/analytics/open-business/cost-groups/${pool['id']}',
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenCostGroupsEmpty extends StatelessWidget {
  const _OpenCostGroupsEmpty({required this.isEmpty, required this.onNewGroup});

  final bool isEmpty;
  final VoidCallback onNewGroup;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(height: spacing.lg),
        Container(
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: AppShapes.of(context).controlRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                isEmpty ? l10n.openCostGroupsNoGroups : l10n.openCostGroupsLoading,
                style: type.bodyMedium,
              ),
              SizedBox(height: spacing.xs),
              Text(
                isEmpty
                    ? l10n.openCostGroupsNoGroupsSubtitle
                    : l10n.openCostGroupsLoadingSubtitle,
                style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        FilledButton.icon(
          onPressed: onNewGroup,
          icon: const Icon(Icons.add),
          label: Text(l10n.openCostGroupsNewGroup),
        ),
      ],
    );
  }
}
