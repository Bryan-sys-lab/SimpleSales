// The sheet that asks how a drink is to be sold.
//
// ## WHAT WENT WRONG
//
// "Selecting products in rotated view of a phone it opens the search triggering
// the keyboard and the size selector (full half quarter) is cut — only shows
// half and full. For that chooser we need to only show half full quarter for
// only products set to be sold like that (half and quarters are not applied to
// all products). Also selecting quarter is a no-op, it does not work at all."
//
// Three defects, and each has its own assertion here:
//
//   * the sheet was CUT — a column in a bottom sheet limited to half the
//     screen, with the quarter as the last row before the shots, so the
//     quarter was the first to go. It scrolls now, and this is measured on a
//     phone held sideways, which is where it was reported from;
//   * it offered portions the shop does not sell — every product got a Full, a
//     Half and a Quarter, at a price the app invented;
//   * the quarter charged nothing on a product with no price, so picking it
//     put a KSh 0 line in the cart.
//
// The rule is now: a portion is offered when the product is SOLD that way.
// A half needs a half price, a quarter needs a quarter price, and the whole
// thing needs a price of its own — a tank's tap has none, because the beer is
// sold by the cup.

import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/widgets/serving_choice_sheet.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// A product, with the parts of it the sheet looks at.
Product product({
  int sellPriceMinor = 10000,
  int? halfPriceMinor,
  int? quarterPriceMinor,
  double stock = 10,
}) {
  return Product(
    id: 1,
    name: 'Tusker',
    category: 'Beer',
    costPrice: Money.fromMinor(5000),
    sellPrice: Money.fromMinor(sellPriceMinor),
    stockQty: stock,
    reorderLevel: 5,
    bottleMl: 500,
    halfPrice: halfPriceMinor == null ? null : Money.fromMinor(halfPriceMinor),
    quarterPrice:
        quarterPriceMinor == null ? null : Money.fromMinor(quarterPriceMinor),
    updatedAt: DateTime.now().toIso8601String(),
  );
}

Future<void> openSheet(
  WidgetTester tester, {
  required Product item,
  List<ShotCup> shots = const <ShotCup>[],
  bool sellsAsVariants = false,
  List<ProductVariant> variants = const <ProductVariant>[],
  double height = 800,
}) async {
  tester.view.physicalSize = Size(400, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpApp(
    home: Scaffold(
      body: ServingChoiceSheet(
        product: item,
        variants: variants,
        sellsAsVariants: sellsAsVariants,
        shots: shots,
        remainingStock: item.stockQty,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('which portions are offered', () {
    testWidgets('a product with no half price is not sold in halves', (
      WidgetTester tester,
    ) async {
      await openSheet(tester, item: product());

      expect(find.textContaining('Full'), findsOneWidget);
      expect(find.textContaining('Half'), findsNothing);
      expect(find.textContaining('Quarter'), findsNothing);
    });

    testWidgets('a product with a half price is sold in halves', (
      WidgetTester tester,
    ) async {
      await openSheet(
        tester,
        item: product(halfPriceMinor: 5000),
      );

      expect(find.textContaining('Full'), findsOneWidget);
      expect(find.textContaining('Half'), findsOneWidget);
      expect(find.textContaining('Quarter'), findsNothing);
    });

    testWidgets('a product with a quarter price is sold in quarters', (
      WidgetTester tester,
    ) async {
      await openSheet(
        tester,
        item: product(halfPriceMinor: 5000, quarterPriceMinor: 2500),
      );

      expect(find.textContaining('Quarter'), findsOneWidget);
    });

    testWidgets('a product with no price of its own is not sold whole', (
      WidgetTester tester,
    ) async {
      // A tank's tap: the beer is sold by the cup, so a "Full" row would be a
      // row that charges nothing.
      await openSheet(
        tester,
        item: product(sellPriceMinor: 0),
        shots: <ShotCup>[
          ShotCup(
            id: 1,
            productId: 1,
            productName: 'Tusker',
            capacityMl: 330,
            price: Money.fromMinor(10000),
            updatedAt: '',
          ),
        ],
      );

      expect(find.textContaining('Full'), findsNothing);
      // The cup is still there: it is how the tank is sold.
      expect(find.text('Shot · 330 ml'), findsOneWidget);
    });
  });

  group('the sheet fits', () {
    testWidgets('every option is reachable on a phone held sideways', (
      WidgetTester tester,
    ) async {
      // 400 x 360: a phone on its side. The quarter was the first row to go,
      // because it was the last of the portions and the sheet could not
      // scroll.
      await openSheet(
        tester,
        item: product(halfPriceMinor: 5000, quarterPriceMinor: 2500),
        height: 360,
      );

      expect(
        find.textContaining('Quarter'),
        findsOneWidget,
        reason: 'the quarter must be in the tree even when it is below the '
            'fold — a sheet that scrolls keeps it, a sheet that does not loses '
            'it',
      );

      // And it can be REACHED: the list scrolls, so the row is not just
      // painted outside the visible area.
      await tester.scrollUntilVisible(
        find.textContaining('Quarter'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Quarter'), findsOneWidget);
    });

    testWidgets('a sheet full of shots does not lose the quarter', (
      WidgetTester tester,
    ) async {
      await openSheet(
        tester,
        item: product(halfPriceMinor: 5000, quarterPriceMinor: 2500),
        shots: <ShotCup>[
          for (var i = 1; i <= 6; i++)
            ShotCup(
              id: i,
              productId: 1,
              productName: 'Tusker',
              capacityMl: 30 * i,
              price: Money.fromMinor(1000 * i),
              updatedAt: '',
            ),
        ],
        height: 360,
      );

      expect(find.textContaining('Quarter'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('what it charges', () {
    testWidgets('the quarter carries the price the owner set', (
      WidgetTester tester,
    ) async {
      await openSheet(
        tester,
        item: product(
          sellPriceMinor: 10000,
          halfPriceMinor: 5000,
          quarterPriceMinor: 2500,
        ),
      );

      // 250 — the owner's quarter price, not a quarter of a price nobody
      // split, and not nothing. The currency symbol is left out of the
      // assertion because the formatter's own spacing is its business.
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              (w.data ?? '').contains('250') &&
              !(w.data ?? '').contains('500'),
        ),
        findsOneWidget,
      );
    });
  });
}
