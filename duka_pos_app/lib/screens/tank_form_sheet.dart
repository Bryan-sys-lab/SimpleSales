/// A tank of beer: stocked by weight, poured by the cup.
///
/// Why this is a form of its own and not another option on the product editor:
/// a tank is not a product with a different unit, it is a different SHAPE of
/// thing. Its stock arrives on a scale in kilograms, its capacity is in litres,
/// what it holds is two named taps that are poured and priced separately, and
/// not one of those numbers is the number a bottle's form asks for. Forcing all
/// of it through the bottle editor is how a 50-kg tank ends up typed into a
/// field labelled "750".
///
/// What it writes is ordinary catalogue, deliberately:
///
///   * one `products` row, `unit = kilogram`, whose `bottle_ml` is the tank's
///     capacity in millilitres and whose `ml_per_kg` converts the weight;
///   * two `product_variants` rows — Dark and Regular — which is how the two
///     taps get their own price, their own stock count, and their own line on a
///     receipt, and how the till's variant picker already works.
///
/// So the product, the variant machinery, the audit entries and the RESTORE path
/// all stay exactly what they were; only the way the numbers are typed in is new.
///
/// The two taps are variants of the tank rather than two products because they
/// are ONE body of beer: a delivery fills both, a stock count weighs both, and
/// two rows saying "Tusker" would be a stock count that disagrees with itself.
library;

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/home_shell.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../utils/money.dart';
import '../utils/units.dart';

/// The serving a tank's taps pour, in millilitres.
///
/// 330 — a standard beer serving — because a tap is poured into a cup of a
/// FIXED size even though the tank behind it is measured by weight. It lives
/// here rather than per product because "how big is a cup of this beer" is the
/// same number for every tank in every shop, and a second copy of it is a tank
/// whose two taps pour different amounts.
const int kTankCupCapacityMl = 330;

/// How many taps a tank has: dark and regular.
///
/// Two, and the count is a named constant because it is the divisor that turns a
/// tank into per-tap servings. A tank with three taps is then one number, not a
/// rewrite.
const int kTankTapCount = 2;

/// The ceiling on a millilitres-per-kilogram factor, in millilitres per kg.
///
/// 100 000 — a hundred litres to the kilogram — which is far above anything real
/// (honey is ~1.4, beer ~1, and even mercury is 13.6) and far below the point
/// where the arithmetic is the problem rather than the entry. A ceiling also
/// makes a mistyped extra zero a rejection instead of a tank that holds a
/// million cups.
const double kMaxMillilitresPerKilogram = 100000;

/// Opens the tank form.
///
/// Bottom sheet, not a route: it is one decision made once, and a route would
/// put it on the back stack of a shop that adds a tank a handful of times.
Future<void> showTankFormSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) => const TankFormSheet(),
  );
}

class TankFormSheet extends StatefulWidget {
  const TankFormSheet({super.key});

  @override
  State<TankFormSheet> createState() => _TankFormSheetState();
}

class _TankFormSheetState extends State<TankFormSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _weightKg = TextEditingController();
  final TextEditingController _capacityLitres = TextEditingController();
  final TextEditingController _mlPerKg = TextEditingController();
  final TextEditingController _cupPrice = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Beer, which is what the default is: a litre of lager weighs a kilogram.
    // Overridable because the next thing that arrives by weight may not be beer.
    _mlPerKg.text = defaultKilogramsToMillilitres.round().toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _weightKg.dispose();
    _capacityLitres.dispose();
    _mlPerKg.dispose();
    _cupPrice.dispose();
    super.dispose();
  }

  /// The weight on hand, or null when the field is not a number yet.
  double? get _weight {
    final text = _weightKg.text.trim();
    if (text.isEmpty) return null;
    return _finite(double.tryParse(text));
  }

  /// Non-finite answers null.
  ///
  /// `double.tryParse` happily accepts "NaN" and "Infinity", and a non-finite
  /// quantity is not a quantity: a NaN weight passes `>= 0` (every NaN compare is
  /// false), reaches the write, and stores a stock figure the till cannot sell
  /// from. One guard at the parse site, rather than a compare per caller.
  static double? _finite(double? value) =>
      value != null && value.isFinite ? value : null;

  /// The tank's capacity in litres, or null when not a number yet.
  double? get _capacity => _finite(double.tryParse(_capacityLitres.text.trim()));

  double? get _perKg {
    final text = _mlPerKg.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    // Finite, not merely positive: `double.tryParse` accepts "Infinity" and
    // "1e999", and a non-finite factor persisted into `ml_per_kg` is a stored
    // conversion no calculation can use — every helper then clamps it to 0 and
    // the tank silently holds nothing, while the row looks populated.
    if (value == null || !value.isFinite || value <= 0) return null;
    if (value > kMaxMillilitresPerKilogram) return null;
    return value;
  }

  double? get _price => _finite(double.tryParse(_cupPrice.text.trim()));

  /// The tank's capacity in millilitres, as [Product] stores it.
  ///
  /// Converted HERE, once, at the edge where a human typed a litre: everything
  /// below this line is a volumetric product and knows nothing about kilograms.
  int? get _capacityMl {
    final litres = _capacity;
    // Non-finite answers null, not a throw: `NaN < min` and `NaN > max` are BOTH
    // false, so an unguarded NaN would pass this compare and then take
    // `ml.round()` — which throws `UnsupportedError` for a non-finite receiver,
    // from a getter the save button calls OUTSIDE its own try.
    if (litres == null || !litres.isFinite) return null;
    final ml = litresToMillilitres(litres);
    if (ml < Product.minBottleMl || ml > Product.maxBottleMl) return null;
    return ml.round();
  }

  /// The litres the weight on hand works out to, for the live preview.
  double? get _weightAsLitres {
    final weight = _weight;
    final perKg = _perKg;
    if (weight == null || perKg == null) return null;
    return millilitresToLitres(
        kilogramsToMillilitres(weight, millilitresPerKilogram: perKg));
  }

  /// The whole tank as servings, which is what a variant's stock counts.
  ///
  /// ONE number, computed once and used for both taps, so the two halves are the
  /// same half by construction. A variant's `stock_qty` is whole CUPS everywhere
  /// else in the app — `VariantCatalogue.deductVariantStock` subtracts cup
  /// counts and `writeAggregateStock` sums them straight back into the parent's
  /// column — so a tap seeded in kilograms would read empty after a couple of
  /// dozen cups, and the tank's own aggregate would be kilograms plus cups.
  double get _cupsPerTap {
    final weight = _weight;
    final perKg = _perKg;
    if (weight == null || perKg == null) return 0;
    final double tankMl =
        kilogramsToMillilitres(weight, millilitresPerKilogram: perKg);
    return tankMl / kTankCupCapacityMl / kTankTapCount;
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _name.text.trim();
    final double? weight = _weight;
    final double? perKg = _perKg;
    final double? price = _price;
    final int? capacityMl = _capacityMl;

    if (name.isEmpty) {
      setState(() => _error = l10n.tankNameRequired);
      return;
    }
    if (weight == null || !weight.isFinite || weight < 0) {
      setState(() => _error = l10n.tankWeightInvalid);
      return;
    }
    if (perKg == null) {
      setState(() => _error = l10n.tankMlPerKgInvalid);
      return;
    }
    if (capacityMl == null) {
      setState(() => _error = l10n.tankCapacityInvalid);
      return;
    }
    if (price == null || !price.isFinite || price < 0) {
      setState(() => _error = l10n.tankPriceInvalid);
      return;
    }
    final double litresFromWeight = millilitresToLitres(
        kilogramsToMillilitres(weight, millilitresPerKilogram: perKg));
    if (litresFromWeight > millilitresToLitres(capacityMl)) {
      setState(() => _error = l10n.tankWeightOverCapacity(
            '${litresFromWeight.toStringAsFixed(1)} kg',
          ));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final double cupsPerTap = _cupsPerTap;

      // ONE transaction for the tank and its two taps, behind one repository
      // method: three implicit transactions is three journal commits on a shop's
      // cheap hardware, and a failure between them would leave a `kilogram`
      // product with no taps in the catalogue — a tank nobody can pour from.
      await db.saveTank(
        tank: Product(
          name: name,
          category: 'Beer',
          costPrice: Money.zero,
          sellPrice: Money.zero,
          // The aggregate, in cup servings, of the two taps below: the parent of
          // a product sold as variants is a summary rather than a second count,
          // and `writeAggregateStock` — which every sale runs — keeps the two
          // equal. Writing an independent number here is what used to let the
          // editor collapse the tank's 50 000 ml into a sum of kilograms.
          stockQty: cupsPerTap * kTankTapCount,
          reorderLevel: 5,
          bottleMl: capacityMl,
          unit: ProductUnit.kilogram,
          millilitresPerKilogram: perKg,
          trackVariants: true,
          updatedAt: DateTime.now().toIso8601String(),
        ),
        taps: <ProductVariant>[
          for (final ({String name, String label}) tap
              in <({String name, String label})>[
            (name: 'Dark', label: l10n.tankVariantDark),
            (name: 'Regular', label: l10n.tankVariantRegular),
          ])
            ProductVariant(
              productId: 0, // set inside the transaction, on the real row
              name: tap.label,
              unit: ProductUnit.cup,
              sizeMl: kTankCupCapacityMl,
              sellPrice: Money.fromMajor(price),
              costPrice: Money.zero,
              // CUP SERVINGS, in the same unit the till deducts: this tap's
              // share of the tank. Seeded in anything else and the tap reads
              // empty after a couple of dozen pours.
              stockQty: cupsPerTap,
              active: true,
            ),
        ],
      );

      // The till reads the catalogue from the database when its generation
      // changes; the module-level signal is the only thing a bottom sheet can
      // reach, because it is drawn outside the shell that owns the provider.
      markCatalogueChanged();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tankCreated(name))),
      );
    } catch (_) {
      // Not an exception in the face: the sheet is still open with the owner's
      // numbers in it, so a retry is possible and is what the message offers.
      if (mounted) setState(() => _error = l10n.tankSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final TextTheme type = AppTypography.of(context);

    final litres = _weightAsLitres;

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.lg,
        end: spacing.lg,
        top: spacing.lg,
        bottom: spacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.tankFormTitle, style: type.headlineSmall),
            SizedBox(height: spacing.xs),
            Text(
              l10n.tankFormSubtitle,
              style: type.bodySmall
                  ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
            ),
            SizedBox(height: spacing.lg),
            _field(_name, l10n.tankFieldName, l10n.tankFieldNameHint,
                TextInputType.name),
            SizedBox(height: spacing.md),
            _field(_capacityLitres, l10n.tankFieldCapacityL,
                l10n.tankFieldCapacityLHint, TextInputType.number),
            SizedBox(height: spacing.md),
            _field(_weightKg, l10n.tankFieldWeightKg,
                l10n.tankFieldWeightKgHint, TextInputType.number),
            // The conversion, live: "50 kg = 50.0 L" is the number that makes
            // the next field make sense, and a form that hides it is a form the
            // owner has to trust rather than check.
            if (litres != null) ...<Widget>[
              SizedBox(height: spacing.xs),
              Text(
                l10n.tankWeightLitres(litres.toStringAsFixed(1)),
                style: type.labelMedium
                    ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
              ),
            ],
            SizedBox(height: spacing.md),
            _field(_mlPerKg, l10n.tankFieldMlPerKg, l10n.tankFieldMlPerKgHint,
                TextInputType.number),
            SizedBox(height: spacing.md),
            _field(_cupPrice, l10n.tankFieldCupPrice,
                l10n.tankFieldCupPriceHint, const TextInputType.numberWithOptions(decimal: true)),
            SizedBox(height: spacing.lg),
            SurfaceCard(
              color: AppColors.of(context).surfaceSunken,
              padding: EdgeInsets.all(spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.tankVariantsTitle, style: type.titleSmall),
                  SizedBox(height: spacing.xs),
                  Text(l10n.tankVariantHint, style: type.bodySmall),
                  SizedBox(height: spacing.sm),
                  Text('${l10n.tankVariantDark} · ${l10n.tankVariantRegular}',
                      style: type.labelLarge),
                ],
              ),
            ),
            if (_error != null) ...<Widget>[
              SizedBox(height: spacing.md),
              Text(
                _error!,
                style: type.bodyMedium
                    ?.copyWith(color: AppColors.of(context).danger),
              ),
            ],
            SizedBox(height: spacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: Size(0, spacing.minTapTarget),
                  shape: RoundedRectangleBorder(
                    borderRadius: shapes.controlRadius,
                  ),
                ),
                child: Text(_saving ? l10n.pinResetSaving : l10n.tankAddAction),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String? hint,
    TextInputType keyboard,
  ) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label, helperText: hint),
      keyboardType: keyboard,
      onChanged: (_) => setState(() {}),
    );
  }
}

