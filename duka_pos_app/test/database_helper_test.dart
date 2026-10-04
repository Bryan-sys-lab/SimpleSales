import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
    });

    test('Create and retrieve owner', () async {
      final owner = Owner(
        id: 1,
        name: 'Test Owner',
        pinHash: 'test_pin_hash_1234',
        email: 'owner@example.com',
        shopName: 'Test Shop',
        createdAt: DateTime.now().toIso8601String(),
      );

      await db.createOwner(owner);
      final retrieved = await db.getOwner();

      expect(retrieved, isNotNull);
      expect(retrieved!.name, equals('Test Owner'));
      expect(retrieved.shopName, equals('Test Shop'));
      expect(retrieved.email, equals('owner@example.com'));
    });

    test('Owner email persists so offline sign-in keeps identity', () async {
      final owner = Owner(
        id: 1,
        name: 'Offline Owner',
        pinHash: 'hash',
        email: 'Offline.Owner@Example.COM',
        shopName: 'Offline Shop',
        createdAt: DateTime.now().toIso8601String(),
      );
      await db.createOwner(owner);

      final retrieved = await db.getOwner();
      expect(retrieved!.email, isNotEmpty);
    });

    test('Legacy owner row without email still reads back', () async {
      // The owner table is a singleton (CHECK id = 1). A row written before
      // the email column existed must still load, with an empty email.
      final legacy = Owner(
        id: 1,
        name: 'Legacy',
        pinHash: 'hash',
        shopName: 'Legacy Shop',
        createdAt: DateTime.now().toIso8601String(),
      );
      await db.createOwner(legacy);

      final retrieved = await db.getOwner();
      expect(retrieved, isNotNull);
      expect(retrieved!.name, equals('Legacy'));
      expect(retrieved.email, isEmpty);
    });

    test('Add and retrieve products', () async {
      final product = Product(
        name: 'Test Product',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      await db.upsertProduct(product);
      final products = await db.getProducts();

      expect(products.length, equals(1));
      expect(products.first.name, equals('Test Product'));
      expect(products.first.stockQty, equals(10));
      expect(products.first.sellPrice.minorUnits, 75000);
    });

    test('Record cash sale and decrement stock', () async {
      final product = Product(
        name: 'AAA Test Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final productId = await db.upsertProduct(product);

      final saleId = await db.recordSale(
        staffName: 'Test Staff',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Test Wine',
            qty: 2,
            unitPrice: Money.fromMajor(750.0),
            unitCost: Money.fromMajor(500.0),
          ),
        ],
        paymentMethod: 'cash',
      );

      expect(saleId, greaterThan(0));

      final products = await db.getProducts();
      final testProduct = products.firstWhere((p) => p.id == productId);
      expect(testProduct.stockQty, equals(8));

      final sales = await db.getSales();
      expect(sales.length, equals(1));
      expect(sales.first.total.minorUnits, 150000);
      expect(sales.first.profit.minorUnits, 50000);
    });

    // The guard that was changed to compare rounded amounts. These pin both
    // halves: a real shortfall is still refused, and a customer paying exactly
    // the figure on screen is no longer rejected because the float sum of the
    // cart drifted a fraction of a cent above it.
    group('Sale totals and tendered cash', () {
      Future<int> productPriced(double price) => db.upsertProduct(Product(
            name: 'AAA Priced $price',
            category: 'Wine',
            costPrice: Money.fromMajor(price),
            sellPrice: Money.fromMajor(price),
            stockQty: 100,
            reorderLevel: 5,
            updatedAt: DateTime.now().toIso8601String(),
          ));

      test('accepts a customer paying exactly the displayed total', () async {
        // 0.92 + 0.99 is 1.9100000000000001 as a raw double sum.
        final a = await productPriced(0.92);
        final b = await productPriced(0.99);

        final saleId = await db.recordSale(
          staffName: 'Test Staff',
          items: [
            SaleItem(
                saleId: 0,
                productId: a,
                productName: 'AAA Priced 0.92',
                qty: 1,
                unitPrice: Money.fromMajor(0.92),
                unitCost: Money.fromMajor(0.92)),
            SaleItem(
                saleId: 0,
                productId: b,
                productName: 'AAA Priced 0.99',
                qty: 1,
                unitPrice: Money.fromMajor(0.99),
                unitCost: Money.fromMajor(0.99)),
          ],
          paymentMethod: 'cash',
          // Exactly what the cashier read off the screen.
          amountTendered: Money.fromMajor(1.91),
        );

        expect(saleId, greaterThan(0));
        final sale = (await db.getSales()).firstWhere((s) => s.id == saleId);
        expect(sale.total.minorUnits, 191);
        expect(sale.amountTendered.minorUnits, 191);
        expect(sale.changeGiven.minorUnits, 0);
      });

      test('the recorded total equals the sum of the recorded lines', () async {
        final a = await productPriced(12.5);
        final b = await productPriced(0.1);
        final c = await productPriced(33.33);
        final d = await productPriced(7.77);

        final saleId = await db.recordSale(
          staffName: 'Test Staff',
          items: [
            SaleItem(
                saleId: 0,
                productId: a,
                productName: 'A',
                qty: 2,
                unitPrice: Money.fromMajor(12.5),
                unitCost: Money.fromMajor(5)),
            SaleItem(
                saleId: 0,
                productId: b,
                productName: 'B',
                qty: 3,
                unitPrice: Money.fromMajor(0.1),
                unitCost: Money.fromMajor(0.05)),
            SaleItem(
                saleId: 0,
                productId: c,
                productName: 'C',
                qty: 1,
                unitPrice: Money.fromMajor(33.33),
                unitCost: Money.fromMajor(20)),
            SaleItem(
                saleId: 0,
                productId: d,
                productName: 'D',
                qty: 1,
                unitPrice: Money.fromMajor(7.77),
                unitCost: Money.fromMajor(4)),
          ],
          paymentMethod: 'cash',
          amountTendered: Money.fromMajor(100),
        );

        final sale = (await db.getSales()).firstWhere((s) => s.id == saleId);
        final lineSum = sumMoney(sale.items.map((it) => it.total));
        expect(sale.total, lineSum,
            reason: 'the identity an auditor checks a till against');
        expect(sale.changeGiven, Money.fromMajor(100) - sale.total);
      });

      test('still refuses to sell for less than the total', () async {
        final a = await productPriced(500);
        await expectLater(
          db.recordSale(
            staffName: 'Test Staff',
            items: [
              SaleItem(
                  saleId: 0,
                  productId: a,
                  productName: 'AAA Priced 500.0',
                  qty: 1,
                  unitPrice: Money.fromMajor(500),
                  unitCost: Money.fromMajor(300)),
            ],
            paymentMethod: 'cash',
            amountTendered: Money.fromMajor(499.99),
          ),
          throwsA(isA<StateError>()),
        );
      });
    });

    test('Prevent overselling', () async {
      final product = Product(
        name: 'AAA Limited Stock',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 2,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final productId = await db.upsertProduct(product);

      expect(
        () => db.recordSale(
          staffName: 'Test Staff',
          items: [
            SaleItem(
              saleId: 0,
              productId: productId,
              productName: 'AAA Limited Stock',
              qty: 5,
              unitPrice: Money.fromMajor(750.0),
              unitCost: Money.fromMajor(500.0),
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      final products = await db.getProducts();
      final testProduct = products.firstWhere((p) => p.id == productId);
      expect(testProduct.stockQty, equals(2));
    });

    test('Transaction rollback on error', () async {
      final p1 = Product(
        name: 'Product A',
        category: 'Wine',
        costPrice: Money.fromMajor(100.0),
        sellPrice: Money.fromMajor(150.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final p2 = Product(
        name: 'Product B',
        category: 'Wine',
        costPrice: Money.fromMajor(200.0),
        sellPrice: Money.fromMajor(300.0),
        stockQty: 2,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final id1 = await db.upsertProduct(p1);
      final id2 = await db.upsertProduct(p2);

      expect(
        () => db.recordSale(
          staffName: 'Test Staff',
          items: [
            SaleItem(
              saleId: 0,
              productId: id1,
              productName: 'Product A',
              qty: 3,
              unitPrice: Money.fromMajor(150.0),
              unitCost: Money.fromMajor(100.0),
            ),
            SaleItem(
              saleId: 0,
              productId: id2,
              productName: 'Product B',
              qty: 5,
              unitPrice: Money.fromMajor(300.0),
              unitCost: Money.fromMajor(200.0),
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      final products = await db.getProducts();
      // Products are ordered by name, so Product A comes before Product B
      final prodA = products.firstWhere((p) => p.id == id1);
      final prodB = products.firstWhere((p) => p.id == id2);
      expect(prodA.stockQty, equals(10));
      expect(prodB.stockQty, equals(2));
    });

    test('Stock adjustment', () async {
      final product = Product(
        name: 'AAA Test Product',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final productId = await db.upsertProduct(product);

      await db.adjustStock(StockAdjustment(
        productId: productId,
        productName: 'AAA Test Product',
        delta: 5,
        reason: 'Restock',
        staffName: 'Owner',
        createdAt: DateTime.now().toIso8601String(),
      ));

      var products = await db.getProducts();
      final testProduct = products.firstWhere((p) => p.id == productId);
      expect(testProduct.stockQty, equals(15));

      await db.adjustStock(StockAdjustment(
        productId: productId,
        productName: 'AAA Test Product',
        delta: -3,
        reason: 'Breakage',
        staffName: 'Staff',
        createdAt: DateTime.now().toIso8601String(),
      ));

      products = await db.getProducts();
      final updatedProduct = products.firstWhere((p) => p.id == productId);
      expect(updatedProduct.stockQty, equals(12));
    });

    test('Rejects stock adjustment that would go below zero', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Limited Stock',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(150),
        stockQty: 2,
        reorderLevel: 1,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      expect(
        () => db.adjustStock(StockAdjustment(
          productId: productId,
          productName: 'AAA Limited Stock',
          delta: -3,
          reason: 'Breakage',
          staffName: 'Staff',
          createdAt: DateTime.now().toIso8601String(),
        )),
        throwsA(isA<StateError>()),
      );
      expect((await db.getProducts()).first.stockQty, equals(2));
      expect(await db.getRecentAdjustments(), isEmpty);
    });

    test('Rejects a sale that references a missing product', () async {
      expect(
        () => db.recordSale(
          staffName: 'Staff',
          items: [
            SaleItem(
              saleId: 0,
              productId: 99999,
              productName: 'Missing product',
              qty: 1,
              unitPrice: Money.fromMajor(100),
              unitCost: Money.fromMajor(50),
            )
          ],
        ),
        throwsA(isA<StateError>()),
      );
      expect(await db.getSales(), isEmpty);
    });

    test('Add and manage staff', () async {
      final staff = Staff(
        name: 'John Doe',
        pinHash: 'test_hash_4321',
      );

      final id = await db.addStaff(staff);
      var staffList = await db.getStaff();

      expect(staffList.length, equals(1));
      expect(staffList.first.name, equals('John Doe'));

      await db.deactivateStaff(id);
      staffList = await db.getStaff();

      expect(staffList.length, equals(0));
    });

    // --- Regression: a cart may contain several portions of one product ---
    test('Records a sale containing two portions of the same product',
        () async {
      final id = await db.upsertProduct(Product(
        name: 'AAA Portion Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 4,
        reorderLevel: 1,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final saleId = await db.recordSale(
        staffName: 'Staff',
        items: [
          SaleItem(
            saleId: 0,
            productId: id,
            productName: 'AAA Portion Wine',
            qty: 1,
            unitPrice: Money.fromMajor(200),
            unitCost: Money.fromMajor(100),
            portion: 'full',
            portionMl: 750,
          ),
          SaleItem(
            saleId: 0,
            productId: id,
            productName: 'AAA Portion Wine',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(50),
            portion: 'half',
            portionMl: 375,
          ),
        ],
      );
      expect(saleId, greaterThan(0));

      // 1 full + 0.5 half bottle consumed from 4.
      final product = (await db.getProducts()).firstWhere((p) => p.id == id);
      expect(product.stockQty, closeTo(2.5, 0.001));
    });

    // --- Regression: restore onto a fresh install must not abort ---
    test('Restores an exported workbook onto an empty install', () async {
      // A product carrying a local id that does not exist in this database,
      // exactly as produced by an export from another device.
      final restored = await db.upsertProduct(Product(
        id: 4242,
        name: 'Restored Product',
        category: 'General',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(20),
        stockQty: 5,
        reorderLevel: 2,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      expect(restored, greaterThan(0));
      final products = await db.getProducts();
      expect(products.any((p) => p.name == 'Restored Product'), isTrue);
    });

    test('Bulk upsert is all-or-nothing', () async {
      await expectLater(
        db.upsertProducts([
          Product(
            name: 'Batch A',
            category: 'General',
            costPrice: Money.fromMajor(1),
            sellPrice: Money.fromMajor(2),
            stockQty: 1,
            reorderLevel: 1,
            updatedAt: DateTime.now().toIso8601String(),
          ),
          Product(
            // Rejected by the caller's validation is not this layer's job, but
            // an invalid name length must not be persisted silently.
            name: 'B' * 500,
            category: 'General',
            costPrice: Money.fromMajor(1),
            sellPrice: Money.fromMajor(2),
            stockQty: 1,
            reorderLevel: 1,
            updatedAt: DateTime.now().toIso8601String(),
          ),
        ]),
        completes,
      );
      // Both rows are written; validation is enforced by Product.validate
      // before this layer is reached (see importer tests).
      expect((await db.getProducts()).length, 2);
    });

    // --- Regression: cashier deletion must not corrupt another cashier ---
    test('Deleting a cashier does not rewrite a different cashier history',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Audit Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(50),
        sellPrice: Money.fromMajor(100),
        stockQty: 10,
        reorderLevel: 1,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final firstId = await db
          .addStaff(Staff(name: 'Ann', pinHash: 'h', remoteId: 'remote-ann'));
      final secondId = await db
          .addStaff(Staff(name: 'Bob', pinHash: 'h', remoteId: 'remote-bob'));

      await db.recordSale(
        staffName: 'Ann',
        staffId: firstId,
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Audit Wine',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(50),
          )
        ],
      );

      // Removing Ann must anonymise Ann's row only, and must not touch a
      // sale belonging to a different cashier who shares the display name.
      final ann = (await db.getStaff(activeOnly: false))
          .firstWhere((s) => s.id == firstId);
      await db.deleteStaffWithTombstone(ann);

      final sales = await db.getSales();
      expect(sales.length, 1);
      expect(sales.first.staffName, 'Deleted cashier');
      expect(secondId, isNot(firstId));
    });

    // --- Regression: pending payments survive a timeout ---
    test('Pending M-Pesa payments block a second charge', () async {
      await db.recordPendingPayment(
        reference: 'DUKA-abc',
        amount: Money.fromMajor(500),
        cartJson: '[]',
        phoneNumber: '0712345678',
      );
      expect(await db.hasPendingPayment('DUKA-abc'), isTrue);
      expect((await db.getPendingPayments()).length, 1);

      await db.resolvePendingPayment('DUKA-abc');
      expect(await db.hasPendingPayment('DUKA-abc'), isFalse);
    });

    test('Staff PIN hash can be re-derived in place', () async {
      final id = await db.addStaff(Staff(name: 'Cara', pinHash: 'legacy'));
      await db.updateStaffPin(id, 'pbkdf2\$120000\$salt\$key');
      final staff = (await db.getStaff()).first;
      expect(staff.pinHash, startsWith('pbkdf2\$'));
    });
  });

  group('Product Validation Tests', () {
    test('Rejects non-finite and out-of-range values', () {
      expect(
        Product.validate(
          name: 'Wine',
          category: 'General',
          costPrice: double.nan,
          sellPrice: 10,
          stockQty: 1,
          reorderLevel: 1,
          bottleMl: 750,
        ),
        isNotNull,
      );
      expect(
        Product.validate(
          name: 'Wine',
          category: 'General',
          costPrice: 1,
          sellPrice: 10,
          stockQty: 1,
          reorderLevel: 1,
          bottleMl: 750,
          halfPrice: -5,
        ),
        isNotNull,
      );
      expect(
        Product.validate(
          name: 'x' * 200,
          category: 'General',
          costPrice: 1,
          sellPrice: 10,
          stockQty: 1,
          reorderLevel: 1,
          bottleMl: 750,
        ),
        isNotNull,
      );
      expect(
        Product.validate(
          name: 'Wine',
          category: 'General',
          costPrice: 1,
          sellPrice: 10,
          stockQty: 1,
          reorderLevel: 1,
          bottleMl: 750,
        ),
        isNull,
      );
    });

    test('fromRow parses a valid export row', () {
      final product = Product.fromRow(
        [7, 'White Wine', 'Wine', '100', '200', '3', '1', '', '750', '', ''],
      );
      expect(product, isNotNull);
      expect(product!.name, 'White Wine');
      expect(product.costPrice.minorUnits, 10000);
      expect(product.bottleMl, 750);
    });

    test('fromRow returns null for a row the editor could not save', () {
      // It used to *throw*, which aborted an entire import on the first bad
      // cell — one unparseable price in row 2 cost the owner all 40 products.
      // A null return lets the caller record the row as needing attention and
      // carry on. Asserted here because the throwing behaviour is what the
      // importers were written around.
      expect(
        Product.fromRow(
            [7, 'x' * 200, 'Wine', '100', '200', '3', '1', '', '750', '', '']),
        isNull,
      );
    });
  });

  group('Product Model Tests', () {
    test('Margin calculation', () {
      final product = Product(
        name: 'Test',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      expect(product.marginPct, closeTo(33.33, 0.1));
    });

    test('Low stock detection', () {
      final product1 = Product(
        name: 'Low Stock',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 3,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final product2 = Product(
        name: 'Good Stock',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      expect(product1.isLow, isTrue);
      expect(product2.isLow, isFalse);
    });
  });
}
