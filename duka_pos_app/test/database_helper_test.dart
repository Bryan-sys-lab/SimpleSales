import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';

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
        costPrice: 500.0,
        sellPrice: 750.0,
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      await db.upsertProduct(product);
      final products = await db.getProducts();

      expect(products.length, equals(1));
      expect(products.first.name, equals('Test Product'));
      expect(products.first.stockQty, equals(10));
      expect(products.first.sellPrice, equals(750.0));
    });

    test('Record cash sale and decrement stock', () async {
      final product = Product(
        name: 'AAA Test Wine',
        category: 'Wine',
        costPrice: 500.0,
        sellPrice: 750.0,
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
            unitPrice: 750.0,
            unitCost: 500.0,
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
      expect(sales.first.total, equals(1500.0));
      expect(sales.first.profit, equals(500.0));
    });

    test('Prevent overselling', () async {
      final product = Product(
        name: 'AAA Limited Stock',
        category: 'Wine',
        costPrice: 500.0,
        sellPrice: 750.0,
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
              unitPrice: 750.0,
              unitCost: 500.0,
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
        costPrice: 100.0,
        sellPrice: 150.0,
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final p2 = Product(
        name: 'Product B',
        category: 'Wine',
        costPrice: 200.0,
        sellPrice: 300.0,
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
              unitPrice: 150.0,
              unitCost: 100.0,
            ),
            SaleItem(
              saleId: 0,
              productId: id2,
              productName: 'Product B',
              qty: 5,
              unitPrice: 300.0,
              unitCost: 200.0,
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
        costPrice: 500.0,
        sellPrice: 750.0,
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
        costPrice: 100,
        sellPrice: 150,
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
              unitPrice: 100,
              unitCost: 50,
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
  });

  group('Product Model Tests', () {
    test('Margin calculation', () {
      final product = Product(
        name: 'Test',
        category: 'Wine',
        costPrice: 500.0,
        sellPrice: 750.0,
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
        costPrice: 500.0,
        sellPrice: 750.0,
        stockQty: 3,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final product2 = Product(
        name: 'Good Stock',
        category: 'Wine',
        costPrice: 500.0,
        sellPrice: 750.0,
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      expect(product1.isLow, isTrue);
      expect(product2.isLow, isFalse);
    });
  });
}
