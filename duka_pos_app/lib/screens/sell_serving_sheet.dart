// "Which one?"
//
// The one decision a product cannot answer for itself. A bottle can be sold
// whole, in halves or in quarters; a variant product has to be picked by name
// from its own list, because "Kenyana Beer" is not a price; and a spirit can be
// poured into a cup in several sizes, each with its own price and its own
// divisibility.
//
// Every reason a row cannot be chosen is spelled out here, in the shop's own
// terms — "The cup is bigger than the 200 ml bottle" rather than "not
// available" — because a blocked row tells the cashier what to change, and that
// changes between the three reasons: use a different cup, add stock, or count
// the drawer down.

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import '../widgets/variant_catalogue.dart';

/// How much of the window the sheet may take.
///
/// A shelf with six shots and a keg with three dozen shot sizes are very
/// different sheets. This leaves the bottom 20% free so the sheet reads as
/// something that came up over the till rather than as a new screen.
const double _kSheetHeightFraction = 0.8;

/// Marks a choice as "this variant", as opposed to a portion or a shot cup.
const String kVariantChoicePrefix = 'v:';

/// Marks a choice as "this shot cup", by its database id.
const String kShotChoicePrefix = 's:';

/// The fraction of one container a cart already holds, or null when none is held.
///
/// Used by the sheet's shot rows. Cart reservations are per product, not per
/// line: two lines of "AAA Vodka · Shot" reserve one pool, and computing it per
/// line would let the sheet promise a pour the second line will not honour.
typedef Reservation = double?;

/// How many shots are left in a container, and whether one can be poured.
///
/// The verdict is a pair rather than a bool because the two states need
/// different answers: a bottle holding "25 shots in the bottle" is pourable and
/// the cashier should know the count; a bottle with less than one shot left is
/// not, and saying "25 shots in the bottle" there would be plainly wrong.
({bool canPour, String reason}) shotAvailability(
  Product product,
  ShotCup cup,
  double remainingMl,
) {
  if (product.bottleMl <= 0) {
    return (canPour: false, reason: '${product.name} has no volume set');
  }
  if (remainingMl < 1) {
    return (
      canPour: false,
      reason: 'No ${product.name} left to pour',
    );
  }
  if (cup.capacityMl > product.bottleMl) {
    return (
      canPour: false,
      reason: 'The cup is bigger than the ${product.bottleMl} ml bottle',
    );
  }
  final int shots = (remainingMl / cup.capacityMl).floor();
  if (shots < 1) {
    return (
      canPour: false,
      reason: 'No ${product.name} left to pour',
    );
  }
  return (canPour: true, reason: '$shots shots in the bottle');
}

/// Shows the serving choices for [product] and returns the one picked.
///
/// Returns null when dismissed. The result is a string rather than a typed
/// choice because it crosses a route boundary, and it is prefixed so the caller
/// can tell "variant 4" from "shot cup 9" without a second channel.
Future<String?> showServingSheet(
  BuildContext context, {
  required Product product,
  required VariantCatalogue variants,
  required List<ShotCup> shots,
  required double Function(ProductVariant variant) variantUnitsLeft,
  required Reservation Function(Product product) productReserved,
}) {
  return showModalBottomSheet<String>(
    context: context,
    // Root, so the sheet covers the till's own chrome rather than stopping at
    // the shell's navigation rail and leaving half the screen live underneath.
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      final List<ProductVariant> available = variants.of(product);
      final Reservation reservation = productReserved(product);

      final List<Widget> rows = <Widget>[];

      if (variants.sellsAsVariants(product)) {
        if (available.isEmpty) {
          rows.add(
            const _UnavailableNotice(
              text: 'This product has no variants yet',
            ),
          );
        } else {
          for (final ProductVariant variant in available) {
            final double left = variantUnitsLeft(variant);
            final bool canAdd = left > 0;
            rows.add(
              ServingOptionRow(
                icon: Icons.local_bar,
                title: variant.label,
                price: formatMoney(variant.sellPrice),
                canAdd: canAdd,
                tone: canAdd
                    ? (variant.isLow ? StatusTone.warning : StatusTone.success)
                    : StatusTone.danger,
                reason: left < 0
                    ? '${_qtyLabel(variant.stockQty)} in stock · already in cart'
                    : canAdd
                        ? variant.isLow
                            ? '${_qtyLabel(variant.stockQty)} in stock · low'
                            : '${_qtyLabel(variant.stockQty)} in stock'
                        : 'No stock left',
                onTap: () => Navigator.pop(
                  sheetContext,
                  '$kVariantChoicePrefix${variant.id}',
                ),
              ),
            );
          }
        }
      } else {
        for (final String portion in const <String>[
          'full',
          'half',
          'quarter'
        ]) {
          final bool hasSize =
              product.unit == ProductUnit.each ? product.bottleMl > 0 : true;
          final double sizeMl = hasSize ? product.mlFor(portion).toDouble() : 0;
          // Availability is the container's remaining stock, not this
          // portion's: a half can be poured from a bottle that cannot supply
          // two halves, because the bottle is counted in fractions of itself.
          final double left = (product.unit == ProductUnit.each
                  ? product.stockQty
                  : product.stockQty * 1000) -
              (reservation ?? 0);
          final bool canAdd = left > 0;
          rows.add(
            ServingOptionRow(
              icon: Icons.local_drink_outlined,
              title:
                  hasSize ? '$portion · ${_mlLabel(sizeMl.toInt())}' : portion,
              price: formatMoney(product.priceFor(portion)),
              canAdd: canAdd,
              tone: canAdd ? StatusTone.success : StatusTone.danger,
              reason: canAdd
                  ? ''
                  : left < 0
                      ? 'All stock for this product is already in the cart'
                      : 'No stock left',
              onTap: () => Navigator.pop(sheetContext, portion),
            ),
          );
        }
      }

      if (shots.isNotEmpty) {
        rows.add(const _SheetSectionLabel('Shots'));
        for (final ShotCup cup in shots) {
          final ({bool canPour, String reason}) verdict = shotAvailability(
            product,
            cup,
            (product.stockQty - (reservation ?? 0)) * 1000,
          );
          rows.add(
            ServingOptionRow(
              icon: Icons.local_drink,
              title: cup.label,
              price: formatMoney(cup.price),
              canAdd: verdict.canPour,
              tone: verdict.canPour ? StatusTone.success : StatusTone.danger,
              reason: verdict.reason,
              onTap: () => Navigator.pop(
                sheetContext,
                '$kShotChoicePrefix${cup.id}',
              ),
            ),
          );
        }
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(sheetContext).height * _kSheetHeightFraction,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _SheetHeader(title: product.name),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: rows.length,
                  itemBuilder: (BuildContext context, int index) => rows[index],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The sheet's title: what the cashier is being asked to choose for.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.lg,
        end: spacing.sm,
        top: spacing.xs,
        bottom: spacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Choose serving · $title',
                style: type.titleMedium,
              ),
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).sellCloseSheetTooltip,
            onPressed: () => Navigator.pop(context),
            icon: const ExcludeSemantics(child: Icon(Icons.close)),
          ),
        ],
      ),
    );
  }
}

/// A divider between the portions and the shots.
class _SheetSectionLabel extends StatelessWidget {
  const _SheetSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.lg,
        end: spacing.lg,
        top: spacing.md,
        bottom: spacing.xs,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
        ),
      ),
    );
  }
}

/// One serving: what it is, what it costs, and whether it can be chosen.
///
/// The reason is the original wording, kept exactly. It is also the only
/// non-colour channel carrying the state here — which is why it is a sentence
/// rather than a tint: "No stock left" and "The cup is bigger than the 200 ml
/// bottle" are the two things a blocked shot row has to be able to say, and they
/// point at two completely different fixes.
class ServingOptionRow extends StatelessWidget {
  const ServingOptionRow({
    required this.icon,
    required this.title,
    required this.price,
    required this.canAdd,
    required this.tone,
    required this.reason,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String price;
  final bool canAdd;
  final StatusTone tone;

  /// Empty when there is nothing to add to the name.
  final String reason;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final Color reasonColor = StatusTone.success.color(colors);

    return Semantics(
      button: canAdd,
      // One node: the name, the price, and — when the option cannot be added —
      // why not. Three separate nodes would let a listener hear "Double, KSh 150"
      // and stop before hearing the reason it is unavailable.
      label: canAdd
          ? AppLocalizations.of(context).sellServingOptionTitle(title, price)
          : AppLocalizations.of(context)
              .sellServingOptionTitleWithReason(title, price, reason),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outline)),
        ),
        child: InkWell(
          onTap: canAdd ? onTap : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: spacing.minTapTarget),
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: spacing.lg,
                vertical: spacing.md,
              ),
              child: Row(
                children: <Widget>[
                  // Decorative: the reason beside it says the same thing in
                  // words, and an icon alone is silence to a screen reader.
                  ExcludeSemantics(
                    child: Icon(
                      icon,
                      color: reasonColor,
                      size: spacing.xl,
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: type.bodyLarge),
                        if (reason.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: spacing.xs),
                            child: Text(
                              reason,
                              style: type.bodySmall?.copyWith(
                                color: reasonColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  MoneyText(
                    amount: price,
                    size: type.titleMedium!.fontSize!,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that is not a choice at all.
///
/// "This product has no variants yet" is a fact about the catalogue, not a
/// reason a row is disabled, so it is not a button and says nothing about stock.
class _UnavailableNotice extends StatelessWidget {
  const _UnavailableNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: spacing.lg,
          vertical: spacing.md,
        ),
        child: Text(
          text,
          style: type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
        ),
      ),
    );
  }
}

/// A quantity as the owner reads it: no trailing `.0`, halves kept as halves.
///
/// Inventory is a `double` because a 0.25 cup is a real thing, but "1.0 in
/// stock" on a tile looks like a bug.
String _qtyLabel(double qty) {
  if (qty == qty.truncateToDouble()) return qty.toStringAsFixed(0);
  final double capped = qty > 100 ? 100 : qty;
  return capped.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

/// A volume, in whole millilitres, the way the rest of the app states one.
String _mlLabel(int ml) => '$ml ml';
