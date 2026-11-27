import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../profile/profile_capabilities.dart';
import '../profile/profile_navigation.dart';
import '../profile/profile_terminology.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../profile/shop_profile.dart';
import '../services/analytics.dart';
import '../services/roles.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/operation_result.dart';
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../ui/dialogs/manager_approval_sheet.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';
import 'dashboard_attention.dart';
import 'dashboard_sections.dart';
import 'dashboard_shared.dart';
import 'receive_stock_sheet.dart';
import 'inventory_screen.dart';
import 'quick_sale_dialog.dart';

const double _dukaDashboardMaxWidth = 1200;
const double _dukaTwoColumnBreakpoint = 840;

/// The duka profile dashboard.
///
/// Stock first: availability, low stock, reorder. Money second — sales today
/// and the till. The cashier's most frequent task (selling) sits beside the
/// figures so the screen is read as one flow, not a stack of cards.
class DukaDashboardScreen extends StatelessWidget {
  const DukaDashboardScreen({
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
    final double gap = spacing.xl;

    final bool hasSales = data.totals.hasSales;
    final bool canManageCredit =
        appState.isOwnerSession || appState.role == ShopRole.manager;
    final bool canManageStock = appState.canManageStock;

    final Widget? attention = data.attention.isEmpty
        ? null
        : DashboardAttentionCard(
            summary: data.attention,
            canFixEtims: appState.isAdmin,
            onRetryEtims: onRetryEtims,
            onOpenEtimsSettings: onOpenEtimsSettings,
            onRetryRejectedEtims:
                appState.isAdmin ? onRetryRejectedEtims : null,
            dismissed: dismissed,
            onDismiss: onDismiss,
          );

    final Widget shift = DashboardShiftCard(
      shift: data.openShift,
      expected: data.expectedTill,
      onOpen: onOpenShift,
    );

    final Widget sales = hasSales
        ? DashboardHourlySales(buckets: data.hours)
        : DashboardNoSalesCard(hasEverSold: data.hasEverSold);

    final Color topAccent = AppColors.of(context).accent;
    final Widget? topProducts = hasSales
        ? DashboardTopProducts(
            rows: data.topProducts, topAccent: topAccent)
        : null;

    final Widget reorder = DashboardLowStockList(
      products: data.lowStock,
      totalCount: data.lowStockCount,
      canOpen: canManageStock,
      onOpenProduct: onOpenProduct,
      onViewAll: onOpenInventory,
      topAccent: topAccent,
    );

    final Widget? credit = canManageCredit
        ? DashboardCreditCard(
            owedMinor: data.creditOwedMinor,
            customerCount: data.creditCustomerCount,
            onOpen: () => context.push(Routes.customers),
          )
        : null;

    final AppLocalizations l10n = AppLocalizations.of(context);
    final Widget header = DashboardBusinessHeader(
      shopName: appState.owner?.shopName ?? SimplePosBrand.appName,
      profile: ShopProfile.duka,
      staffName: appState.currentStaffName ?? appState.owner?.name,
      shift: data.openShift,
      showPortfolioLink: appState.isOwnerSession,
      onOpenPortfolio: () => context.push(Routes.portfolio),
    );

    final Widget financialHero = DashboardMoneyHero(
      profile: ShopProfile.duka,
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
        label: l10n.dashboardGrossProfit,
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
          label: l10n.dashboardCreditOwed,
          value: formatMoney(Money.fromMinor(data.creditOwedMinor)),
          icon: Icons.credit_card_outlined,
          tone: DashboardKpiTone.pending,
          onTap: () => context.push(Routes.customers),
        ),
    ];

    final Widget kpiGrid = DashboardKpiGrid(items: kpis);

    final String addProductLabel =
        'Add ${appState.shopProfile.terminologyLocalized(AppLocalizations.of(context)).product}';

    final Widget quickActions = _DukaDashboardQuickActions(
      onOpenSell: onOpenSell,
      onOpenAddProduct: () => _openAddProduct(context),
      onOpenReceiveStock: () => _receiveStock(context),
      onOpenStocktake: () => _openStocktake(context),
      addProductLabel: addProductLabel,
      canManageStock:
          canManageStock && appState.shopProfile.capabilities.trackStock,
      canReceiveStock: appState.hasPermission(PermissionKey.receiveStock),
      canStocktake: appState.hasPermission(PermissionKey.stocktake),
    );

    final bool twoColumns =
        MediaQuery.sizeOf(context).width >= _dukaTwoColumnBreakpoint;

    final List<Widget> body = <Widget>[
      header,
      if (attention != null)
        Semantics(
          sortKey: const OrdinalSortKey(0),
          child: attention,
        ),
      SizedBox(height: gap),
    ];

    if (twoColumns) {
      body.addAll(<Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: spaced(
                  <Widget?>[
                    financialHero,
                    quickActions,
                    kpiGrid,
                    BackupReminderBanner(onBackupNow: onBackupNow),
                    sales,
                    topProducts,
                    if (data.tanks.isNotEmpty)
                      _LooseGoodsCards(
                        tanks: data.tanks,
                        tankSales: data.tankSales,
                        onOpenProduct: onOpenProduct,
                      ),
                  ],
                  gap,
                ),
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: spaced(
                  <Widget?>[
                    reorder,
                    shift,
                    credit,
                  ],
                  gap,
                ),
              ),
            ),
          ],
        ),
      ]);
    } else {
      body.addAll(spaced(
        <Widget?>[
          financialHero,
          quickActions,
          kpiGrid,
          BackupReminderBanner(onBackupNow: onBackupNow),
          sales,
          topProducts,
          if (data.tanks.isNotEmpty)
            _LooseGoodsCards(
              tanks: data.tanks,
              tankSales: data.tankSales,
              onOpenProduct: onOpenProduct,
            ),
          reorder,
          shift,
          credit,
        ],
        gap,
      ));
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _dukaDashboardMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      ),
    );
  }

  /// Opens the duka-tailored add-product form. This is the visible entry point
  /// for the profile-defined product creation capability, gated on the profile
  /// tracking stock. Uses the shared ProductEditor so dashboard and inventory
  /// create/edit through the same widget.
  Future<void> _openAddProduct(BuildContext context) async {
    final appState = context.read<AppState>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductEditor(
        existing: null,
        allowVariants: appState.shopProfile.navigation.showVariants,
        shopProfile: appState.shopProfile,
        onSaved: () {},
      ),
    );
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
  }

  void _openStocktake(BuildContext context) {
    context.push(Routes.stocktake);
  }
}

/// Stock availability, risk counts, and the value of the current inventory.
class _DukaStockOverview extends StatelessWidget {
  const _DukaStockOverview({
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
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    final int productCount = totalProducts < 0 ? 0 : totalProducts;
    final int lowCount = lowStockCount.clamp(0, productCount).toInt();
    final int outCount = outOfStockCount.clamp(0, productCount).toInt();
    final int availableProducts = productCount - outCount;
    final double availability =
        productCount == 0 ? 0 : availableProducts / productCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(label: l10n.dashboardStockOverview),
        SizedBox(height: spacing.sm),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int columns = constraints.maxWidth >= 560
                ? 3
                : constraints.maxWidth >= 280
                    ? 2
                    : 1;
            final double metricWidth =
                (constraints.maxWidth - spacing.sm * (columns - 1)) / columns;
            return Padding(
              padding: EdgeInsets.all(spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    l10n.dashboardStockValue,
                    style: AppTypography.of(context).labelMedium,
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    formatMoney(stockValue),
                    style: AppTypography.money(
                      context,
                      size: 26,
                      weight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          l10n.dashboardStockAvailability(
                            availableProducts,
                            productCount,
                          ),
                          style: AppTypography.of(context).titleSmall,
                        ),
                      ),
                      SizedBox(width: spacing.sm),
                      Text('${(availability * 100).round()}%'),
                    ],
                  ),
                  SizedBox(height: spacing.xs),
                  Semantics(
                    label: l10n.dashboardStockAvailability(
                      availableProducts,
                      productCount,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: availability,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  Wrap(
                    spacing: spacing.sm,
                    runSpacing: spacing.sm,
                    children: <Widget>[
                      SizedBox(
                        width: metricWidth,
                        child: _StockMetric(
                          label: l10n.dashboardTotalProducts,
                          value: '$productCount',
                          icon: Icons.inventory_2_outlined,
                        ),
                      ),
                      SizedBox(
                        width: metricWidth,
                        child: _StockMetric(
                          label: l10n.dashboardLowStockCount,
                          value: '$lowCount',
                          icon: Icons.warning_amber_outlined,
                          tone: StatusTone.warning,
                        ),
                      ),
                      SizedBox(
                        width: metricWidth,
                        child: _StockMetric(
                          label: l10n.dashboardOutOfStockCount,
                          value: '$outCount',
                          icon: Icons.cancel_outlined,
                          tone: StatusTone.danger,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.md),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: onOpenInventory,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(l10n.dashboardInventory),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _StockMetric extends StatelessWidget {
  const _StockMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    return Semantics(
      label: '$label: $value',
      child: Container(
        padding: EdgeInsets.all(spacing.sm),
        decoration: BoxDecoration(
          color: tone != null ? tone!.container(colors) : colors.surfaceSunken,
          borderRadius: AppShapes.of(context).controlRadius,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 20,
              color: tone != null
                  ? tone!.onContainer(colors)
                  : colors.onSurfaceMuted,
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    value,
                    style: AppTypography.money(
                      context,
                      size: 20,
                      weight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.of(context)
                        .labelMedium
                        ?.copyWith(color: colors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The duka quick actions: Sell, Add product, Receive stock, Stocktake.
class _DukaDashboardQuickActions extends StatelessWidget {
  const _DukaDashboardQuickActions({
    required this.onOpenSell,
    required this.onOpenAddProduct,
    required this.onOpenReceiveStock,
    required this.onOpenStocktake,
    required this.addProductLabel,
    required this.canManageStock,
    required this.canReceiveStock,
    required this.canStocktake,
  });

  final VoidCallback onOpenSell;
  final VoidCallback onOpenAddProduct;
  final VoidCallback onOpenReceiveStock;
  final VoidCallback onOpenStocktake;
  final String addProductLabel;
  final bool canManageStock;
  final bool canReceiveStock;
  final bool canStocktake;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<Widget> tiles = <Widget>[
      _DukaQuickTile(
        icon: Icons.point_of_sale_outlined,
        label: l10n.dashboardSellAction,
        subtitle: 'Open Till',
        onTap: onOpenSell,
      ),
      if (canManageStock)
        _DukaQuickTile(
          icon: Icons.add_circle_outline,
          label: addProductLabel,
          subtitle: 'New catalogue item',
          onTap: onOpenAddProduct,
        ),
      _DukaQuickTile(
        icon: Icons.flash_on_outlined,
        label: 'QuickSale',
        subtitle: 'Fast sale dialog',
        onTap: () =>
            showQuickSaleDialog(context: context, profile: ShopProfile.duka),
      ),
      _DukaQuickTile(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Cost of Goods',
        subtitle: 'Pools and reload',
        onTap: () => context.push(Routes.openCostGroups),
      ),
      if (canReceiveStock)
        _DukaQuickTile(
          icon: Icons.local_shipping_outlined,
          label: 'Receive stock',
          subtitle: 'Record delivery',
          onTap: onOpenReceiveStock,
        ),
      if (canStocktake)
        _DukaQuickTile(
          icon: Icons.fact_check_outlined,
          label: 'Stocktake',
          subtitle: 'Count inventory',
          onTap: onOpenStocktake,
        ),
    ];

    return DashboardQuickActionStrip(actions: tiles);
  }
}

/// One quick-action tile in the horizontal action strip.
class _DukaQuickTile extends StatelessWidget {
  const _DukaQuickTile({
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

/// Per-loose-good cards for the duka dashboard: each card shows one loose
/// good's total sold, the remaining amount to break even (or profit if past
/// break-even), and the quantity left — all as absolute numbers, never negatives.
class _LooseGoodsCards extends StatelessWidget {
  const _LooseGoodsCards({
    required this.tanks,
    required this.tankSales,
    required this.onOpenProduct,
  });

  final List<Product> tanks;
  final Map<int, ProductSalesRow> tankSales;
  final void Function(Product product) onOpenProduct;

  /// Amount still needed to break even (positive), or profit already made.
  /// Never renders a negative.
  (String label, String value, StatusTone tone) _breakEven(Product tank) {
    final cost = Money.fromMinor(
      (tank.stockQty * tank.costPrice.minorUnits).round(),
    );
    final row = tankSales[tank.id];
    final sold = row != null ? Money.fromMinor(row.revenueMinor) : Money.zero;
    final remaining = cost - sold;

    if (remaining.minorUnits > 0) {
      return ('to break even', formatMoney(remaining.abs), StatusTone.warning);
    }
    return ('profit', formatMoney(sold.abs), StatusTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(label: l10n.dashboardLooseGoods),
        SizedBox(height: spacing.sm),
        ...tanks.map((tank) {
          final breakEven = _breakEven(tank);
          return Semantics(
            button: true,
            label: '${tank.name}: ${breakEven.$1} ${breakEven.$2}',
            child: InkWell(
              onTap: () => onOpenProduct(tank),
              child: SurfaceCard(
                margin: EdgeInsets.only(bottom: spacing.md),
                padding: EdgeInsets.all(spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                tank.name,
                                style: type.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                l10n.dashboardLooseGoodsRemaining,
                                style: type.bodySmall?.copyWith(
                                  color: colors.onSurfaceMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          breakEven.$2,
                          style: type.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: breakEven.$3 == StatusTone.success
                                ? colors.success
                                : colors.warning,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: spacing.md),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                l10n.dashboardLooseGoodsSold,
                                style: type.bodySmall?.copyWith(
                                  color: colors.onSurfaceMuted,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                formatMoney(
                                  tankSales[tank.id] != null
                                      ? Money.fromMinor(
                                          tankSales[tank.id]!.revenueMinor,
                                        )
                                      : Money.zero,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                breakEven.$1,
                                style: type.bodySmall?.copyWith(
                                  color: colors.onSurfaceMuted,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '${tank.stockQty.toStringAsFixed(1)} ${tank.unit.suffix}',
                                style: type.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: ActionChip(
                        avatar: const Icon(Icons.arrow_outward, size: 16),
                        onPressed: () => onOpenProduct(tank),
                        label: Text(l10n.dashboardLooseGoodsViewDetails),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
