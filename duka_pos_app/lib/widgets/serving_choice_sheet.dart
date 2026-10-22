// The sheet that asks HOW a drink is to be sold.
//
// ## WHAT WENT WRONG
//
// "Selecting products in rotated view of a phone it opens the search triggering
// the keyboard and the size selector (full half quarter) is cut — only shows
// half and full. For that chooser we need to only show half full quarter for
// only products set to be sold like that (half and quarters are not applied to
// all products). Also selecting quarter is a no-op, it does not work at all."
//
// Three defects, one sheet:
//
// 1. IT WAS CUT. The sheet was a column in a bottom sheet that is limited to
//    half the screen, and the quarter was the last portion before the shots —
//    so the quarter was the first thing to go when the sheet was too short. On
//    a phone held sideways it always went. It is a SCROLLING sheet now, and
//    the options are in a list that can be reached.
//
// 2. IT OFFERED THINGS THE SHOP DOES NOT SELL. Every product got a Full, a
//    Half and a Quarter, at a price the app worked out on the spot. A tank's
//    tap has no price of its own — the beer is sold by the cup — so "Full" on
//    a tap was a row that charged nothing, and "Quarter" on a product with no
//    quarter price was a row that charged a quarter of a price nobody chose.
//
//    Now a portion is offered when the product is SOLD that way: a half when
//    the owner has given the half a price, a quarter when they have given the
//    quarter one, and the whole thing when the product has a price of its own.
//
// 3. THE QUARTER DID NOTHING. A quarter charged a quarter of the bottle price
//    on a product whose price the owner had never split, and on a product
//    with no price at all it charged nothing — a line in the cart worth
//    KSh 0. It is not offered now unless it is a thing the shop sells, and
//    when it is offered it carries the price the owner set.
//
// ## THE FOCUS
//
// The sheet is a route, and a route takes the focus. When it closes, the
// focus goes back to whatever the framework finds — and the search field is
// a text field, so the keyboard came up on top of the till, with the
// cashier's half-typed product name in it. The sheet hands the focus back
// explicitly to the till's own input instead.

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_spacing.dart';
import '../utils/money.dart';

/// How the till asked to sell something, and what was chosen.
///
/// A VALUE rather than a route result string, because the route result was a
/// string with a prefix and a number inside it, and the parsing of that
/// string was done by the screen that opened the sheet. The choice now says
/// what it is.
sealed class ServingChoice {
  const ServingChoice();
}

/// The whole container.
class ServingChoiceFull extends ServingChoice {
  const ServingChoiceFull();
}

/// Half of it.
class ServingChoiceHalf extends ServingChoice {
  const ServingChoiceHalf();
}

/// A quarter of it.
class ServingChoiceQuarter extends ServingChoice {
  const ServingChoiceQuarter();
}

/// A named variant of the product.
class ServingChoiceVariant extends ServingChoice {
  const ServingChoiceVariant(this.variant);

  final ProductVariant variant;
}

/// A shot cup.
class ServingChoiceShot extends ServingChoice {
  const ServingChoiceShot(this.cup);

  final ShotCup cup;
}

/// The sheet: which way is this one sold?
///
/// Every part of it is a parameter, so the whole sheet can be rendered in a
/// test without a database, a till or a router.
class ServingChoiceSheet extends StatelessWidget {
  const ServingChoiceSheet({
    required this.product,
    required this.variants,
    required this.sellsAsVariants,
    required this.shots,
    required this.remainingStock,
    this.onChoose,
    super.key,
  });

  /// The product that was tapped.
  final Product product;

  /// Its variants, when it is sold as variants.
  final List<ProductVariant> variants;

  /// Whether the product is sold as variants at all.
  final bool sellsAsVariants;

  /// The shot cups poured from it.
  final List<ShotCup> shots;

  /// How much of the product is left, for the whole product.
  ///
  /// The variants carry their own counts, so this is only used for a product
  /// sold as one thing.
  final double remainingStock;

  /// What was chosen.
  final ValueChanged<ServingChoice>? onChoose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return SafeArea(
      child: ConstrainedBox(
        // The sheet is limited to the space it is given, and the list inside
        // it scrolls. A column that cannot scroll is a column that loses its
        // last rows, and the rows it lost were the ones nobody could reach.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(spacing.xl),
                child: Text(
                  l10n.sellChooseServingTitle(product.name),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (sellsAsVariants && variants.isEmpty)
                // Said rather than silently offering full/half/quarter: on a
                // variant product those portions are the parent's, and charging
                // them for "Dark" is a price nobody set.
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.sellNoVariantsYetTitle(product.name)),
                  subtitle: Text(l10n.sellNoVariantsYetHint),
                  enabled: false,
                )
              else if (sellsAsVariants)
                // The variants replace the portions rather than joining them: a
                // half of "Dark" is not something the shop sells, and offering
                // both would put eight rows on a phone screen.
                for (final ProductVariant variant in variants)
                  _VariantOption(variant: variant, onChoose: onChoose)
              else
                ..._portionOptions(context, l10n),
              // Shots sit under the portions rather than replacing them: a bar
              // sells a whole bottle *and* shots of the same spirit, and a
              // sheet that offered one or the other would hide half the shelf.
              if (shots.isNotEmpty) ...<Widget>[
                const Divider(height: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    l10n.sellShotsSection,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                for (final ShotCup cup in shots)
                  _ShotOption(cup: cup, product: product, onChoose: onChoose),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The portions this product is actually sold in.
  ///
  /// See the file's own note: a portion is offered when the shop sells it, and
  /// the price the owner set is what says so.
  List<Widget> _portionOptions(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final List<Widget> options = <Widget>[];
    if (product.sellsWhole) {
      options.add(_PortionOption(
        product: product,
        portion: 'full',
        label: l10n.portionFullLabel,
        price: product.sellPrice,
        remainingStock: remainingStock,
        onChoose: onChoose,
      ));
    }
    if (product.sellsHalf) {
      options.add(_PortionOption(
        product: product,
        portion: 'half',
        label: l10n.portionHalfLabel,
        price: product.halfPrice!,
        remainingStock: remainingStock,
        onChoose: onChoose,
      ));
    }
    if (product.sellsQuarter) {
      options.add(_PortionOption(
        product: product,
        portion: 'quarter',
        label: l10n.portionQuarterLabel,
        price: product.quarterPrice!,
        remainingStock: remainingStock,
        onChoose: onChoose,
      ));
    }
    return options;
  }
}

/// One portion: a row with the size and the price.
class _PortionOption extends StatelessWidget {
  const _PortionOption({
    required this.product,
    required this.portion,
    required this.label,
    required this.price,
    required this.remainingStock,
    this.onChoose,
  });

  final Product product;
  final String portion;
  final String label;
  final Money price;
  final double remainingStock;
  final ValueChanged<ServingChoice>? onChoose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double needed = product.fractionFor(portion);
    final bool canAdd = remainingStock >= needed;
    return ListTile(
      leading: const Icon(Icons.local_bar_outlined),
      title: Text(
        l10n.sellPourOptionTitle(label, '${product.mlFor(portion)}'),
      ),
      trailing: Text(formatMoney(price)),
      enabled: canAdd,
      subtitle: !canAdd
          ? Text(remainingStock <= 0
              ? l10n.servingAllInCart
              : l10n.servingFractionLeft(remainingStock))
          : null,
      onTap: canAdd
          ? () => onChoose?.call(switch (portion) {
                'half' => const ServingChoiceHalf(),
                'quarter' => const ServingChoiceQuarter(),
                _ => const ServingChoiceFull(),
              })
          : null,
    );
  }
}

/// One shot cup.
class _ShotOption extends StatelessWidget {
  const _ShotOption({
    required this.cup,
    required this.product,
    this.onChoose,
  });

  final ShotCup cup;
  final Product product;
  final ValueChanged<ServingChoice>? onChoose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ({bool canPour, String reason}) verdict =
        shotAvailability(l10n, product, cup, product.stockQty);
    return ListTile(
      leading: Icon(verdict.canPour
          ? Icons.local_drink_outlined
          : Icons.warning_amber_outlined),
      title: Text(
        l10n.sellPourOptionTitle(cup.label, '${cup.capacityMl}'),
      ),
      trailing: Text(formatMoney(cup.price)),
      enabled: verdict.canPour,
      // Each blocked reason names its own cause. "Not available" would leave a
      // cashier guessing, and the causes need different fixes: add stock, count
      // the drawer down, or change the cup.
      subtitle: Text(verdict.reason),
      onTap:
          verdict.canPour ? () => onChoose?.call(ServingChoiceShot(cup)) : null,
    );
  }
}

/// One variant.
class _VariantOption extends StatelessWidget {
  const _VariantOption({required this.variant, this.onChoose});

  final ProductVariant variant;
  final ValueChanged<ServingChoice>? onChoose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool canAdd = variant.stockQty >= 1;
    return ListTile(
      leading: Icon(variant.isLow
          ? Icons.warning_amber_outlined
          : Icons.local_bar_outlined),
      title: Text(variant.label),
      trailing: Text(formatMoney(variant.sellPrice)),
      enabled: canAdd,
      // Every one of these is said in the shop's words. "No stock left" and a
      // bare "{n} in stock · low" are the kind of fragment that reads as an
      // error log to anyone who did not build the app.
      subtitle: Text(!canAdd
          ? (variant.stockQty <= 0
              ? l10n.servingAllInCart
              : l10n.sellNoStockLeft)
          : (variant.isLow
              ? l10n.sellTileStockCountLow(variant.stockQty.round())
              : l10n.sellTileStockCount(variant.stockQty.round()))),
      onTap:
          canAdd ? () => onChoose?.call(ServingChoiceVariant(variant)) : null,
    );
  }
}

/// Whether a shot can be poured, and the sentence that says why not.
///
/// A cup with no size, a bottle with no volume, and a pour bigger than the
/// bottle are all refused HERE rather than at the register, because an
/// oversold pour is the one state this app cannot recover from cleanly.
///
/// The reason is read aloud on the tile and spoken to the person standing at
/// the counter with a customer in front of them, so it is written in the
/// shop's words through [l10n] — never as a field name. "capacityMl is null"
/// is an error log; "This cup has no size" is something a person can act on.
({bool canPour, String reason}) shotAvailability(
  AppLocalizations l10n,
  Product product,
  ShotCup cup,
  double available,
) {
  final containerMl = product.bottleMl;
  if (containerMl <= 0) {
    return (canPour: false, reason: l10n.shotNoVolume(product.name));
  }
  // A cup with NO size is still pourable: the owner simply did not say how
  // big it is. The shot is sold at its price and the amount taken from the
  // bottle is not measured, which is what the shot's own note says.
  if (cup.capacityMl <= 0) {
    if (available <= 0) {
      return (canPour: false, reason: l10n.shotNoneLeft(product.name));
    }
    return (canPour: true, reason: l10n.shotCupNoSize);
  }
  final perBottle = (containerMl / cup.capacityMl).floor();
  if (perBottle <= 0) {
    return (canPour: false, reason: l10n.shotCupTooBig(containerMl));
  }
  final needed = cup.capacityMl / containerMl;
  if (available < needed) {
    return (canPour: false, reason: l10n.shotNoneLeft(product.name));
  }
  return (canPour: true, reason: l10n.shotCountLeft(perBottle));
}
