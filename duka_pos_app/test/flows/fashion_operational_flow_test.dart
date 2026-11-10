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

  group('Fashion operational flow', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
      await db.setShopProfile(ShopProfile.fashion);
    });

    test('create style with variants persists parent and variants', () async {
      final product = Product(
        name: 'Summer Dress',
        category: 'Dresses',
        costPrice: Money.fromMajor(1500.00),
        sellPrice: Money.fromMajor(2500.00),
        stockQty: 0,
        reorderLevel: 5,
        unit: ProductUnit.each,
        trackVariants: true,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final productId = await db.upsertProduct(product);
      expect(productId, greaterThan(0));

      final small = ProductVariant(
        productId: productId,
        name: 'Small',
        sku: 'SD-SMALL',
        unit: ProductUnit.each,
        sizeMl: 0,
        sellPrice: Money.fromMajor(2500.00),
        costPrice: Money.fromMajor(1500.00),
        stockQty: 10,
        active: true,
      );
      final medium = ProductVariant(
        productId: productId,
        name: 'Medium',
        sku: 'SD-MEDIUM',
        unit: ProductUnit.each,
        sizeMl: 0,
        sellPrice: Money.fromMajor(2500.00),
        costPrice: Money.fromMajor(1500.00),
        stockQty: 15,
        active: true,
      );

      await db.upsertVariant(small);
      await db.upsertVariant(medium);

      final variants = await db.getVariants(productId, activeOnly: true);
      expect(variants.length, 2);
      expect(variants.any((v) => v.name == 'Small'), isTrue);
      expect(variants.any((v) => v.name == 'Medium'), isTrue);
    });

    test('edit style updates parent without losing variants', () async {
      final product = Product(
        name: 'Winter Coat',
        category: 'Coats',
        costPrice: Money.fromMajor(3000.00),
        sellPrice: Money.fromMajor(5000.00),
        stockQty: 5,
        reorderLevel: 2,
        unit: ProductUnit.each,
        trackVariants: true,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final productId = await db.upsertProduct(product);

      await db.upsertVariant(ProductVariant(
        productId: productId,
        name: 'Black',
        sku: 'WC-BLACK',
        unit: ProductUnit.each,
        sizeMl: 0,
        sellPrice: Money.fromMajor(5000.00),
        costPrice: Money.fromMajor(3000.00),
        stockQty: 5,
        active: true,
      ));

      final updated = Product(
        id: productId,
        name: 'Winter Coat Deluxe',
        category: 'Coats',
        costPrice: Money.fromMajor(3200.00),
        sellPrice: Money.fromMajor(5200.00),
        stockQty: 5,
        reorderLevel: 2,
        unit: ProductUnit.each,
        trackVariants: true,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      await db.upsertProduct(updated);

      final retrieved = await db.getProductById(productId);
      expect(retrieved!.name, 'Winter Coat Deluxe');
      expect(retrieved.costPrice, Money.fromMajor(3200.00));

      final variants = await db.getVariants(productId, activeOnly: true);
      expect(variants.length, 1);
      expect(variants.first.name, 'Black');
    });

    test('remove variant deletes variant row', () async {
      final product = Product(
        name: 'Test Shirt',
        category: 'Shirts',
        costPrice: Money.fromMajor(800.00),
        sellPrice: Money.fromMajor(1200.00),
        stockQty: 10,
        reorderLevel: 3,
        unit: ProductUnit.each,
        trackVariants: true,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final productId = await db.upsertProduct(product);

      await db.upsertVariant(ProductVariant(
        productId: productId,
        name: 'Red',
        sku: 'TS-RED',
        unit: ProductUnit.each,
        sizeMl: 0,
        sellPrice: Money.fromMajor(1200.00),
        costPrice: Money.fromMajor(800.00),
        stockQty: 10,
        active: true,
      ));

      final variants = await db.getVariants(productId, activeOnly: true);
      expect(variants.length, 1);

      await db.deleteVariant(variants.first.id!);

      final remaining = await db.getVariants(productId, activeOnly: true);
      expect(remaining.length, 0);
    });
  });
}
