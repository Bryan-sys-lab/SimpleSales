import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../ui/dialogs/manager_approval_sheet.dart';
import 'receive_stock_sheet.dart';
import '../profile/shop_profile.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../theme/app_spacing.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import '../ui/components/operation_result.dart';
import '../ui/layout/page.dart';
import 'dashboard_sections.dart';
import 'dashboard_shared.dart';
import '../profile/profile_product_forms.dart';
import 'loose_goods_form_sheet.dart';
import 'quick_sale_dialog.dart';

const double _openDashboardMaxWidth = 1200;

class OpenDashboardScreen extends StatelessWidget {
  const OpenDashboardScreen({
    required this.data,
    required this.onRefresh,
    required this.onBackupNow,
    required this.onOpenShift,
    required this.onOpenSell,
    required this.onOpenInventory,
    required this.onOpenEtimsSettings,
    required this.onOpenProduct,
    required this.onRetryEtims,
    required this.onRetryRejectedEtims,
    required this.dismissed,
    required this.onDismiss,
    super.key,
  });

  final DashboardReady data;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onBackupNow;
  final Future<void> Function() onOpenShift;
  final VoidCallback onOpenSell;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenEtimsSettings;
  final ValueChanged<Product> onOpenProduct;
  final Future<void> Function() onRetryEtims;
  final Future<void> Function() onRetryRejectedEtims;
  final Set<String> dismissed;
  final ValueChanged<String>? onDismiss;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppState appState = context.watch<AppState>();
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool canManageStock = appState.canManageStock;
    final bool canManageCredit =
        appState.isOwnerSession || appState.role == ShopRole.manager;
    final bool canViewCost = appState.isOwnerSession ||
        appState.hasPermission(PermissionKey.viewCost);

    final Widget header = DashboardBusinessHeader(
      shopName: appState.owner?.shopName ?? SimplePosBrand.appName,
      profile: ShopProfile.open,
      staffName: appState.currentStaffName ?? appState.owner?.name,
      shift: data.openShift,
      showPortfolioLink: appState.isOwnerSession,
      onOpenPortfolio: () => context.push(Routes.portfolio),
    );

    final Widget financialHero = DashboardMoneyHero(
      profile: ShopProfile.open,
      label: l10n.dashboardNetSalesToday,
      amount: data.totals.total,
      primaryActionLabel: l10n.dashboardNewSale,
      onPrimaryAction: onOpenSell,
      secondaryLine: l10n.dashboardPeriodToday,
      scopeLabel: data.scopeLabel,
      paymentMix: data.paymentMix,
      onTransactions: () => context.push(Routes.transactions),
    );

    final List<DashboardKpiData> kpis = <DashboardKpiData>[
      DashboardKpiData(
        label: 'Gross profit (costed)',
        value: formatMoney(Money.fromMinor(data.totals.profitMinor)),
        icon: Icons.trending_up_outlined,
        tone: DashboardKpiTone.positive,
      ),
      DashboardKpiData(
        label: l10n.dashboardExpenses,
        value: formatMoney(Money.fromMinor(data.totals.expensesMinor)),
        icon: Icons.payments_outlined,
        tone: DashboardKpiTone.expense,
      ),
      DashboardKpiData(
        label: 'Average sale',
        value: formatMoney(data.totals.averageBasket),
        icon: Icons.shopping_basket_outlined,
        tone: DashboardKpiTone.neutral,
      ),
      if (data.openShift != null)
        DashboardKpiData(
          label: 'Expected till',
          value: formatMoney(data.expectedTill),
          icon: Icons.point_of_sale_outlined,
          tone: DashboardKpiTone.info,
        ),
      DashboardKpiData(
        label: l10n.dashboardStockValue,
        value: formatMoney(data.stockValue),
        icon: Icons.inventory_2_outlined,
        tone: DashboardKpiTone.info,
        onTap: onOpenInventory,
      ),
      if (canManageCredit)
        DashboardKpiData(
          label: 'Customer tabs',
          value: formatMoney(Money.fromMinor(data.creditOwedMinor)),
          icon: Icons.credit_card_outlined,
          tone: DashboardKpiTone.pending,
          onTap: () => context.push(Routes.customers),
        )
      else
        DashboardKpiData(
          label: l10n.dashboardTransactionsLabel,
          value: '${data.totals.transactions}',
          icon: Icons.receipt_long_outlined,
          tone: DashboardKpiTone.neutral,
          onTap: () => context.push(Routes.transactions),
        ),
    ];

    final Widget kpiGrid = DashboardKpiGrid(items: kpis);

    final Widget shift = DashboardShiftCard(
      shift: data.openShift,
      expected: data.expectedTill,
      onOpen: onOpenShift,
    );

    final Widget stockOverview = _OpenStockOverview(
      totalProducts: data.totalProducts,
      lowStockCount: data.lowStockCount,
      outOfStockCount: data.outOfStockCount,
      stockValue: data.stockValue,
      onOpenInventory: onOpenInventory,
    );

    final Widget quickActions = _OpenQuickActions(
      onOpenSell: onOpenSell,
      onOpenQuickSale: () => showQuickSaleDialog(
        context: context,
        profile: ShopProfile.open,
      ),
      onOpenAddProduct: () => _openAddProduct(context),
      onOpenLooseGoods: () => _openLooseGoods(context),
      onOpenReceiveStock: () => _receiveStock(context),
      onOpenStocktake: () => _openStocktake(context),
      onOpenCostOfGoods: () => context.push(Routes.openCostGroups),
      onOpenServings: () => context.push(Routes.servings),
      canManageStock: canManageStock,
      canReceiveStock: appState.hasPermission(PermissionKey.receiveStock),
      canStocktake: appState.hasPermission(PermissionKey.stocktake),
    );

    final Widget? credit = canManageCredit
        ? DashboardCreditCard(
            owedMinor: data.creditOwedMinor,
            customerCount: data.creditCustomerCount,
            onOpen: () => context.push(Routes.customers),
          )
        : null;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _openDashboardMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            SizedBox(height: spacing.lg),
            financialHero,
            SizedBox(height: spacing.lg),
            quickActions,
            SizedBox(height: spacing.lg),
            kpiGrid,
            SizedBox(height: spacing.lg),
            shift,
            SizedBox(height: spacing.lg),
            stockOverview,
            if (canViewCost && data.openCostPoolCount > 0) ...<Widget>[
              SizedBox(height: spacing.lg),
              _OpenCostSummary(
                  data: data,
                  onOpen: () => context.push(Routes.openCostGroups)),
            ],
            if (data.paymentMix.isNotEmpty) ...<Widget>[
              SizedBox(height: spacing.lg),
              _OpenPaymentMix(data: data),
            ],
            if (data.topProducts.isNotEmpty) ...<Widget>[
              SizedBox(height: spacing.lg),
              _OpenTopProducts(data: data),
            ],
            if (credit != null) ...<Widget>[
              SizedBox(height: spacing.lg),
              credit,
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openAddProduct(BuildContext context) async {
    final result = await ProfileProductForms.showForm(
      context: context,
      profile: ShopProfile.open,
    );
    if (!context.mounted || result == null) return;
    final trackStock = (result['track_stock'] as bool?) ?? true;
    final product = Product(
      name: result['name'] as String,
      category: (result['category'] as String? ?? 'Item or service'),
      costPrice: Money.fromMajor((result['cost'] as num?)?.toDouble() ?? 0),
      sellPrice: Money.fromMajor((result['price'] as num?)?.toDouble() ?? 0),
      stockQty: trackStock ? (result['stock'] as num?)?.toDouble() ?? 0 : 0,
      trackStock: trackStock,
      costPoolId: (result['cost_pool_id'] as num?)?.toInt(),
      reorderLevel: (result['reorder_level'] as num?)?.toInt() ?? 0,
      unit: ProductUnit.parse(result['unit'] as String?),
      updatedAt: DateTime.now().toIso8601String(),
    );
    await DatabaseHelper.instance.upsertProduct(product);
    if (!context.mounted) return;
    await onRefresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${product.name} saved')));
  }

  void _receiveStock(BuildContext context) async {
    final AppState state = context.read<AppState>();
    if (!state.isOwnerSession &&
        state.permissionMode(PermissionKey.receiveStock) ==
            PermissionMode.approval) {
      final approver = await showManagerApprovalSheet(
        context,
        purpose: 'Approve receiving new stock',
      );
      if (!context.mounted || approver == null) return;
    }
    final DatabaseHelper db = DatabaseHelper.instance;
    final List<Product> products = await db.getProducts();
    final List<Supplier> suppliers = await db.getSuppliers();
    final Map<String, dynamic>? draftJson =
        await db.getReceiveDraft(state.currentStaffId);
    final ReceiveDraftSnapshot? draft =
        draftJson == null ? null : ReceiveDraftSnapshot.fromJson(draftJson);
    final String costingMode = await db.getCostingMode();
    if (!context.mounted) return;
    final int? receiptId = await showReceiveStockSheet(
      context,
      products: products,
      suppliers: suppliers,
      lastCostFor: db.lastCostForProduct,
      staffName: state.currentStaffName ?? '',
      staffId: state.currentStaffId,
      costingMode: costingMode,
      draft: draft,
    );
    if (receiptId == null || !context.mounted) return;
    if (receiptId == 0) {
      showOperationSuccess(
        context,
        title: 'Draft discarded',
      );
    }
    await onRefresh();
  }

  Future<void> _openLooseGoods(BuildContext context) async {
    await showLooseGoodsFormSheet(context, profile: ShopProfile.open);
    if (context.mounted) await onRefresh();
  }

  void _openStocktake(BuildContext context) {
    context.push(Routes.stocktake);
  }
}

class _OpenCostSummary extends StatelessWidget {
  const _OpenCostSummary({required this.data, required this.onOpen});

  final DashboardReady data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final invested = Money.fromMinor(data.openCostInvestedMinor);
    final recovered = Money.fromMinor(data.openCostRecoveredMinor);
    return DashboardPanel(
      title: 'Cost of Goods',
      trailing: ActionChip(
        avatar: const Icon(Icons.arrow_outward, size: 16),
        label: const Text('Open'),
        onPressed: onOpen,
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: <Widget>[
          Text('${data.openCostPoolCount} open pools'),
          Text('Invested ${formatMoney(invested)}'),
          Text('Recovered ${formatMoney(recovered)}'),
          Text('Remaining ${formatMoney(invested - recovered)}'),
        ],
      ),
    );
  }
}

class _OpenPaymentMix extends StatelessWidget {
  const _OpenPaymentMix({required this.data});

  final DashboardReady data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DashboardPanel(
      title: 'Payment mix today',
      child: Column(
        children: <Widget>[
          for (final row in data.paymentMix)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(row.label(l10n: l10n)),
              trailing: Text(formatMoney(row.sales)),
              subtitle: Text('${row.transactions} transactions'),
            ),
        ],
      ),
    );
  }
}

class _OpenTopProducts extends StatelessWidget {
  const _OpenTopProducts({required this.data});

  final DashboardReady data;

  @override
  Widget build(BuildContext context) {
    return DashboardPanel(
      title: 'Top-selling items today',
      child: Column(
        children: <Widget>[
          for (final row in data.topProducts)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(row.productName),
              subtitle: Text('${row.units} units'),
              trailing: Text(formatMoney(row.revenue)),
            ),
        ],
      ),
    );
  }
}

class _OpenStockOverview extends StatelessWidget {
  const _OpenStockOverview({
    required this.totalProducts,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.stockValue,
    required this.onOpenInventory,
  });

  final int totalProducts;
  final int lowStockCount;
  final int outOfStockCount;
  final Money stockValue;
  final VoidCallback onOpenInventory;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('Inventory health'),
        subtitle: Text(
          '$totalProducts SKUs · Low: $lowStockCount · Out: $outOfStockCount · ${formatMoney(stockValue)}',
        ),
        trailing: null,
        onTap: null,
      ),
    );
  }
}

class _OpenQuickActions extends StatelessWidget {
  const _OpenQuickActions({
    required this.onOpenSell,
    required this.onOpenQuickSale,
    required this.onOpenAddProduct,
    required this.onOpenLooseGoods,
    required this.onOpenReceiveStock,
    required this.onOpenStocktake,
    required this.onOpenCostOfGoods,
    required this.onOpenServings,
    required this.canManageStock,
    required this.canReceiveStock,
    required this.canStocktake,
  });

  final VoidCallback onOpenSell;
  final VoidCallback onOpenQuickSale;
  final VoidCallback onOpenAddProduct;
  final VoidCallback onOpenLooseGoods;
  final VoidCallback onOpenReceiveStock;
  final VoidCallback onOpenStocktake;
  final VoidCallback onOpenCostOfGoods;
  final VoidCallback onOpenServings;
  final bool canManageStock;
  final bool canReceiveStock;
  final bool canStocktake;

  @override
  Widget build(BuildContext context) {
    final List<Widget> tiles = <Widget>[
      _OpenQuickTile(
        icon: Icons.point_of_sale_outlined,
        label: 'New Sale',
        subtitle: 'Open Till',
        onTap: onOpenSell,
      ),
      _OpenQuickTile(
        icon: Icons.flash_on_outlined,
        label: 'QuickSale',
        subtitle: 'Fast sale dialog',
        onTap: onOpenQuickSale,
      ),
      if (canManageStock)
        _OpenQuickTile(
          icon: Icons.add_circle_outline,
          label: 'Add Item',
          subtitle: 'New catalogue item',
          onTap: onOpenAddProduct,
        ),
      if (canReceiveStock)
        _OpenQuickTile(
          icon: Icons.local_shipping_outlined,
          label: 'Receive Stock',
          subtitle: 'Record delivery',
          onTap: onOpenReceiveStock,
        ),
      if (canStocktake)
        _OpenQuickTile(
          icon: Icons.fact_check_outlined,
          label: 'Stocktake',
          subtitle: 'Count inventory',
          onTap: onOpenStocktake,
        ),
      _OpenQuickTile(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Cost of Goods',
        subtitle: 'Pools and reload',
        onTap: onOpenCostOfGoods,
      ),
      if (canManageStock)
        _OpenQuickTile(
          icon: Icons.local_bar_outlined,
          label: 'Loose goods',
          subtitle: 'Tanks and servings',
          onTap: onOpenLooseGoods,
        ),
      if (canManageStock)
        _OpenQuickTile(
          icon: Icons.local_drink_outlined,
          label: 'Servings',
          subtitle: 'Measured goods',
          onTap: onOpenServings,
        ),
    ];

    return DashboardQuickActionStrip(actions: tiles);
  }
}

class _OpenQuickTile extends StatelessWidget {
  const _OpenQuickTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
