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

  group('Offline replay idempotency', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
      await db.setShopProfile(ShopProfile.open);
    });

    test('same UUID payment is rejected (UUID is unique)', () async {
      final jobId = await db.createJob(
        uuid: 'idemp-job-001',
        title: 'Idempotency Test',
        customerName: 'Test Customer',
        quote: Money.fromMajor(60000.00),
        dueAt: DateTime.now(),
        costPoolId: null,
      );

      await db.recordJobPayment(
        uuid: 'idemp-pay-001',
        jobId: jobId,
        amount: Money.fromMajor(20000.00),
        paymentMethod: 'mpesa',
      );

      // Re-recording with same UUID should be rejected by UNIQUE constraint
      await expectLater(
        () => db.recordJobPayment(
          uuid: 'idemp-pay-001',
          jobId: jobId,
          amount: Money.fromMajor(20000.00),
          paymentMethod: 'mpesa',
        ),
        throwsA(isA<Exception>()),
      );

      final count = (await db.getJobPayments(jobId)).length;
      expect(count, 1); // Only one row exists
    });

    test('different UUID payments create separate records', () async {
      final jobId = await db.createJob(
        uuid: 'idemp-job-002',
        title: 'Multiple Payments',
        customerName: 'Test Customer 2',
        quote: Money.fromMajor(100000.00),
        dueAt: DateTime.now(),
        costPoolId: null,
      );

      await db.recordJobPayment(
        uuid: 'idemp-pay-002',
        jobId: jobId,
        amount: Money.fromMajor(30000.00),
        paymentMethod: 'mpesa',
      );
      await db.recordJobPayment(
        uuid: 'idemp-pay-003',
        jobId: jobId,
        amount: Money.fromMajor(30000.00),
        paymentMethod: 'mpesa',
      );

      final payments = await db.getJobPayments(jobId);
      expect(payments.length, 2);
    });

    test('job completion sets final price once', () async {
      final jobId = await db.createJob(
        uuid: 'idemp-job-003',
        title: 'Completion Test',
        customerName: 'Test Customer 3',
        quote: Money.fromMajor(40000.00),
        dueAt: DateTime.now(),
        costPoolId: null,
      );

      await db.completeJob(
        jobId: jobId,
        finalPrice: Money.fromMajor(40000.00),
      );

      final jobs = await db.getOpenJobs();
      final completed = jobs.firstWhere((j) => j['id'] == jobId);
      // Money.fromMajor(40000.00) = 4000000 minor units
      expect(completed['final_price_minor'], 4000000);
    });

    test('product persists correctly through create and read', () async {
      final product = Product(
        name: 'Idempotency Product',
        category: 'Test',
        costPrice: Money.fromMajor(100.00),
        sellPrice: Money.fromMajor(150.00),
        stockQty: 10,
        reorderLevel: 2,
        unit: ProductUnit.each,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final productId = await db.upsertProduct(product);

      final retrieved = await db.getProductById(productId);
      expect(retrieved!.stockQty, 10);
    });
  });
}
