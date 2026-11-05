import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/financial_event.dart';
import '../services/analytics.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/chart.dart';
import 'analytics_shared.dart';
import 'analytics_screen.dart';

/// The duka profile analytics screen.
///
/// Takings lead, then supporting figures — profit, transactions, average
/// basket — then payment mix, stock, VAT, the revenue trend, the product
/// table, and shift reconciliation. No beverage-specific sections: a duka
/// sells units, not pours.
class DukaAnalyticsScreen extends StatelessWidget {
  const DukaAnalyticsScreen({
    required this.range,
    required this.onRangeChanged,
    required this.snapshot,
    required this.onRetry,
    this.onSortBy,
    this.sort = ProductSort.revenue,
    this.ascending = false,
    required this.sortedProducts,
    required this.salesPoints,
    required this.chartSemantics,
    this.chartEmphasis,
    this.statement,
    this.bottomInset = 0,
    this.onOpenPortfolio,
    this.onProductTap,
    this.showPortfolioLink = false,
    super.key,
  });

  final AnalyticsRange range;
  final ValueChanged<AnalyticsRange> onRangeChanged;
  final AnalyticsSnapshot snapshot;
  final Future<void> Function() onRetry;
  final void Function(ProductSort)? onSortBy;
  final ProductSort sort;
  final bool ascending;
  final List<ProductSalesRow> sortedProducts;
  final List<PosLinePoint> salesPoints;
  final String? chartSemantics;
  final String? chartEmphasis;
  final FinancialStatement? statement;
  final double bottomInset;
  final VoidCallback? onOpenPortfolio;
  final void Function(ProductSalesRow)? onProductTap;
  final bool showPortfolioLink;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);

    return AnalyticsScaffold(
      range: range,
      onRangeChanged: onRangeChanged,
      snapshot: snapshot,
      onRetry: onRetry,
      onSortBy: onSortBy,
      sort: sort,
      ascending: ascending,
      sortedProducts: sortedProducts,
      salesPoints: salesPoints,
      chartSemantics: chartSemantics,
      chartEmphasis: chartEmphasis,
      bottomInset: bottomInset,
      onOpenPortfolio: onOpenPortfolio,
      onProductTap: onProductTap,
      showPortfolioLink: showPortfolioLink,
      title: l10n.navAnalytics,
      statement: statement,
      children: standardAnalyticsSections(
        context: context,
        shown: snapshot,
        range: range,
        chartSemantics: chartSemantics,
        chartEmphasis: chartEmphasis,
        statement: statement,
        salesPoints: salesPoints,
        sortedProducts: sortedProducts,
        sort: sort,
        ascending: ascending,
        onSortBy: onSortBy,
        onProductTap: onProductTap,
        spacing: spacing,
        l10n: l10n,
        colors: colors,
      ),
    );
  }
}
