import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/utils/units.dart';
import 'package:duka_pos/profile/shop_profile.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Duka operational flow', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
      await db.setShopProfile(ShopProfile.duka);
    });

    test('create product from dashboard persists identical fields', () async {
      final product = Product(
        name: 'Maize Flour 2kg',
        category: 'Dry Goods',
        costPrice: Money.fromMajor(180.00),
        sellPrice: Money.fromMajor(220.00),
        stockQty: 50,
        reorderLevel: 10,
        unit: ProductUnit.each,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final id = await db.upsertProduct(product);
      expect(id, greaterThan(0));

      final retrieved = await db.getProductById(id);
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Maize Flour 2kg');
      expect(retrieved.category, 'Dry Goods');
      expect(retrieved.costPrice, Money.fromMajor(180.00));
      expect(retrieved.sellPrice, Money.fromMajor(220.00));
      expect(retrieved.stockQty, 50);
      expect(retrieved.reorderLevel, 10);
      expect(retrieved.unit, ProductUnit.each);
      expect(retrieved.trackVariants, isFalse);
    });

    test('start stock count and apply variance', () async {
      final product = Product(
        name: 'Sugar 1kg',
        category: 'Dry Goods',
        costPrice: Money.fromMajor(140.00),
        sellPrice: Money.fromMajor(170.00),
        stockQty: 30,
        reorderLevel: 5,
        unit: ProductUnit.each,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final productId = await db.upsertProduct(product);

      final countId = await db.startStockCount(
        uuid: 'count-001',
        staffId: 1,
        staffName: 'Cashier',
        blind: false,
        freeze: false,
        name: 'Sugar count',
        scopeType: 'all',
        note: 'Variance adjustment',
      );
      expect(countId, greaterThan(0));

      await db.applyStockCount(
        countId: countId,
        staffId: 1,
        staffName: 'Cashier',
      );

      final movements = await db.getStockMovements(productId);
      expect(movements.isNotEmpty, isTrue);
    });

    test('no unsupported variant flag is persisted for Duka product', () async {
      final product = Product(
        name: 'Cooking Oil',
        category: 'Cooking',
        costPrice: Money.fromMajor(200.00),
        sellPrice: Money.fromMajor(250.00),
        stockQty: 20,
        reorderLevel: 5,
        unit: ProductUnit.each,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final id = await db.upsertProduct(product);

      final retrieved = await db.getProductById(id);
      expect(retrieved!.trackVariants, isFalse);
    });
  });
}
