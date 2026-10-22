// Receiving stock, and what it cost.
//
// ## WHAT THIS IS FOR
//
// "Record stock coming in with its cost, keep product costs current, and keep
// a purchase history. Today cost is a static field, so profit drifts from
// reality."
//
// The drift is the whole point. A bottle bought at 90 and a bottle bought at
// 110 are the same bottle and different money, and the profit on every later
// sale is measured against the price the shop actually paid. So a delivery
// does three things at once: it puts the stock on the shelf, it sets the
// product's cost to what was paid, and it records HOW the cost got there.
//
// ## WHAT IS PINNED
//
//   * the stock arrives, and the ledger says so;
//   * the product's cost becomes what this delivery paid;
//   * the previous cost is kept, so a price that moved in March can be told
//     from one that moved last Tuesday;
//   * the total is the sum of the lines, in minor units — the same integer
//     cents the whole app counts in.

import 'package:duka_pos/db/database_helper.dart';
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

  group('the delivery', () {
    test('the stock arrives and the ledger says so', () async {
      final int productId = await seedProduct(stock: 10);
      final int receiptId = await DatabaseHelper.instance.postStockReceipt(
        lines: <StockReceiptLine>[
          StockReceiptLine(
            productId: productId,
            productName: 'Tusker',
            qty: 12,
            unitCost: Money.fromMajor(70),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );
      expect(receiptId, greaterThan(0));

      final Product after = (await DatabaseHelper.instance.getProducts())
          .firstWhere((Product p) => p.id == productId);
      expect(after.stockQty, 22);

      final List<StockMovement> movements =
          await DatabaseHelper.instance.getStockMovements(productId);
      expect(
        movements.any((StockMovement m) => m.type == StockMovementType.receipt),
        isTrue,
        reason: 'the goods arriving has to be in the ledger, or the count and '
            'the ledger stop agreeing',
      );
    });

    test('the cost becomes what was paid', () async {
      final int productId = await seedProduct(cost: 60);
      await DatabaseHelper.instance.postStockReceipt(
        lines: <StockReceiptLine>[
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

      final Product after = (await DatabaseHelper.instance.getProducts())
          .firstWhere((Product p) => p.id == productId);
      expect(after.costPrice, Money.fromMajor(90));
    });

    test('the previous cost is kept, so the drift is readable', () async {
      final int productId = await seedProduct(cost: 60);
      await DatabaseHelper.instance.postStockReceipt(
        lines: <StockReceiptLine>[
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
      final StockReceiptItem line = receipt.items.single;
      expect(line.oldCost, Money.fromMajor(60));
      expect(line.newCost, Money.fromMajor(90));
    });

    test('the total is the sum of the lines', () async {
      final int first = await seedProduct();
      final int second = await DatabaseHelper.instance.upsertProduct(Product(
        name: 'Balozi',
        category: 'Spirits',
        costPrice: Money.fromMajor(400),
        sellPrice: Money.fromMajor(650),
        stockQty: 5,
        reorderLevel: 1,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await DatabaseHelper.instance.postStockReceipt(
        lines: <StockReceiptLine>[
          StockReceiptLine(
            productId: first,
            productName: 'Tusker',
            qty: 12,
            unitCost: Money.fromMajor(90),
          ),
          StockReceiptLine(
            productId: second,
            productName: 'Balozi',
            qty: 6,
            unitCost: Money.fromMajor(400),
          ),
        ],
        staffName: 'Amina',
        staffId: 7,
      );

      final StockReceipt receipt =
          (await DatabaseHelper.instance.getStockReceipts()).single;
      // 12 at 90 is 1080; 6 at 400 is 2400.
      expect(receipt.totalCost, Money.fromMajor(3480));
    });

    test('a delivery of nothing is refused', () async {
      await expectLater(
        DatabaseHelper.instance.postStockReceipt(
          lines: <StockReceiptLine>[],
          staffName: 'Amina',
          staffId: 7,
        ),
        throwsStateError,
      );
    });

    test('a product that is not in the catalogue is refused', () async {
      await expectLater(
        DatabaseHelper.instance.postStockReceipt(
          lines: <StockReceiptLine>[
            StockReceiptLine(
              productId: 999,
              productName: 'Nothing',
              qty: 1,
              unitCost: Money.fromMajor(10),
            ),
          ],
          staffName: 'Amina',
          staffId: 7,
        ),
        throwsStateError,
      );
    });
  });

  group('the last cost', () {
    test('the next delivery can be prefilled with it', () async {
      final int productId = await seedProduct(cost: 60);
      await DatabaseHelper.instance.postStockReceipt(
        lines: <StockReceiptLine>[
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

      final Money? last =
          await DatabaseHelper.instance.lastCostForProduct(productId);
      expect(last, Money.fromMajor(90));
    });

    test('a product that has never been bought has no last cost', () async {
      final int productId = await seedProduct();
      expect(
          await DatabaseHelper.instance.lastCostForProduct(productId), isNull);
    });
  });

  group('the suppliers', () {
    test('a supplier is added and listed', () async {
      final int id = await DatabaseHelper.instance.addSupplier(
        name: 'Kentex Distributors',
        phone: '0712345678',
      );
      expect(id, greaterThan(0));
      final List<Supplier> suppliers =
          await DatabaseHelper.instance.getSuppliers();
      expect(suppliers.single.name, 'Kentex Distributors');
    });

    test('the same supplier is not added twice', () async {
      await DatabaseHelper.instance.addSupplier(name: 'Kentex');
      // The same name in a different case is the same supplier: a history that
      // splits them is a history nobody can read.
      await expectLater(
        DatabaseHelper.instance.addSupplier(name: 'kentex'),
        throwsStateError,
      );
    });

    test('a supplier needs a name', () async {
      await expectLater(
        DatabaseHelper.instance.addSupplier(name: '   '),
        throwsStateError,
      );
    });
  });

  group('the push', () {
    test('a posted delivery is pending until the server has it', () async {
      final int productId = await seedProduct();
      final int receiptId = await DatabaseHelper.instance.postStockReceipt(
        lines: <StockReceiptLine>[
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

      final List<StockReceipt> pending =
          await DatabaseHelper.instance.getUnsyncedReceipts();
      expect(pending.map((StockReceipt r) => r.id), contains(receiptId));

      await DatabaseHelper.instance.markReceiptsSynced(<int>[receiptId]);
      expect(await DatabaseHelper.instance.getUnsyncedReceipts(), isEmpty);
    });
  });
}
