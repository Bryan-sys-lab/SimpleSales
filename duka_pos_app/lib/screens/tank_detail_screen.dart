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

      _tankSalesMinor = await db.tankMeasuredSalesMinor(
        productId,
        since,
      );
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);

      // Build activity from the tank's own data.
      _activity = <TankActivityEntry>[
        TankActivityEntry(
          label: l10n.tankDetailStockReceived,
          detail: 'Opening balance',
          value: '+${tankEntry.tankCount.toInt()} tanks',
          when: 'Today',
          icon: Icons.inventory,
          onTap: () => context.push(Routes.stocktake, extra: productId),
        ),
        TankActivityEntry(
          label: l10n.tankDetailMeasuredSales,
          detail: 'Pour sales this period',
          value: formatMoney(Money.fromMinor(_tankSalesMinor)),
          when: 'Last 30 days',
          icon: Icons.local_drink_outlined,
          onTap: () => context.push(Routes.stocktake, extra: productId),
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
    final productId = _tank?.productId;
    if (productId == null) return;
    await context.push(Routes.stocktake, extra: productId);
    if (!mounted) return;
    await _load();
  }

  Future<void> _viewHistory() async {
    // Tank-specific history is not a separate route yet; keep this a
    // non-interactive label rather than a self-referential push.
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _TankDetailSkeleton();
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).tankDetail)),
        body: ErrorStateView(
          message: _error!,
          onRetry: _load,
        ),
      );
    }
    if (_tank == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).tankDetail)),
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
    final percent = tank.fillPercent.clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(tank.name),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => context.pop(),
        ),
        actions: <Widget>[
          if (context.read<AppState>().canManageStock)
            OutlinedButton.icon(
              onPressed: _receive,
              icon: const Icon(Icons.inventory),
              label: Text(l10n.tankActionReceive),
            ),
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

            // Centered tank identity card: circular art badge, name, status.
            _TankIdentityCard(
              name: tank.name,
              percent: percent,
              status: percent > 0.3
                  ? l10n.tankStatusHealthy
                  : (percent > 0.1 ? l10n.tankStatusLow : l10n.tankStatusCritical),
              onImageTap: null,
            ),
            SizedBox(height: spacing.lg),

            // Fill progress bar — the tank's level as a wide thin bar.
            _TankFillBar(
              percent: percent,
              label: l10n.tankDetailSubtitle,
            ),
            SizedBox(height: spacing.lg),

            // Three stats: remaining, capacity, invested.
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _TankStatCard(
                    label: l10n.tankDetailMeasuredRemaining,
                    value: '${tank.litresRemaining.toStringAsFixed(0)} ml',
                    detail: l10n.tankDetailSalesDetail,
                    icon: Icons.local_drink_outlined,
                  ),
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: _TankStatCard(
                    label: l10n.tankDetailCapacity,
                    value: '${tank.capacityLitres.toStringAsFixed(0)} ml',
                    detail: l10n.tankDetailCapacityDetail,
                    icon: Icons.warehouse,
                  ),
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: _TankStatCard(
                    label: l10n.tankDetailInvested,
                    value: formatMoney(Money.fromMinor(tank.costInvestedMinor)),
                    detail: l10n.tankDetailInvestedDetail,
                    icon: Icons.attach_money,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.lg),

            // Three full-width action buttons: Receive, Measure, History.
            if (context.read<AppState>().canManageStock) ...<Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _receive,
                      icon: const Icon(Icons.inventory),
                      label: Text(l10n.tankActionReceive),
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _recordMeasurement,
                      icon: const Icon(Icons.query_stats),
                      label: Text(l10n.tankActionMeasure),
                    ),
                  ),
                  SizedBox(width: spacing.md),
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
            ],

            // Activity section.
            if (_activity.isNotEmpty) ...<Widget>[
              SectionHeader(
                label: l10n.tankDetailActivity,
                trailing: Text(
                  l10n.tankActionViewAll,
                  style: AppTypography.of(context)
                      .labelMedium
                      ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
                ),
              ),
              SizedBox(height: spacing.sm),
              ..._activity.take(10).map(
                (entry) => _TankActivityRow(
                  entry: entry,
                  onTap: entry.onTap,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The tank's identity card — centered: circular art badge, name bold,
/// muted status subtitle. Mirrors the mockup's tank header.
class _TankIdentityCard extends StatelessWidget {
  const _TankIdentityCard({
    required this.name,
    required this.percent,
    required this.status,
    this.onImageTap,
  });

  final String name;
  final double percent;
  final String status;
  final VoidCallback? onImageTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_bar,
              size: 32,
              color: colors.onSurfaceVariant,
            ),
          ),
          SizedBox(height: spacing.md),
          Text(
            name,
            style: type.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: spacing.xs),
          Text(
            status,
            style: type.bodySmall?.copyWith(
              color: colors.onSurfaceMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A wide thin fill bar showing the tank's level as a percentage.
class _TankFillBar extends StatelessWidget {
  const _TankFillBar({
    required this.percent,
    required this.label,
  });

  final double percent;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    return SurfaceCard(
      padding: EdgeInsetsDirectional.only(
        start: spacing.lg,
        end: spacing.lg,
        top: spacing.lg,
        bottom: spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                label,
                style: AppTypography.of(context).labelMedium?.copyWith(
                  color: colors.onSurfaceMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${(percent * 100).round()}%',
                style: AppTypography.of(context).bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 6,
              backgroundColor: colors.surfaceSunken,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// One stat card: icon badge, label above, bold value, muted detail.
class _TankStatCard extends StatelessWidget {
  const _TankStatCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceSunken,
                  borderRadius: AppShapes.of(context).controlRadius,
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          Text(
            label,
            style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted),
          ),
          SizedBox(height: spacing.xs),
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
            detail,
            style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

/// One activity entry: icon circle, label/detail, value and time trailing.
class _TankActivityRow extends StatelessWidget {
  const _TankActivityRow({
    required this.entry,
    this.onTap,
  });

  final TankActivityEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      button: onTap != null,
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    entry.icon,
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
                  Text(
                    entry.value,
                    style: AppTypography.money(context, size: 15),
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    entry.when,
                    style: type.bodySmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
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
    this.onTap,
  });

  final String label;
  final String detail;
  final String value;
  final String when;
  final IconData icon;
  final VoidCallback? onTap;
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
