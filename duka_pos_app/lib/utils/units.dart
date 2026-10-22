import 'package:flutter/foundation.dart';

/// What a product or variant is measured in.
///
/// This exists because "750" is ambiguous on its own: 750 millilitres of beer
/// in a tank, 750 millilitres in a bottle, or 750 of something countable. All
/// three are stocked, priced and reported differently, and the app previously
/// had only a single integer `bottle_ml` that silently meant whichever the
/// importer happened to put in that column.
///
/// Storage stays millilitres everywhere. [litre] and [cup] are *input* units a
/// supplier's spreadsheet might use and a human might type; they convert on the
/// way in and never reach the database. Storing one representation is what makes
/// "how much did I sell" a single subtraction rather than a conversion table
/// lookup on every query.
enum ProductUnit {
  /// A countable thing. A bottle, a loaf, a bar of soap. `sizeMl` is 1.
  each('each', 'each'),

  /// Sold by volume, priced per millilitre. Rare in retail, common for syrups.
  millilitre('ml', 'ml'),

  /// Sold by volume, priced per litre. What a supplier's price list usually says.
  litre('litre', 'L'),

  /// Sold by volume, priced per cup. A tank is bought and a cup is sold, and the
  /// two never meet: the price is for the cup, and the volume only exists to
  /// work out how many cups a tank holds.
  cup('cup', 'cup'),

  /// What a tank of beer is measured in, and stocked in.
  ///
  /// A tank is bought by weight and sold by the cup. Its stock is kilograms —
  /// the number on the delivery note and the number on the scale — and the app
  /// converts to millilitres ONCE, at [kilogramsToMillilitres], then treats the
  /// tank exactly as any other volumetric product for every pour, cup and sale.
  /// A mass is not stored: a second representation of the same quantity is how a
  /// stock count ends up disagreeing with itself, and this app counts in
  /// millilitres for a reason.
  ///
  /// The conversion is ONE number, [kilogramsToMillilitres], and it is overridable
  /// per product: a 50-kg tank of lager holds about 50 litres, and a liqueur or a
  /// syrup holds a different amount per kilogram, which is why it is not baked
  /// into the unit.
  kilogram('kilogram', 'kg');

  const ProductUnit(this.wire, this.suffix);

  /// The value stored in the column. A const class rather than an enum because
  /// the value is written straight to TEXT with no default and read back into a
  /// plain string.
  final String wire;

  /// What a human writes after a number in this unit. `L`, not `litre`.
  final String suffix;

  /// Whether quantities in this unit are volumes.
  ///
  /// True for [kilogram] too — deliberately. A tank is stocked by weight but it
  /// is VOLUME that a sale deducts (a cup is millilitres), and `isVolumetric` is
  /// the flag that says "this product can be poured from", which is exactly what
  /// a tank is for. The weight lives only in the form and the stock count; the
  /// pour never sees it.
  bool get isVolumetric => this != ProductUnit.each;

  /// One of these, in millilitres.
  ///
  /// 0 for [each]: a countable thing has no volume, and pretending it has one
  /// (1 ml) would make every litres-to-ml conversion silently multiply a
  /// carton of soap by a thousand.
  ///
  /// 0 for [kilogram]: a kilogram is not a fixed volume — see
  /// [kilogramsToMillilitres], which carries the per-product factor instead of
  /// baking one density into every tank in the shop.
  double get millilitresPerUnit => switch (this) {
        ProductUnit.each => 0,
        ProductUnit.millilitre => 1,
        ProductUnit.litre => 1000,
        ProductUnit.cup => 1, // a cup is not a fixed size; size_ml says how big
        ProductUnit.kilogram => 0, // per product: the tank's ml per kg
      };

  /// Whether this unit is stocked by weight rather than by volume or count.
  ///
  /// A tank is the only case, and the only thing that makes it different from a
  /// litre product is that its stock is read off a scale. Everything after the
  /// conversion is a litre product's life.
  bool get isMeasuredByWeight => this == ProductUnit.kilogram;

  static ProductUnit parse(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) return ProductUnit.each;
    // The wire value AND the suffix, because a supplier's spreadsheet says "kg"
    // and "L" where the database says "kilogram" and "litre". Matching only the
    // wire value silently read every kg-stocked tank as a countable product —
    // which is the exact failure the `unit` column exists to prevent.
    return ProductUnit.values.firstWhere(
      (unit) => unit.wire == value || unit.suffix == value,
      orElse: () => ProductUnit.each,
    );
  }

  /// Human label for a picker.
  String get label => switch (this) {
        ProductUnit.each => 'Each (countable)',
        ProductUnit.millilitre => 'Per millilitre',
        ProductUnit.litre => 'Per litre',
        ProductUnit.cup => 'Per cup',
        ProductUnit.kilogram => 'Per kilogram (tank)',
      };
}

/// How much beer one kilogram of it is, in millilitres.
///
/// 1000 ml/kg is beer, which is why it is the default: a litre of lager weighs
/// a kilogram to within the few percent a tank's own gauge is accurate to. It
/// is a plain constant rather than a law of nature because the next thing that
/// arrives by weight may not be beer — a syrup or a liqueur holds a different
/// amount per kilogram — and a tank's own conversion is stored per product, at
/// [Product.millilitresPerKilogram], for exactly that reason.
const double defaultKilogramsToMillilitres = 1000;

/// Kilograms to millilitres, at [millilitresPerKilogram] per kg.
///
/// The one conversion the app does for a weight-stocked product. A negative or
/// non-finite factor answers 0 rather than a garbage volume, because a tank
/// whose conversion was mistyped should hold nothing rather than hold a
/// negative amount of beer.
double kilogramsToMillilitres(
  num kilograms, {
  double millilitresPerKilogram = defaultKilogramsToMillilitres,
}) {
  if (!kilograms.isFinite || kilograms < 0) return 0;
  if (!millilitresPerKilogram.isFinite || millilitresPerKilogram <= 0) return 0;
  return kilograms * millilitresPerKilogram;
}

/// Millilitres to kilograms, at [millilitresPerKilogram] per kg.
///
/// The other direction, for reading a stock figure back as the weight the owner
/// would see on a scale. A tank at 0 ml reads as 0 kg, not as a negative.
double millilitresToKilograms(
  num millilitres, {
  double millilitresPerKilogram = defaultKilogramsToMillilitres,
}) {
  if (!millilitres.isFinite || millilitres < 0) return 0;
  if (!millilitresPerKilogram.isFinite || millilitresPerKilogram <= 0) return 0;
  return millilitres / millilitresPerKilogram;
}

/// Litres to millilitres.
///
/// The same factor [Volume.parse] applies when a litre suffix is written out,
/// named rather than repeated as `* 1000` at every call site: a factor-of-
/// thousand conversion is the stock error nobody notices until the month-end
/// count, so it is spelled exactly once.
double litresToMillilitres(num litres) =>
    litres.isFinite && litres >= 0 ? litres * 1000 : 0;

/// Millilitres to litres, for reading a volume back the way a delivery note or
/// a tank's own gauge states it.
double millilitresToLitres(num millilitres) =>
    millilitres.isFinite && millilitres >= 0 ? millilitres / 1000 : 0;

/// Conversions between a typed volume and millilitres.
///
/// Pure and separate from both the model and the database so the importer, the
/// product editor and the receipt can all share one answer. Getting this wrong
/// is a factor-of-a-thousand error on every stock figure for the product, which
/// is the kind of bug nobody notices until the month-end stock count.
@immutable
class Volume {
  /// Public so a caller holding an already-converted number can build a
  /// Volume without going back through text. Named rather than the private
  /// constructor so [ProductVariant.label] is not forced to reach into a
  /// library-private factory for a value it already holds.
  const Volume(this.millilitres);

  /// A volume that could not be read from its input.
  static const Volume invalid = Volume(-1);

  final double millilitres;

  bool get isValid => millilitres >= 0;
  bool get isZero => millilitres == 0;

  /// Parses a human- or spreadsheet-written volume into millilitres.
  ///
  /// Accepts every shape a real supplier file actually contains, because the
  /// alternative is a column that silently reads as 750 when it means 0.75:
  ///
  ///   `750` -> 750 (bare numbers are millilitres, the existing convention)
  ///   `0.75` -> 750  (a bare number under 10 in a volume column is litres)
  ///   `0.75 L`, `0.75l`, `0.75 litre`, `750ml`, `750 mL` -> 750
  ///   `1.5 L` -> 1500
  ///   `750 ML`, `750Ml` -> 750
  ///
  /// The bare-number heuristic is the one genuinely ambiguous case, and it is
  /// only ambiguous *because* the app has always stored millilitres in that
  /// column. A value under 10 cannot plausibly be a 750ml bottle expressed in
  /// ml, and a supplier writing `0.5` in a volume column means half a litre.
  /// Anything at or above 10 is read as millilitres, which is what every
  /// existing row and every existing export means.
  static Volume parse(String? raw, {ProductUnit? declared}) {
    if (raw == null) return invalid;
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return invalid;

    final match = RegExp(r'^(-?\d+(?:\.\d+)?)\s*'
            r'(ml|millilitre?s?|milliliter?s?|l|litre?s?|liter?s?)?\s*$')
        .firstMatch(text);
    if (match == null) return invalid;

    final amount = double.tryParse(match.group(1)!);
    if (amount == null || !amount.isFinite) return invalid;
    final suffix = match.group(2);

    // An explicit unit always wins, including over a declared column unit: the
    // shopkeeper who wrote "500ml" meant 500.
    final ml = switch (suffix) {
      'ml' ||
      'millilitre' ||
      'millilitres' ||
      'milliliter' ||
      'milliliters' =>
        amount,
      'l' || 'litre' || 'litres' || 'liter' || 'liters' => amount * 1000,
      _ => null,
    };
    if (ml != null) {
      return ml < 0 ? invalid : Volume(ml);
    }

    if (declared == ProductUnit.litre) {
      // The column declared itself as litres, so a bare number is litres even
      // if it is large — a 50-litre keg is a real thing and must not become
      // 50 millilitres.
      return amount < 0 ? invalid : Volume(amount * 1000);
    }
    // Declared millilitre or cup: a bare number stays millilitres — no litre
    // guess, so a 5 ml shot cup does not become 5 litres.
    if (declared == ProductUnit.millilitre || declared == ProductUnit.cup) {
      return amount < 0 ? invalid : Volume(amount);
    }
    // Declared countable, or no declaration at all: a bare number under 10 is
    // plausibly litres typed without the suffix ("0.5"), while anything at or
    // above 10 is plausibly millilitres ("750"). This guess is the one the
    // existing convention relies on, and keeping it means every existing export
    // still reads back unchanged.
    return amount < 0 ? invalid : Volume(amount < 10 ? amount * 1000 : amount);
  }

  /// Renders millilitres the way the editor and a supplier sheet both prefer:
  /// whole millilitres when that is the natural number, otherwise litres with
  /// two decimals, so `750` does not become `0.75 L` and `1750` becomes
  /// `1.75 L`.
  String get display {
    if (!isValid) return '';
    if (millilitres >= 1000) {
      final litres = millilitres / 1000;
      return '${litres.toStringAsFixed(litres % 1 == 0 ? 0 : 2)} L';
    }
    return '${millilitres.round()} ml';
  }

  int get rounded => millilitres.round();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Volume && other.millilitres == millilitres;

  @override
  int get hashCode => millilitres.hashCode;

  @override
  String toString() => isValid ? '${millilitres.round()} ml' : 'invalid';
}

/// A stock count, said the way a shop says it.
///
/// "20" and "0.5", never "20.0". A count with a pointless decimal reads as a
/// different number from the one the owner is looking at, and a diagnostic
/// that says "20.0 against 24.0" makes the owner check the arithmetic instead
/// of reading the difference.
String stockCountLabel(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);
