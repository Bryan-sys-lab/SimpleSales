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

const double _fashionDashboardMaxWidth = 1200;
const double _fashionTwoColumnBreakpoint = 840;

/// The fashion profile dashboard.
///
/// Lay-bys and exchanges first — the cashier's frequent tasks — then today's
/// sales and the till. Stock stays compact; fashion turns on customer
/// commitments, not shelf counts.
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

    final Widget quickActions = _FashionDashboardQuickActions(
      onOpenSell: onOpenSell,
      onOpenInventory: onOpenInventory,
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
          financialHero,
          supportingMetrics,
          quickActions,
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
        maxContentWidth: _fashionDashboardMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      ),
    );
  }
}

/// The fashion quick actions: Sell (primary), Lay-bys, Stock.
class _FashionDashboardQuickActions extends StatelessWidget {
  const _FashionDashboardQuickActions({
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
          onPressed: () => context.push(Routes.laybys),
          icon: const Icon(Icons.bookmark_border),
          label: const Text('Lay-bys'),
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
