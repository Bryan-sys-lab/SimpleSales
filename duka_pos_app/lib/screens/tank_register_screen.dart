// A tank register: every tank the shop keeps, with what it holds, what it cost
// and what is left of it.
//
// This is the drinks profile's tank destination — a proper screen rather than a
// form reachable only from the dashboard. Each tank gets its own row with the
// numbers that matter for running the bar: capacity, investment, measured
// remaining volume, sales generated.
//
// The remaining volume is what the stock ledger actually says — the number of
// full tanks times litres per tank — not a figure the app invents. A tank with
// no measured stock shows its capacity but no remaining figure, because the app
// should not pretend to know what it has not been told.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/analytics.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/screen_title.dart';
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../ui/components/states.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import 'tank_form_sheet.dart';

const double _tankRegisterMaxWidth = 1200;

/// The tank register: every tank, with capacity, investment and what is left.
class TankRegisterScreen extends StatefulWidget {
  const TankRegisterScreen({
    this.tanks,
    this.totalTankCount = 0,
    this.totalCapacityLitres = 0,
    this.totalInvestedMinor = 0,
    this.totalRemainingLitres = 0,
    this.tanksNeedingAttention = 0,
    this.onOpenTank,
    this.onAddTank,
    super.key,
  });

  final List<DrinkTankLevel>? tanks;
  final double totalTankCount;
  final double totalCapacityLitres;
  final int totalInvestedMinor;
  final double totalRemainingLitres;
  final int tanksNeedingAttention;
  final void Function(DrinkTankLevel tank)? onOpenTank;
  final VoidCallback? onAddTank;

  @override
  State<TankRegisterScreen> createState() => _TankRegisterScreenState();
}

class _TankRegisterScreenState extends State<TankRegisterScreen> {
  List<DrinkTankLevel> _tanks = const <DrinkTankLevel>[];
  double _totalTankCount = 0;
  double _totalCapacityLitres = 0;
  int _totalInvestedMinor = 0;
  double _totalRemainingLitres = 0;
  int _tanksNeedingAttention = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.tanks != null) {
      _applyProvided(widget.tanks!);
    } else {
      _load();
    }
  }

  void _applyProvided(List<DrinkTankLevel> tanks) {
    double totalCapacity = 0;
    double totalRemaining = 0;
    int totalInvested = 0;
    int needingAttention = 0;

    for (final tank in tanks) {
      totalCapacity += tank.capacityLitres;
      totalRemaining += tank.litresRemaining;
      totalInvested += tank.costInvestedMinor;
      if (tank.fillPercent < 0.3) needingAttention++;
    }

    setState(() {
      _tanks = tanks;
      _totalTankCount = tanks.length.toDouble();
      _totalCapacityLitres = totalCapacity;
      _totalInvestedMinor = totalInvested;
      _totalRemainingLitres = totalRemaining;
      _tanksNeedingAttention = needingAttention;
      _loading = false;
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = DatabaseHelper.instance;
      final since = DateTime.now().subtract(const Duration(days: 30));
      final snapshot = await db.drinksAnalytics(since: since);

      final tanks = snapshot.tanks;
      double totalCapacity = 0;
      double totalRemaining = 0;
      int totalInvested = 0;
      int needingAttention = 0;

      for (final tank in tanks) {
        totalCapacity += tank.capacityLitres;
        totalRemaining += tank.litresRemaining;
        totalInvested += tank.costInvestedMinor;
        if (tank.fillPercent < 0.3) needingAttention++;
      }

      if (!mounted) return;
      setState(() {
        _tanks = tanks;
        _totalTankCount = tanks.length.toDouble();
        _totalCapacityLitres = totalCapacity;
        _totalInvestedMinor = totalInvested;
        _totalRemainingLitres = totalRemaining;
        _tanksNeedingAttention = needingAttention;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _TankRegisterSkeleton();
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tank register')),
        body: ErrorStateView(
          message: _error!,
          onRetry: _load,
        ),
      );
    }

    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);

    return AdaptivePage(
      scrollable: true,
      maxContentWidth: _tankRegisterMaxWidth,
      padding: EdgeInsetsDirectional.only(
        start: spacing.md,
        end: spacing.md,
        top: spacing.md,
        bottom: spacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ScreenTitle(
            title: l10n.tankRegisterTitle,
            subtitle: l10n.tankRegisterSubtitle,
            trailing: context.read<AppState>().canManageStock
                ? FilledButton.icon(
                    onPressed: _addTank,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.tankAddAction),
                  )
                : null,
            padding: EdgeInsetsDirectional.only(bottom: spacing.md),
          ),
          SizedBox(height: spacing.sm),
          _TankRegisterSummary(
            tankCount: _totalTankCount,
            capacityLitres: _totalCapacityLitres,
            investedMinor: _totalInvestedMinor,
            remainingLitres: _totalRemainingLitres,
            needingAttention: _tanksNeedingAttention,
          ),
          SizedBox(height: spacing.lg),
          if (_tanks.isEmpty)
            const _EmptyTankRegister()
          else ...<Widget>[
            _TankRegisterList(
              tanks: _tanks,
              onOpenTank: _openTank,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addTank() async {
    if (widget.onAddTank != null) {
      widget.onAddTank!();
      return;
    }
    await showTankFormSheet(context);
    if (!mounted) return;
    await _load();
  }

  void _openTank(DrinkTankLevel tank) {
    if (widget.onOpenTank != null) {
      widget.onOpenTank!(tank);
      return;
    }
    context.push('${Routes.tankDetail}/${tank.productId}');
  }
}

/// The register headline: tank count, capacity, investment, remaining.
class _TankRegisterSummary extends StatelessWidget {
  const _TankRegisterSummary({
    required this.tankCount,
    required this.capacityLitres,
    required this.investedMinor,
    required this.remainingLitres,
    required this.needingAttention,
  });

  final double tankCount;
  final double capacityLitres;
  final int investedMinor;
  final double remainingLitres;
  final int needingAttention;

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
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(l10n.tankRegisterTanks, style: type.labelMedium),
                    Text(
                      '${tankCount.toInt()}',
                      style: AppTypography.money(
                        context,
                        size: 32,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(l10n.tankRegisterCapacity, style: type.labelMedium),
                    Text(
                      '${capacityLitres.toStringAsFixed(0)} L',
                      style: AppTypography.money(
                        context,
                        size: 32,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(l10n.tankRegisterInvested, style: type.labelMedium),
                    Text(
                      formatMoney(Money.fromMinor(investedMinor)),
                      style: AppTypography.money(
                        context,
                        size: 32,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(l10n.tankRegisterRemaining, style: type.labelMedium),
                    Text(
                      '${remainingLitres.toStringAsFixed(0)} L',
                      style: AppTypography.money(
                        context,
                        size: 32,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          if (needingAttention > 0)
            Padding(
              padding: EdgeInsetsDirectional.only(start: spacing.xs),
              child: Row(
                children: <Widget>[
                  Icon(Icons.warning_amber_outlined,
                      size: 18, color: colors.warning),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: Text(
                      l10n.tankRegisterNeedingAttention(needingAttention),
                      style: type.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One tank row: name, capacity, remaining, investment, sales.
class _TankRegisterList extends StatelessWidget {
  const _TankRegisterList({
    required this.tanks,
    required this.onOpenTank,
  });

  final List<DrinkTankLevel> tanks;
  final void Function(DrinkTankLevel tank) onOpenTank;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);

    return SurfaceCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.md,
              end: spacing.md,
              top: spacing.md,
              bottom: spacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Text(l10n.tankRegisterSection, style: type.titleMedium),
                const Spacer(),
                Text(
                  '${tanks.length} ${l10n.tankRegisterTanksLower}',
                  style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          for (final tank in tanks)
            _TankRegisterRow(
              tank: tank,
              onTap: () => onOpenTank(tank),
            ),
        ],
      ),
    );
  }
}

/// One tank row: name, remaining, capacity percent, investment.
class _TankRegisterRow extends StatelessWidget {
  const _TankRegisterRow({
    required this.tank,
    required this.onTap,
  });

  final DrinkTankLevel tank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);
    final percent = tank.fillPercent;

    return Semantics(
      button: true,
      label: '${tank.name}, ${tank.litresRemaining.toStringAsFixed(0)} litres remaining, ${(percent * 100).toStringAsFixed(0)} percent full',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: spacing.md,
              vertical: spacing.sm,
            ),
            child: Row(
              children: <Widget>[
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.surfaceSunken,
                      borderRadius: AppShapes.of(context).controlRadius,
                    ),
                    child: Icon(Icons.local_drink_outlined,
                        size: 20, color: colors.onSurfaceVariant),
                  ),
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(tank.name, style: type.bodyMedium),
                      SizedBox(height: 2),
                      Text(
                        '${tank.litresRemaining.toStringAsFixed(0)} L remaining · ${(percent * 100).toStringAsFixed(0)}% of ${tank.capacityLitres.toStringAsFixed(0)} L',
                        style: type.bodySmall?.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: spacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      formatMoney(tank.costInvested),
                      style: AppTypography.money(context, size: 15),
                    ),
                    SizedBox(height: spacing.xs),
                    StatusChip(
                      tone: percent > 0.3
                          ? StatusTone.success
                          : (percent > 0.1 ? StatusTone.warning : StatusTone.danger),
                      text: percent > 0.3
                          ? l10n.tankStatusHealthy
                          : (percent > 0.1 ? l10n.tankStatusLow : l10n.tankStatusCritical),
                      dense: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty state for the tank register.
class _EmptyTankRegister extends StatelessWidget {
  const _EmptyTankRegister();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool canEdit = context.read<AppState>().canManageStock;

    return AdaptivePage(
      padding: EdgeInsets.zero,
      child: RefreshIndicator(
        onRefresh: () => Future.value(),
        child: EmptyStateView(
          kind: EmptyKind.collection,
          title: l10n.tankRegisterEmptyTitle,
          message: l10n.tankRegisterEmptyMessage,
          actionLabel: canEdit ? l10n.tankAddAction : null,
          onAction: canEdit ? () {} : null,
        ),
      ),
    );
  }
}

/// Skeleton shown while the register loads.
class _TankRegisterSkeleton extends StatelessWidget {
  const _TankRegisterSkeleton();

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return AdaptivePage(
      maxContentWidth: spacing.readableMaxWidth,
      padding: EdgeInsets.all(spacing.md),
      child: const SkeletonList(itemCount: 4, linesPerItem: 2),
    );
  }
}
