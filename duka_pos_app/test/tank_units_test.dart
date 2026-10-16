// A tank of beer: stocked by weight, poured by the cup.
//
// What this pins is the ONE conversion the app does for a weight-stocked
// product, and the invariant that makes it safe to do at all — that the
// millilitres the pour maths reads are the kilograms the owner typed, times the
// tank's own factor, and nothing else. Getting that factor wrong is a
// factor-of-a-thousand stock error on every pour, which is the kind of bug
// nobody notices until the month-end count.

import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/utils/units.dart';

void main() {
  group('kilograms to millilitres, the tank\'s one conversion', () {
    test('beer is a litre a kilogram, which is the default', () {
      expect(kilogramsToMillilitres(50), 50000,
          reason: 'a 50-kg tank holds 50 litres; that is the whole point');
      expect(kilogramsToMillilitres(1), 1000);
      expect(
          kilogramsToMillilitres(0), 0, reason: 'an empty tank reads as 0 kg');
    });

    test('a tank with its own factor converts at that factor', () {
      // Not everything that arrives by weight is beer. A syrup holds a
      // different amount per kilogram, and the factor is per product precisely
      // so the shop does not have to pretend it is beer.
      expect(
        kilogramsToMillilitres(10, millilitresPerKilogram: 850),
        8500,
      );
    });

    test('a nonsense factor holds nothing rather than a negative amount', () {
      // A factor of 0 or a mistyped value would divide somewhere or multiply
      // into a garbage volume. Answering 0 makes the tank empty, which is
      // wrong loudly rather than wrong quietly.
      expect(kilogramsToMillilitres(50, millilitresPerKilogram: 0), 0);
      expect(kilogramsToMillilitres(50, millilitresPerKilogram: -1), 0);
    });

    test('a negative or non-finite weight is not a weight', () {
      expect(kilogramsToMillilitres(-5), 0);
      expect(kilogramsToMillilitres(double.nan), 0);
      expect(kilogramsToMillilitres(double.infinity), 0);
    });

    test('millilitres back to kilograms, for a stock count off a scale', () {
      expect(millilitresToKilograms(50000), 50);
      expect(millilitresToKilograms(0), 0);
      expect(millilitresToKilograms(1750), 1.75);
      expect(millilitresToKilograms(10000, millilitresPerKilogram: 850), 10000 / 850);
    });
  });

  group('the tank unit', () {
    test('a tank is pourable, which is what isVolumetric gates', () {
      // `isVolumetric` is the flag that says "can be poured from" — the shot
      // cups screen filters on it — and a tank is exactly that.
      expect(ProductUnit.kilogram.isVolumetric, isTrue);
      expect(ProductUnit.kilogram.isMeasuredByWeight, isTrue);
      expect(ProductUnit.kilogram.millilitresPerUnit, 0,
          reason: 'a kilogram is not a fixed volume; the factor is per product');
    });

    test('only a tank is measured by weight', () {
      for (final ProductUnit unit in ProductUnit.values) {
        expect(unit.isMeasuredByWeight, unit == ProductUnit.kilogram,
            reason: '$unit');
      }
    });

    test('a tank round-trips through the stored vocabulary', () {
      expect(ProductUnit.parse('kilogram'), ProductUnit.kilogram);
      expect(ProductUnit.parse('kg'), ProductUnit.kilogram,
          reason: 'the wire value is what a spreadsheet column would say');
      expect(ProductUnit.kilogram.wire, 'kilogram');
      expect(ProductUnit.kilogram.suffix, 'kg');
      // An unknown value still falls back to the countable default rather than
      // throwing on a legacy row.
      expect(ProductUnit.parse('casks'), ProductUnit.each);
    });
  });

  group('the product row a tank writes', () {
    test('stock is in millilitres, converted from the weight', () {
      final double weightKg = 50;
      final double perKg = 1000;
      final product = Product(
        name: 'Tusker',
        category: 'Beer',
        costPrice: Money.zero,
        sellPrice: Money.zero,
        // What the form writes: the kg, converted, into the same volume column
        // every other product uses.
        stockQty: kilogramsToMillilitres(weightKg,
            millilitresPerKilogram: perKg),
        reorderLevel: 5,
        bottleMl: 50000,
        unit: ProductUnit.kilogram,
        millilitresPerKilogram: perKg,
        updatedAt: DateTime(2026, 1, 1).toIso8601String(),
      );

      expect(product.stockQty, 50000);
      expect(product.unit, ProductUnit.kilogram);
      expect(product.millilitresPerKilogram, perKg);
      expect(product.isLow, isFalse);
    });

    test('the row round-trips through the map and back', () {
      final product = Product(
        name: 'Balozi',
        category: 'Beer',
        costPrice: Money.zero,
        sellPrice: Money.zero,
        stockQty: 50000,
        reorderLevel: 5,
        bottleMl: 50000,
        unit: ProductUnit.kilogram,
        millilitresPerKilogram: 1000,
        updatedAt: DateTime(2026, 1, 1).toIso8601String(),
      );

      final Product back = Product.fromMap(product.toMap());

      expect(back.unit, ProductUnit.kilogram,
          reason: 'a tank must not come back out of the database as "each"');
      expect(back.millilitresPerKilogram, 1000);
      expect(back.stockQty, 50000);
    });

    test('a row written before tanks existed reads as a volume product', () {
      // The migration default is 0, and 0 is the field's way of saying "not
      // stocked by weight" — so an old keg stays exactly the keg it was.
      final Product legacy = Product.fromMap(<String, dynamic>{
        'name': 'Keg',
        'category': 'Beer',
        'cost_price': 0,
        'sell_price': 0,
        'stock_qty': 50000.0,
        'reorder_level': 5,
        'bottle_ml': 50000,
        'unit': 'litre',
        'active': 1,
        'updated_at': '2026-01-01T00:00:00.000Z',
      });

      expect(legacy.unit, ProductUnit.litre);
      expect(legacy.millilitresPerKilogram, 0);
      expect(legacy.unit.isMeasuredByWeight, isFalse);
    });

    test('a tank that is not a tank is distinguishable without a flag', () {
      final tank = Product(
        name: 'Tank',
        category: 'Beer',
        costPrice: Money.zero,
        sellPrice: Money.zero,
        stockQty: 0,
        reorderLevel: 5,
        updatedAt: DateTime(2026, 1, 1).toIso8601String(),
        unit: ProductUnit.kilogram,
        millilitresPerKilogram: 1000,
      );
      final litre = Product(
        name: 'Keg',
        category: 'Beer',
        costPrice: Money.zero,
        sellPrice: Money.zero,
        stockQty: 0,
        reorderLevel: 5,
        updatedAt: DateTime(2026, 1, 1).toIso8601String(),
        unit: ProductUnit.litre,
      );

      expect(
          tank.unit.isMeasuredByWeight && tank.millilitresPerKilogram > 0,
          isTrue);
      expect(litre.unit.isMeasuredByWeight && litre.millilitresPerKilogram > 0,
          isFalse);
    });
  });
}
