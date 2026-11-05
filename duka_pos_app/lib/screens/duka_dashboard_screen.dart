import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../theme/app_spacing.dart';
import '../ui/layout/page.dart';
import '../widgets/backup_reminder_banner.dart';
import 'dashboard_attention.dart';
import 'dashboard_sections.dart';
import 'dashboard_shared.dart';

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

    final Widget quickActions = _DukaDashboardQuickActions(
      onOpenSell: onOpenSell,
      onOpenInventory: onOpenInventory,
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
          reorder,
          sales,
          topProducts,
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
}

/// The duka quick actions: Sell (primary), Inventory.
class _DukaDashboardQuickActions extends StatelessWidget {
  const _DukaDashboardQuickActions({
    required this.onOpenSell,
    required this.onOpenInventory,
  });

  final VoidCallback onOpenSell;
  final VoidCallback onOpenInventory;

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
          onPressed: onOpenInventory,
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('Stock'),
        ),
      ],
    );
  }
}
