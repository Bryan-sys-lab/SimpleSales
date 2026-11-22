import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';

const double _openCostGroupsMaxWidth = 1200;

/// Cost groups list for the Open profile.
///
/// Each row: group name, total invested, allocated/consumed, remaining
/// unallocated, and allocated sales. Tap opens cost group detail.
class OpenCostGroupsScreen extends StatefulWidget {
  const OpenCostGroupsScreen({super.key, this.loadPools});

  final Future<List<Map<String, dynamic>>> Function()? loadPools;

  @override
  State<OpenCostGroupsScreen> createState() => _OpenCostGroupsScreenState();
}

class _OpenCostGroupsScreenState extends State<OpenCostGroupsScreen> {
  List<Map<String, dynamic>> _pools = const [];
  bool _loading = true;
  bool _loadError = false;

  DatabaseHelper get _db => DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final pools = await (widget.loadPools?.call() ?? _db.getCostPools());
      if (!mounted) return;
      setState(() {
        _pools = pools;
        _loading = false;
      });
    } catch (error, stack) {
      debugPrint('Could not load cost groups: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final pools = _pools;
    final int investedMinor = pools.fold<int>(
      0,
      (int total, Map<String, dynamic> pool) =>
          total + ((pool['invested_minor'] as num?)?.toInt() ?? 0),
    );
    final int recoveredMinor = pools.fold<int>(
      0,
      (int total, Map<String, dynamic> pool) =>
          total + ((pool['recovered_minor'] as num?)?.toInt() ?? 0),
    );
    final Money totalInvested = Money.fromMinor(investedMinor);
    final Money totalRecovered = Money.fromMinor(recoveredMinor);
    final Money totalRemaining = Money.fromMinor(
      investedMinor > recoveredMinor ? investedMinor - recoveredMinor : 0,
    );
    final double totalProgress = investedMinor <= 0
        ? 1
        : (recoveredMinor / investedMinor).clamp(0, 1).toDouble();

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
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return Row(
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
                    SizedBox(width: spacing.sm),
                    if (constraints.maxWidth < 420)
                      IconButton.filled(
                        tooltip: l10n.openCostGroupsNewGroup,
                        onPressed: () => context.push(Routes.openCostGroupNew),
                        icon: const Icon(Icons.add),
                      )
                    else
                      FilledButton.icon(
                        onPressed: () => context.push(Routes.openCostGroupNew),
                        icon: const Icon(Icons.add),
                        label: Text(l10n.openCostGroupsNewGroup),
                      ),
                  ],
                );
              },
            ),
            SizedBox(height: spacing.lg),
            if (_loading)
              _OpenCostGroupsLoading()
            else if (_loadError)
              PersistentBanner(
                message: l10n.openCostGroupsLoadFailed,
                icon: Icons.error_outline,
                actionLabel: l10n.openCostGroupsRetry,
                onAction: _load,
                tone: StatusTone.danger,
              )
            else if (pools.isEmpty)
              _OpenCostGroupsEmpty(
                onNewGroup: () => context.push(Routes.openCostGroupNew),
              )
            else ...<Widget>[
              _CostGroupOverview(
                invested: totalInvested,
                recovered: totalRecovered,
                remaining: totalRemaining,
                progress: totalProgress,
              ),
              SizedBox(height: spacing.lg),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pools.length,
                separatorBuilder: (_, i) => SizedBox(height: spacing.sm),
                itemBuilder: (_, i) {
                  final Map<String, dynamic> pool = pools[i];
                  final Money invested = Money.fromMinor(
                    (pool['invested_minor'] as num?)?.toInt() ?? 0,
                  );
                  final Money recovered = Money.fromMinor(
                    (pool['recovered_minor'] as num?)?.toInt() ?? 0,
                  );
                  final Money remaining = Money.fromMinor(
                    invested.minorUnits > recovered.minorUnits
                        ? invested.minorUnits - recovered.minorUnits
                        : 0,
                  );
                  final double progress = invested.minorUnits <= 0
                      ? 1
                      : (recovered.minorUnits / invested.minorUnits)
                          .clamp(0, 1)
                          .toDouble();

                  return SurfaceCard(
                    padding: EdgeInsets.all(spacing.md),
                    semanticLabel:
                        '${pool['name']} · Invested ${formatMoney(invested)} · Recovered ${formatMoney(recovered)} · Remaining ${formatMoney(remaining)}',
                    onTap: () => context.push(
                      Routes.openCostGroupDetail((pool['id'] as num).toInt()),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                pool['name'] as String,
                                style: AppTypography.of(context)
                                    .titleSmall
                                    ?.copyWith(
                                      color: colors.onSurface,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: colors.onSurfaceMuted,
                            ),
                          ],
                        ),
                        SizedBox(height: spacing.md),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _CostGroupAmount(
                                label: l10n.openCostGroupsInvested,
                                amount: formatMoney(invested),
                              ),
                            ),
                            SizedBox(width: spacing.sm),
                            Expanded(
                              child: _CostGroupAmount(
                                label: l10n.openCostGroupsRecovered,
                                amount: formatMoney(recovered),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: spacing.md),
                        ClipRRect(
                          borderRadius: AppShapes.of(context).barRadius,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            backgroundColor: colors.surfaceSunken,
                            color: colors.accent,
                          ),
                        ),
                        SizedBox(height: spacing.sm),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                l10n.openCostGroupsRemaining,
                                style: AppTypography.of(context)
                                    .labelMedium
                                    ?.copyWith(color: colors.onSurfaceMuted),
                              ),
                            ),
                            Text(
                              formatMoney(remaining),
                              style: AppTypography.of(context)
                                  .labelLarge
                                  ?.copyWith(
                                    color: remaining.minorUnits > 0
                                        ? colors.onSurface
                                        : colors.success,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CostGroupOverview extends StatelessWidget {
  const _CostGroupOverview({
    required this.invested,
    required this.recovered,
    required this.remaining,
    required this.progress,
  });

  final Money invested;
  final Money recovered;
  final Money remaining;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      accentEdge: true,
      clipContent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _CostGroupAmount(
                  label: l10n.openCostGroupsInvested,
                  amount: formatMoney(invested),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: _CostGroupAmount(
                  label: l10n.openCostGroupsRecovered,
                  amount: formatMoney(recovered),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          ClipRRect(
            borderRadius: shapes.barRadius,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: colors.surfaceSunken,
              color: colors.accent,
            ),
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.openCostGroupsRemaining,
                  style: AppTypography.of(context)
                      .labelMedium
                      ?.copyWith(color: colors.onSurfaceMuted),
                ),
              ),
              Text(
                formatMoney(remaining),
                style: AppTypography.of(context).labelLarge?.copyWith(
                      color: remaining.minorUnits > 0
                          ? colors.onSurface
                          : colors.success,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpenCostGroupsLoading extends StatelessWidget {
  const _OpenCostGroupsLoading();

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.xl),
      child: Column(
        children: <Widget>[
          const CircularProgressIndicator(),
          SizedBox(height: spacing.md),
          Text(l10n.openCostGroupsLoading, style: type.titleSmall),
          SizedBox(height: spacing.xs),
          Text(
            l10n.openCostGroupsLoadingSubtitle,
            textAlign: TextAlign.center,
            style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

class _CostGroupAmount extends StatelessWidget {
  const _CostGroupAmount({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted)),
        Text(
          amount,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.titleSmall?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _OpenCostGroupsEmpty extends StatelessWidget {
  const _OpenCostGroupsEmpty({required this.onNewGroup});

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
              Text(l10n.openCostGroupsNoGroups, style: type.bodyMedium),
              SizedBox(height: spacing.xs),
              Text(
                l10n.openCostGroupsNoGroupsSubtitle,
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
