// The tank form: what it says, and what it saves.
//
// ## WHAT WENT WRONG
//
// "In the tank form there are code leaks to the interface and the wording used
// is very hard to understand."
//
// Three things were wrong, and all three are pinned below.
//
// 1. THE LEAK. The field that says how much a kilogram holds was labelled
//    "Litres per kilogram" and the number in it was MILLILITRES — the default
//    was 1000, which is 1000 millilitres, not 1000 litres. A person reading
//    the label would write 1 for a litre of beer, and the app would treat
//    that as one millilitre.
//
// 2. THE SILENT FIELD. The form asked how much was loaded in each tap, and
//    then THREW IT AWAY: the tap's stock and cost were both written from the
//    tank count alone. Two taps on one tank, one of them empty, were saved
//    as two full taps.
//
// 3. THE WORDING. "Litres per kilogram", "Size (ml)", "Loaded", "Tanks on
//    hand" are words for the person who wrote the software. The form is
//    filled in by whoever is standing at the tank.
//
// ## WHAT IS PINNED
//
//   * the label says millilitres, and the number the form starts with is the
//     number the label promises;
//   * a tap that holds more than the tank is refused;
//   * two taps together holding more than the tank are refused;
//   * the load IS saved: a tap with a quarter of the tank in it carries a
//     quarter of the stock and a quarter of the cost.
//
// ## WHY THE SAVE IS TESTED WITHOUT A WIDGET
//
// `sqflite`'s ffi backend does real file I/O on a background isolate, and a
// `testWidgets` body runs inside a FAKE async zone where that never
// completes — a write inside a widget test hangs until the harness kills the
// file. So the writing is a plain function ([saveTank]) and it is tested as
// one, outside the widget; the widget test covers the checks, which happen
// before any write.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/tank_form_sheet.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/utils/units.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    await DatabaseHelper.openInMemoryForTests();
  });

  /// A tank with two taps, for [saveTank].
  TankValues tank({
    int capacityMl = 50000,
    int tankCount = 1,
    double cost = 10000,
    List<double> loads = const <double>[25000, 25000],
  }) {
    return TankValues(
      name: 'Tusker',
      capacityMl: capacityMl,
      tankCount: tankCount,
      cost: cost,
      taps: <TankTapValues>[
        TankTapValues(
          name: 'Dark',
          loadMl: loads[0],
          smallMl: 330,
          smallPrice: 100,
          bigMl: 500,
          bigPrice: 150,
        ),
        TankTapValues(
          name: 'Regular',
          loadMl: loads[1],
          smallMl: 330,
          smallPrice: 100,
          bigMl: 500,
          bigPrice: 150,
        ),
      ],
    );
  }

  group('the wording', () {
    test('the kilogram field says millilitres', () async {
      final AppLocalizations l10n = await loadL10n();
      expect(
        l10n.tankFieldMlPerKg.toLowerCase(),
        contains('millilitre'),
        reason: 'the number in this field is millilitres, so the label has to '
            'say millilitres: "${l10n.tankFieldMlPerKg}"',
      );
    });

    test('the form starts on the beer default, in millilitres', () async {
      // 1000 millilitres in a kilogram. The label says millilitres and the
      // number has to agree with it.
      expect(defaultKilogramsToMillilitres, 1000);
    });

    test('the fields say what the number is', () async {
      final AppLocalizations l10n = await loadL10n();
      expect(l10n.tankFieldCapacityL.toLowerCase(), contains('litres'));
      expect(l10n.tankFieldTankCost, contains('KSh'));
      expect(l10n.tankFieldSmallMl.toLowerCase(), contains('ml'));
      expect(l10n.tankFieldBigMl.toLowerCase(), contains('ml'));
    });

    testWidgets('the tap headings are words, not the machinery behind them', (
      WidgetTester tester,
    ) async {
      // THE LEAK. The tap heading interpolated the l10n GETTER instead of
      // calling it, and `tankTapLabel` is a TEMPLATE — "Tap {n}" — so the
      // screen showed the template's own machinery:
      //
      //   Closure: (Object) => String from Function 'tankTapLabel':. 1
      //
      // A shop filling in a tank form was reading the software's source
      // code, in the place where the form names its taps.
      await tester.pumpApp(
        home: const Scaffold(body: TankFormSheet()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tap 1'), findsOneWidget);
      expect(find.text('Tap 2'), findsOneWidget);
      expect(find.textContaining('Closure:'), findsNothing);
      expect(find.textContaining('Function'), findsNothing);
    });
  });

  group('the checks', () {
    testWidgets('a tap that holds more than the tank is refused', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        home: const Scaffold(body: TankFormSheet()),
      );
      await tester.pumpAndSettle();

      Future<void> type(int index, String text) async {
        await tester.enterText(find.byType(TextField).at(index), text);
        await tester.pump();
      }

      await type(0, 'Tusker');
      await type(1, '50');
      await type(2, '1');
      await type(4, '10000');
      await type(6, '60');
      await type(8, '100');
      await type(10, '150');
      await type(12, '50');
      await type(14, '100');
      await type(16, '150');

      // The sheet is taller than the phone, so the button is scrolled to
      // before it is pressed.
      await tester.ensureVisible(find.text('Save this tank'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save this tank'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('more than the whole tank'),
        findsOneWidget,
        reason: 'a tap cannot hold more beer than the tank it is part of',
      );
    });

    testWidgets('two taps together holding more than the tank are refused', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        home: const Scaffold(body: TankFormSheet()),
      );
      await tester.pumpAndSettle();

      Future<void> type(int index, String text) async {
        await tester.enterText(find.byType(TextField).at(index), text);
        await tester.pump();
      }

      await type(0, 'Tusker');
      await type(1, '50');
      await type(2, '1');
      await type(4, '10000');
      await type(6, '40');
      await type(8, '100');
      await type(10, '150');
      await type(12, '40');
      await type(14, '100');
      await type(16, '150');

      // The sheet is taller than the phone, so the button is scrolled to
      // before it is pressed.
      await tester.ensureVisible(find.text('Save this tank'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save this tank'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The taps together hold more than the tank'),
        findsOneWidget,
      );
    });
  });

  group('what it saves', () {
    test('a tap holds its share of the tank, and its share of the cost',
        () async {
      // A 50-litre tank, one tank, KSh 10,000, and 25 litres in each of two
      // taps: each tap holds half the beer and carries half the cost.
      final db = await DatabaseHelper.instance.database;
      await saveTank(
        db,
        tank(),
        smallCupLabel: 'Small cup',
        bigCupLabel: 'Big cup',
      );

      final List<Product> products =
          await DatabaseHelper.instance.getProducts();
      expect(products.length, 2);

      for (final Product product in products) {
        expect(
          product.stockQty,
          closeTo(0.5, 0.0001),
          reason: '${product.name} should hold half a tank',
        );
        expect(
          product.costPrice,
          Money.fromMajor(5000),
          reason: '${product.name} should carry half the tank cost',
        );
      }
    });

    test('a tap that is empty is saved empty', () async {
      // One tap full, one tap empty: the empty one can pour nothing, and
      // the full one holds the whole tank.
      final db = await DatabaseHelper.instance.database;
      await saveTank(
        db,
        tank(loads: const <double>[50000, 0]),
        smallCupLabel: 'Small cup',
        bigCupLabel: 'Big cup',
      );

      final List<Product> products =
          await DatabaseHelper.instance.getProducts();
      expect(products.length, 2);

      final Product full = products.firstWhere((Product p) => p.stockQty > 0);
      final Product empty = products.firstWhere((Product p) => p.stockQty == 0);
      expect(full.stockQty, closeTo(1.0, 0.0001));
      expect(empty.stockQty, 0);
      expect(full.costPrice, Money.fromMajor(10000));
      expect(empty.costPrice, Money.fromMajor(0));
    });

    test('both cups are written for each tap', () async {
      final db = await DatabaseHelper.instance.database;
      await saveTank(
        db,
        tank(),
        smallCupLabel: 'Small cup',
        bigCupLabel: 'Big cup',
      );

      final List<Product> products =
          await DatabaseHelper.instance.getProducts();
      for (final Product product in products) {
        final List<ShotCup> cups = await DatabaseHelper.instance
            .getShotCups()
            .then(
              (List<ShotCup> all) =>
                  all.where((ShotCup c) => c.productId == product.id).toList(),
            );
        expect(cups.length, 2, reason: '${product.name} needs both cups');
      }
    });
  });
}
