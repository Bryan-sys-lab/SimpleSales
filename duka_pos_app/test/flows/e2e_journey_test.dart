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

    test('create item → create job → edit job → add cost → '
        'record payment → complete job', () async {
      // 1. Create an item/service
      final itemId = await db.upsertProduct(
        Product(
          name: 'Consulting Service',
          category: 'Services',
          costPrice: Money.fromMajor(0.00),
          sellPrice: Money.fromMajor(5000.00),
          stockQty: 0,
          reorderLevel: 0,
          unit: ProductUnit.each,
          trackVariants: false,
          active: true,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );
      expect(itemId, greaterThan(0));

      // 2. Create a job
      final jobId = await db.createJob(
        uuid: 'job-001',
        title: 'Office Renovation',
        customerName: 'Acme Corp',
        quote: Money.fromMajor(150000.00),
        dueAt: DateTime.now().add(const Duration(days: 7)),
        costPoolId: null,
      );
      expect(jobId, greaterThan(0));

      // 3. Edit the job (same ID, not a duplicate)
      await db.updateJob(
        id: jobId,
        title: 'Office Renovation (Revised)',
        customerName: 'Acme Corp Ltd',
        finalPriceMinor: 180000,
      );

      // 4. Verify job count is still 1 (no duplicate)
      final jobs = await db.getOpenJobs();
      expect(jobs.length, 1);
      expect(jobs.first['title'], 'Office Renovation (Revised)');

      // 5. Add a direct cost to the job
      await db.addJobCost(
        uuid: 'cost-001',
        jobId: jobId,
        description: 'Materials',
        amount: Money.fromMajor(300.00),
        costType: 'materials',
      );

      // 6. Record a job payment
      await db.recordJobPayment(
        uuid: 'pay-001',
        jobId: jobId,
        amount: Money.fromMajor(50000.00),
        paymentMethod: 'mpesa',
      );

      // 7. Verify job payment
      final payments = await db.getJobPayments(jobId);
      expect(payments.length, 1);
      expect(payments.first['amount_minor'], 5000000);

      // 8. Complete the job
      await db.completeJob(jobId: jobId, finalPrice: Money.fromMajor(180000.00));

      // 9. Verify job is completed (status changed)
      final allJobs = await db.getOpenJobs();
      final completedJob = allJobs.firstWhere((j) => j['id'] == jobId);
      expect(completedJob['status'], 'closed');
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
