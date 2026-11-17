import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../db/database_helper.dart';
import '../services/live_refresh_mixin.dart';
import '../services/session_refresh_mixin.dart';
import '../services/live_channel_service.dart';
import '../models/layby.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../profile/shop_profile.dart';
import '../services/roles.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../theme/dashboard_profile_palette.dart';
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';
import 'dashboard_attention.dart';
import 'dashboard_sections.dart';
import 'dashboard_shared.dart';

const double _fashionDashboardMaxWidth = 1200;
const double _fashionTwoColumnBreakpoint = 840;

/// The fashion profile dashboard.
///
/// Variant-first: low-stock variants and best-selling variants lead, then
/// today's sales and reserves that need attention. A fashion shop turns on
/// colour-size combinations, not shelf counts — the dashboard shows what
/// variants are running out and what reserves are awaiting payment or ready
/// for collection.
class FashionDashboardScreen extends StatelessWidget {
  const FashionDashboardScreen({
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

    // Fashion low-stock variants — colour-size combinations running out.
    final Widget variantReorder = _FashionLowStockVariants(
      variants: data.lowStockVariants,
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

    final AppLocalizations l10n = AppLocalizations.of(context);
    final Widget header = DashboardBusinessHeader(
      shopName: appState.owner?.shopName ?? SimplePosBrand.appName,
      profile: ShopProfile.fashion,
      staffName: appState.currentStaffName ?? appState.owner?.name,
      shift: data.openShift,
    );

    final Widget financialHero = DashboardMoneyHero(
      profile: ShopProfile.fashion,
      label: l10n.dashboardNetSalesToday,
      amount: data.totals.total,
      primaryActionLabel: l10n.dashboardNewSale,
      onPrimaryAction: onOpenSell,
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
      DashboardKpiData(
        label: l10n.dashboardStockValue,
        value: formatMoney(data.stockValue),
        icon: Icons.inventory_2_outlined,
        tone: DashboardKpiTone.info,
        onTap: onOpenInventory,
      ),
      DashboardKpiData(
        label: l10n.dashboardTransactionsLabel,
        value: '${data.totals.transactions}',
        icon: Icons.receipt_long_outlined,
        tone: DashboardKpiTone.neutral,
        onTap: () => context.push(Routes.transactions),
      ),
      DashboardKpiData(
        label: l10n.dashboardLowStockVariants,
        value: '${data.lowStockVariants.length}',
        icon: Icons.style_outlined,
        tone: DashboardKpiTone.pending,
        onTap: onOpenInventory,
      ),
    ];
    final Widget kpiGrid = DashboardKpiGrid(items: kpis);

    final Widget reserves = _FashionReservesOverview(
      onOpenReserves: () => context.push(Routes.laybys),
      canManageStock: canManageStock,
    );

    final Widget quickActions = _FashionDashboardQuickActions(
      onOpenSell: onOpenSell,
      onOpenAddProduct: () => _openProductEditor(context),
      onOpenReceiveStock: () => _receiveStock(context),
      onOpenReserves: () => context.push(Routes.laybys),
      onViewCatalogue: () => _viewCatalogue(context),
      canManageStock: canManageStock,
      canReceiveStock: appState.hasPermission(PermissionKey.receiveStock),
    );

    final bool twoColumns =
        MediaQuery.sizeOf(context).width >= _fashionTwoColumnBreakpoint;

    final List<Widget> body = <Widget>[
      header,
      if (appState.isOwnerSession)
        DashboardPortfolioCard(onOpen: () => context.push(Routes.portfolio)),
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
                    kpiGrid,
                    BackupReminderBanner(onBackupNow: onBackupNow),
                    quickActions,
                    sales,
                    topProducts,
                    reserves,
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
                    variantReorder,
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
          kpiGrid,
          BackupReminderBanner(onBackupNow: onBackupNow),
          quickActions,
          sales,
          topProducts,
          reserves,
          variantReorder,
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
        maxContentWidth: _fashionDashboardMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      ),
    );
  }

  void _openProductEditor(BuildContext context) {
    context.push(Routes.fashionProductForm);
  }

  void _receiveStock(BuildContext context) {
    context.push(Routes.inventory);
  }

  void _viewCatalogue(BuildContext context) {
    context.push(Routes.inventory);
  }
}

/// Fashion low-stock variants: colour-size combinations at or below reorder.
class _FashionLowStockVariants extends StatelessWidget {
  const _FashionLowStockVariants({
    required this.variants,
    required this.canOpen,
    required this.onOpenProduct,
    required this.onViewAll,
  });

  final List<ProductVariant> variants;
  final bool canOpen;
  final ValueChanged<Product> onOpenProduct;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final palette = DashboardProfilePalette.forProfile(ShopProfile.fashion,
        brightness: Theme.of(context).brightness);
    return DashboardPanel(
      title: l10n.fashionDashboardLowStockVariants,
      topAccent: palette.accent,
      trailing: ActionChip(
        avatar: const Icon(Icons.arrow_outward, size: 16),
        onPressed: onViewAll,
        label: Text(l10n.fashionDashboardViewAll),
      ),
      padChild: false,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool row = constraints.maxWidth >= 640;
          final List<Widget> rows = variants.take(4).map((v) {
            return _VariantRow(
              variant: v,
              onTap: canOpen ? () => onOpenProduct(_variantAsProduct(v)) : null,
            );
          }).toList();
          if (row) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: rows,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rows,
          );
        },
      ),
    );
  }

  Product _variantAsProduct(ProductVariant v) {
    return Product(
      id: v.id,
      name: v.name,
      category: 'Variant',
      costPrice: v.costPrice,
      sellPrice: v.sellPrice,
      stockQty: v.availableStockQty,
      reservedQty: 0,
      reorderLevel: v.reorderLevel,
      bottleMl: v.sizeMl,
      unit: v.unit,
      millilitresPerKilogram: 0,
      trackVariants: false,
      trackExpiry: false,
      active: v.active,
      updatedAt: '',
    );
  }
}

/// One low-stock variant row: name, colour-size, stock, reorder level.
class _VariantRow extends StatelessWidget {
  const _VariantRow({required this.variant, required this.onTap});

  final ProductVariant variant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Semantics(
      button: onTap != null,
      label:
          '${variant.name} · ${variant.availableStockQty} left · reorder at ${variant.reorderLevel}',
      child: ExcludeSemantics(
        child: SurfaceCard(
          padding: EdgeInsets.all(spacing.md),
          onTap: onTap,
          child: Row(
            children: <Widget>[
              Container(
                padding: EdgeInsets.all(spacing.xs),
                decoration: BoxDecoration(
                  color: StatusTone.warning.container(colors),
                  borderRadius: AppShapes.of(context).controlRadius,
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: StatusTone.warning.onContainer(colors),
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      variant.label,
                      style: type.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      '${variant.availableStockQty.toInt()} left · reorder at ${variant.reorderLevel}',
                      style: type.labelSmall?.copyWith(
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fashion reserves overview: open reserves, awaiting payment, ready for collection.
class _FashionReservesOverview extends StatefulWidget {
  const _FashionReservesOverview({
    required this.onOpenReserves,
    required this.canManageStock,
  });

  final VoidCallback onOpenReserves;
  final bool canManageStock;

  @override
  State<_FashionReservesOverview> createState() =>
      _FashionReservesOverviewState();
}

class _FashionReservesOverviewState extends State<_FashionReservesOverview>
    with
        LiveRefresh<_FashionReservesOverview>,
        SessionRefresh<_FashionReservesOverview> {
  int _openCount = 0;
  int _awaitingCount = 0;
  int _readyCount = 0;
  int _laybyBalanceMinor = 0;

  @override
  Set<LiveReason> get liveReasons => const <LiveReason>{};

  @override
  bool get liveIsVisible => TickerMode.valuesOf(context).enabled;

  @override
  Future<void> reloadFromLive() => _load();

  @override
  void clearForSession() {
    _openCount = 0;
    _awaitingCount = 0;
    _readyCount = 0;
    _laybyBalanceMinor = 0;
  }

  @override
  Future<void> reloadFromSession() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final laybys = await DatabaseHelper.instance.getLaybys();
      int open = 0;
      int awaiting = 0;
      int ready = 0;
      int balance = 0;
      for (final layby in laybys) {
        if (layby.status == LaybyStatus.open) {
          open++;
          balance += layby.balance.minorUnits;
          if (layby.balance.minorUnits > 0) {
            awaiting++;
          } else {
            ready++;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _openCount = open;
        _awaitingCount = awaiting;
        _readyCount = ready;
        _laybyBalanceMinor = balance;
      });
    } catch (_) {
      // Leave counts at zero rather than showing dummy figures.
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final palette = DashboardProfilePalette.forProfile(ShopProfile.fashion,
        brightness: Theme.of(context).brightness);
    return DashboardPanel(
      title: l10n.fashionDashboardReserves,
      topAccent: palette.accent,
      trailing: ActionChip(
        avatar: const Icon(Icons.arrow_outward, size: 16),
        onPressed: widget.onOpenReserves,
        label: Text(l10n.fashionDashboardViewAll),
      ),
      padChild: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ReservesMetric(
            label: l10n.fashionDashboardReservesOpen,
            value: '$_openCount',
            tone: StatusTone.warning,
            icon: Icons.schedule_outlined,
          ),
          SizedBox(height: spacing.sm),
          _ReservesMetric(
            label: l10n.fashionDashboardReservesAwaitingPayment,
            value: '$_awaitingCount',
            tone: StatusTone.warning,
            icon: Icons.payment_outlined,
          ),
          SizedBox(height: spacing.sm),
          _ReservesMetric(
            label: l10n.fashionDashboardReservesReady,
            value: '$_readyCount',
            tone: StatusTone.success,
            icon: Icons.check_circle_outlined,
          ),
          SizedBox(height: spacing.sm),
          _ReservesMetric(
            label: l10n.dashboardLaybyBalance,
            value: formatMoney(Money.fromMinor(_laybyBalanceMinor)),
            tone: StatusTone.warning,
            icon: Icons.account_balance_wallet_outlined,
          ),
        ],
      ),
    );
  }
}

class _ReservesMetric extends StatelessWidget {
  const _ReservesMetric({
    required this.label,
    required this.value,
    required this.tone,
    required this.icon,
  });

  final String label;
  final String value;
  final StatusTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Row(
      children: <Widget>[
        Container(
          padding: EdgeInsets.all(spacing.xs),
          decoration: BoxDecoration(
            color: tone.container(colors),
            borderRadius: AppShapes.of(context).controlRadius,
          ),
          child: Icon(
            icon,
            size: 18,
            color: tone.onContainer(colors),
          ),
        ),
        SizedBox(width: spacing.md),
        Expanded(
          child: Text(
            label,
            style: type.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: AppTypography.money(
            context,
            size: 20,
            weight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// The fashion quick actions: Sell, Add style, Receive stock, Create reserves,
/// View catalogue — as a 2x2 grid of tiles with icon + label + subtitle,
/// mirroring the mockup.
class _FashionDashboardQuickActions extends StatelessWidget {
  const _FashionDashboardQuickActions({
    required this.onOpenSell,
    required this.onOpenAddProduct,
    required this.onOpenReceiveStock,
    required this.onOpenReserves,
    required this.onViewCatalogue,
    required this.canManageStock,
    required this.canReceiveStock,
  });

  final VoidCallback onOpenSell;
  final VoidCallback onOpenAddProduct;
  final VoidCallback onOpenReceiveStock;
  final VoidCallback onOpenReserves;
  final VoidCallback onViewCatalogue;
  final bool canManageStock;
  final bool canReceiveStock;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    final List<Widget> tiles = <Widget>[
      if (canManageStock)
        _FashionQuickTile(
          icon: Icons.add_circle_outline,
          label: 'Add style',
          subtitle: 'Catalogue',
          onTap: onOpenAddProduct,
        ),
      if (canReceiveStock)
        _FashionQuickTile(
          icon: Icons.local_shipping_outlined,
          label: 'Receive stock',
          subtitle: 'New delivery',
          onTap: onOpenReceiveStock,
        ),
      _FashionQuickTile(
        icon: Icons.bookmark_border,
        label: 'New reserves',
        subtitle: 'Reserve item',
        onTap: onOpenReserves,
      ),
      _FashionQuickTile(
        icon: Icons.inventory_2_outlined,
        label: 'Catalogue',
        subtitle: 'View all',
        onTap: onViewCatalogue,
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

/// One quick-action tile for the fashion dashboard.
class _FashionQuickTile extends StatelessWidget {
  const _FashionQuickTile({
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
                color: colors.surfaceSunken,
                borderRadius: AppShapes.of(context).controlRadius,
              ),
              child: Icon(
                icon,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: spacing.md),
            Text(
              label,
              style: type.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
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
