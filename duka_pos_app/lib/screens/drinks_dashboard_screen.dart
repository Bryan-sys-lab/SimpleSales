import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/routes.dart';
import '../services/analytics.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/layout/page.dart';
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
    final AppState appState = context.watch<AppState>();
    final double gap = spacing.xl;

    final bool hasSales = data.totals.hasSales;
    final bool canManageCredit =
        appState.isOwnerSession || appState.role == ShopRole.manager;

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
      canOpen: appState.canManageStock,
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

    final Widget quickActions = _DrinksDashboardQuickActions(
      onOpenSell: onOpenSell,
      onOpenInventory: onOpenInventory,
      onOpenShots: () => context.push(Routes.shotCups),
      onOpenTanks: () => context.push(Routes.inventory),
    );

    final Widget? beverageStock = data.tanks.isNotEmpty
        ? BeverageStockPreview(
            tanks: data.tanks,
            tankSales: data.tankSales,
            onOpenTankRegister: () => context.push(Routes.inventory),
            onOpenPackaged: () => context.push(Routes.inventory),
            onOpenMeasured: () => context.push(Routes.shotCups),
          )
        : null;

    final bool twoColumns =
        MediaQuery.sizeOf(context).width >= _drinksTwoColumnBreakpoint;

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
                    beverageStock,
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
          financialHero,
          supportingMetrics,
          quickActions,
          beverageStock,
          sales,
          topProducts,
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
      sortKey: 2,
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

/// The drinks quick actions: Sell (primary), Tanks, Shots, Stock.
class _DrinksDashboardQuickActions extends StatelessWidget {
  const _DrinksDashboardQuickActions({
    required this.onOpenSell,
    required this.onOpenInventory,
    required this.onOpenShots,
    required this.onOpenTanks,
  });

  final VoidCallback onOpenSell;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenShots;
  final VoidCallback onOpenTanks;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        QuickAction(
          onPressed: onOpenSell,
          icon: const Icon(Icons.point_of_sale_outlined),
          label: const Text('Sell'),
          primary: true,
        ),
        QuickAction(
          onPressed: onOpenTanks,
          icon: const Icon(Icons.propane_tank_outlined),
          label: const Text('Tanks'),
        ),
        QuickAction(
          onPressed: onOpenShots,
          icon: const Icon(Icons.local_drink_outlined),
          label: const Text('Shots'),
        ),
        QuickAction(
          onPressed: onOpenInventory,
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('Stock'),
        ),
      ],
    );
  }
}
