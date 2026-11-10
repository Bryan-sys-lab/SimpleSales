import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../profile/profile_capabilities.dart';
import '../profile/profile_product_forms.dart';
import '../profile/profile_terminology.dart';
import '../profile/shop_profile.dart';
import '../routing/routes.dart';
import '../services/analytics.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import '../widgets/backup_reminder_banner.dart';
import 'dashboard_attention.dart';
import 'dashboard_sections.dart';
import 'dashboard_shared.dart';

const double _drinksDashboardMaxWidth = 1200;
const double _drinksTwoColumnBreakpoint = 840;

/// The Drinks profile dashboard.
///
/// Money first, then actions, then the chart — with shift, tabs, alerts and
/// stock in a supporting column on wider screens.
///
/// Redesigned to match the SimpleSales drinks profile mockup: a green-gradient
/// hero with today's sales, a two-stat grid, a shift-overview mini-list, and a
/// prominent "+ Start a sale" primary action.
class DrinksDashboardScreen extends StatelessWidget {
  const DrinksDashboardScreen({
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
    final AppLocalizations l10n = AppLocalizations.of(context);
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

    // Hero: green-gradient card with today's sales figure — the one number the
    // drinks shop lands on the screen to see.
    final Widget hero = _DrinksSalesHero(
      totals: data.totals,
      onTransactions: () => context.push(Routes.transactions),
    );

    // Two-stat grid: gross profit and transactions.
    final Widget stats = _DrinksStatsGrid(
      profit: formatMoney(Money.fromMinor(data.totals.profitMinor)),
      transactions: data.totals.transactions,
    );

    // Shift overview section: shift state, tank operations, stock attention.
    final Widget shiftOverview = _DrinksShiftOverview(
      shift: data.openShift,
      tanks: data.tanks,
      tankSales: data.tankSales,
      lowStockCount: data.lowStockCount,
      onOpenShift: onOpenShift,
      onOpenInventory: onOpenInventory,
      onOpenShots: () => context.push(Routes.servings),
      l10n: l10n,
    );

    // Primary action: start a sale, full width.
    final Widget startSale = Semantics(
      button: true,
      label: '${l10n.dashboardSellAction} · ${formatMoney(data.totals.total)}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onOpenSell,
            icon: const Icon(Icons.point_of_sale_outlined, size: 18),
            label: Text('+ ${l10n.dashboardSellAction}'),
          ),
        ),
      ),
    );

  final Widget beverageStock = data.tanks.isNotEmpty
      ? BeverageStockPreview(
          tanks: data.tanks,
          tankSales: data.tankSales,
          onOpenTankRegister: () => context.push(Routes.tankRegister),
          onOpenPackaged: () => context.push(Routes.inventory),
          onOpenMeasured: () => context.push(Routes.servings),
        )
        : const SizedBox.shrink();

    final bool twoColumns =
        MediaQuery.sizeOf(context).width >= _drinksTwoColumnBreakpoint;

    final List<Widget> body = <Widget>[
      BackupReminderBanner(onBackupNow: onBackupNow),
      SizedBox(height: spacing.section),
      header,
      SizedBox(height: spacing.lg),
      hero,
      SizedBox(height: spacing.lg),
      stats,
      SizedBox(height: spacing.lg),
      shiftOverview,
      SizedBox(height: spacing.lg),
      if (data.tanks.isNotEmpty)
        _TankCards(
          tanks: data.tanks,
          tankSales: data.tankSales,
          onOpenTank: (int productId) => context.push(
            Routes.tankDetail(productId),
          ),
        ),
      SizedBox(height: spacing.lg),
      if (appState.shopProfile.capabilities.trackStock) ...<Widget>[
        Semantics(
          button: true,
          label: 'Add ${appState.shopProfile.terminologyLocalized(AppLocalizations.of(context)).product}',
          child: ExcludeSemantics(
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _openAddProduct(context),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: Text(
                    '+ Add ${appState.shopProfile.terminologyLocalized(AppLocalizations.of(context)).product}'),
              ),
            ),
          ),
        ),
        SizedBox(height: spacing.lg),
      ],
      startSale,
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
                    if (attention != null)
                      Semantics(
                        sortKey: const OrdinalSortKey(0),
                        child: attention,
                      ),
                    sales,
                    topProducts,
                    beverageStock,
                      if (data.tanks.isNotEmpty)
                      _TankCards(
                        tanks: data.tanks,
                        tankSales: data.tankSales,
                        onOpenTank: (int productId) => context.push(
                          Routes.tankDetail(productId),
                        ),
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
                    shift,
                    credit,
                    reorder,
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
          if (attention != null)
            Semantics(
              sortKey: const OrdinalSortKey(0),
              child: attention,
            ),
          sales,
          topProducts,
          beverageStock,
          shift,
          credit,
          reorder,
        ],
        gap,
      ));
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _drinksDashboardMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      ),
    );
  }

  /// Opens the drinks-tailored add-product form. This is the visible entry
  /// point for the profile-defined product creation capability, gated on the
  /// profile tracking stock.
  Future<void> _openAddProduct(BuildContext context) async {
    final result = await ProfileProductForms.showForm(
      context: context,
      profile: ShopProfile.drinks,
    );
    if (!context.mounted || result == null) return;
    final unit = ProductUnit.parse(result['unit'] as String?);
    final cost = (result['cost'] as num?)?.toDouble() ?? 0;
    final price = (result['price'] as num?)?.toDouble() ?? 0;
    final stock = (result['stock'] as num?)?.toDouble() ?? 0;
    final bottleMl = (result['bottle_ml'] as num?)?.toInt() ?? 750;
    final halfPrice = (result['half_price'] as num?)?.toDouble();
    final quarterPrice = (result['quarter_price'] as num?)?.toDouble();
    final product = Product(
      name: result['name'] as String,
      category: (result['category'] as String? ?? 'Drinks'),
      costPrice: Money.fromMajor(cost),
      sellPrice: Money.fromMajor(price),
      stockQty: stock,
      reorderLevel: 5,
      bottleMl: bottleMl,
      unit: unit,
      halfPrice: halfPrice != null ? Money.fromMajor(halfPrice) : null,
      quarterPrice:
          quarterPrice != null ? Money.fromMajor(quarterPrice) : null,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await DatabaseHelper.instance.upsertProduct(product);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product.name} saved')),
    );
  }
}

/// Hero card for the drinks dashboard: green-gradient fill with today's sales
/// figure, a comparison line, and a door into the transaction list.
class _DrinksSalesHero extends StatelessWidget {
  const _DrinksSalesHero({
    required this.totals,
    required this.onTransactions,
  });

  final DailyTotals totals;
  final VoidCallback onTransactions;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DashboardPanel(
      sortKey: 0,
      title: l10n.dashboardSalesLabel,
      padChild: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: PageGutter.card(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(spacing.lg),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        colors.accent,
                        Color.alphaBlend(
                          colors.accent.withValues(alpha: 0.85),
                          colors.canvas,
                        ),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: AppShapes.of(context).cardRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        l10n.dashboardNetSalesToday,
                        style: AppTypography.of(context)
                            .labelMedium
                            ?.copyWith(
                              color: colors.onAccent.withValues(alpha: 0.9),
                              letterSpacing: 0.6,
                            ),
                      ),
                      SizedBox(height: spacing.xs),
                      Semantics(
                        label:
                            '${l10n.dashboardSalesLabel}: ${formatMoney(totals.total)}',
                        child: ExcludeSemantics(
                          child: Text(
                            formatMoney(totals.total),
                            style: AppTypography.money(
                              context,
                              size: 32,
                              weight: FontWeight.w800,
                            ).copyWith(color: colors.onAccent),
                          ),
                        ),
                      ),
                      if (totals.hasSales) ...<Widget>[
                        SizedBox(height: spacing.xs),
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.trending_up_outlined,
                              size: 14,
                              color: colors.onAccent.withValues(alpha: 0.9),
                            ),
                            SizedBox(width: spacing.xs),
                            Expanded(
                              child: Text(
                                l10n.dashboardVersusPreviousDay,
                                style: AppTypography.of(context)
                                    .bodySmall
                                    ?.copyWith(
                                      color: colors.onAccent.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: spacing.lg),
                Semantics(
                  button: true,
                  label:
                      '${l10n.dashboardTransactionsLabel}: ${totals.transactions}',
                  child: ExcludeSemantics(
                    child: InkWell(
                      onTap: onTransactions,
                      child: Padding(
                        padding: PageGutter.card(context),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.receipt_long_outlined,
                              size: 18,
                            ),
                            SizedBox(width: spacing.md),
                            Expanded(
                              child: Text(
                                l10n.dashboardTransactionsLabel,
                                style: AppTypography.of(context).bodyMedium,
                              ),
                            ),
                            SizedBox(width: spacing.md),
                            Text(
                              '${totals.transactions}',
                              style: AppTypography.money(
                                context,
                                size: 18,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outline),
        ],
      ),
    );
  }
}

/// Two-stat grid: gross profit and transactions.
class _DrinksStatsGrid extends StatelessWidget {
  const _DrinksStatsGrid({
    required this.profit,
    required this.transactions,
  });

  final String profit;
  final int transactions;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DashboardPanel(
      sortKey: 1,
      title: l10n.dashboardSupportingMetrics,
      padChild: false,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool row = constraints.maxWidth >= 640;
          final List<Widget> tiles = <Widget>[
            _DrinksStatTile(
              label: l10n.dashboardProfitLabel,
              value: profit,
              icon: Icons.trending_up_outlined,
            ),
            _DrinksStatTile(
              label: l10n.dashboardTransactionsLabel,
              value: '$transactions',
              icon: Icons.receipt_long_outlined,
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

/// One stat tile: a muted label above a large tabular figure, with a tonal
/// icon badge on the leading side.
class _DrinksStatTile extends StatelessWidget {
  const _DrinksStatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: spacing.minTapTarget),
      child: Column(
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
          Semantics(
            label: '$label: $value',
            child: ExcludeSemantics(
              child: Text(
                value,
                style: AppTypography.money(
                  context,
                  size: 20,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SizedBox(height: spacing.xs),
          Text(
            label,
            style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

/// Shift overview section: the current shift, tank operations, and stock
/// attention as a mini-list of three rows.
class _DrinksShiftOverview extends StatelessWidget {
  const _DrinksShiftOverview({
    required this.shift,
    required this.tanks,
    required this.tankSales,
    required this.lowStockCount,
    required this.onOpenShift,
    required this.onOpenInventory,
    required this.onOpenShots,
    required this.l10n,
  });

  final Shift? shift;
  final List<Product> tanks;
  final Map<int, ProductSalesRow> tankSales;
  final int lowStockCount;
  final VoidCallback onOpenShift;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenShots;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final int activeTanks = tanks.where((p) => p.active).length;
    final int remainingLitres = tanks.fold<int>(
      0,
      (sum, p) => sum + p.bottleMl.round(),
    ) ~/ 1000;

    return DashboardPanel(
      sortKey: 2,
      title: 'Shift overview',
      trailing: TextButton.icon(
        onPressed: onOpenShift,
        icon: const Icon(Icons.chevron_right, size: 18),
        label: Text(l10n.dashboardViewAll),
      ),
      padChild: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DrinksMiniListRow(
            icon: Icons.access_time_outlined,
            title: 'Current shift',
            subtitle: shift == null
                ? l10n.dashboardNoShiftMessage
                : l10n.dashboardStaffNameSince(
                    shift!.staffName,
                    shift!.startTime.toString(),
                  ),
            pill: shift == null
                ? null
                : StatusChip(
                    tone: StatusTone.success,
                    text: l10n.shiftOpenChip,
                    dense: true,
                  ),
            onTap: onOpenShift,
          ),
          _DrinksMiniListRow(
            icon: Icons.local_drink_outlined,
            title: 'Tank operations',
            subtitle:
                '$activeTanks active tanks · $remainingLitres L remaining',
            onTap: onOpenInventory,
          ),
          _DrinksMiniListRow(
            icon: Icons.warning_amber_outlined,
            title: 'Stock attention',
            subtitle: '$lowStockCount items running low',
            pill: lowStockCount > 0
                ? StatusChip(
                    tone: StatusTone.warning,
                    text: 'Review',
                    dense: true,
                  )
                : null,
            onTap: onOpenShots,
          ),
        ],
      ),
    );
  }
}

/// One mini-list row: a circular icon badge, a title/subtitle description, and
/// an optional status pill on the trailing side.
class _DrinksMiniListRow extends StatelessWidget {
  const _DrinksMiniListRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.pill,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? pill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      button: onTap != null,
      label: '$title, $subtitle',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppShapes.of(context).controlRadius,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: spacing.minTapTarget),
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.xl,
                end: spacing.md,
                top: spacing.md,
                bottom: spacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    padding: EdgeInsets.all(spacing.sm),
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
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          style: type.bodyMedium,
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
                  if (pill != null) ...<Widget>[
                    SizedBox(width: spacing.md),
                    pill!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Beverage stock preview: one compact section instead of a full tank list.
class BeverageStockPreview extends StatelessWidget {
  const BeverageStockPreview({
    required this.tanks,
    required this.tankSales,
    required this.onOpenTankRegister,
    required this.onOpenPackaged,
    required this.onOpenMeasured,
    super.key,
  });

  final List<Product> tanks;
  final Map<int, ProductSalesRow> tankSales;
  final VoidCallback onOpenTankRegister;
  final VoidCallback onOpenPackaged;
  final VoidCallback onOpenMeasured;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DashboardPanel(
      sortKey: 3,
      title: l10n.dashboardBeverageStock,
      trailing: TextButton.icon(
        onPressed: onOpenTankRegister,
        icon: const Icon(Icons.chevron_right, size: 18),
        label: Text(l10n.dashboardViewAll),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _BeverageStockRow(
            label: l10n.dashboardTankInventory,
            detail: '${tanks.length} active tanks · measured quantities',
            icon: Icons.propane_tank_outlined,
            onTap: onOpenTankRegister,
          ),
          _BeverageStockRow(
            label: l10n.dashboardPackagedBeverages,
            detail: l10n.dashboardPackagedDetail,
            icon: Icons.inventory_2_outlined,
            onTap: onOpenPackaged,
          ),
          _BeverageStockRow(
            label: l10n.dashboardMeasuredServings,
            detail: l10n.dashboardMeasuredDetail,
            icon: Icons.local_drink_outlined,
            onTap: onOpenMeasured,
          ),
        ],
      ),
    );
  }
}

class _BeverageStockRow extends StatelessWidget {
  const _BeverageStockRow({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      button: true,
      label: '$label, $detail',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: spacing.sm),
          child: Row(
            children: <Widget>[
              ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: AppShapes.of(context).controlRadius,
                  ),
                  child: Icon(icon, size: 20, color: colors.onSurfaceVariant),
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
              Icon(
                Icons.chevron_right,
                color: colors.onSurfaceMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-tank cards for the drinks dashboard: each card shows one tank's total
/// sold, the remaining amount to break even (or profit if past break-even),
/// and the quantity left — all as absolute numbers, never negatives.
class _TankCards extends StatelessWidget {
  const _TankCards({
    required this.tanks,
    required this.tankSales,
    required this.onOpenTank,
  });

  final List<Product> tanks;
  final Map<int, ProductSalesRow> tankSales;
  final void Function(int productId) onOpenTank;

  /// Amount still needed to break even (positive), or profit already made
  /// (shown as "past break-even"). Never renders a negative.
  (String label, String value, StatusTone tone) _breakEven(Product tank) {
    final cost = Money.fromMinor(
      (tank.stockQty * tank.costPrice.minorUnits).round(),
    );
    final row = tankSales[tank.id];
    final sold = row != null ? Money.fromMinor(row.revenueMinor) : Money.zero;
    final remaining = cost - sold;

    if (remaining.minorUnits > 0) {
      return (
        'to break even',
        formatMoney(remaining.abs),
        StatusTone.warning,
      );
    }
    return ('profit', formatMoney(sold.abs), StatusTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(label: l10n.tankRegisterSection),
        SizedBox(height: spacing.sm),
        ...tanks.map((tank) {
          final breakEven = _breakEven(tank);
          return Semantics(
            button: true,
            label: '${tank.name}: ${breakEven.$1} ${breakEven.$2}',
            child: InkWell(
              onTap: () => onOpenTank(tank.id!),
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
                                style: AppTypography.of(context)
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 2),
                              Text(
                                l10n.tankRegisterRemaining,
                                style: AppTypography.of(context)
                                    .bodySmall
                                    ?.copyWith(
                                  color: colors.onSurfaceMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          breakEven.$2,
                          style: AppTypography.of(context).bodyLarge?.copyWith(
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
                                l10n.tankRegisterSold,
                                style: AppTypography.of(context)
                                    .bodySmall
                                    ?.copyWith(
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
                                style: AppTypography.of(context)
                                    .bodySmall
                                    ?.copyWith(
                                  color: colors.onSurfaceMuted,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '${tank.stockQty.toStringAsFixed(1)} ${tank.unit.suffix}',
                                style: AppTypography.of(context).bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: () => onOpenTank(tank.id!),
                        icon: const Icon(Icons.chevron_right, size: 18),
                        label: Text(l10n.tankActionViewDetails),
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
