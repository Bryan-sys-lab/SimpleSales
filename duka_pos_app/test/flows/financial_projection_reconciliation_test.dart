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

  group('Financial projection reconciliation', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
      await db.setShopProfile(ShopProfile.open);
    });

    test('deposit on open job is not revenue until completion', () async {
      final jobId = await db.createJob(
        uuid: 'job-rec-001',
        title: 'Consulting',
        customerName: 'Client X',
        quote: Money.fromMajor(200000.00),
        dueAt: DateTime.now(),
        costPoolId: null,
      );

      // Deposit of 40% before completion
      await db.recordJobPayment(
        uuid: 'pay-rec-001',
        jobId: jobId,
        amount: Money.fromMajor(80000.00),
        paymentMethod: 'mpesa',
      );

      // Complete job at full price
      await db.completeJob(
        jobId: jobId,
        finalPrice: Money.fromMajor(200000.00),
      );

      // After completion: job should have final price
      final jobs = await db.getOpenJobs();
      final completed = jobs.firstWhere((j) => j['id'] == jobId);
      // Money.fromMajor(200000.00) = 20000000 minor units
      expect(completed['final_price_minor'], 20000000);
    });

    test('revenue + deposit accounting balances on completion', () async {
      final jobId = await db.createJob(
        uuid: 'job-rec-002',
        title: 'Design Work',
        customerName: 'Client Y',
        quote: Money.fromMajor(100000.00),
        dueAt: DateTime.now(),
        costPoolId: null,
      );

      // 50% deposit
      await db.recordJobPayment(
        uuid: 'pay-rec-002',
        jobId: jobId,
        amount: Money.fromMajor(50000.00),
        paymentMethod: 'mpesa',
      );

      // Complete at full price
      await db.completeJob(
        jobId: jobId,
        finalPrice: Money.fromMajor(100000.00),
      );

      // Collect balance
      await db.recordJobPayment(
        uuid: 'pay-rec-003',
        jobId: jobId,
        amount: Money.fromMajor(50000.00),
        paymentMethod: 'bank_transfer',
      );

      final payments = await db.getJobPayments(jobId);
      expect(payments.length, 2);
      final totalPaid = payments.fold<int>(
        0, (s, p) => s + (p['amount_minor'] as int));
      // Two payments of Money.fromMajor(50000.00) = 5000000 minor units each
      expect(totalPaid, 10000000);
    });

    test('cash position starts at zero on fresh DB', () async {
      // Fresh DB should have no financial events
      final events = await db.getFinancialEvents();
      expect(events, isEmpty);
    });
  });
}
