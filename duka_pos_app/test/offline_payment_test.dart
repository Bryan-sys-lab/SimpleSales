// Recording a payment that could not be confirmed.
//
// An offline M-Pesa sale is a real sale — the customer handed over money in the
// shop. What it is not is a *confirmed* payment, and the distinction has to
// survive into the ledger or the day's figures cannot be reconciled.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;
  late int productId;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
    productId = await db.upsertProduct(Product(
      name: 'Soda 350ml',
      category: 'Drinks',
      costPrice: Money.fromMajor(45),
      sellPrice: Money.fromMajor(80),
      stockQty: 24,
      reorderLevel: 5,
      updatedAt: DateTime.now().toIso8601String(),
    ));
  });

  tearDown(() => DatabaseHelper.resetForTests());

  SaleItem item() => SaleItem(
        saleId: 0,
        productId: productId,
        productName: 'Soda 350ml',
        qty: 2,
        unitPrice: Money.fromMajor(80),
        unitCost: Money.fromMajor(45),
      );

  test('a cash sale is verified without saying so', () async {
    final id = await db.recordSale(
      staffName: 'Amina',
      items: [item()],
      paymentMethod: 'cash',
      amountTendered: Money.fromMajor(160),
    );
    expect((await db.getSaleRowById(id))!['payment_verified'], 1,
        reason: 'default is verified, so no call site has to opt in');
  });

  test('an offline M-Pesa sale is recorded and flagged unverified', () async {
    final id = await db.recordSale(
      staffName: 'Amina',
      items: [item()],
      paymentMethod: 'mpesa',
      paymentReference: 'offline-0712345678',
      amountTendered: Money.fromMajor(160),
      paymentVerified: false,
    );

    // The money was taken. The sale is not somehow less of a sale.
    final sale = await db.getSaleById(id);
    expect(sale!.total.minorUnits, 16000);
    expect(sale.items.single.qty, 2.0);
    expect(sale.paymentMethod, 'mpesa');
    expect(sale.paymentReference, 'offline-0712345678');

    // But nothing confirmed it, and that must be visible.
    final row = (await db.getSaleRowById(id))!;
    expect(row['payment_verified'], 0);
    expect(row['payment_confirmed_at'], isNull);
  });

  test('unverified sales are listed so they can be reconciled', () async {
    await db.recordSale(
      staffName: 'Amina',
      items: [item()],
      paymentMethod: 'mpesa',
      amountTendered: Money.fromMajor(160),
      paymentVerified: false,
    );
    await db.recordSale(
      staffName: 'Amina',
      items: [item()],
      paymentMethod: 'cash',
      amountTendered: Money.fromMajor(160),
    );

    expect(await db.countUnverifiedPayments(), 1);
    final outstanding = await db.getUnverifiedSales();
    expect(outstanding, hasLength(1));
    expect(outstanding.single.$1.paymentMethod, 'mpesa');
    // A verified sale must never appear in the reconciliation list, or the
    // owner is chasing money that was never in question.
    expect(outstanding.single.$1.paymentMethod, 'mpesa');
    expect(outstanding.single.$2['payment_verified'], 0);
  });

  test('confirming one clears it from the list', () async {
    final id = await db.recordSale(
      staffName: 'Amina',
      items: [item()],
      paymentMethod: 'mpesa',
      amountTendered: Money.fromMajor(160),
      paymentVerified: false,
    );
    expect(await db.countUnverifiedPayments(), 1);
    await db.confirmPayment(saleId: id, reference: 'DUKA-abc');
    expect(await db.countUnverifiedPayments(), 0);
  });

  test('a stale row still decrements stock, like any other sale', () async {
    // An offline sale consumes stock exactly as a pushed one does. Refusing to
    // decrement would let the till oversell everything it sold while dark.
    final before = await db.stockQtyForProduct(productId);
    await db.recordSale(
      staffName: 'Amina',
      items: [item()],
      paymentMethod: 'mpesa',
      amountTendered: Money.fromMajor(160),
      paymentVerified: false,
    );
    expect(await db.stockQtyForProduct(productId), before - 2);
  });
}
