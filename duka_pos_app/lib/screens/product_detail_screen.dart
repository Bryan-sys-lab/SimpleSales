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
import '../ui/components/states.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import 'inventory_screen.dart' show ProductEditor;
import 'tank_form_sheet.dart';

/// Product detail: identity, stock and pricing metrics, inventory metadata,
/// recent movement, and role-aware stock actions on one scrollable page.
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
  bool _loadError = false;

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
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final p = await DatabaseHelper.instance.getProductById(productId);
      if (!mounted) return;
      setState(() => _product = p);
      final movements = p == null
          ? const <StockMovement>[]
          : await DatabaseHelper.instance
              .getStockMovements(productId, limit: 4);
      if (!mounted) return;
      setState(() {
        _product = p;
        _stockActivity = movements;
        _loading = false;
        _loadError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.inventoryProductDetail)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final product = _product;
    if (product == null) {
      if (_loadError) {
        return Scaffold(
          appBar: AppBar(title: Text(l10n.inventoryProductDetail)),
          body: Center(
            child: ErrorStateView(
              message: l10n.inventoryProductLoadFailed,
              retryLabel: l10n.retry,
              onRetry: () {
                _load();
              },
              icon: Icons.inventory_2_outlined,
            ),
          ),
        );
      }
      return NotFoundScreen(
        location: Routes.productDetail(widget.productId ?? 0),
      );
    }
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final appState = context.watch<AppState>();
    final Widget productPhoto = Semantics(
      image: true,
      label: product.name,
      child: ProductPhoto(
        imagePath: product.imagePath,
        size: 80,
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

    final bool tracksStock = product.trackStock &&
        product.itemKind != 'service' &&
        product.itemKind != 'fee';
    final bool isOut = product.isOutOfStock;
    final bool isLow = !isOut && product.isLow;

    final StatusTone tone = !tracksStock
        ? StatusTone.neutral
        : isOut
            ? StatusTone.danger
            : isLow
                ? StatusTone.warning
                : StatusTone.success;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inventoryProductDetail),
        actions: <Widget>[
          if (canEdit)
            IconButton(
              tooltip: l10n.edit,
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.edit_outlined),
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
            SurfaceCard(
              accentEdge: true,
              child: Row(
                children: <Widget>[
                  product.id == null
                      ? productPhoto
                      : Hero(
                          tag: 'product-photo-${product.id}',
                          child: productPhoto,
                        ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          product.name,
                          style: type.headlineSmall,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: spacing.xs),
                        Text(
                          product.category.isNotEmpty
                              ? product.category
                              : l10n.inventoryDefaultCategory,
                          style: type.bodySmall?.copyWith(
                            color: colors.onSurfaceMuted,
                          ),
                        ),
                        SizedBox(height: spacing.sm),
                        StatusChip(
                          tone: tone,
                          text: !tracksStock
                              ? l10n.inventoryStockNotTracked
                              : isOut
                                  ? l10n.inventoryOutOfStock
                                  : isLow
                                      ? l10n.inventoryLowStock
                                      : l10n.inventoryInStock,
                          dense: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.lg),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final int columns = constraints.maxWidth >= 740 ? 4 : 2;
                final double gap = spacing.sm;
                final double tileWidth =
                    (constraints.maxWidth - (gap * (columns - 1))) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: <Widget>[
                    SizedBox(
                      width: tileWidth,
                      child: _DukaStatCard(
                        label: l10n.inventoryAvailableStock,
                        value: tracksStock
                            ? _stockCountLabel(product.availableStockQty)
                            : l10n.inventoryStockNotTracked,
                        unit: tracksStock ? product.unit.suffix : null,
                        icon: Icons.warehouse_outlined,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _DukaStatCard(
                        label: l10n.inventorySellingPrice,
                        value: formatMoney(product.sellPrice),
                        icon: Icons.sell_outlined,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _DukaStatCard(
                        label: l10n.inventoryCostPrice,
                        value: formatMoney(product.costPrice),
                        icon: Icons.shopping_cart_outlined,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _DukaStatCard(
                        label: l10n.inventoryStockValue,
                        value: formatMoney(stockValue),
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: spacing.lg),
            SectionHeader(label: l10n.inventoryProductInformation),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  KeyValueRow(
                    label: l10n.inventoryFieldCategory,
                    value: product.category.isNotEmpty
                        ? product.category
                        : l10n.inventoryDefaultCategory,
                  ),
                  if (product.merchantSku?.trim().isNotEmpty == true)
                    KeyValueRow(
                      label: l10n.productMerchantSku,
                      value: product.merchantSku!,
                    ),
                  if (product.brandLabelLocal?.trim().isNotEmpty == true)
                    KeyValueRow(
                      label: l10n.productBrandLabel,
                      value: product.brandLabelLocal!,
                    ),
                  if (tracksStock) ...<Widget>[
                    KeyValueRow(
                      label: l10n.inventoryReorderLevel,
                      value: '${product.reorderLevel} ${product.unit.suffix}',
                    ),
                    if (product.reservedQty > 0)
                      KeyValueRow(
                        label: l10n.inventoryReservedStock,
                        value:
                            '${_stockCountLabel(product.reservedQty)} ${product.unit.suffix}',
                      ),
                  ],
                  KeyValueRow(
                    label: l10n.productUnitPickerLabel,
                    value: product.unit.suffix,
                    showDivider: !product.trackExpiry,
                  ),
                  if (product.trackExpiry)
                    KeyValueRow(
                      label: l10n.trackExpiryDates,
                      value: l10n.inventoryTracked,
                      showDivider: false,
                    ),
                ],
              ),
            ),
            SizedBox(height: spacing.lg),
            SectionHeader(label: l10n.inventoryStockMovement),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_loadError)
                    ErrorStateView(
                      message: l10n.inventoryProductLoadFailed,
                      retryLabel: l10n.retry,
                      onRetry: () {
                        _load();
                      },
                      icon: Icons.inventory_2_outlined,
                    )
                  else if (_stockActivity.isEmpty)
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
            SectionHeader(label: l10n.inventoryActionsTooltip),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (canReceive)
                    FilledButton.icon(
                      onPressed: () => _receiveStock(context),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: Text(l10n.receiveStock),
                    ),
                  if (canAdjust) ...<Widget>[
                    if (canReceive) SizedBox(height: spacing.sm),
                    OutlinedButton.icon(
                      onPressed: () => _adjustStock(context),
                      icon: const Icon(Icons.tune_outlined),
                      label: Text(l10n.adjustStock),
                    ),
                  ],
                  if (canReceive || canAdjust) SizedBox(height: spacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => _viewSales(context),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(l10n.viewSales),
                  ),
                ],
              ),
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

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
          SizedBox(height: spacing.sm),
          Text(
            label,
            style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted),
          ),
          SizedBox(height: spacing.xs),
          Text(
            value,
            style: AppTypography.money(
              context,
              size: 18,
              weight: FontWeight.w800,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (unit != null) ...<Widget>[
            SizedBox(height: spacing.xs),
            Text(
              unit!,
              style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
            ),
          ],
        ],
      ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: EdgeInsets.all(spacing.xs),
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: colors.onSurfaceVariant),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(label, style: type.bodyMedium),
                SizedBox(height: spacing.xs),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: type.bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
                SizedBox(height: spacing.xs),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    value,
                    style: AppTypography.money(context, size: 14),
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
