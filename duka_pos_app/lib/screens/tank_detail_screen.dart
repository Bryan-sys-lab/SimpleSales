// One tank's detail: its numbers, its history, and the three actions an owner
// takes against it — receive, measure, view history.
//
// An adjustment must require a reason and leave an auditable movement record.
// The tank's remaining volume comes from the stock ledger, not from a figure
// the app invents: capacity and original stock do not equal measured remainder.

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/analytics.dart';
import 'tank_form_sheet.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/components/product_photo.dart';
import '../ui/components/states.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../models/stock_movement.dart';

const double _tankDetailMaxWidth = 1200;

/// Tank detail figures are stored as litres even though the product's stock
/// ledger stores millilitres. Keep that conversion visible in the label so a
/// 50-litre drum is never presented as "50 ml".
String formatTankLitres(double litres) {
  if (!litres.isFinite) return '0 L';
  final value = litres < 0 ? 0 : litres;
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text L';
}

/// An individual tank's detail page.
///
/// Loads its own tank data from the database using the tank id from the route.
class TankDetailScreen extends StatefulWidget {
  const TankDetailScreen({this.productId, super.key});

  /// The product id from the route. Keeping it in the widget makes the detail
  /// screen reconstructable from a cold deep link and from a restored route.
  final int? productId;

  @override
  State<TankDetailScreen> createState() => _TankDetailScreenState();
}

class _TankDetailScreenState extends State<TankDetailScreen> {
  DrinkTankLevel? _tank;
  String? _tankImagePath;
  String? _tankImageRevision;
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
      final productId = widget.productId;
      if (productId == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'No tank specified';
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
      _tankImagePath = product.imagePath;
      _tankImageRevision = product.updatedAt;

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
    final productId = _tank?.productId;
    if (productId == null) return;
    final state = context.read<AppState>();
    final product = await DatabaseHelper.instance.getProductById(productId);
    if (!mounted || product == null) return;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        final quantity = TextEditingController();
        final unitCost = TextEditingController(
          text: product.costPrice.asMajor.toStringAsFixed(2),
        );
        return AlertDialog(
          title: Text('Receive ${product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: quantity,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantity (${product.unit.suffix})',
                ),
              ),
              TextField(
                controller: unitCost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Unit cost (KES)',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(dialogContext).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, <String, String>{
                'quantity': quantity.text.trim(),
                'unitCost': unitCost.text.trim(),
              }),
              child: const Text('Receive stock'),
            ),
          ],
        );
      },
    );
    if (!mounted || result == null) return;
    final quantity = double.tryParse(result['quantity'] ?? '');
    final cost = parseMoneyInput(result['unitCost']);
    if (quantity == null ||
        !quantity.isFinite ||
        quantity <= 0 ||
        cost == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity and unit cost')),
      );
      return;
    }
    try {
      await DatabaseHelper.instance.postStockReceipt(
        lines: <StockReceiptLine>[
          StockReceiptLine(
            productId: product.id!,
            productName: product.name,
            qty: quantity,
            unitCost: Money.fromMajor(cost),
          ),
        ],
        note: 'Tank stock received',
        staffName: state.currentStaffName ?? state.owner?.name ?? 'Owner',
        staffId: state.currentStaffId,
        costingMode: await DatabaseHelper.instance.getCostingMode(),
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tank stock received')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not receive tank stock: $error')),
      );
    }
  }

  Future<void> _recordMeasurement() async {
    final productId = _tank?.productId;
    if (productId == null) return;
    await context.push(Routes.stocktake, extra: productId);
    if (!mounted) return;
    await _load();
  }

  Future<void> _editTank() async {
    final productId = _tank?.productId;
    if (productId == null || !mounted) return;
    final product = await DatabaseHelper.instance.getProductById(productId);
    if (!mounted || product == null) return;
    await showTankFormSheet(context, existing: product);
    if (mounted) await _load();
  }

  Future<void> _viewHistory() async {
    final productId = _tank?.productId;
    if (productId == null || !mounted) return;
    try {
      final movements =
          await DatabaseHelper.instance.getStockMovements(productId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.75,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Tank stock history',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: movements.isEmpty
                      ? const Center(child: Text('No stock movements recorded'))
                      : ListView.builder(
                          itemCount: movements.length,
                          itemBuilder: (context, index) {
                            final StockMovement movement = movements[index];
                            final sign = movement.qtyDelta >= 0 ? '+' : '';
                            return ListTile(
                              leading: Icon(movement.isPositive
                                  ? Icons.add_circle_outline
                                  : Icons.remove_circle_outline),
                              title: Text(movement.type.wire),
                              subtitle: Text(
                                '${movement.createdAt.toLocal()}${movement.note == null ? '' : ' · ${movement.note}'}',
                              ),
                              trailing: Text(
                                '$sign${movement.qtyDelta.toStringAsFixed(2)}\n'
                                'balance ${movement.balanceAfter.toStringAsFixed(2)}',
                                textAlign: TextAlign.end,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load tank history: $error')),
      );
    }
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
            IconButton(
              tooltip: 'Edit tank',
              onPressed: _editTank,
              icon: const Icon(Icons.edit_outlined),
            ),
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
              imagePath: _tankImagePath,
              imageRevision: _tankImageRevision,
              productId: tank.productId,
              percent: percent,
              status: percent > 0.3
                  ? l10n.tankStatusHealthy
                  : (percent > 0.1
                      ? l10n.tankStatusLow
                      : l10n.tankStatusCritical),
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
                    value: formatTankLitres(tank.litresRemaining),
                    detail: l10n.tankDetailSalesDetail,
                    icon: Icons.local_drink_outlined,
                  ),
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: _TankStatCard(
                    label: l10n.tankDetailCapacity,
                    value: formatTankLitres(tank.capacityLitres),
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
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final actions = <Widget>[
                    OutlinedButton.icon(
                      onPressed: _receive,
                      icon: const Icon(Icons.inventory),
                      label: Text(l10n.tankActionReceive),
                    ),
                    FilledButton.icon(
                      onPressed: _recordMeasurement,
                      icon: const Icon(Icons.query_stats),
                      label: Text(l10n.tankActionMeasure),
                    ),
                    OutlinedButton.icon(
                      onPressed: _viewHistory,
                      icon: const Icon(Icons.history),
                      label: Text(l10n.tankActionHistory),
                    ),
                  ];
                  if (constraints.maxWidth < 620) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final action in actions) ...<Widget>[
                          action,
                          if (action != actions.last)
                            SizedBox(height: spacing.sm),
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int index = 0;
                          index < actions.length;
                          index++) ...<Widget>[
                        Expanded(child: actions[index]),
                        if (index < actions.length - 1)
                          SizedBox(width: spacing.md),
                      ],
                    ],
                  );
                },
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
    required this.imagePath,
    required this.imageRevision,
    required this.productId,
    required this.percent,
    required this.status,
  });

  final String name;
  final String? imagePath;
  final String? imageRevision;
  final int productId;
  final double percent;
  final String status;

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
          Hero(
            tag: 'product-photo-$productId',
            child: Semantics(
              image: true,
              label: name,
              child: ProductPhoto(
                imagePath: imagePath,
                size: 128,
                revision: imageRevision,
              ),
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
