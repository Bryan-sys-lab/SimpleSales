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
import '../services/roles.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../widgets/backup_reminder_banner.dart';
import 'dashboard_attention.dart';
import 'dashboard_sections.dart';
import 'dashboard_shared.dart';

const double _fashionDashboardMaxWidth = 1200;
const double _fashionTwoColumnBreakpoint = 840;

/// The fashion profile dashboard.
///
/// Variant-first: low-stock variants and best-selling variants lead, then
/// today's sales and laybys that need attention. A fashion shop turns on
/// colour-size combinations, not shelf counts — the dashboard shows what
/// variants are running out and what laybys are awaiting payment or ready
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

    final Widget laybys = _FashionLaybyOverview(
      onOpenLaybys: () => context.push(Routes.laybys),
      canManageStock: canManageStock,
    );

    final Widget quickActions = _FashionDashboardQuickActions(
      onOpenSell: onOpenSell,
      onOpenAddProduct: () => _openProductEditor(context),
      onOpenReceiveStock: () => _receiveStock(context),
      onOpenLaybys: () => context.push(Routes.laybys),
      onViewCatalogue: () => _viewCatalogue(context),
      canManageStock: canManageStock,
      canReceiveStock:
          appState.hasPermission(PermissionKey.receiveStock),
    );

    final bool twoColumns =
        MediaQuery.sizeOf(context).width >= _fashionTwoColumnBreakpoint;

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
                    sales,
                    topProducts,
                    laybys,
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
          supportingMetrics,
          quickActions,
          sales,
          topProducts,
          laybys,
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
    context.push(Routes.inventory);
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

    return DashboardPanel(
      title: l10n.fashionDashboardLowStockVariants,
      trailing: TextButton(
        onPressed: onViewAll,
        child: Text(l10n.fashionDashboardViewAll),
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

/// Fashion layby overview: open laybys, awaiting payment, ready for collection.
class _FashionLaybyOverview extends StatefulWidget {
  const _FashionLaybyOverview({
    required this.onOpenLaybys,
    required this.canManageStock,
  });

  final VoidCallback onOpenLaybys;
  final bool canManageStock;

  @override
  State<_FashionLaybyOverview> createState() => _FashionLaybyOverviewState();
}

class _FashionLaybyOverviewState extends State<_FashionLaybyOverview>
    with LiveRefresh<_FashionLaybyOverview>, SessionRefresh<_FashionLaybyOverview> {
  int _openCount = 0;
  int _awaitingCount = 0;
  int _readyCount = 0;

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
      for (final layby in laybys) {
        if (layby.status == LaybyStatus.open) {
          open++;
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
      });
    } catch (_) {
      // Leave counts at zero rather than showing dummy figures.
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DashboardPanel(
      title: l10n.fashionDashboardReserves,
      trailing: TextButton(
        onPressed: widget.onOpenLaybys,
        child: Text(l10n.fashionDashboardViewAll),
      ),
      padChild: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _LaybyMetric(
            label: l10n.fashionDashboardReservesOpen,
            value: '$_openCount',
            tone: StatusTone.warning,
            icon: Icons.schedule_outlined,
          ),
          SizedBox(height: spacing.sm),
          _LaybyMetric(
            label: l10n.fashionDashboardReservesAwaitingPayment,
            value: '$_awaitingCount',
            tone: StatusTone.warning,
            icon: Icons.payment_outlined,
          ),
          SizedBox(height: spacing.sm),
          _LaybyMetric(
            label: l10n.fashionDashboardReservesReady,
            value: '$_readyCount',
            tone: StatusTone.success,
            icon: Icons.check_circle_outlined,
          ),
        ],
      ),
    );
  }
}

class _LaybyMetric extends StatelessWidget {
  const _LaybyMetric({
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

/// The fashion quick actions: Sell, Add style, Receive stock, Create layby,
/// View catalogue — as a 2x2 grid of tiles with icon + label + subtitle,
/// mirroring the mockup.
class _FashionDashboardQuickActions extends StatelessWidget {
  const _FashionDashboardQuickActions({
    required this.onOpenSell,
    required this.onOpenAddProduct,
    required this.onOpenReceiveStock,
    required this.onOpenLaybys,
    required this.onViewCatalogue,
    required this.canManageStock,
    required this.canReceiveStock,
  });

  final VoidCallback onOpenSell;
  final VoidCallback onOpenAddProduct;
  final VoidCallback onOpenReceiveStock;
  final VoidCallback onOpenLaybys;
  final VoidCallback onViewCatalogue;
  final bool canManageStock;
  final bool canReceiveStock;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    final List<Widget> tiles = <Widget>[
      _FashionQuickTile(
        icon: Icons.point_of_sale_outlined,
        label: 'Sell',
        subtitle: 'New sale',
        onTap: onOpenSell,
        primary: true,
      ),
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
        label: 'New layby',
        subtitle: 'Reserve item',
        onTap: onOpenLaybys,
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
