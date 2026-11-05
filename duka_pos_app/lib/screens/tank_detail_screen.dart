// One tank's detail: its numbers, its history, and the three actions an owner
// takes against it — receive, measure, view history.
//
// An adjustment must require a reason and leave an auditable movement record.
// The tank's remaining volume comes from the stock ledger, not from a figure
// the app invents: capacity and original stock do not equal measured remainder.

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
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../ui/components/states.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import 'tank_form_sheet.dart';

const double _tankDetailMaxWidth = 1200;

/// An individual tank's detail page.
///
/// Loads its own tank data from the database using the tank id from the route.
class TankDetailScreen extends StatefulWidget {
  const TankDetailScreen({super.key});

  @override
  State<TankDetailScreen> createState() => _TankDetailScreenState();
}

class _TankDetailScreenState extends State<TankDetailScreen> {
  DrinkTankLevel? _tank;
  int _tankSalesMinor = 0;
  String? _lastMeasured;
  List<TankActivityEntry> _activity = const <TankActivityEntry>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final GoRouterState state = GoRouterState.of(context);
      final tankId = state.pathParameters['tankId'];
      if (tankId == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'No tank specified';
        });
        return;
      }

      final productId = int.tryParse(tankId);
      if (productId == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Invalid tank id';
        });
        return;
      }

      final db = DatabaseHelper.instance;
      final product = await db.getProductById(productId);
      if (!mounted) return;
      if (product == null) {
        setState(() {
          _loading = false;
          _error = 'Tank not found';
        });
        return;
      }

      // Build a DrinkTankLevel from the product's stock data.
      final capacityMl = product.bottleMl.toDouble();
      final stockQty = product.stockQty.toDouble();
      final litresRemaining = stockQty * capacityMl / 1000;
      final capacityLitres = capacityMl / 1000 * stockQty;
      final costInvestedMinor =
          (stockQty * product.costPrice.minorUnits).round();

      _tank = DrinkTankLevel(
        productId: productId,
        name: product.name,
        litresRemaining: litresRemaining,
        tankCount: stockQty,
        capacityLitres: capacityLitres,
        costInvestedMinor: costInvestedMinor,
      );

      // Get sales for this tank from the analytics snapshot.
      final since = DateTime.now().subtract(const Duration(days: 30));
      final snapshot = await db.drinksAnalytics(since: since);
      final tankEntry = snapshot.tanks.firstWhere(
        (t) => t.productId == productId,
        orElse: () => DrinkTankLevel(
          productId: productId,
          name: product.name,
          litresRemaining: 0,
          tankCount: 0,
        ),
      );
      _tank = tankEntry;

      _tankSalesMinor = 0;
      _lastMeasured = null;

      // Build activity from the tank's own data.
      _activity = <TankActivityEntry>[
        TankActivityEntry(
          label: 'Stock received',
          detail: 'Opening balance',
          value: '+${tankEntry.tankCount.toInt()} tanks',
          when: 'Today',
          icon: Icons.inventory,
          onTap: () {},
        ),
        TankActivityEntry(
          label: 'Measured sales',
          detail: 'Pour sales this period',
          value: formatMoney(Money.fromMinor(_tankSalesMinor)),
          when: 'Last 30 days',
          icon: Icons.local_drink_outlined,
          onTap: () {},
        ),
      ];

      if (!mounted) return;
      setState(() {
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

  Future<void> _receive() async {
    await showTankFormSheet(context, existing: null);
    if (!mounted) return;
    await _load();
  }

  Future<void> _recordMeasurement() async {
    await context.push('/inventory/stocktake');
    if (!mounted) return;
    await _load();
  }

  Future<void> _viewHistory() async {
    await context.push(Routes.tankRegister);
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _TankDetailSkeleton();
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tank detail')),
        body: ErrorStateView(
          message: _error!,
          onRetry: _load,
        ),
      );
    }
    if (_tank == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tank detail')),
        body: const EmptyStateView(
          kind: EmptyKind.collection,
          title: 'No tank data',
          message: 'Unable to load tank details.',
        ),
      );
    }

    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    final tank = _tank!;
    final percent = tank.fillPercent;

    return Scaffold(
      appBar: AppBar(
        title: Text(tank.name),
        actions: <Widget>[
          if (context.read<AppState>().canManageStock) ...<Widget>[
            OutlinedButton.icon(
              onPressed: _recordMeasurement,
              icon: const Icon(Icons.query_stats),
              label: Text(l10n.tankActionMeasure),
            ),
            SizedBox(width: spacing.sm),
            FilledButton.icon(
              onPressed: _receive,
              icon: const Icon(Icons.inventory),
              label: Text(l10n.tankActionReceive),
            ),
          ],
        ],
      ),
      body: AdaptivePage(
        scrollable: true,
        maxContentWidth: _tankDetailMaxWidth,
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
            _TankDetailHeader(
              name: tank.name,
              percent: percent,
              litresRemaining: tank.litresRemaining,
              capacityLitres: tank.capacityLitres,
              costInvestedMinor: tank.costInvestedMinor,
              salesMinor: _tankSalesMinor,
              lastMeasured: _lastMeasured,
            ),
            SizedBox(height: spacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _receive,
                    icon: const Icon(Icons.inventory),
                    label: Text(l10n.tankActionReceive),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _recordMeasurement,
                    icon: const Icon(Icons.query_stats),
                    label: Text(l10n.tankActionMeasure),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _viewHistory,
                    icon: const Icon(Icons.history),
                    label: Text(l10n.tankActionHistory),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.lg),
            if (_activity.isNotEmpty) ...<Widget>[
              SectionHeader(
                label: l10n.tankDetailActivity,
                trailing: TextButton(
                  onPressed: _viewHistory,
                  child: Text(l10n.tankActionViewAll),
                ),
              ),
              SizedBox(height: spacing.sm),
              ..._activity.take(10).map(
                (entry) => _TankActivityRow(
                  entry: entry,
                  onTap: entry.onTap,
                ),
              ),
              if (_activity.length > 10)
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: spacing.md,
                    end: spacing.md,
                    top: spacing.md,
                  ),
                  child: TextButton(
                    onPressed: _viewHistory,
                    child: Text(l10n.tankActionViewAll),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The tank's headline numbers: status chip, measured remaining, capacity.
class _TankDetailHeader extends StatelessWidget {
  const _TankDetailHeader({
    required this.name,
    required this.percent,
    required this.litresRemaining,
    required this.capacityLitres,
    required this.costInvestedMinor,
    required this.salesMinor,
    required this.lastMeasured,
  });

  final String name;
  final double percent;
  final double litresRemaining;
  final double capacityLitres;
  final int costInvestedMinor;
  final int salesMinor;
  final String? lastMeasured;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      style: type.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    StatusChip(
                      tone: percent > 0.3
                          ? StatusTone.success
                          : (percent > 0.1 ? StatusTone.warning : StatusTone.danger),
                      text: l10n.tankStatusActive,
                      dense: true,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${litresRemaining.toStringAsFixed(0)} L',
                    style: AppTypography.money(
                      context,
                      size: 40,
                      weight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    l10n.tankDetailMeasuredRemaining,
                    style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _TankDetailMetric(
                  label: l10n.tankDetailCapacity,
                  value: '${capacityLitres.toStringAsFixed(0)} L',
                  detail: l10n.tankDetailCapacityDetail,
                ),
              ),
              Expanded(
                child: _TankDetailMetric(
                  label: l10n.tankDetailInvested,
                  value: formatMoney(Money.fromMinor(costInvestedMinor)),
                  detail: l10n.tankDetailInvestedDetail,
                ),
              ),
              Expanded(
                child: _TankDetailMetric(
                  label: l10n.tankDetailSales,
                  value: formatMoney(Money.fromMinor(salesMinor)),
                  detail: l10n.tankDetailSalesDetail,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          if (lastMeasured != null)
            Padding(
              padding: EdgeInsetsDirectional.only(start: spacing.xs),
              child: Row(
                children: <Widget>[
                  Icon(Icons.access_time,
                      size: 16, color: colors.onSurfaceMuted),
                  SizedBox(width: spacing.xs),
                  Text(
                    l10n.tankDetailLastMeasured(lastMeasured!),
                    style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One metric: label, value, detail.
class _TankDetailMetric extends StatelessWidget {
  const _TankDetailMetric({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label,
            style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted)),
        SizedBox(height: spacing.xs),
        Text(value,
            style: AppTypography.money(
              context,
              size: 20,
              weight: FontWeight.w700,
            )),
        SizedBox(height: spacing.xs),
        Text(detail,
            style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted)),
      ],
    );
  }
}

/// One activity entry: when, what, how much, who.
class _TankActivityRow extends StatelessWidget {
  const _TankActivityRow({
    required this.entry,
    required this.onTap,
  });

  final TankActivityEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Semantics(
      button: true,
      label: '${entry.label}, ${entry.value}, ${entry.when}',
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: AppShapes.of(context).controlRadius,
                  ),
                  child: Icon(
                    entry.icon,
                    size: 16,
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
                    Text(entry.label, style: type.bodyMedium),
                    SizedBox(height: 2),
                    Text(entry.detail, style: type.bodySmall),
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(entry.value,
                      style: AppTypography.money(context, size: 15)),
                  SizedBox(height: spacing.xs),
                  Text(entry.when,
                      style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tank activity entry.
class TankActivityEntry {
  const TankActivityEntry({
    required this.label,
    required this.detail,
    required this.value,
    required this.when,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String detail;
  final String value;
  final String when;
  final IconData icon;
  final VoidCallback onTap;
}

class _TankDetailSkeleton extends StatelessWidget {
  const _TankDetailSkeleton();

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
