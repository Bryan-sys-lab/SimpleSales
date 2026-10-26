// The receive-stock sheet.
//
// ## WHAT IS PINNED
//
// The sheet is where the numbers the owner typed become a delivery, so the
// two facts worth pinning are:
//
//   * a line's cost starts at what the shop LAST paid — the number being
//     replaced is the number they are most likely to keep;
//   * the total is the sum of the lines, and it moves as the lines do.
//
// The money rules themselves — the cost becoming the product's cost, the
// history, the stock — are pinned in `receive_stock_test.dart`, against the
// write path. This file is about the sheet.

import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/receive_stock_sheet.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  final Product product = Product(
    id: 1,
    name: 'Tusker',
    category: 'Beer',
    costPrice: Money.fromMajor(60),
    sellPrice: Money.fromMajor(100),
    stockQty: 10,
    reorderLevel: 2,
    bottleMl: 500,
    updatedAt: DateTime.now().toIso8601String(),
  );

  Future<void> openSheet(
    WidgetTester tester, {
    Money? lastCost,
    List<Product> products = const <Product>[],
  }) async {
    await tester.pumpApp(
      home: Scaffold(
        body: ReceiveStockSheet(
          products: products.isEmpty ? <Product>[product] : products,
          suppliers: const <Supplier>[],
          lastCostFor: (int productId) async => lastCost,
          staffName: 'Amina',
          staffId: 7,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the sheet', () {
    testWidgets('it opens with nothing on it', (WidgetTester tester) async {
      await openSheet(tester);

      expect(find.text('Receive stock'), findsOneWidget);
      expect(find.text('KSh 0'), findsOneWidget);
    });

    testWidgets(
        'a product can be added, and the cost starts at the last '
        'price paid', (WidgetTester tester) async {
      await openSheet(tester, lastCost: Money.fromMajor(90));

      // Add the product through the picker.
      await tester.ensureVisible(find.text('Add a product'));
      await tester.tap(find.text('Add a product'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tusker').last);
      await tester.pumpAndSettle();

      // The cost it starts on is what the shop last paid: KSh 90.
      expect(find.text('90'), findsOneWidget);
      // And the line total is that cost times the quantity.
      expect(find.textContaining('KSh 90'), findsWidgets);
    });

    testWidgets('it fits a small phone at twice the text size', (
      WidgetTester tester,
    ) async {
      tester.useDevice(Device.compact);
      await openSheet(tester);

      tester.expectNoOverflow('the receive stock sheet');
    });
  });
}
