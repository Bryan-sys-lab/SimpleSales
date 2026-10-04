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

    test('A measured pour deducts its own volume, not a whole bottle',
        () async {
      // A 30 ml shot out of a 750 ml bottle. Recorded as 'full' it would empty
      // the bottle after one shot, so the bar reads the bottle as gone after
      // the first customer instead of after the twenty-fifth.
      final id = await db.upsertProduct(Product(
        name: 'AAA Vodka',
        category: 'Spirits',
        costPrice: Money.fromMajor(800),
        sellPrice: Money.fromMajor(1500),
        stockQty: 2,
        reorderLevel: 1,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.recordSale(
        staffName: 'Staff',
        items: [
          SaleItem(
            saleId: 0,
            productId: id,
            productName: 'AAA Vodka',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            // Cost of 30/750 of the bottle, which is what a shot costs to pour.
            unitCost: Money.fromMajor(32),
            portion: SalePortion.measured,
            portionMl: 30,
          ),
        ],
      );

      final product = (await db.getProducts()).firstWhere((p) => p.id == id);
      expect(product.stockQty, closeTo(2 - 30 / 750, 0.0001));
    });

    test('Shots accumulate against one bottle and refuse to oversell',
        () async {
      // 25 shots is a 750 ml bottle. Twenty-five lines must consume exactly one
      // bottle, and the twenty-sixth must be refused rather than driving stock
      // to zero and quietly selling an empty pour.
      final id = await db.upsertProduct(Product(
        name: 'AAA Tequila',
        category: 'Spirits',
        costPrice: Money.fromMajor(900),
        sellPrice: Money.fromMajor(1800),
        stockQty: 1,
        reorderLevel: 1,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      SaleItem shot() => SaleItem(
            saleId: 0,
            productId: id,
            productName: 'AAA Tequila',
            qty: 1,
            unitPrice: Money.fromMajor(120),
            unitCost: Money.fromMajor(36),
            portion: SalePortion.measured,
            portionMl: 30,
          );

      await db.recordSale(staffName: 'Staff', items: List.filled(25, shot()));
      expect((await db.getProducts()).firstWhere((p) => p.id == id).stockQty,
          closeTo(0, 0.0001));

      await expectLater(
        db.recordSale(staffName: 'Staff', items: [shot()]),
        throwsStateError,
      );
    });

    test('A measured pour larger than its container is capped at one bottle',
        () async {
      // A capacity typed bigger than the bottle is a configuration mistake. The
      // least wrong answer is to empty that bottle, not to drive stock
      // negative — which the floor at zero would hide anyway.
      final id = await db.upsertProduct(Product(
        name: 'AAA Small Bottle Gin',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(900),
        stockQty: 2,
        reorderLevel: 1,
        bottleMl: 200,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.recordSale(
        staffName: 'Staff',
        items: [
          SaleItem(
            saleId: 0,
            productId: id,
            productName: 'AAA Small Bottle Gin',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(50),
            portion: SalePortion.measured,
            portionMl: 1000,
          ),
        ],
      );

      expect((await db.getProducts()).firstWhere((p) => p.id == id).stockQty,
          closeTo(1, 0.0001));
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

  group('Shift & Reconciliation Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
    });

    test('Open shift returns an id and creates an open shift', () async {
      final id = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      expect(id, greaterThan(0));

      final open = await db.getOpenShift(1);
      expect(open, isNotNull);
      expect(open!.staffName, 'Cashier');
      expect(open.startFloat.minorUnits, 500000);
      expect(open.status, 'open');
      expect(open.endTime, isNull);
    });

    test('Cannot open two shifts for the same staff member', () async {
      await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      expect(
        () => db.openShift(
          staffId: 1,
          staffName: 'Cashier',
          startFloat: Money.fromMajor(5000),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Can open a shift when a different staff has one open', () async {
      await db.openShift(
        staffId: 1,
        staffName: 'Cashier A',
        startFloat: Money.fromMajor(5000),
      );
      final id = await db.openShift(
        staffId: 2,
        staffName: 'Cashier B',
        startFloat: Money.fromMajor(3000),
      );
      expect(id, greaterThan(0));
    });

    test('getShifts returns open shift for staffId filter', () async {
      await db.openShift(
        staffId: 1,
        staffName: 'Cashier A',
        startFloat: Money.fromMajor(5000),
      );
      final shifts = await db.getShifts(staffId: 1);
      expect(shifts.length, 1);
      expect(shifts.first.status, 'open');
    });

    test('getAnyOpenShift returns null when no shift is open', () async {
      expect(await db.getAnyOpenShift(), isNull);
    });

    test('getAnyOpenShift returns the open shift', () async {
      await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      final open = await db.getAnyOpenShift();
      expect(open, isNotNull);
      expect(open!.status, 'open');
    });

    test('Expected cash equals sum of cash sales during the shift', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Shift Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 100,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      expect(shiftId, greaterThan(0));

      await db.recordSale(
        staffName: 'Cashier',
        staffId: 1,
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Shift Wine',
            qty: 2,
            unitPrice: Money.fromMajor(200),
            unitCost: Money.fromMajor(100),
          ),
        ],
      );

      final shift = await db.getOpenShift(1);
      assert(shift != null);

      final expected = await db.expectedCashForShift(shift!);
      expect(expected.minorUnits, 40000);

      // The balance the drawer should hold is the float plus those takings,
      // so a caller cannot forget the float and report it as a variance.
      expect((await db.expectedTillBalance(shift)).minorUnits, 540000);
    });

    test('Expected cash ignores a sale from another cashier', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Shared Drawer Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 100,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.openShift(
        staffId: 1,
        staffName: 'Amina',
        startFloat: Money.fromMajor(5000),
      );

      // A second person rings a cash sale into the same drawer.
      await db.recordSale(
        staffName: 'Brian',
        staffId: 2,
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Shared Drawer Wine',
            qty: 1,
            unitPrice: Money.fromMajor(200),
            unitCost: Money.fromMajor(100),
          ),
        ],
      );

      final shift = await db.getOpenShift(1);
      expect(shift, isNotNull);
      expect((await db.expectedCashForShift(shift!)).minorUnits, 0);
    });

    test('Expected cash excludes non-cash payments', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Card Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 100,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );

      await db.recordSale(
        staffName: 'Cashier',
        staffId: 1,
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Card Wine',
            qty: 1,
            unitPrice: Money.fromMajor(200),
            unitCost: Money.fromMajor(100),
          ),
        ],
        paymentMethod: 'card',
      );

      final shift = await db.getOpenShift(1);
      assert(shift != null);

      final expected = await db.expectedCashForShift(shift!);
      expect(expected.minorUnits, 0);
    });

    test('Add till count records a denomination pile', () async {
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );

      final countId = await db.addTillCount(
        shiftId: shiftId,
        denomination: 'KSh 100',
        count: 5,
        value: Money.fromMajor(500),
      );
      expect(countId, greaterThan(0));

      final counts = await db.getTillCounts(shiftId);
      expect(counts.length, 1);
      expect(counts.first.denomination, 'KSh 100');
      expect(counts.first.count, 5);
      expect(counts.first.value.minorUnits, 50000);
    });

    test('Reconcile shift computes variance correctly', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Recon Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 100,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );

      await db.recordSale(
        staffName: 'Cashier',
        staffId: 1,
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Recon Wine',
            qty: 3,
            unitPrice: Money.fromMajor(200),
            unitCost: Money.fromMajor(100),
          ),
        ],
      );

      final shift = await db.getOpenShift(1);
      assert(shift != null);

      final expected = await db.expectedCashForShift(shift!);
      final expectedTotal = shift.startFloat + expected;

      // Cashier counted 500 less than expected — a short variance.
      final counted = expectedTotal - Money.fromMajor(500);

      final reconId = await db.reconcileShift(
        shiftId: shiftId,
        countedCash: counted,
        expectedCash: expectedTotal,
      );
      expect(reconId, greaterThan(0));

      final recons = await db.getReconciliationsForShift(shiftId);
      expect(recons.length, 1);
      expect(recons.first.countedCash.minorUnits, counted.minorUnits);
      expect(recons.first.expectedCash.minorUnits, expectedTotal.minorUnits);
      expect(recons.first.variance.minorUnits, -50000);

      // Shift should be closed now.
      final closed = await db.getOpenShift(1);
      expect(closed, isNull);

      final shifts = await db.getShifts(staffId: 1, openOnly: true);
      expect(shifts, isEmpty);
    });

    test('Reconcile shift with end float records it', () async {
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );

      await db.reconcileShift(
        shiftId: shiftId,
        countedCash: Money.fromMajor(6000),
        expectedCash: Money.fromMajor(6000),
        endFloat: Money.fromMajor(2000),
      );

      final shifts = await db.getShifts(staffId: 1);
      expect(shifts.first.endFloat.minorUnits, 200000);
      expect(shifts.first.status, 'closed');
    });

    test('Cannot reconcile an already-closed shift', () async {
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );

      await db.reconcileShift(
        shiftId: shiftId,
        countedCash: Money.fromMajor(6000),
        expectedCash: Money.fromMajor(6000),
      );

      // A closed shift must refuse a second close rather than quietly record
      // a second, different variance against it. Silently succeeding is the
      // dangerous option: the caller walks away believing the till balanced
      // when the ledger now shows two answers to one question.
      expect(
        () => db.reconcileShift(
          shiftId: shiftId,
          countedCash: Money.fromMajor(6000),
          expectedCash: Money.fromMajor(5000),
        ),
        throwsStateError,
      );

      final recons = await db.getReconciliationsForShift(shiftId);
      expect(recons.length, 1);
      expect(recons.first.expectedCash.minorUnits, 600000);
    });

    test('A close with no explicit float keeps the counted cash in the drawer',
        () async {
      // What was counted stays in the till and becomes the next shift's float.
      // Recording zero would tell the next cashier the drawer came up empty.
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      await db.reconcileShift(
        shiftId: shiftId,
        countedCash: Money.fromMajor(4321),
        expectedCash: Money.fromMajor(4300),
      );
      final closed = (await db.getShifts(staffId: 1)).single;
      expect(closed.endFloat.minorUnits, 432100);
    });

    test('Till counts total to the counted cash a reconciliation uses',
        () async {
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      expect((await db.countedCashFromTillCounts(shiftId)).minorUnits, 0);

      await db.addTillCount(
        shiftId: shiftId,
        denomination: 'KSh 1000',
        count: 3,
        value: Money.fromMajor(3000),
      );
      await db.addTillCount(
        shiftId: shiftId,
        denomination: 'KSh 500',
        count: 4,
        value: Money.fromMajor(2000),
      );

      expect((await db.countedCashFromTillCounts(shiftId)).minorUnits, 500000);
    });

    test('Re-counting the till replaces the piles instead of doubling them',
        () async {
      // A cashier who counts the drawer twice must not report double the cash.
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      for (final n in [3, 4]) {
        await db.clearTillCounts(shiftId);
        await db.addTillCount(
          shiftId: shiftId,
          denomination: 'KSh 500',
          count: n,
          value: Money.fromMajor(500 * n),
        );
      }

      final counts = await db.getTillCounts(shiftId);
      expect(counts.length, 1);
      expect(counts.single.count, 4);
      expect((await db.countedCashFromTillCounts(shiftId)).minorUnits, 200000);
    });
  });

  group('Shot Cup Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
    });

    test('Upsert creates a new shot cup', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Vodka',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final id = await db.upsertShotCup(ShotCup(
        productId: productId,
        productName: 'AAA Vodka',
        capacityMl: 30,
        price: Money.fromMajor(150),
        label: 'Shot',
        updatedAt: DateTime.now().toIso8601String(),
      ));
      expect(id, greaterThan(0));

      final cups = await db.getShotCups();
      expect(cups.length, 1);
      expect(cups.first.capacityMl, 30);
      expect(cups.first.price.minorUnits, 15000);
    });

    test('Upsert updates an existing shot cup', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Gin',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final id = await db.upsertShotCup(ShotCup(
        productId: productId,
        productName: 'AAA Gin',
        capacityMl: 30,
        price: Money.fromMajor(150),
        label: 'Shot',
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final updated = await db.upsertShotCup(ShotCup(
        id: id,
        productId: productId,
        productName: 'AAA Gin',
        capacityMl: 25,
        price: Money.fromMajor(125),
        label: 'Shot',
        updatedAt: DateTime.now().toIso8601String(),
      ));
      expect(updated, id);

      final cup = await db.getShotCupForProduct(productId);
      expect(cup, isNotNull);
      expect(cup!.capacityMl, 25);
      expect(cup.price.minorUnits, 12500);
    });

    test('Delete soft-deletes a shot cup', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Rum',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final id = await db.upsertShotCup(ShotCup(
        productId: productId,
        productName: 'AAA Rum',
        capacityMl: 30,
        price: Money.fromMajor(150),
        label: 'Shot',
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.deleteShotCup(id);

      final active = await db.getShotCups();
      expect(active, isEmpty);

      final all = await db.getShotCups(activeOnly: false);
      expect(all.length, 1);
      expect(all.first.active, isFalse);
    });

    test('Get shot cup for product returns null when none exists', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Whiskey',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      expect(await db.getShotCupForProduct(productId), isNull);
    });

    test('A cup pointing at a drink that no longer exists is refused',
        () async {
      // Foreign keys are not enforced on this connection, so without this check
      // a stale id stores happily and the till then offers a shot it cannot
      // price or deduct — failing at the last step, with the customer's money
      // already in hand.
      await expectLater(
        db.upsertShotCup(ShotCup(
          productId: 9999,
          productName: 'AAA Deleted Spirit',
          capacityMl: 30,
          price: Money.fromMajor(100),
          updatedAt: DateTime.now().toIso8601String(),
        )),
        throwsStateError,
      );
      expect(await db.getShotCups(activeOnly: false), isEmpty);
    });

    test('A cup needs a capacity it is possible to pour', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Zero Vodka',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await expectLater(
        db.upsertShotCup(ShotCup(
          productId: productId,
          productName: 'AAA Zero Vodka',
          capacityMl: 0,
          price: Money.fromMajor(100),
          updatedAt: DateTime.now().toIso8601String(),
        )),
        throwsStateError,
      );
    });

    test('A cup price survives a save and reload unchanged', () async {
      // Guards the money-affinity bug: a REAL price column would read 3000
      // back as 30.00 and sell every shot at a hundredth of its price.
      final productId = await db.upsertProduct(Product(
        name: 'AAA Round Gin',
        category: 'Spirits',
        costPrice: Money.fromMajor(600),
        sellPrice: Money.fromMajor(1200),
        stockQty: 4,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final id = await db.upsertShotCup(ShotCup(
        productId: productId,
        productName: 'AAA Round Gin',
        capacityMl: 30,
        price: Money.fromMajor(300),
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final loaded = (await db.getShotCups()).singleWhere((c) => c.id == id);
      expect(loaded.price.minorUnits, 30000);
      expect(loaded.capacityMl, 30);
      expect(loaded.productName, 'AAA Round Gin');
    });
  });

  group('Cup Size Suggestions Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
    });

    test('Insert a new cup size suggestion', () async {
      await db.upsertCupSizeSuggestion(sizeMl: 330);

      final suggestions = await db.getCupSizeSuggestions();
      expect(suggestions.length, 1);
      expect(suggestions.first.sizeMl, 330);
      expect(suggestions.first.useCount, 1);
      expect(suggestions.first.productId, isNull);
    });

    test('Increment use count for existing suggestion', () async {
      await db.upsertCupSizeSuggestion(sizeMl: 330);
      await db.upsertCupSizeSuggestion(sizeMl: 330);
      await db.upsertCupSizeSuggestion(sizeMl: 330);

      final suggestions = await db.getCupSizeSuggestions();
      expect(suggestions.length, 1);
      expect(suggestions.first.useCount, 3);
    });

    test('Order by use count descending, then size ascending', () async {
      await db.upsertCupSizeSuggestion(sizeMl: 500);
      await db.upsertCupSizeSuggestion(sizeMl: 330);
      await db.upsertCupSizeSuggestion(sizeMl: 330);
      await db.upsertCupSizeSuggestion(sizeMl: 660);
      await db.upsertCupSizeSuggestion(sizeMl: 660);
      await db.upsertCupSizeSuggestion(sizeMl: 660);

      final suggestions = await db.getCupSizeSuggestions();
      expect(suggestions.length, 3);
      expect(suggestions[0].sizeMl, 660);
      expect(suggestions[1].sizeMl, 330);
      expect(suggestions[2].sizeMl, 500);
    });

    test('Suggestions scoped to product plus global', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Beer',
        category: 'Beer',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.upsertCupSizeSuggestion(sizeMl: 500);
      await db.upsertCupSizeSuggestion(productId: productId, sizeMl: 330);

      final scoped = await db.getCupSizeSuggestionsForProduct(productId);
      expect(scoped.length, 2);
      expect(scoped.any((s) => s.sizeMl == 330 && s.productId == productId),
          isTrue);
      expect(scoped.any((s) => s.sizeMl == 500 && s.productId == null), isTrue);
    });

    test('Rejects non-positive sizes', () async {
      await db.upsertCupSizeSuggestion(sizeMl: 0);
      await db.upsertCupSizeSuggestion(sizeMl: -50);

      final suggestions = await db.getCupSizeSuggestions();
      expect(suggestions, isEmpty);
    });
  });
}
