import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper db;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
  });

  tearDown(DatabaseHelper.resetForTests);

  test('expected cash counts cash job payments, not mobile-money ones',
      () async {
    await db.openShift(
      staffId: 7,
      staffName: 'Amina',
      startFloat: Money.fromMajor(1000),
    );
    final shift = (await db.getOpenShift(7))!;
    final Money before = await db.expectedCashForShift(shift);

    final jobId = await db.createJob(
      uuid: 'job-cash-1',
      title: 'Gate repair',
      customerName: 'Client',
      quote: Money.fromMajor(5000),
      dueAt: DateTime.now().add(const Duration(days: 2)),
      costPoolId: null,
    );
    await db.recordJobPayment(
      uuid: 'pay-cash-1',
      jobId: jobId,
      amount: Money.fromMajor(1500),
      paymentMethod: 'cash',
    );
    await db.recordJobPayment(
      uuid: 'pay-mpesa-1',
      jobId: jobId,
      amount: Money.fromMajor(500),
      paymentMethod: 'mpesa',
    );

    final Money after = await db.expectedCashForShift(shift);
    // Only the 1,500 that went into the drawer.
    expect((after - before).minorUnits, 150000);
  });
}
