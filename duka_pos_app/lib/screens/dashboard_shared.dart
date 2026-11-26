// Shared dashboard widgets used by every profile's dashboard screen.
//
// Each profile (drinks, duka, fashion, open) gets its own screen file, but the
// common building blocks — the compact header, the financial hero, the
// supporting metrics, the quick-action chip — live here so there is one
// component language across profiles.

import 'package:material_ui/material_ui.dart';
import 'package:flutter/physics.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../profile/shop_profile.dart';
import '../services/analytics.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
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
    this.drinksAnalytics = DrinksAnalyticsSnapshot.empty,
    this.paymentMix = const <PaymentMixRow>[],
    this.openCostPoolCount = 0,
    this.openCostInvestedMinor = 0,
    this.openCostRecoveredMinor = 0,
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

  final Shift? openShift;
  final Money expectedTill;
  final int creditOwedMinor;
  final int creditCustomerCount;
  final List<Product> tanks;
  final Map<int, ProductSalesRow> tankSales;
  final int totalProducts;
  final int outOfStockCount;
  final Money stockValue;
  final DrinksAnalyticsSnapshot drinksAnalytics;
  final List<PaymentMixRow> paymentMix;
  final int openCostPoolCount;
  final int openCostInvestedMinor;
  final int openCostRecoveredMinor;
}

List<Widget> spaced(List<Widget?> children, double gap) {
  return children.whereType<Widget>().expand((Widget child) {
    return <Widget>[child, SizedBox(height: gap)];
  }).toList()
    ..removeLast();
}

/// Profile-specific primary actions share one horizontally scrollable row.
class DashboardQuickActionStrip extends StatelessWidget {
  const DashboardQuickActionStrip({required this.actions, super.key});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double textScale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1, 2).toDouble();

    return Semantics(
      container: true,
      label: l10n.dashboardQuickActions,
      child: SizedBox(
        height: 56 * textScale,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(vertical: spacing.xxs),
          itemCount: actions.length,
          separatorBuilder: (_, __) => SizedBox(width: spacing.sm),
          itemBuilder: (_, int index) => actions[index],
        ),
      ),
    );
  }
}

/// Compact business header: identity, status, date, and the business switch.
///
/// No large logo, no giant greeting, no oversized top padding.
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

    return SurfaceCard(
      padding: PageGutter.card(context),
      accentEdge: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.dashboardNetSalesToday,
                  style: AppTypography.of(context).labelMedium?.copyWith(
                        color: colors.accent,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
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
            label: '${l10n.dashboardSalesLabel}: ${formatMoney(totals.total)}',
            child: ExcludeSemantics(
              child: Text(
                formatMoney(totals.total),
                style: AppTypography.money(
                  context,
                  size: 40,
                  weight: FontWeight.w800,
                ).copyWith(color: colors.onSurface),
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
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: spacing.lg),
          Semantics(
            button: true,
            label: '${l10n.dashboardTransactionsLabel}: ${totals.transactions}',
            child: InkWell(
              onTap: onTransactions,
              child: Padding(
                padding: PageGutter.card(context),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.receipt_long_outlined,
                        size: 18, color: colors.onSurfaceMuted),
                    SizedBox(width: spacing.md),
                    Expanded(
                      child: Text(
                        l10n.dashboardTransactionsLabel,
                        style: AppTypography.of(context)
                            .bodyMedium
                            ?.copyWith(color: colors.onSurface),
                      ),
                    ),
                    SizedBox(width: spacing.md),
                    Text(
                      '${totals.transactions}',
                      style: AppTypography.money(
                        context,
                        size: 18,
                        weight: FontWeight.w700,
                      ).copyWith(color: colors.onSurface),
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
            children: tiles
                .map((t) => SizedBox(
                    width: ((constraints.maxWidth - spacing.lg) / 2)
                        .clamp(120.0, double.infinity),
                    child: t))
                .toList(),
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
      child: Padding(
        padding: EdgeInsets.all(spacing.md),
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

/// Truthful shift status chip for the business header.
///
/// Never infers state from the time of day or from whether the dashboard
/// loaded. Reads the authoritative [Shift] status instead.
class _ShiftStateChip extends StatelessWidget {
  const _ShiftStateChip({required this.shift});

  final Shift? shift;

  @override
  Widget build(BuildContext context) {
    final Shift? s = shift;
    if (s == null) return const SizedBox.shrink();

    final bool open = s.status == 'open';
    return StatusChip(
      tone: open ? StatusTone.success : StatusTone.neutral,
      text: open ? 'Open' : 'Closed',
    );
  }
}

/// Reads localisations without holding a [BuildContext] across an await.

double dashboardTextScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.5).toDouble();

int dashboardGridColumns({
  required double availableWidth,
  required double textScale,
  required double minCellWidth,
  int maxColumns = 4,
  double gap = 12,
}) {
  final double requiredCellWidth = minCellWidth * textScale;
  final int count =
      ((availableWidth + gap) / (requiredCellWidth + gap)).floor();
  return count.clamp(1, maxColumns).toInt();
}

bool dashboardCanUseTwoColumns({
  required double availableWidth,
  required double textScale,
}) =>
    availableWidth >= 840 && textScale <= 1.25;

// ---------------------------------------------------------------------------
// New shared dashboard components (v79 redesign)
// ---------------------------------------------------------------------------

enum DashboardKpiTone { neutral, positive, expense, pending, info }

class DashboardKpiData {
  const DashboardKpiData({
    required this.label,
    required this.value,
    required this.icon,
    this.tone = DashboardKpiTone.neutral,
    this.onTap,
    this.semanticsLabel,
  });

  final String label;
  final String value;
  final IconData icon;
  final DashboardKpiTone tone;
  final VoidCallback? onTap;
  final String? semanticsLabel;
}

class DashboardKpiCard extends StatelessWidget {
  const DashboardKpiCard({required this.data, super.key});

  final DashboardKpiData data;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final (Color fg, Color bg) = switch (data.tone) {
      DashboardKpiTone.positive => (colors.success, colors.successContainer),
      DashboardKpiTone.expense => (colors.danger, colors.dangerContainer),
      DashboardKpiTone.pending => (colors.warning, colors.warningContainer),
      DashboardKpiTone.info => (colors.info, colors.infoContainer),
      DashboardKpiTone.neutral => (colors.onSurface, colors.surfaceSunken),
    };
    final Widget card = SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, size: 20, color: fg),
          ),
          SizedBox(height: spacing.sm),
          Text(
            data.label,
            style: AppTypography.of(context)
                .labelMedium
                ?.copyWith(color: colors.onSurfaceMuted),
            softWrap: true,
          ),
          SizedBox(height: spacing.xs),
          _AnimatedDashboardText(
            value: data.value,
            style: AppTypography.money(
              context,
              size: 18,
              weight: FontWeight.w700,
            ).copyWith(color: fg),
          ),
        ],
      ),
    );

    if (data.onTap == null) {
      return Semantics(
        label: data.semanticsLabel ?? '${data.label}: ${data.value}',
        child: card,
      );
    }
    return Semantics(
      button: true,
      label: data.semanticsLabel ?? '${data.label}: ${data.value}',
      child: _DashboardPressable(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(spacing.md + 4),
        child: card,
      ),
    );
  }
}

/// A small physical response for dashboard doors.
///
/// The scale is deliberately restrained: the card follows the press without
/// becoming a toy. A spring starts from the controller's current value, so a
/// quick press/release is interruptible instead of snapping between two
/// scripted animations. Reduced-motion users receive the same immediate state
/// change with no animated travel.
class _DashboardPressable extends StatefulWidget {
  const _DashboardPressable({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  @override
  State<_DashboardPressable> createState() => _DashboardPressableState();
}

/// Changes in dashboard figures crossfade and travel a few pixels upward. The
/// key is the committed display value, so a refresh that returns the same value
/// remains visually quiet.
class _AnimatedDashboardText extends StatelessWidget {
  const _AnimatedDashboardText({required this.value, required this.style});

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final AppMotion motion = AppMotion.of(context);
    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, motion.fast),
      switchInCurve: AppMotion.resolveCurve(context, motion.enter),
      switchOutCurve: AppMotion.resolveCurve(context, motion.exit),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(
        value,
        key: ValueKey<String>(value),
        style: style,
        softWrap: true,
      ),
    );
  }
}

class _DashboardPressableState extends State<_DashboardPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 1,
    value: 0,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _settle(double target) {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = target;
      return;
    }
    final SpringDescription spring = SpringDescription(
      mass: 1,
      stiffness: 520,
      damping: 38,
    );
    _controller.animateWith(
      SpringSimulation(spring, _controller.value, target, _controller.velocity),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: widget.borderRadius,
      onTapDown: (_) => _settle(1),
      onTapUp: (_) => _settle(0),
      onTapCancel: () => _settle(0),
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (BuildContext context, Widget? child) {
          return Transform.scale(
            scale: 1 - (_controller.value * 0.025),
            child: child,
          );
        },
      ),
    );
  }
}

class DashboardKpiGrid extends StatelessWidget {
  const DashboardKpiGrid({required this.items, super.key});

  final List<DashboardKpiData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double ts = dashboardTextScale(context);
        final int cols = dashboardGridColumns(
          availableWidth: constraints.maxWidth,
          textScale: ts,
          minCellWidth: 150,
          maxColumns: 4,
        );
        final double gap = 12;
        final double cellWidth =
            (constraints.maxWidth - (cols - 1) * gap) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map((DashboardKpiData d) => SizedBox(
                    width: cellWidth,
                    child: DashboardKpiCard(data: d),
                  ))
              .toList(),
        );
      },
    );
  }
}

class DashboardBusinessHeader extends StatelessWidget {
  const DashboardBusinessHeader({
    required this.shopName,
    required this.profile,
    this.staffName,
    this.shift,
    this.onOpenPortfolio,
    this.showPortfolioLink = false,
    super.key,
  });

  final String shopName;
  final ShopProfile profile;
  final String? staffName;
  final Shift? shift;
  final VoidCallback? onOpenPortfolio;
  final bool showPortfolioLink;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  (staffName != null && staffName!.trim().isNotEmpty)
                      ? l10n.dashboardGreetingNamed(
                          timeOfDayWord(l10n), staffName!.trim())
                      : l10n.dashboardGreetingAnonymous(timeOfDayWord(l10n)),
                  style: AppTypography.of(context).headlineSmall?.copyWith(
                        color: AppColors.of(context).onSurface,
                      ),
                  softWrap: true,
                ),
                SizedBox(height: spacing.xs),
                Text(
                  shopName,
                  style: AppTypography.of(context)
                      .bodySmall
                      ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: spacing.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: spacing.sm,
          runSpacing: spacing.xs,
          children: <Widget>[
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: spacing.sm, vertical: spacing.xs),
              decoration: BoxDecoration(
                color: colors.accentContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.storefront_outlined,
                    size: 14,
                    color: colors.onAccentContainer,
                  ),
                  SizedBox(width: spacing.xs),
                  Text(
                    profile.displayName.toUpperCase(),
                    style: AppTypography.of(context).labelSmall?.copyWith(
                        color: colors.onAccentContainer,
                        fontWeight: FontWeight.w700,
                      ),
                  ),
                ],
              ),
            ),
            _ShiftStateChip(shift: shift),
            Text(
              formatted,
              style: AppTypography.of(context)
                  .bodySmall
                  ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
            ),
            if (showPortfolioLink && onOpenPortfolio != null)
              ActionChip(
                avatar: const Icon(Icons.insights_outlined, size: 16),
                label: const Text('Portfolio'),
                onPressed: onOpenPortfolio,
              ),
          ],
        ),
        SizedBox(height: spacing.lg),
      ],
    );
  }
}

class DashboardMoneyHero extends StatelessWidget {
  const DashboardMoneyHero({
    required this.profile,
    required this.label,
    required this.amount,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    this.secondaryLine,
    this.scopeLabel,
    this.paymentMix = const <PaymentMixRow>[],
    this.onTransactions,
    super.key,
  });

  final ShopProfile profile;
  final String label;
  final Money amount;
  final String primaryActionLabel;
  final VoidCallback onPrimaryAction;
  final String? secondaryLine;
  final String? scopeLabel;
  final List<PaymentMixRow> paymentMix;
  final VoidCallback? onTransactions;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double ts = dashboardTextScale(context);
        final bool stackAction = constraints.maxWidth < 420 || ts > 1.25;
        return SurfaceCard(
          padding: PageGutter.card(context),
          accentEdge: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.of(context).labelMedium?.copyWith(
                            color: colors.accent,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                    ),
                  ),
                  if (secondaryLine != null)
                    Text(
                      secondaryLine!,
                      style: AppTypography.of(context)
                          .labelSmall
                          ?.copyWith(color: colors.onSurfaceMuted),
                    ),
                ],
              ),
              SizedBox(height: spacing.xs),
              if (stackAction)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Semantics(
                      label: '$label: ${formatMoney(amount)}',
                      child: _AnimatedDashboardText(
                        value: formatMoney(amount),
                        style: AppTypography.money(
                          context,
                          size: 40,
                          weight: FontWeight.w800,
                        ).copyWith(color: colors.onSurface),
                      ),
                    ),
                    SizedBox(height: spacing.sm),
                    FilledButton(
                      onPressed: onPrimaryAction,
                      child: Text(primaryActionLabel),
                    ),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: Semantics(
                        label: '$label: ${formatMoney(amount)}',
                        child: _AnimatedDashboardText(
                          value: formatMoney(amount),
                          style: AppTypography.money(
                            context,
                            size: 40,
                            weight: FontWeight.w800,
                          ).copyWith(color: colors.onSurface),
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: onPrimaryAction,
                      child: Text(primaryActionLabel),
                    ),
                  ],
                ),
              if (scopeLabel != null) ...<Widget>[
                SizedBox(height: spacing.xs),
                Text(
                  scopeLabel!,
                  style: AppTypography.of(context)
                      .bodySmall
                      ?.copyWith(color: colors.onSurfaceMuted),
                ),
              ],
              if (paymentMix.isNotEmpty) ...<Widget>[
                SizedBox(height: spacing.sm),
                Wrap(
                  spacing: spacing.xs,
                  runSpacing: spacing.xs,
                  children: paymentMix
                      .map((PaymentMixRow row) => Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: spacing.sm,
                              vertical: spacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceSunken,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${row.label(l10n: l10n)} ${formatMoney(row.sales)}',
                              style: AppTypography.of(context)
                                  .labelSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ))
                      .toList(),
                ),
              ],
              if (onTransactions != null) ...<Widget>[
                SizedBox(height: spacing.sm),
                InkWell(
                  onTap: onTransactions,
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.receipt_long_outlined,
                          size: 18, color: colors.onSurfaceMuted),
                      SizedBox(width: spacing.xs),
                      Text(
                        l10n.dashboardTransactionsLabel,
                        style: AppTypography.of(context)
                            .bodySmall
                            ?.copyWith(color: colors.onSurface),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

String _headerDate(AppLocalizations l10n) {
  final now = DateTime.now();
  final dayOfWeek = DateFormat.EEEE(l10n.localeName).format(now);
  final month = DateFormat.MMMM(l10n.localeName).format(now);
  return '$dayOfWeek · ${now.day} $month';
}
