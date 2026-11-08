// Shared dashboard widgets used by every profile's dashboard screen.
//
// Each profile (drinks, duka, fashion, open) gets its own screen file, but the
// common building blocks — the compact header, the financial hero, the
// supporting metrics, the quick-action chip — live here so there is one
// component language across profiles.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/routes.dart';
import '../services/analytics.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import 'dashboard_sections.dart';

sealed class DashboardState {
  const DashboardState();
}

final class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

final class DashboardFailed extends DashboardState {
  const DashboardFailed();
}

final class DashboardReady extends DashboardState {
  const DashboardReady({
    required this.totals,
    required this.hasEverSold,
    required this.hours,
    required this.topProducts,
    required this.lowStock,
    required this.lowStockCount,
    required this.attention,
    required this.scopeLabel,
    required this.greeting,
    required this.openShift,
    required this.expectedTill,
    this.creditOwedMinor = 0,
    this.creditCustomerCount = 0,
    this.tanks = const <Product>[],
    this.tankSales = const <int, ProductSalesRow>{},
    this.totalProducts = 0,
    this.outOfStockCount = 0,
    this.stockValue = Money.zero,
    this.lowStockVariants = const <ProductVariant>[],
  });

  final DailyTotals totals;

  final bool hasEverSold;

  final List<TimeBucket> hours;
  final List<ProductSalesRow> topProducts;
  final List<Product> lowStock;
  final int lowStockCount;
  final List<ProductVariant> lowStockVariants;
  final AttentionSummary attention;

  final String scopeLabel;

  final String greeting;

  final Shift? openShift;
  final Money expectedTill;
  final int creditOwedMinor;
  final int creditCustomerCount;
  final List<Product> tanks;
  final Map<int, ProductSalesRow> tankSales;
  final int totalProducts;
  final int outOfStockCount;
  final Money stockValue;
}

List<Widget> spaced(List<Widget?> children, double gap) {
  return children.whereType<Widget>().expand((Widget child) {
    return <Widget>[child, SizedBox(height: gap)];
  }).toList()..removeLast();
}

/// Compact business header: identity, status, date, and the business switch.
///
/// No large logo, no giant greeting, no oversized top padding.
class CompactBusinessHeader extends StatelessWidget {
  const CompactBusinessHeader({
    required this.shopName,
    required this.eyebrow,
    required this.subtitle,
    required this.onSell,
    this.onSwitchBusiness,
    super.key,
  });

  final String shopName;
  final String eyebrow;
  final String subtitle;
  final VoidCallback onSell;
  final VoidCallback? onSwitchBusiness;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String formatted = _headerDate(l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.lg,
            top: spacing.sm,
            end: spacing.lg,
            bottom: spacing.xs,
          ),
          child: Semantics(
            header: true,
            child: Text(
              '$eyebrow · $shopName — $subtitle',
              style: AppTypography.of(context).headlineSmall?.copyWith(
                    color: AppColors.of(context).onSurface,
                  ),
              softWrap: true,
            ),
          ),
        ),
        SizedBox(height: spacing.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: spacing.sm,
          runSpacing: spacing.xs,
          children: <Widget>[
            StatusChip(tone: StatusTone.success, text: l10n.shiftOpenChip),
            Text(
              formatted,
              style: AppTypography.of(context)
                  .bodySmall
                  ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
            ),
          ],
        ),
        SizedBox(height: spacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                label: l10n.dashboardCurrentBusiness(shopName),
                child: ExcludeSemantics(
                  child: Text(
                    l10n.dashboardCurrentBusinessLabel,
                    style: AppTypography.of(context)
                        .labelSmall
                        ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
                  ),
                ),
              ),
            ),
            if (onSwitchBusiness != null)
              OutlinedButton.icon(
                onPressed: onSwitchBusiness,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Switch'),
              ),
          ],
        ),
        SizedBox(height: spacing.lg),
        Semantics(
          button: true,
          label: l10n.dashboardSellAction,
          child: ExcludeSemantics(
            child: FilledButton.icon(
              onPressed: onSell,
              icon: const Icon(Icons.point_of_sale_outlined, size: 18),
              label: Text(AppDestination.sell.label(l10n)),
            ),
          ),
        ),
      ],
    );
  }
}

String _headerDate(AppLocalizations l10n) {
  final now = DateTime.now();
  final dayOfWeek = DateFormat.EEEE(l10n.localeName).format(now);
  final month = DateFormat.MMMM(l10n.localeName).format(now);
  return '$dayOfWeek · ${now.day} $month';
}

/// Financial hero: the one display-size figure, with the comparison beneath it.
class FinancialHero extends StatelessWidget {
  const FinancialHero({
    required this.totals,
    required this.scopeLabel,
    required this.hasSales,
    required this.onTransactions,
    super.key,
  });

  final DailyTotals totals;
  final String scopeLabel;
  final bool hasSales;
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
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.dashboardNetSalesToday,
                        style: AppTypography.of(context)
                            .labelMedium
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                    ),
                    Text(
                      l10n.dashboardPeriodToday,
                      style: AppTypography.of(context)
                          .labelSmall
                          ?.copyWith(color: colors.onSurfaceMuted),
                    ),
                  ],
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
                        size: 40,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: spacing.sm),
                if (totals.hasSales) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.trending_up_outlined,
                        size: 16,
                        color: colors.success,
                      ),
                      SizedBox(width: spacing.xs),
                      Expanded(
                        child: Text(
                          l10n.dashboardVersusPreviousDay,
                          style: AppTypography.of(context)
                              .bodySmall
                              ?.copyWith(color: colors.success),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: colors.outline),
          Semantics(
            button: true,
            label: '${l10n.dashboardTransactionsLabel}: ${totals.transactions}',
            child: InkWell(
              onTap: onTransactions,
              child: Padding(
                padding: PageGutter.card(context),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.receipt_long_outlined, size: 18),
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
        ],
      ),
    );
  }
}

/// Supporting metrics: profit, transactions, average sale — smaller than the hero.
class SupportingMetrics extends StatelessWidget {
  const SupportingMetrics({required this.totals, super.key});

  final DailyTotals totals;

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
            _MetricTile(
              label: l10n.dashboardProfitLabel,
              value: formatMoney(Money.fromMinor(totals.profitMinor)),
            ),
            _MetricTile(
              label: l10n.dashboardTransactionsLabel,
              value: '${totals.transactions}',
            ),
            _MetricTile(
              label: l10n.dashboardAverageSaleLabel,
              value: formatMoney(Money.fromMinor(totals.averageMinor)),
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

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
          Text(
            label,
            style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted),
          ),
          SizedBox(height: spacing.xs),
          Text(
            value,
            style: AppTypography.money(
              context,
              size: 20,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// One quick action: a destination into an existing function.
class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.primary = false,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final Widget label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final Widget button = primary
        ? FilledButton.icon(onPressed: onPressed, icon: icon, label: label)
        : FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: icon,
            label: label,
          );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: spacing.minTapTarget,
        minHeight: spacing.minTapTarget,
      ),
      child: button,
    );
  }
}

String timeOfDayWord(AppLocalizations l10n) {
  final int hour = DateTime.now().hour;
  final String word = hour < 12
      ? l10n.dashboardGreetingMorning
      : hour < 17
          ? l10n.dashboardGreetingAfternoon
          : l10n.dashboardGreetingEvening;
  return word.toUpperCase();
}

/// Reads localisations without holding a [BuildContext] across an await.

