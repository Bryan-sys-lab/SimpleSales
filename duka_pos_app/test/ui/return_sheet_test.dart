// The return flow.
//
// ## WHAT IS PINNED
//
// The sheet is where the rules become visible, so the rules that live in the
// sheet are the ones that get their own test here:
//
//   * the stepper is limited by what has NOT already come back — a bottle can
//     be returned once, and the second time round the line says so and offers
//     nothing;
//   * the money to give back is the sum of the line refunds, and it moves as
//     the stepper moves;
//   * the sheet says WHY it refused, in a sentence a person can act on.
//
// The money rules themselves — the rounding, the cumulative quantity, the
// stock — are pinned in `returns_test.dart`, against the write path. This
// file is about the sheet.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/return_sale_sheet.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/harness.dart';

/// A product and a sale of two of it.
///
/// The database is real I/O on a background isolate, so this runs inside
/// `tester.runAsync` where the fake async zone of a widget test cannot
/// starve it.
Future<Sale> seedSale(
  WidgetTester tester, {
  double qty = 2,
  double price = 100,
}) async {
  late Sale sale;
  await tester.runAsync(() async {
    final DatabaseHelper db = DatabaseHelper.instance;
    final int productId = await db.upsertProduct(Product(
      name: 'Tusker',
      category: 'Beer',
      costPrice: Money.fromMajor(60),
      sellPrice: Money.fromMajor(price),
      stockQty: 20,
      reorderLevel: 2,
      bottleMl: 500,
      updatedAt: DateTime.now().toIso8601String(),
    ));
    await db.recordSale(
      staffName: 'Amina',
      staffId: 7,
      paymentMethod: 'cash',
      items: <SaleItem>[
        SaleItem(
          saleId: 0,
          productId: productId,
          productName: 'Tusker',
          qty: qty,
          unitPrice: Money.fromMajor(price),
          unitCost: Money.fromMajor(price * 0.6),
        ),
      ],
    );
    sale = (await db.getSales()).first;
  });
  return sale;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DatabaseHelper.openInMemoryForTests();
  });

  Future<void> openSheet(
    WidgetTester tester,
    Sale sale, {
    Map<int, double> alreadyReturned = const <int, double>{},
  }) async {
    await tester.pumpApp(
      home: Scaffold(
        body: ReturnSaleSheet(
          sale: sale,
          staffName: 'Amina',
          staffId: 7,
          alreadyReturned: alreadyReturned,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the stepper', () {
    testWidgets('it is limited by what is left to return', (
      WidgetTester tester,
    ) async {
      final Sale sale = await seedSale(tester, qty: 2);
      await openSheet(tester, sale);

      // Two were sold, so the stepper can go to two and no further.
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      // The third tap is refused: the button is disabled.
      final IconButton more = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.add_circle_outline),
          matching: find.byType(IconButton),
        ),
      );
      expect(more.onPressed, isNull);
    });

    testWidgets('a line that is fully returned says so and offers nothing', (
      WidgetTester tester,
    ) async {
      final Sale sale = await seedSale(tester, qty: 1);
      // The bottle has already come back.
      await tester.runAsync(() async {
        await DatabaseHelper.instance.recordReturn(
          sale: sale,
          lines: <ReturnLineDraft>[
            ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
          ],
          reason: 'Already returned',
          refundMethod: 'mpesa',
          staffName: 'Amina',
          staffId: 7,
        );
      });

      await openSheet(
        tester,
        sale,
        alreadyReturned: <int, double>{sale.items.single.id!: 1},
      );

      expect(find.text('All returned'), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    });
  });

  group('the money', () {
    testWidgets('it says what will be given back', (WidgetTester tester) async {
      final Sale sale = await seedSale(tester, qty: 2, price: 100);
      await openSheet(tester, sale);

      // Nothing chosen yet: nothing to give back.
      expect(find.text('KSh 0'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      // One bottle at KSh 100.
      expect(find.text('KSh 100'), findsOneWidget);
    });
  });

  group('the refusal', () {
    testWidgets('it says what to do, not that something went wrong', (
      WidgetTester tester,
    ) async {
      final Sale sale = await seedSale(tester, qty: 1);
      await openSheet(tester, sale);

      // No reason yet: the sheet says so.
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Give it back'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Say why it is coming back'), findsOneWidget);
    });
  });

  group('the layout', () {
    testWidgets('it fits a small phone at twice the text size', (
      WidgetTester tester,
    ) async {
      final Sale sale = await seedSale(tester, qty: 2);
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        textScaler: const TextScaler.linear(2.0),
        home: Scaffold(
          body: ReturnSaleSheet(
            sale: sale,
            staffName: 'Amina',
            staffId: 7,
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester.expectNoOverflow('the return sheet');
    });
  });
}
