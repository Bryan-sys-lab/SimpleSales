import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/audit_log.dart';
import '../models/models.dart';
import '../models/stock_movement.dart';
import '../db/database_helper.dart';
import '../services/app_state.dart';
import '../services/audit_actor.dart';
import '../services/roles.dart';
import '../screens/receive_stock_sheet.dart';
import '../routing/routes.dart';
import '../routing/not_found_screen.dart';
import '../profile/profile_navigation.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/components/product_photo.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import 'inventory_screen.dart' show ProductEditor;
import 'tank_form_sheet.dart';

/// Product detail: everything an owner or cashier needs to know about one
/// product, on a single scrollable page.
///
/// Redesigned to match the SimpleSales duka profile mockup: centered product
/// art badge, name + category subtitle, stock/selling/buying/stock-value
/// stats grid, stock activity list, and receive/adjust action buttons.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({this.product, this.productId, super.key});

  final Product? product;
  final int? productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Product? _product;
  List<StockMovement> _stockActivity = const <StockMovement>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    if (_product?.id != null || widget.productId != null) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    final int? productId = widget.productId ?? _product?.id;
    if (productId == null) return;
    try {
      final p = await DatabaseHelper.instance.getProductById(productId);
      final movements = p == null
          ? const <StockMovement>[]
          : await DatabaseHelper.instance
              .getStockMovements(productId, limit: 4);
      if (!mounted) return;
      setState(() {
        _product = p;
        _stockActivity = movements;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final product = _product;
    if (product == null) {
      return NotFoundScreen(
        location: Routes.productDetail(widget.productId ?? 0),
      );
    }
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);
    final appState = context.watch<AppState>();
    final Widget productPhoto = Semantics(
      image: true,
      label: product.name,
      child: ProductPhoto(
        imagePath: product.imagePath,
        size: 128,
        revision: product.updatedAt,
      ),
    );

    final bool canAdjust = appState.isOwnerSession ||
        appState.hasPermission(PermissionKey.adjustStock);
    final bool canReceive = appState.isOwnerSession ||
        appState.hasPermission(PermissionKey.receiveStock);
    // Product editing belongs to the inventory capability, not supplier
    // administration. A manager with stock access must see the same editor
    // from detail that they can already open from Inventory; tying this to
    // manageSuppliers made the detail page silently lose its Edit action when
    // those permissions were customized independently.
    final bool canEdit = appState.canManageStock;

    final Money stockValue = Money.fromMinor(
      (product.stockQty * product.costPrice.minorUnits).round(),
    );

    final bool isOut = product.isOutOfStock;
    final bool isLow = !isOut && product.isLow;

    final StatusTone tone = isOut
        ? StatusTone.danger
        : isLow
            ? StatusTone.warning
            : StatusTone.success;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inventoryProductDetail),
        actions: <Widget>[
          if (canEdit)
            TextButton.icon(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.edit_outlined),
              label: Text(AppLocalizations.of(context).edit),
            ),
        ],
      ),
      body: AdaptivePage(
        scrollable: true,
        maxContentWidth: 900,
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

            // Centered product identity: large circular art badge, name bold,
            // muted category subtitle. Mirrors the mockup's product header.
            SurfaceCard(
              padding: EdgeInsets.all(spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  product.id == null
                      ? productPhoto
                      : Hero(
                          tag: 'product-photo-${product.id}',
                          child: productPhoto,
                        ),
                  SizedBox(height: spacing.md),
                  Text(
                    product.name,
                    style: type.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    product.category.isNotEmpty
                        ? product.category
                        : 'All products',
                    style: type.bodySmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: spacing.sm),
                  StatusChip(
                    tone: tone,
                    text: isOut
                        ? l10n.inventoryOutOfStock
                        : isLow
                            ? l10n.inventoryLowStock
                            : l10n.inventoryInStock,
                    dense: true,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.lg),

            // Four stats in a 2x2 grid: available stock, selling price, buying
            // cost, stock value.
            SurfaceCard(
              padding: EdgeInsets.all(spacing.lg),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool row = constraints.maxWidth >= 640;
                  final List<Widget> tiles = <Widget>[
                    _DukaStatCard(
                      label: 'Available stock',
                      value: _stockCountLabel(product.stockQty),
                      unit: product.unit.suffix,
                      icon: Icons.warehouse_outlined,
                    ),
                    _DukaStatCard(
                      label: l10n.inventorySellingPrice,
                      value: formatMoney(product.sellPrice),
                      icon: Icons.sell_outlined,
                    ),
                    _DukaStatCard(
                      label: l10n.inventoryCostPrice,
                      value: formatMoney(product.costPrice),
                      icon: Icons.shopping_cart_outlined,
                    ),
                    _DukaStatCard(
                      label: l10n.inventoryStockValue,
                      value: formatMoney(stockValue),
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ];
                  if (row) {
                    return IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              for (int i = 0; i < 2; i++) ...<Widget>[
                                if (i > 0) SizedBox(width: spacing.lg),
                                Expanded(child: tiles[i]),
                              ],
                            ],
                          ),
                          SizedBox(height: spacing.lg),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              for (int i = 2; i < 4; i++) ...<Widget>[
                                if (i > 2) SizedBox(width: spacing.lg),
                                Expanded(child: tiles[i]),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int i = 0; i < tiles.length; i++) ...<Widget>[
                        if (i > 0) SizedBox(height: spacing.lg),
                        tiles[i],
                      ],
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: spacing.lg),

            // Stock activity section.
            SurfaceCard(
              padding: EdgeInsetsDirectional.only(
                start: spacing.lg,
                end: spacing.lg,
                top: spacing.lg,
                bottom: spacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Stock activity',
                    style: type.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  if (_stockActivity.isEmpty)
                    Text(
                      l10n.inventoryNoMovement,
                      style: type.bodySmall?.copyWith(
                        color: colors.onSurfaceMuted,
                      ),
                    )
                  else
                    for (final movement in _stockActivity)
                      _DukaActivityRow(
                        icon: _movementIcon(movement.type),
                        label: _movementLabel(movement.type, l10n),
                        detail: _movementDetail(movement),
                        value:
                            '${movement.qtyDelta >= 0 ? '+' : ''}${_stockCountLabel(movement.qtyDelta)} ${product.unit.suffix}',
                      ),
                ],
              ),
            ),
            SizedBox(height: spacing.lg),

            // Quick actions are pills, not full-width form rows: they are
            // adjacent choices around the product and wrap naturally on a
            // compact phone while keeping a clear primary receive action.
            Wrap(
              spacing: spacing.sm,
              runSpacing: spacing.sm,
              children: <Widget>[
                if (canReceive)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: EdgeInsets.symmetric(horizontal: spacing.md),
                    ),
                    onPressed: () => _receiveStock(context),
                    icon: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: Text(AppLocalizations.of(context).receiveStock),
                  ),
                if (canAdjust)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: EdgeInsets.symmetric(horizontal: spacing.md),
                    ),
                    onPressed: () => _adjustStock(context),
                    icon: const Icon(Icons.tune_outlined, size: 18),
                    label: Text(AppLocalizations.of(context).adjustStock),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: EdgeInsets.symmetric(horizontal: spacing.md),
                  ),
                  onPressed: () => _viewSales(context),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(AppLocalizations.of(context).viewSales),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    final product = _product;
    if (product == null) return;
    if (product.category == kTankCategory) {
      await showTankFormSheet(context, existing: product);
      if (mounted) await _load();
      return;
    }

    final appState = context.read<AppState>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductEditor(
        existing: product,
        allowVariants: appState.shopProfile.navigation.showVariants,
        shopProfile: appState.shopProfile,
        onSaved: _load,
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _receiveStock(BuildContext context) async {
    final state = context.read<AppState>();
    final db = DatabaseHelper.instance;
    final products = await db.getProducts();
    final suppliers = await db.getSuppliers();
    final costingMode = await db.getCostingMode();
    if (!context.mounted) return;
    final receiptId = await showReceiveStockSheet(
      context,
      products: products,
      suppliers: suppliers,
      lastCostFor: db.lastCostForProduct,
      staffName: state.currentStaffName ?? state.owner?.name ?? 'Owner',
      staffId: state.currentStaffId,
      costingMode: costingMode,
    );
    if (!context.mounted || receiptId == null) return;
    await _load();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(receiptId == 0 ? 'Receipt cancelled' : 'Stock received')),
    );
  }

  Future<void> _adjustStock(BuildContext context) async {
    final product = _product;
    if (product?.id == null) return;
    final state = context.read<AppState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        final delta = TextEditingController();
        final reason = TextEditingController();
        return AlertDialog(
          title: Text('Adjust ${product!.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: delta,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Change in stock',
                  helperText: 'Use a negative number to remove stock',
                ),
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
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
                'delta': delta.text.trim(),
                'reason': reason.text.trim(),
              }),
              child: const Text('Save adjustment'),
            ),
          ],
        );
      },
    );
    if (result == null || !context.mounted) return;
    final value = double.tryParse(result['delta'] ?? '');
    if (value == null || !value.isFinite || value == 0) return;
    try {
      await DatabaseHelper.instance.adjustStock(
        StockAdjustment(
          productId: product!.id!,
          productName: product.name,
          delta: value,
          reason: result['reason'] ?? '',
          staffName: state.currentStaffName ?? state.owner?.name ?? 'Owner',
          createdAt: DateTime.now().toIso8601String(),
        ),
        staffId: state.currentStaffId,
        movementType: StockMovementType.adjustment,
      );
      await recordActionAudit(
        state,
        action: AuditAction.stockAdjusted,
        entity: AuditEntity.product,
        entityId: 'id-${product.id}',
        detail: '${value > 0 ? '+' : ''}$value',
      );
      if (!context.mounted) return;
      await _load();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock adjustment saved')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not adjust stock: $error')),
      );
    }
  }

  void _viewSales(BuildContext context) {
    context.push(Routes.transactions);
  }

  String _stockCountLabel(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  IconData _movementIcon(StockMovementType type) => switch (type) {
        StockMovementType.receipt => Icons.local_shipping_outlined,
        StockMovementType.sale => Icons.sell_outlined,
        StockMovementType.saleReturn => Icons.assignment_return_outlined,
        StockMovementType.receiptVoid => Icons.remove_circle_outline,
        StockMovementType.opening => Icons.inventory_2_outlined,
        StockMovementType.writeoff => Icons.delete_outline,
        StockMovementType.count => Icons.fact_check_outlined,
        StockMovementType.repack => Icons.all_inbox_outlined,
        _ => Icons.tune_outlined,
      };

  String _movementLabel(
    StockMovementType type,
    AppLocalizations l10n,
  ) =>
      switch (type) {
        StockMovementType.receipt => l10n.dashboardQuickReceiveStock,
        StockMovementType.sale => l10n.activitySaleRecorded,
        StockMovementType.saleReturn => 'Sale return',
        StockMovementType.receiptVoid => 'Receipt voided',
        StockMovementType.opening => 'Opening stock',
        StockMovementType.writeoff => 'Stock written off',
        StockMovementType.count => 'Stock counted',
        StockMovementType.repack => 'Stock repacked',
        _ => l10n.inventoryStockMovement,
      };

  String _movementDetail(StockMovement movement) {
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(movement.createdAt.toLocal());
    final details = <String>[
      date,
      if (movement.staffName?.trim().isNotEmpty == true) movement.staffName!,
      if (movement.note?.trim().isNotEmpty == true) movement.note!,
    ];
    return details.join(' · ');
  }
}

/// One stat card: label above bold value, optional unit, icon badge.
class _DukaStatCard extends StatelessWidget {
  const _DukaStatCard({
    required this.label,
    required this.value,
    this.unit,
    required this.icon,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              padding: EdgeInsets.all(spacing.xs),
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
        SizedBox(height: spacing.lg),
        Text(
          label,
          style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted),
        ),
        SizedBox(height: spacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              value,
              style: AppTypography.money(
                context,
                size: 20,
                weight: FontWeight.w800,
              ),
            ),
            if (unit != null) ...<Widget>[
              SizedBox(width: spacing.xs),
              Text(
                unit!,
                style: type.labelSmall?.copyWith(
                  color: colors.onSurfaceMuted,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// One activity row: icon circle, label/detail, value trailing.
class _DukaActivityRow extends StatelessWidget {
  const _DukaActivityRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String detail;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        children: <Widget>[
          Container(
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
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: type.bodyMedium),
                SizedBox(height: 2),
                Text(
                  detail,
                  style: type.bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: spacing.sm),
          Text(
            value,
            style: AppTypography.money(context, size: 14),
          ),
        ],
      ),
    );
  }
}
