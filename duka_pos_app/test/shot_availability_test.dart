// What the till says when a shot cannot be poured.
//
// The wording is the part worth testing. A blocked shot row tells the cashier
// why, and the three reasons need three different responses: change the cup,
// add stock, or count the drawer down. A single "not available" leaves them
// guessing, and they find out at the worst possible moment — with a customer
// waiting and a bottle open.
//
// The sentence is built from `AppLocalizations`, not baked into the function:
// "capacityMl is null" is an error log, and the person at the counter is not
// reading a log. Loading the real strings here is what pins the words the
// cashier actually sees.
//
// These are pure functions on purpose, so the decision can be checked without a
// widget tree and without a database.

import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/widgets/serving_choice_sheet.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/utils/units.dart';

import 'support/harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadL10n();
  });

  Product spirit({
    int id = 1,
    String name = 'AAA Vodka',
    int bottleMl = 750,
    ProductUnit unit = ProductUnit.cup,
  }) =>
      Product(
        id: id,
        name: name,
        category: 'Spirits',
        costPrice: Money.fromMajor(800),
        sellPrice: Money.fromMajor(1500),
        stockQty: 2,
        reorderLevel: 1,
        bottleMl: bottleMl,
        unit: unit,
        updatedAt: '2026-01-01T00:00:00.000',
      );

  ShotCup cup({int capacityMl = 30, String label = 'Shot'}) => ShotCup(
        productId: 1,
        productName: 'AAA Vodka',
        capacityMl: capacityMl,
        price: Money.fromMajor(100),
        label: label,
        updatedAt: '2026-01-01T00:00:00.000',
      );

  group('a shot that can be poured', () {
    test('a full bottle says how many cups are in it', () {
      // 750 / 30 is 25, and saying so is what stops the cashier opening the
      // bottle to find out.
      final verdict = shotAvailability(l10n, spirit(), cup(), 2);
      expect(verdict.canPour, isTrue);
      expect(verdict.reason, '25 cups left in the bottle');
    });

    test('the last shot is still pourable', () {
      // Exactly enough left. The comparison must not reject the bottle's final
      // pour because of a rounding hair, the same trap the stock check in
      // `recordSale` had.
      final verdict =
          shotAvailability(l10n, spirit(), cup(), 30 / 750);
      expect(verdict.canPour, isTrue);
    });

    test('a different cup size divides the same bottle differently', () {
      expect(
        shotAvailability(l10n, spirit(), cup(capacityMl: 50), 2).reason,
        '15 cups left in the bottle',
      );
      expect(
        shotAvailability(l10n, spirit(), cup(capacityMl: 750), 2).reason,
        '1 cups left in the bottle',
      );
    });
  });

  group('a shot whose size is not known', () {
    test('it is still pourable', () {
      // The size of a shot cup is optional, so a cup can have none. The
      // owner did not say how big the shot is, and the app does not guess —
      // but refusing to sell it would be worse: the shot is still a shot, and
      // it still has a price.
      final verdict =
          shotAvailability(l10n, spirit(), cup(capacityMl: 0), 5);
      expect(verdict.canPour, isTrue);
      expect(verdict.reason, contains('no size'));
    });

    test('an empty bottle still stops it', () {
      final verdict =
          shotAvailability(l10n, spirit(), cup(capacityMl: 0), 0);
      expect(verdict.canPour, isFalse);
      expect(verdict.reason, 'There is no AAA Vodka left');
    });
  });

  group('a shot that cannot be poured', () {
    test('the cup is bigger than the bottle it comes from', () {
      // A 1-litre cup poured from a 200 ml bottle. Saying so is the only useful
      // answer; "no stock" would send the cashier to fix a stock problem they
      // do not have.
      final verdict = shotAvailability(
          l10n, spirit(bottleMl: 200), cup(capacityMl: 1000), 5);
      expect(verdict.canPour, isFalse);
      expect(verdict.reason, 'This cup is bigger than the bottle (200 ml)');
      expect(verdict.reason, isNot(contains('left')));
    });

    test('the bottle has no volume at all', () {
      // A spirit switched to "each" after its cup was configured. Distinct from
      // an out-of-stock bottle and fixed differently.
      final verdict =
          shotAvailability(l10n, spirit(bottleMl: 0), cup(), 5);
      expect(verdict.canPour, isFalse);
      expect(verdict.reason, contains('no size written'));
    });

    test('the bottle is empty', () {
      final verdict = shotAvailability(l10n, spirit(), cup(), 0);
      expect(verdict.canPour, isFalse);
      expect(verdict.reason, 'There is no AAA Vodka left');
    });

    test('there is not enough for even one shot', () {
      // A quarter-pour is left: not enough to serve, and saying "25 cups in the
      // bottle" here would be plainly wrong.
      final verdict = shotAvailability(l10n, spirit(), cup(), 0.01);
      expect(verdict.canPour, isFalse);
      expect(verdict.reason, 'There is no AAA Vodka left');
    });

    test('the drink is named, so the fix is obvious', () {
      final verdict =
          shotAvailability(l10n, spirit(name: 'AAA Tusker'), cup(), 0);
      expect(verdict.reason, contains('AAA Tusker'));
    });
  });

  group('shots per bottle', () {
    test('a countable drink with no volume is not pourable', () {
      // A countable drink has nothing to measure against unless a size exists.
      final verdict = shotAvailability(
        l10n,
        spirit(unit: ProductUnit.each, bottleMl: 0),
        cup(),
        5,
      );
      expect(verdict.canPour, isFalse);
    });

    test('a volumetric drink with volume is pourable', () {
      // Once upsertShotCup has derived a product to millilitres, it pours.
      final verdict = shotAvailability(
        l10n,
        spirit(unit: ProductUnit.millilitre, bottleMl: 750),
        cup(),
        5,
      );
      expect(verdict.canPour, isTrue);
    });
  });
}
