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
  cup('cup', 'cup');

  const ProductUnit(this.wire, this.suffix);

  /// The value stored in the column. A const class rather than an enum because
  /// the value is written straight to TEXT with no default and read back into a
  /// plain string.
  final String wire;

  /// What a human writes after a number in this unit. `L`, not `litre`.
  final String suffix;

  /// Whether quantities in this unit are volumes.
  bool get isVolumetric => this != ProductUnit.each;

  /// One of these, in millilitres.
  ///
  /// 0 for [each]: a countable thing has no volume, and pretending it has one
  /// (1 ml) would make every litres-to-ml conversion silently multiply a
  /// carton of soap by a thousand.
  double get millilitresPerUnit => switch (this) {
        ProductUnit.each => 0,
        ProductUnit.millilitre => 1,
        ProductUnit.litre => 1000,
        ProductUnit.cup => 1, // a cup is not a fixed size; size_ml says how big
      };

  static ProductUnit parse(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    return ProductUnit.values.firstWhere(
      (unit) => unit.wire == value,
      orElse: () => ProductUnit.each,
    );
  }

  /// Human label for a picker.
  String get label => switch (this) {
        ProductUnit.each => 'Each (countable)',
        ProductUnit.millilitre => 'Per millilitre',
        ProductUnit.litre => 'Per litre',
        ProductUnit.cup => 'Per cup',
      };
}

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
            r'(ml|millilitres?|millilitres|l|litres?|liters?)?')
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
      'milliltres' ||
      'milliliter' ||
      'milliliters' =>
        amount,
      'l' || 'litre' || 'litres' || 'liter' || 'liters' => amount * 1000,
      _ => null,
    };
    if (ml != null) {
      return ml < 0 ? invalid : Volume(ml);
    }

    if (declared == ProductUnit.litre || declared == ProductUnit.cup) {
      // The column declared itself as litres, so a bare number is litres even
      // if it is large — a 50-litre keg is a real thing and must not become
      // 50 millilitres.
      return amount < 0 ? invalid : Volume(amount * 1000);
    }
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
