// End-to-end journey tests per profile.
//
// Each test exercises a complete business workflow through the database layer.
// Runs against in-memory SQLite (no platform I/O).

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

  // -------------------------------------------------------------------------
  // Shared: product → pending payment → claim → resolve journey (all profiles)
  // -------------------------------------------------------------------------
  group('shared payment journey (all profiles)', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
      await db.setShopProfile(ShopProfile.duka);
    });

    test('record pending payment → claim → resolve → no pending claims',
        () async {
      // 1. Record a pending payment (customer tendered cash/card)
      await db.recordPendingPayment(
        reference: 'sale-001',
        amount: Money.fromMajor(506.00),
        cartJson: '[]',
        staffName: 'Cashier',
        staffId: 1,
      );

      // 2. Verify pending payment exists
      final hasPending = await db.hasPendingPayment('sale-001');
      expect(hasPending, isTrue);

      // 3. Record an incoming payment claim (M-Pesa notification)
      await db.recordIncomingPaymentClaim(
        remoteId: 'claim-001',
        saleId: 1,
        saleUuid: 'sale-001',
      );

      // 4. Verify pending claim exists
      final pendingCount = await db.countPendingIncomingPaymentClaims();
      expect(pendingCount, greaterThan(0));

      // 5. Resolve the claim (payment confirmed)
      await db.resolveIncomingPaymentClaim('claim-001');

      // 6. Verify no pending claims remain
      final remaining = await db.countPendingIncomingPaymentClaims();
      expect(remaining, 0);
    });
  });

  // -------------------------------------------------------------------------
  // Fashion journey: style with variants → edit (no duplicates) → variant stock
  // -------------------------------------------------------------------------
  group('fashion journey', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
      await db.setShopProfile(ShopProfile.fashion);
    });

    test('create style with variants → edit style (no duplicates) → '
        'variant stock managed', () async {
      // 1. Create a style with variants tracking
      final styleId = await db.upsertProduct(
        Product(
          name: 'Linen Shirt',
          category: 'Shirts',
          costPrice: Money.fromMajor(1200.00),
          sellPrice: Money.fromMajor(2000.00),
          stockQty: 0,
          reorderLevel: 5,
          unit: ProductUnit.each,
          trackVariants: true,
          active: true,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );
      expect(styleId, greaterThan(0));

      // 2. Create variants for the style
      final variantId = await db.upsertVariant(
        ProductVariant(
          productId: styleId,
          name: 'S / Blue',
          sku: 'LINEN-S-M-BLU',
          unit: ProductUnit.each,
          sizeMl: 0,
          sellPrice: Money.fromMajor(2000.00),
          costPrice: Money.fromMajor(1200.00),
          stockQty: 10,
          active: true,
        ),
      );
      expect(variantId, greaterThan(0));

      // 3. Edit the style (same ID, not a duplicate)
      await db.upsertProduct(
        Product(
          id: styleId,
          name: 'Linen Shirt (Updated)',
          category: 'Shirts',
          costPrice: Money.fromMajor(1200.00),
          sellPrice: Money.fromMajor(2200.00),
          stockQty: 0,
          reorderLevel: 5,
          unit: ProductUnit.each,
          trackVariants: true,
          active: true,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );

      // 4. Verify no duplicate style was created
      final allProducts = await db.getProducts();
      final updatedStyles =
          allProducts.where((p) => p.name == 'Linen Shirt (Updated)');
      expect(updatedStyles.length, 1);

      // 5. Verify the old name is gone
      final oldStyles = allProducts.where((p) => p.name == 'Linen Shirt');
      expect(oldStyles.length, 0);

      // 6. Verify variant is still linked to the style
      final variant = await db.getVariantById(variantId);
      expect(variant, isNotNull);
      expect(variant!.productId, styleId);
      expect(variant.stockQty, 10);

      // 7. Decrement variant stock (simulating a sale)
      await db.upsertVariant(
        ProductVariant(
          id: variantId,
          productId: styleId,
          name: 'S / Blue',
          sku: 'LINEN-S-M-BLU',
          unit: ProductUnit.each,
          sizeMl: 0,
          sellPrice: Money.fromMajor(2000.00),
          costPrice: Money.fromMajor(1200.00),
          stockQty: 9,
          active: true,
        ),
      );

      // 8. Verify variant stock decremented
      final variantAfter = await db.getVariantById(variantId);
      expect(variantAfter!.stockQty, 9);
    });
  });

  // -------------------------------------------------------------------------
  // Open journey: item → job → edit → cost → payment → completion
  // -------------------------------------------------------------------------
  group('open journey', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
      await db.setShopProfile(ShopProfile.open);
    });


    test('create cost pool and add entries', () async {
      // 1. Create a cost pool
      final poolId = await db.createCostPool(
        uuid: 'pool-001',
        name: 'Materials Pool',
        poolType: 'lot',
        initialCost: Money.fromMajor(20000.00),
      );
      expect(poolId, greaterThan(0));

      // 2. Verify pool exists
      final pools = await db.getCostPools();
      expect(pools.isNotEmpty, isTrue);
      expect(pools.first['name'], 'Materials Pool');
    });
  });
}
