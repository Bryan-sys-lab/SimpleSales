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
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../ui/components/states.dart';
import '../ui/layout/page.dart';
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
    double totalRemaining = 0;
    int needingAttention = 0;

    for (final tank in tanks) {
      totalRemaining += tank.litresRemaining;
      if (tank.fillPercent < 0.3) needingAttention++;
    }

    setState(() {
      _tanks = tanks;
      _totalTankCount = tanks.length.toDouble();
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
      double totalRemaining = 0;
      int needingAttention = 0;

      for (final tank in tanks) {
        totalRemaining += tank.litresRemaining;
        if (tank.fillPercent < 0.3) needingAttention++;
      }

      if (!mounted) return;
      setState(() {
        _tanks = tanks;
        _totalTankCount = tanks.length.toDouble();
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

    final lowStock = _tanks.where((t) => t.fillPercent < 0.3).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tankRegisterTitle),
        actions: <Widget>[
          if (context.read<AppState>().canManageStock)
            TextButton.icon(
              onPressed: _addTank,
              icon: const Icon(Icons.add),
              label: Text(l10n.tankAddAction),
            ),
        ],
      ),
      body: AdaptivePage(
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
            SizedBox(height: spacing.sm),

            // Search + chips row.
            _TankRegisterSearch(
              query: '',
              chips: const <String>['All', 'Tanks', 'Packaged', 'Low stock'],
              selected: 'All',
            ),
            SizedBox(height: spacing.lg),

            // Operations section.
            SectionHeader(
              label: l10n.tankRegisterSection,
              trailing: TextButton(
                onPressed: () => context.push(Routes.tankRegister),
                child: const Text('History'),
              ),
            ),
            SizedBox(height: spacing.sm),
            _TankRegisterOperationRow(
              icon: Icons.local_bar,
              title: 'Tank inventory',
              detail:
                  '${_totalTankCount.toInt()} tanks · ${_totalRemainingLitres.toStringAsFixed(0)} L remaining',
              onTap: () {},
            ),
            _TankRegisterOperationRow(
              icon: Icons.inventory_2_outlined,
              title: 'Packaged beverages',
                  detail: '${_tanks.length} products · $_tanksNeedingAttention low stock',
              onTap: () {},
            ),
            _TankRegisterOperationRow(
              icon: Icons.local_drink_outlined,
              title: 'Measured servings',
              detail: '12 active pour definitions',
              onTap: () => context.push(Routes.shotCups),
            ),
            SizedBox(height: spacing.lg),

            // Low stock section.
            if (lowStock.isNotEmpty) ...<Widget>[
              SectionHeader(
                label: 'Low stock',
              ),
              SizedBox(height: spacing.sm),
              ...lowStock.take(6).map(
                (tank) => _TankRegisterLowStockRow(
                  name: tank.name,
                  remaining: '${tank.litresRemaining.toStringAsFixed(0)} L remaining',
                  percent: tank.fillPercent,
                  onTap: () => _openTank(tank),
                ),
              ),
              SizedBox(height: spacing.lg),
            ],

            // Receive stock button.
            if (context.read<AppState>().canManageStock)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _addTank,
                  icon: const Icon(Icons.add),
                  label: const Text('Receive stock'),
                ),
              ),
          ],
        ),
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

/// Search field + filter chips for the tank register.
class _TankRegisterSearch extends StatelessWidget {
  const _TankRegisterSearch({
    required this.query,
    required this.chips,
    required this.selected,
  });

  final String query;
  final List<String> chips;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.xl,
            end: spacing.md,
            bottom: spacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                  child: Text(
                  'Search inventory',
                  style: AppTypography.of(context).bodyMedium?.copyWith(
                    color: AppColors.of(context).onSurfaceMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.md),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsetsDirectional.only(
            start: spacing.xl,
            end: spacing.md,
          ),
          child: Row(
            children: <Widget>[
              for (final chip in chips)
                Padding(
                  padding: EdgeInsets.only(right: spacing.sm),
                  child: FilterChip(
                    label: Text(chip),
                    selected: chip == selected,
                    onSelected: (_) {},
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One operation row: icon badge, title/detail, trailing chevron.
class _TankRegisterOperationRow extends StatelessWidget {
  const _TankRegisterOperationRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      button: true,
      label: '$title, $detail',
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
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(title, style: type.bodyMedium),
                    SizedBox(height: 2),
                    Text(detail, style: type.bodySmall),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colors.onSurfaceMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One low stock row: name, remaining, low pill.
class _TankRegisterLowStockRow extends StatelessWidget {
  const _TankRegisterLowStockRow({
    required this.name,
    required this.remaining,
    required this.percent,
    required this.onTap,
  });

  final String name;
  final String remaining;
  final double percent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      button: true,
      label: '$name, $remaining, low stock',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: spacing.md,
            vertical: spacing.xs,
          ),
          child: Row(
            children: <Widget>[
              ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.local_drink_outlined,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(name, style: type.bodyMedium),
                    SizedBox(height: 2),
                    Text(remaining, style: type.bodySmall),
                  ],
                ),
              ),
              StatusChip(
                tone: StatusTone.warning,
                text: 'Low',
                dense: true,
              ),
            ],
          ),
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
