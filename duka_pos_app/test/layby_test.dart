import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/credit.dart';
import 'package:duka_pos/models/layby.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;
  late int productId;
  late int customerId;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
    productId = await db.upsertProduct(Product(
      name: 'Dress',
      category: 'Fashion',
      costPrice: Money.fromMinor(500),
      sellPrice: Money.fromMinor(1200),
      stockQty: 2,
      reorderLevel: 0,
      updatedAt: DateTime.now().toIso8601String(),
    ));
    customerId = await db.upsertCustomer(Customer(
      uuid: 'customer-test',
      name: 'Njeri',
      createdAt: DateTime.now().toIso8601String(),
    ));
  });

  tearDown(() => DatabaseHelper.resetForTests());

  SaleItem item() => SaleItem(
        saleId: 0,
        productId: productId,
        productName: 'Dress',
        qty: 1,
        unitPrice: Money.fromMinor(1200),
        unitCost: Money.fromMinor(500),
      );

  test('deposit reserves stock without recording revenue', () async {
    final id = await db.createLayby(
      customerId: customerId,
      items: [item()],
      deposit: Money.fromMinor(400),
      depositMethod: 'cash',
      dueAt: DateTime.now().add(const Duration(days: 7)),
      staffName: 'Amina',
    );

    final layby = await db.getLayby(id);
    final product = (await db.getProducts()).single;
    final totals = await db.getFinancialEventTotals();
    expect(layby!.status, LaybyStatus.open);
    expect(layby.paid, Money.fromMinor(400));
    expect(product.stockQty, 2);
    expect(product.reservedQty, 1);
    expect(totals.revenueMinor, 0);
    expect(totals.customerDepositDeltaMinor, 400);
  });

  test('payment and completion settle the deposit atomically', () async {
    final id = await db.createLayby(
      customerId: customerId,
      items: [item()],
      deposit: Money.fromMinor(400),
      depositMethod: 'cash',
      dueAt: DateTime.now().add(const Duration(days: 7)),
      staffName: 'Amina',
    );
    await db.addLaybyPayment(
      laybyId: id,
      amount: Money.fromMinor(800),
      method: 'cash',
      staffName: 'Amina',
    );
    final saleId = await db.completeLayby(id, staffName: 'Amina');

    final layby = await db.getLayby(id);
    final product = (await db.getProducts()).single;
    final saleRows = await (await db.database)
        .query('sales', where: 'id = ?', whereArgs: [saleId]);
    final totals = await db.getFinancialEventTotals();
    expect(saleRows, hasLength(1));
    expect(layby!.status, LaybyStatus.completed);
    expect(layby.saleId, saleId);
    expect(product.stockQty, 1);
    expect(product.reservedQty, 0);
    expect(totals.revenueMinor, 1034);
    expect(totals.customerDepositDeltaMinor, 0);
    expect(totals.cashInMinor, 1200);
  });

  test('cancellation releases stock and refunds the deposit', () async {
    final id = await db.createLayby(
      customerId: customerId,
      items: [item()],
      deposit: Money.fromMinor(400),
      depositMethod: 'cash',
      dueAt: DateTime.now().add(const Duration(days: 7)),
      staffName: 'Amina',
    );
    await db.cancelLayby(laybyId: id, staffName: 'Amina');

    final layby = await db.getLayby(id);
    final product = (await db.getProducts()).single;
    final totals = await db.getFinancialEventTotals();
    expect(layby!.status, LaybyStatus.cancelled);
    expect(layby.payments.last.isRefund, isTrue);
    expect(product.reservedQty, 0);
    expect(totals.cashOutMinor, 400);
    expect(totals.customerDepositDeltaMinor, 0);
  });

  test('due lay-bys expire and release their reservation', () async {
    final dueAt = DateTime.now().add(const Duration(days: 1));
    final id = await db.createLayby(
      customerId: customerId,
      items: [item()],
      deposit: Money.fromMinor(400),
      depositMethod: 'cash',
      dueAt: dueAt,
      staffName: 'Amina',
    );

    final expired = await db.expireDueLaybys(
      now: dueAt.add(const Duration(seconds: 1)),
      staffName: 'Amina',
    );
    final layby = await db.getLayby(id);
    final product = (await db.getProducts()).single;
    expect(expired, 1);
    expect(layby!.status, LaybyStatus.expired);
    expect(product.reservedQty, 0);
  });
}
