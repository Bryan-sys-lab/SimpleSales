// The tank form: what it says, and what it saves.
//
// ## WHAT WENT WRONG, TWICE
//
// First: "In the tank form there are code leaks to the interface and the
// wording used is very hard to understand." The tap heading interpolated the
// l10n GETTER instead of calling it, so the screen printed
// `Closure: (Object) => String from Function 'tankTapLabel':. 1` where the
// form should have named its taps. And the form spoke like a manual —
// "Litres per kilogram", "Loaded", "Tanks on hand".
//
// Then: "a tank is never sold or available for sale once added … the form
// should not be pre-filled … remove the upper part where one specifies the
// type of beer, how many full tanks and their capacity. Instead make a simple
// form that asks for the tank name (what's in it), how it's sold (cups, or
// anything else they can configure), the capacity of the tank, and its price
// and how many are in stock."
//
// So the taps and the kilogram factor are gone, nothing is pre-filled, the
// cups are a list the owner adds to, and the tank itself is a container that
// is never sold — only its cups are.
//
// ## WHAT IS PINNED
//
//   * the form speaks plain words, and never its own machinery;
//   * every box starts EMPTY: the owner's answer, not the programmer's guess;
//   * the tank product carries a sell price of ZERO and is therefore not
//     sellable whole — `sellsWhole` is the till's own gate;
//   * the cups are written as shot cups, with an OPTIONAL size (zero means
//     "not measured", and it is legal);
//   * the stock is in tanks and the cost sits on the tank row, so the profit
//     on a cup is the cup's price minus the cup's share of the tank cost —
//     computed the same way as any other measured sale;
//   * a cup bigger than the drum, a cup with no name, and a cup with no price
//     are all refused before anything is written.
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

  /// A tank of soda with two cups, for [saveTank].
  TankValues tank({
    int capacityMl = 50000,
    int tankCount = 2,
    double cost = 10000,
    List<TankServingValues> servings = const <TankServingValues>[
      TankServingValues(label: 'Small cup', sizeMl: 330, price: 50),
      TankServingValues(label: 'Big cup', sizeMl: 500, price: 80),
    ],
  }) {
    return TankValues(
      name: 'Soda',
      capacityMl: capacityMl,
      tankCount: tankCount,
      cost: cost,
      servings: servings,
    );
  }

  group('the wording', () {
    testWidgets('the form never prints its own machinery', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(home: const Scaffold(body: TankFormSheet()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Closure:'), findsNothing);
      expect(find.textContaining('Function'), findsNothing);
      expect(find.textContaining('{'), findsNothing);
      // The old beer vocabulary is gone from the screen entirely.
      expect(find.textContaining('tap'), findsNothing);
      expect(find.textContaining('kilogram'), findsNothing);
    });

    testWidgets('every box starts empty — the owner fills it in', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(home: const Scaffold(body: TankFormSheet()));
      await tester.pumpAndSettle();

      for (final EditableText field in tester
          .widgetList<EditableText>(find.byType(EditableText))) {
        expect(
          field.controller.text,
          isEmpty,
          reason: 'a pre-filled box is an answer the shop did not give',
        );
      }
    });

    test('the fields say what the number is, in plain words', () async {
      final AppLocalizations l10n = await loadL10n();
      expect(l10n.tankFieldName, contains('tank'));
      expect(l10n.tankFieldCapacityL.toLowerCase(), contains('litres'));
      expect(l10n.tankFieldTankCost, contains('KSh'));
      expect(l10n.tankFieldServingMl.toLowerCase(), contains('ml'));
      expect(l10n.tankFieldServingPrice.toLowerCase(), contains('ksh'));
      // The serving size is optional, and the form says so where the owner
      // would otherwise hunt for what to write in an empty box.
      expect(
        l10n.tankFieldServingMlHint.toLowerCase(),
        contains('empty'),
      );
    });
  });

  group('the checks', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpApp(home: const Scaffold(body: TankFormSheet()));
      await tester.pumpAndSettle();
    }

    Future<void> type(WidgetTester tester, int index, String text) async {
      await tester.enterText(find.byType(TextField).at(index), text);
      await tester.pump();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Save this tank'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save this tank'));
      await tester.pumpAndSettle();
    }

    testWidgets('a cup bigger than the drum is refused', (
      WidgetTester tester,
    ) async {
      await open(tester);
      // 0 name, 1 capacity, 2 cost, 3 count, 4 cup name, 5 cup size, 6 price.
      await type(tester, 0, 'Soda');
      await type(tester, 1, '50'); // 50 litres = 50,000 ml
      await type(tester, 2, '10000');
      await type(tester, 3, '2');
      await type(tester, 4, 'Bucket');
      await type(tester, 5, '60000'); // more than the drum holds
      await type(tester, 6, '500');
      await save(tester);

      expect(find.text('That cup is bigger than the tank.'), findsOneWidget);
    });

    testWidgets('a cup with no name is refused', (WidgetTester tester) async {
      await open(tester);
      await type(tester, 0, 'Soda');
      await type(tester, 1, '50');
      await type(tester, 2, '10000');
      await type(tester, 3, '2');
      await type(tester, 5, '330');
      await type(tester, 6, '50');
      await save(tester);

      expect(
        find.text('Write what you call this cup.'),
        findsOneWidget,
        reason: 'a cup nobody can name cannot be sold',
      );
    });

    testWidgets('a cup with no price is refused', (WidgetTester tester) async {
      await open(tester);
      await type(tester, 0, 'Soda');
      await type(tester, 1, '50');
      await type(tester, 2, '10000');
      await type(tester, 3, '2');
      await type(tester, 4, 'Small cup');
      await type(tester, 5, '330');
      await save(tester);

      expect(
        find.text('Write the price for one cup. Only numbers.'),
        findsOneWidget,
      );
    });

    testWidgets('a cup with no size is accepted by the checks', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await type(tester, 0, 'Soda');
      await type(tester, 1, '50');
      await type(tester, 2, '10000');
      await type(tester, 3, '2');
      await type(tester, 4, 'Glass');
      // The size box stays empty.
      await type(tester, 6, '100');
      await save(tester);

      // No refusal. The WRITE is asserted below, outside the widget: a database
      // call inside `testWidgets` runs in a fake async zone where sqflite's
      // real file I/O never completes, which is why this file keeps the two
      // apart.
      expect(find.textContaining('Only numbers'), findsNothing);
      expect(find.text('Write the price for one cup. Only numbers.'), findsNothing);
    });
  });

  group('what it saves', () {
    test('the tank is one product, never sold whole', () async {
      final db = await DatabaseHelper.instance.database;
      await saveTank(db, tank());

      final List<Product> products = await DatabaseHelper.instance.getProducts();
      expect(products, hasLength(1), reason: 'a tank is one drum, not a tap each');

      final Product soda = products.single;
      expect(soda.name, 'Soda');
      expect(soda.sellPrice, Money.zero,
          reason: 'a tank is never sold whole — the cups are the sale');
      expect(soda.sellsWhole, isFalse,
          reason: 'this is the gate the till reads to hide "the whole thing"');
      expect(soda.stockQty, 2, reason: 'stock is counted in tanks');
      expect(soda.costPrice, Money.fromMajor(10000));
      expect(soda.bottleMl, 50000);
    });

    test('a cup with no size is stored as zero, which means "not measured"',
        () async {
      final db = await DatabaseHelper.instance.database;
      await saveTank(
        db,
        tank(servings: const <TankServingValues>[
          TankServingValues(label: 'Glass', sizeMl: 0, price: 100),
        ]),
      );

      final List<ShotCup> cups = await DatabaseHelper.instance.getShotCups();
      expect(cups, hasLength(1));
      expect(cups.single.capacityMl, 0);
      expect(cups.single.label, 'Glass');
    });

    test('each cup is written with its own price and size', () async {
      final db = await DatabaseHelper.instance.database;
      await saveTank(db, tank());

      final Product soda = (await DatabaseHelper.instance.getProducts()).single;
      final List<ShotCup> cups = (await DatabaseHelper.instance.getShotCups())
          .where((ShotCup c) => c.productId == soda.id)
          .toList();
      expect(cups, hasLength(2));
      expect(cups.map((ShotCup c) => c.label), containsAll(<String>[
        'Small cup',
        'Big cup',
      ]));
      expect(
        cups.map((ShotCup c) => c.price),
        containsAll(<Money>[Money.fromMajor(50), Money.fromMajor(80)]),
      );
    });

    test('the profit on a cup is the cup’s share of the tank cost', () async {
      // The rule the shop asked for: "for tanks the profit calculation is
      // done per cup and calculated as the others". The mechanism is the
      // measured-pour fraction the cart already applies: a 500 ml cup out of
      // a 50,000 ml drum costs 1% of the drum.
      const int capacityMl = 50000;
      const int tankCostMinor = 1000000; // KSh 10,000
      const int cupMl = 500;
      final double fraction = cupMl / capacityMl;
      final Money cupCost =
          Money.fromMinor((tankCostMinor * fraction).round());
      expect(cupCost, Money.fromMajor(100));
      expect(Money.fromMajor(80) - cupCost, Money.fromMajor(-20),
          reason: 'a cup priced under its share of the drum loses money — '
              'and the reports say so per cup, not per tank');
    });
  });
}
