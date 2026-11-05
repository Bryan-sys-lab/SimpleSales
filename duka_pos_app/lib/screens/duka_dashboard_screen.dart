import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
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
import 'stocktake_screen.dart';

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

    final Widget? topProducts =
        hasSales ? DashboardTopProducts(rows: data.topProducts) : null;

    final Widget reorder = DashboardLowStockList(
      products: data.lowStock,
      totalCount: data.lowStockCount,
      canOpen: canManageStock,
      onOpenProduct: onOpenProduct,
      onViewAll: onOpenInventory,
    );

    final Widget? credit = canManageCredit
        ? DashboardCreditCard(
            owedMinor: data.creditOwedMinor,
            customerCount: data.creditCustomerCount,
            onOpen: () => context.push(Routes.customers),
          )
        : null;

    final Widget header = CompactBusinessHeader(
      shopName: appState.owner?.shopName ?? SimplePosBrand.appName,
      eyebrow: timeOfDayWord(AppLocalizations.of(context)),
      subtitle: data.greeting,
      onSell: onOpenSell,
      onSwitchBusiness: () => context.push(Routes.profile),
    );

    final Widget financialHero = FinancialHero(
      totals: data.totals,
      scopeLabel: data.scopeLabel,
      hasSales: hasSales,
      onTransactions: () => context.push(Routes.transactions),
    );

    final Widget supportingMetrics = SupportingMetrics(totals: data.totals);

    final Widget stockOverview = _DukaStockOverview(
      totalProducts: data.totalProducts,
      lowStockCount: data.lowStockCount,
      outOfStockCount: data.outOfStockCount,
      stockValue: data.stockValue,
      onOpenInventory: onOpenInventory,
    );

    final Widget quickActions = _DukaDashboardQuickActions(
      onOpenSell: onOpenSell,
      onOpenAddProduct: () => _openEditor(context),
      onOpenReceiveStock: () => _receiveStock(context),
      onOpenStocktake: () => _openStocktake(context),
      canManageStock: canManageStock,
      canReceiveStock: appState.hasPermission(PermissionKey.receiveStock),
      canStocktake: appState.hasPermission(PermissionKey.stocktake),
    );

    final bool twoColumns =
        MediaQuery.sizeOf(context).width >= _dukaTwoColumnBreakpoint;

    final List<Widget> body = <Widget>[
      BackupReminderBanner(onBackupNow: onBackupNow),
      SizedBox(height: spacing.section),
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
                    supportingMetrics,
                    quickActions,
                    stockOverview,
                    sales,
                    topProducts,
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
          supportingMetrics,
          quickActions,
          stockOverview,
          sales,
          topProducts,
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

  void _openEditor(BuildContext context) {
    Navigator.of(context).pushNamed(Routes.inventory);
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StocktakeScreen()),
    );
  }
}

/// Stock overview: total products, low stock, out of stock, stock value.
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

    return DashboardPanel(
      title: l10n.dashboardStockOverview,
      padChild: false,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool row = constraints.maxWidth >= 640;
          final List<Widget> tiles = <Widget>[
            _OverviewTile(
              label: l10n.dashboardTotalProducts,
              value: '$totalProducts',
              icon: Icons.inventory_2_outlined,
              onTap: onOpenInventory,
            ),
            _OverviewTile(
              label: l10n.dashboardLowStockCount,
              value: '$lowStockCount',
              icon: Icons.warning_amber_outlined,
              tone: StatusTone.warning,
            ),
            _OverviewTile(
              label: l10n.dashboardOutOfStockCount,
              value: '$outOfStockCount',
              icon: Icons.cancel_outlined,
              tone: StatusTone.danger,
            ),
            _OverviewTile(
              label: l10n.dashboardStockValue,
              value: formatMoney(stockValue),
              icon: Icons.account_balance_wallet_outlined,
              onTap: onOpenInventory,
            ),
          ];
          if (row) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < tiles.length; i++) ...<Widget>[
                    if (i > 0) SizedBox(width: spacing.lg),
                    Expanded(child: tiles[i]),
                  ],
                ],
              ),
            );
          }
          return Wrap(
            spacing: spacing.lg,
            runSpacing: spacing.lg,
            children: tiles.map((t) => SizedBox(width: 150, child: t)).toList(),
          );
        },
      ),
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final StatusTone? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Semantics(
      button: onTap != null,
      label: '$label: $value',
      child: ExcludeSemantics(
        child: SurfaceCard(
          padding: EdgeInsets.all(spacing.md),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: EdgeInsets.all(spacing.xs),
                    decoration: BoxDecoration(
                      color: tone != null
                          ? tone!.container(colors)
                          : colors.surfaceSunken,
                      borderRadius: AppShapes.of(context).controlRadius,
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: tone != null
                          ? tone!.onContainer(colors)
                          : colors.onSurfaceMuted,
                    ),
                  ),
                  const Spacer(),
                  if (tone != null)
                    StatusChip(tone: tone!, text: tone!.label, dense: true),
                ],
              ),
              SizedBox(height: spacing.lg),
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
                label,
                style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The duka quick actions: Sell (primary), Add product, Receive stock, Stocktake.
class _DukaDashboardQuickActions extends StatelessWidget {
  const _DukaDashboardQuickActions({
    required this.onOpenSell,
    required this.onOpenAddProduct,
    required this.onOpenReceiveStock,
    required this.onOpenStocktake,
    required this.canManageStock,
    required this.canReceiveStock,
    required this.canStocktake,
  });

  final VoidCallback onOpenSell;
  final VoidCallback onOpenAddProduct;
  final VoidCallback onOpenReceiveStock;
  final VoidCallback onOpenStocktake;
  final bool canManageStock;
  final bool canReceiveStock;
  final bool canStocktake;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        QuickAction(
          onPressed: onOpenSell,
          icon: const Icon(Icons.point_of_sale_outlined),
          label: Text(l10n.dashboardSellAction),
          primary: true,
        ),
        if (canManageStock)
          QuickAction(
            onPressed: onOpenAddProduct,
            icon: const Icon(Icons.add_circle_outline),
            label: Text(l10n.dashboardQuickAddProduct),
          ),
        if (canReceiveStock)
          QuickAction(
            onPressed: onOpenReceiveStock,
            icon: const Icon(Icons.local_shipping_outlined),
            label: Text(l10n.dashboardQuickReceiveStock),
          ),
        if (canStocktake)
          QuickAction(
            onPressed: onOpenStocktake,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(l10n.dashboardQuickStocktake),
          ),
      ],
    );
  }
}
