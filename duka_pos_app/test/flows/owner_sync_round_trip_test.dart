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

  group('Owner sync round trip', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
      await db.setShopProfile(ShopProfile.open);
    });

    test('job and cost pool records have stable UUIDs for sync', () async {
      final jobId = await db.createJob(
        uuid: 'sync-job-001',
        title: 'Sync Test Job',
        customerName: 'Sync Customer',
        quote: Money.fromMajor(75000.00),
        dueAt: DateTime.now(),
        costPoolId: null,
      );
      expect(jobId, greaterThan(0));

      final jobs = await db.getOpenJobs();
      final job = jobs.firstWhere((j) => j['id'] == jobId);
      expect(job['uuid'], 'sync-job-001');
      expect(job['title'], 'Sync Test Job');
    });

    test('cost pool created for job syncs as independent record', () async {
      final poolId = await db.createCostPool(
        uuid: 'sync-pool-001',
        name: 'Materials',
        poolType: 'lot',
        initialCost: Money.fromMajor(30000.00),
      );
      expect(poolId, greaterThan(0));

      final pools = await db.getCostPools();
      final pool = pools.firstWhere((p) => p['id'] == poolId);
      expect(pool['uuid'], 'sync-pool-001');
      expect(pool['name'], 'Materials');
    });

    test('job links to cost pool via stable pool id', () async {
      final poolId = await db.createCostPool(
        uuid: 'sync-pool-002',
        name: 'Labor Pool',
        poolType: 'lot',
        initialCost: Money.fromMajor(40000.00),
      );

      final jobId = await db.createJob(
        uuid: 'sync-job-002',
        title: 'Linked Job',
        customerName: 'Linked Customer',
        quote: Money.fromMajor(120000.00),
        dueAt: DateTime.now(),
        costPoolId: poolId,
      );

      final jobs = await db.getOpenJobs();
      final job = jobs.firstWhere((j) => j['id'] == jobId);
      expect(job['cost_pool_id'], poolId);
    });

    test('owner transaction has UUID for cross-device reconciliation', () async {
      await db.recordOwnerTransaction(
        uuid: 'sync-owner-001',
        transactionType: 'loan_received',
        amount: Money.fromMajor(100000.00),
        staffName: 'Owner',
        staffId: 1,
        note: 'Startup loan',
      );

      final transactions = await db.getOwnerTransactions();
      expect(transactions.length, 1);
      expect(transactions.first['transaction_type'], 'loan_received');
    });
  });
}
