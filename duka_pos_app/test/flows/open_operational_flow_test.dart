import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/profile/shop_profile.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Open operational flow', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
      await db.setShopProfile(ShopProfile.open);
    });

    test('create job with cost pool persists all fields', () async {
      final jobId = await db.createJob(
        uuid: 'job-001',
        title: 'Office Renovation',
        customerName: 'Acme Corp',
        quote: Money.fromMajor(150000.00),
        dueAt: DateTime.now().add(const Duration(days: 7)),
        costPoolId: null,
      );
      expect(jobId, greaterThan(0));

      final jobs = await db.getOpenJobs();
      expect(jobs.isNotEmpty, isTrue);
      expect(jobs.first['title'], 'Office Renovation');
      expect(jobs.first['customer_name'], 'Acme Corp');
    });

    test('edit job updates fields preserving job id', () async {
      final jobId = await db.createJob(
        uuid: 'job-002',
        title: 'Initial Title',
        customerName: 'Client A',
        quote: Money.fromMajor(100000.00),
        dueAt: DateTime.now().add(const Duration(days: 3)),
        costPoolId: null,
      );

      await db.updateJob(
        id: jobId,
        title: 'Updated Title',
        customerName: 'Client B',
        finalPriceMinor: 120000,
      );

      final jobs = await db.getOpenJobs();
      final updated = jobs.firstWhere((j) => j['id'] == jobId);
      expect(updated['title'], 'Updated Title');
      expect(updated['customer_name'], 'Client B');
      expect(updated['final_price_minor'], 120000);
    });

    test('record job payment verifies amount and method', () async {
      final jobId = await db.createJob(
        uuid: 'job-003',
        title: 'Plumbing Repair',
        customerName: 'Home Owner',
        quote: Money.fromMajor(50000.00),
        dueAt: DateTime.now().add(const Duration(days: 2)),
        costPoolId: null,
      );

      await db.recordJobPayment(
        uuid: 'pay-001',
        jobId: jobId,
        amount: Money.fromMajor(15000.00),
        paymentMethod: 'mpesa',
      );

      final payments = await db.getJobPayments(jobId);
      expect(payments.length, 1);
      // Money.fromMajor(15000.00) = 1500000 minor units
      expect(payments.first['amount_minor'], 1500000);
      expect(payments.first['payment_method'], 'mpesa');
    });

    test('create cost pool and add entry', () async {
      final poolId = await db.createCostPool(
        uuid: 'pool-001',
        name: 'Materials Pool',
        poolType: 'lot',
        initialCost: Money.fromMajor(20000.00),
      );
      expect(poolId, greaterThan(0));

      final pools = await db.getCostPools();
      expect(pools.isNotEmpty, isTrue);
      expect(pools.first['name'], 'Materials Pool');

      await db.addCostPoolEntry(
        uuid: 'entry-001',
        poolId: poolId,
        entryType: 'purchase',
        amount: Money.fromMajor(5000.00),
        paidFrom: 'other',
        description: 'Wiring and switches',
      );

      final entries = await db.getCostPoolEntries(poolId);
      // createCostPool with initialCost creates one entry, plus our add = 2
      expect(entries.length, 2);
      // Money.fromMajor(5000.00) = 500000 minor units
      expect(entries.first['amount_minor'], 500000);
    });

    test('complete job recognizes final price', () async {
      final jobId = await db.createJob(
        uuid: 'job-005',
        title: 'Painting Job',
        customerName: 'Office Client',
        quote: Money.fromMajor(100000.00),
        dueAt: DateTime.now().add(const Duration(days: 1)),
        costPoolId: null,
      );

      await db.recordJobPayment(
        uuid: 'pay-002',
        jobId: jobId,
        amount: Money.fromMajor(30000.00),
        paymentMethod: 'mpesa',
      );

      await db.completeJob(
        jobId: jobId,
        finalPrice: Money.fromMajor(100000.00),
      );

      final jobs = await db.getOpenJobs();
      final completed = jobs.firstWhere((j) => j['id'] == jobId);
      // Money.fromMajor(100000.00) = 10000000 minor units
      expect(completed['final_price_minor'], 10000000);
    });

    test('record owner transaction does not affect revenue', () async {
      await db.recordOwnerTransaction(
        uuid: 'owner-001',
        transactionType: 'capital_in',
        amount: Money.fromMajor(50000.00),
        staffName: 'Owner',
        staffId: 1,
        note: 'Initial capital',
      );

      final transactions = await db.getOwnerTransactions();
      expect(transactions.length, 1);
      expect(transactions.first['transaction_type'], 'capital_in');
      // Money.fromMajor(50000.00) = 5000000 minor units
      expect(transactions.first['amount_minor'], 5000000);
    });
  });
}
