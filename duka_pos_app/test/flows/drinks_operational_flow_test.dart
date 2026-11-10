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

  group('Drinks operational flow', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
      await db.setShopProfile(ShopProfile.drinks);
    });

    test('create beverage product persists pack-related fields', () async {
      final product = Product(
        name: 'Lager Beer 500ml',
        category: 'Beer',
        costPrice: Money.fromMajor(80.00),
        sellPrice: Money.fromMajor(120.00),
        stockQty: 24,
        reorderLevel: 6,
        unit: ProductUnit.each,
        bottleMl: 500,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final id = await db.upsertProduct(product);
      expect(id, greaterThan(0));

      final retrieved = await db.getProductById(id);
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Lager Beer 500ml');
      expect(retrieved.unit, ProductUnit.each);
      expect(retrieved.bottleMl, 500);
    });

    test('tank product persists capacity and volume fields', () async {
      final product = Product(
        name: 'Stout Tank A',
        category: 'Tanks',
        costPrice: Money.fromMajor(50000.00),
        sellPrice: Money.fromMajor(0.00),
        stockQty: 500,
        reorderLevel: 50,
        unit: ProductUnit.each,
        bottleMl: 50000,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final id = await db.upsertProduct(product);

      final retrieved = await db.getProductById(id);
      expect(retrieved!.category, 'Tanks');
      expect(retrieved.bottleMl, 50000);
    });

    test('variant with portion_ml persists for measured servings', () async {
      final product = Product(
        name: 'Stout Tank B',
        category: 'Tanks',
        costPrice: Money.fromMajor(40000.00),
        sellPrice: Money.fromMajor(0.00),
        stockQty: 1000,
        reorderLevel: 100,
        unit: ProductUnit.each,
        bottleMl: 50000,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final productId = await db.upsertProduct(product);

      final variant = ProductVariant(
        productId: productId,
        name: 'Pint',
        sku: 'STB-PINT',
        unit: ProductUnit.each,
        sizeMl: 568,
        sellPrice: Money.fromMajor(150.00),
        costPrice: Money.fromMajor(100.00),
        stockQty: 200,
        active: true,
      );
      final variantId = await db.upsertVariant(variant);

      final retrieved = await db.getVariantById(variantId);
      expect(retrieved, isNotNull);
      expect(retrieved!.sizeMl, 568);
      expect(retrieved.sellPrice, Money.fromMajor(150.00));
    });

    test('shot cup variant persists for serving configuration', () async {
      final product = Product(
        name: 'Whiskey',
        category: 'Spirits',
        costPrice: Money.fromMajor(3000.00),
        sellPrice: Money.fromMajor(0.00),
        stockQty: 700,
        reorderLevel: 100,
        unit: ProductUnit.each,
        bottleMl: 700,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final productId = await db.upsertProduct(product);

      final variant = ProductVariant(
        productId: productId,
        name: 'Shot 50ml',
        sku: 'WHISKEY-50ML',
        unit: ProductUnit.each,
        sizeMl: 50,
        sellPrice: Money.fromMajor(60.00),
        costPrice: Money.fromMajor(40.00),
        stockQty: 100,
        active: true,
      );
      final variantId = await db.upsertVariant(variant);
      expect(variantId, greaterThan(0));
    });
  });
}
