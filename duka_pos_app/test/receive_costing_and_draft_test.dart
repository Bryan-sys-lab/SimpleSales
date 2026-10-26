// How a delivery is PRICED, what survives an app kill, and the void.
//
// ## WHAT THIS IS FOR
//
// The costing mode decides every margin figure the shop will read until the
// next delivery: weighted average (the default) blends the incoming cost with
// what is still on the shelf; last cost replaces it. The draft is what the
// person at the counter loses nothing to. The void is the owner's way back
// out of a mistyped delivery, and its rules are where the stock can fight
// back — a void of goods already sold would be a make-believe correction.
//
// ## WHAT IS PINNED
//
//   * weighted average: blend, half-up, negative shelf clamped to zero,
//     first-stock-is-cost — every boundary the spec names;
//   * last cost replaces outright;
//   * the draft round-trips and clears, per staff member;
//   * the void restores stock and (only where no later receipt claims the
//     cost) the cost; a short shelf refuses the whole void, which changes
//     nothing;
//   * supplier numbers are canonical Kenyan numbers or refused.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/screens/receive_stock_sheet.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/models/stock_movement.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  /// A product on the shelf, at a known cost.
  Future<int> seedProduct({double cost = 60, double stock = 10}) async {
    final int id = await DatabaseHelper.instance.upsertProduct(Product(
      name: 'Tusker',
      category: 'Beer',
      costPrice: Money.fromMajor(cost),
      sellPrice: Money.fromMajor(100),
      stockQty: stock,
      reorderLevel: 2,
      bottleMl: 500,
      updatedAt: DateTime.now().toIso8601String(),
    ));
    expect(id, greaterThan(0));
    return id;
  }

  Future<Product> product(int id) async =>
      (await DatabaseHelper.instance.getProducts())
          .firstWhere((Product p) => p.id == id);

  group('weighted average costing (the default)', () {
    test('no stock on hand: the delivery IS the cost', () async {
      final int productId = await seedProduct(cost: 60, stock: 0);
      await DatabaseHelper.instance.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 24,
            unitCost: Money.fromMajor(100),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );
      expect((await product(productId)).costPrice, Money.fromMajor(100));
    });

    test('the shelf and the delivery blend, half-up', () async {
      // 10 on hand @ 60 = 60000 minor; 24 in @ 100.90 => 10090*24 = 242160;
      // (60000 + 242160) / 34 = 8887.06 — 8887 half-up.
      final int productId = await seedProduct(cost: 60, stock: 10);
      await DatabaseHelper.instance.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 24,
            unitCost: Money.fromMinor(10090),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );
      expect((await product(productId)).costPrice, Money.fromMinor(8887));
    });

    test('a negative shelf counts as zero, not as credit', () async {
      // −8 on hand does not donate −48000 to the blend: stock below zero is
      // a stocktake problem, and pricing it in would dive the cost.
      final int productId = await seedProduct(cost: 60, stock: -8);
      await DatabaseHelper.instance.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 24,
            unitCost: Money.fromMajor(100),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );
      expect((await product(productId)).costPrice, Money.fromMajor(100));
    });

    test('the delivery total is what was PAID, not the blended figure', () async {
      // The blend prices the SHELF; the receipt's total is the invoice.
      final int productId = await seedProduct(cost: 60, stock: 10);
      await DatabaseHelper.instance.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 12,
            unitCost: Money.fromMajor(90),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );
      final StockReceipt receipt =
          (await DatabaseHelper.instance.getStockReceipts()).single;
      expect(receipt.totalCost, Money.fromMajor(1080));
    });

    test('the history keeps the old and new figures', () async {
      // 10 @ 60 blend with 12 @ 90 = (60000 + 108000) / 22 = 7636.36 → 7636.
      final int productId = await seedProduct(cost: 60, stock: 10);
      await DatabaseHelper.instance.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 12,
            unitCost: Money.fromMajor(90),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );
      final StockReceipt receipt =
          (await DatabaseHelper.instance.getStockReceipts()).single;
      expect(receipt.items.single.oldCost, Money.fromMajor(60));
      // A blended figure, to the minor unit, is the point of the snapshot.
      expect(receipt.items.single.newCost, Money.fromMinor(7636));
    });
  });

  group('last-cost mode (the shop setting)', () {
    test('replaces the cost outright', () async {
      final int productId = await seedProduct(cost: 60, stock: 10);
      await DatabaseHelper.instance.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 12,
            unitCost: Money.fromMajor(90),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
        costingMode: 'last_cost',
      );
      expect((await product(productId)).costPrice, Money.fromMajor(90));
    });

    test('an unknown mode is refused, not interpreted', () async {
      final int productId = await seedProduct();
      await expectLater(
        DatabaseHelper.instance.postStockReceipt(
          lines: [
            StockReceiptLine(
              productId: productId,
              productName: 'Tusker',
              qty: 12,
              unitCost: Money.fromMajor(90),
            ),
          ],
          staffName: 'Amina',
          staffId: 7,
          costingMode: 'average-ish',
        ),
        throwsArgumentError,
      );
    });
  });

  group('the receive-session draft', () {
    test('round-trips per staff member and clears', () async {
      await DatabaseHelper.instance.saveReceiveDraft(7, <String, Object?>{
        'supplier_id': 3,
        'supplier_ref': 'INV-77',
        'lines': <Object?>[
          <String, Object?>{
            'product_id': 1,
            'product_name': 'Tusker',
            'qty': 6,
            'unit_cost_minor': 9000,
          },
        ],
      });
      Map<String, dynamic>? draft =
          await DatabaseHelper.instance.getReceiveDraft(7);
      expect(draft, isNotNull);
      final ReceiveDraftSnapshot? snapshot =
          ReceiveDraftSnapshot.fromJson(draft!);
      expect(snapshot, isNotNull);
      expect(snapshot!.supplierId, 3);
      expect(snapshot.supplierRef, 'INV-77');
      expect(snapshot.lines.single.productName, 'Tusker');
      expect(snapshot.lines.single.unitCost, Money.fromMajor(90));

      // Post clears it: a filed delivery has no draft left standing.
      await DatabaseHelper.instance.saveReceiveDraft(7, null);
      draft = await DatabaseHelper.instance.getReceiveDraft(7);
      expect(draft, isNull);
    });

    test('one staff member\'s draft is their own', () async {
      await DatabaseHelper.instance.saveReceiveDraft(7, <String, Object?>{
        'lines': <Object?>[
          <String, Object?>{
            'product_id': 1,
            'product_name': 'Tusker',
            'qty': 1,
            'unit_cost_minor': 100,
          },
        ],
      });
      expect(await DatabaseHelper.instance.getReceiveDraft(8), isNull);
      expect(
        (await DatabaseHelper.instance.getReceiveDraft(7))!,
        isNotNull,
      );
    });
  });

  group('voiding a posted delivery', () {
    test('restores the stock, and the cost where nothing later claims it',
        () async {
      final int productId = await seedProduct(cost: 60, stock: 0);
      final int receiptId = await DatabaseHelper.instance.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 12,
            unitCost: Money.fromMajor(90),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );
      // Cost and stock as the delivery left them.
      expect((await product(productId)).stockQty, 12);
      expect((await product(productId)).costPrice, Money.fromMajor(90));

      final int linesVoided = await DatabaseHelper.instance.voidStockReceipt(
        receiptId: receiptId,
        staffName: 'Owner',
        staffId: 1,
      );
      expect(linesVoided, 1);
      expect(
        (await DatabaseHelper.instance.getStockReceipts()).single.status,
        'voided',
      );
      expect((await product(productId)).stockQty, 0);
      // The cost rolls back: this delivery was the last thing to touch it.
      expect((await product(productId)).costPrice, Money.fromMajor(60));

      // The ledger says why: one receipt in, one void out, net zero.
      final List<StockMovement> movements =
          await DatabaseHelper.instance.getStockMovements(productId);
      final int receiptQty = movements
          .where((StockMovement m) => m.type == StockMovementType.receipt)
          .fold<double>(0, (double sum, StockMovement m) => sum + m.qtyDelta)
          .round();
      final int voidQty = movements
          .where((StockMovement m) => m.type == StockMovementType.receiptVoid)
          .fold<double>(0, (double sum, StockMovement m) => sum + m.qtyDelta)
          .round();
      expect(receiptQty, 12);
      expect(voidQty, -12);
    });

    test('a shelf that consumed the goods refuses the void, which changes '
        'nothing', () async {
      final int productId = await seedProduct(cost: 60, stock: 0);
      final int receiptId = await DatabaseHelper.instance.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 12,
            unitCost: Money.fromMajor(90),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );
      // Half the delivery sold.
      await DatabaseHelper.instance.upsertProduct(
        (await product(productId)).copyWith(stockQty: 5),
      );

      await expectLater(
        DatabaseHelper.instance.voidStockReceipt(
          receiptId: receiptId,
          staffName: 'Owner',
        ),
        throwsStateError,
      );
      // Nothing moved: the stock stands, and the receipt stands posted.
      expect((await product(productId)).stockQty, 5);
      expect(
        (await DatabaseHelper.instance.getStockReceipts()).single.status,
        'posted',
      );
    });

    test('a voiding twice is refused', () async {
      final int productId = await seedProduct(cost: 60, stock: 0);
      final int receiptId = await DatabaseHelper.instance.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 12,
            unitCost: Money.fromMajor(90),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );
      await DatabaseHelper.instance
          .voidStockReceipt(receiptId: receiptId, staffName: 'Owner');
      await expectLater(
        DatabaseHelper.instance
            .voidStockReceipt(receiptId: receiptId, staffName: 'Owner'),
        throwsStateError,
      );
    });

    test('a cost a LATER delivery already moved is left alone by a void',
        () async {
      final int productId = await seedProduct(cost: 60, stock: 0);
      final int firstReceipt = await DatabaseHelper.instance.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 12,
            unitCost: Money.fromMajor(90),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );
      await DatabaseHelper.instance.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 12,
            unitCost: Money.fromMajor(120),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );
      await DatabaseHelper.instance
          .voidStockReceipt(receiptId: firstReceipt, staffName: 'Owner');
      // The newer delivery owns the cost now; rolling back the old receipt
      // would put a stale figure on a live one.
      expect(
        (await product(productId)).costPrice.minorUnits,
        inInclusiveRange(Money.fromMajor(90).minorUnits,
            Money.fromMajor(120).minorUnits),
      );
      expect(
        (await product(productId)).stockQty,
        12.0, // 24 minus the 12 the void took back.
      );
    });
  });

  group('supplier numbers', () {
    test('the local, national and international forms become one number',
        () async {
      for (final (String name, String typed) in const <(String, String)>[
        ('07xx form', '0712 345 678'),
        ('local bare', '0712345678'),
        ('national', '254712345678'),
        ('international', '+254 712 345 678'),
      ]) {
        final int id = await DatabaseHelper.instance.addSupplier(
          name: 'Supplier $name',
          phone: typed,
        );
        final List<Supplier> suppliers =
            await DatabaseHelper.instance.getSuppliers();
        expect(suppliers.firstWhere((Supplier s) => s.id == id).phone,
            '+254712345678', reason: name);
      }
    });

    test('a number that is not Kenyan is refused, not stored broken', () async {
      await expectLater(
        DatabaseHelper.instance.addSupplier(
          name: 'Foreign',
          phone: '+441632960437',
        ),
        throwsArgumentError,
      );
    });

    test('an optional number may be empty', () async {
      final int id = await DatabaseHelper.instance.addSupplier(name: 'Loose');
      final List<Supplier> suppliers =
          await DatabaseHelper.instance.getSuppliers();
      expect(suppliers.firstWhere((Supplier s) => s.id == id).phone, isNull);
    });
  });
}
