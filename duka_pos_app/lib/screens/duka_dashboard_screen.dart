import 'package:flutter/material.dart';
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
import 'stocktake_screen.dart';
import 'inventory_screen.dart';

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
      shift: data.openShift,
      onSwitchBusiness: () => context.push(Routes.profile),
    );

    final Widget financialHero = FinancialHero(
      totals: data.totals,
      scopeLabel: data.scopeLabel,
      hasSales: hasSales,
      onTransactions: () => context.push(Routes.transactions),
      imageAsset: 'assets/branding/hero-and-profile-images/duka-retail-hero.webp',
    );

    final Widget supportingMetrics = SupportingMetrics(totals: data.totals);

    final Widget stockOverview = _DukaStockOverview(
      totalProducts: data.totalProducts,
      lowStockCount: data.lowStockCount,
      outOfStockCount: data.outOfStockCount,
      stockValue: data.stockValue,
      onOpenInventory: onOpenInventory,
    );

    final String addProductLabel = 'Add ${appState.shopProfile.terminologyLocalized(AppLocalizations.of(context)).product}';

    final Widget quickActions = _DukaDashboardQuickActions(
      onOpenSell: onOpenSell,
      onOpenAddProduct: () => _openAddProduct(context),
      onOpenReceiveStock: () => _receiveStock(context),
      onOpenStocktake: () => _openStocktake(context),
      addProductLabel: addProductLabel,
      canManageStock: canManageStock &&
          appState.shopProfile.capabilities.trackStock,
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
          supportingMetrics,
          quickActions,
          stockOverview,
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
            children: tiles.map((t) => SizedBox(width: ((constraints.maxWidth - spacing.lg) / 2).clamp(120.0, double.infinity), child: t)).toList(),
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: spacing.sm,
                runSpacing: spacing.xs,
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

/// The duka quick actions: Sell, Add product, Receive stock, Stocktake — as a
/// 2x2 grid of tiles with icon + label + subtitle, mirroring the mockup.
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
    final AppSpacing spacing = AppSpacing.of(context);

    final List<Widget> tiles = <Widget>[
      _DukaQuickTile(
        icon: Icons.point_of_sale_outlined,
        label: 'Sell',
        subtitle: 'Start transaction',
        onTap: onOpenSell,
        primary: true,
      ),
      if (canManageStock)
        _DukaQuickTile(
          icon: Icons.add_circle_outline,
          label: addProductLabel,
          subtitle: 'New catalogue item',
          onTap: onOpenAddProduct,
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

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool twoColumns = constraints.maxWidth >= 320;
        if (twoColumns) {
          return Wrap(
            spacing: spacing.md,
            runSpacing: spacing.md,
            children: <Widget>[
              for (final tile in tiles)
                SizedBox(
                  width: (constraints.maxWidth - spacing.md) / 2,
                  child: tile,
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < tiles.length; i++) ...<Widget>[
              if (i > 0) SizedBox(height: spacing.md),
              tiles[i],
            ],
          ],
        );
      },
    );
  }
}

/// One quick-action tile: icon + label + subtitle, matching the mockup's
/// 2x2 grid of action tiles.
class _DukaQuickTile extends StatelessWidget {
  const _DukaQuickTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      button: true,
      label: '$label, $subtitle',
      child: SurfaceCard(
        padding: EdgeInsets.all(spacing.md),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: EdgeInsets.all(spacing.xs),
              decoration: BoxDecoration(
                color: primary
                    ? colors.accentContainer
                    : colors.surfaceSunken,
                borderRadius: AppShapes.of(context).controlRadius,
              ),
              child: Icon(
                icon,
                size: 20,
                color: primary ? colors.accent : colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: spacing.md),
            Text(
              label,
              style: type.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: primary ? colors.accent : colors.onSurface,
              ),
            ),
            SizedBox(height: 2),
            Text(
              subtitle,
              style: type.bodySmall?.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
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
            label:
                '${tank.name}: ${breakEven.$1} ${breakEven.$2}',
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
                                          tankSales[tank.id]!
                                              .revenueMinor,
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
                      child: TextButton.icon(
                        onPressed: () => onOpenProduct(tank),
                        icon: const Icon(Icons.chevron_right, size: 18),
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
