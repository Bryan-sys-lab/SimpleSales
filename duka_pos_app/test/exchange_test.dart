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
  late int originalProductId;
  late int replacementProductId;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
    originalProductId = await db.upsertProduct(Product(
      name: 'Blue dress',
      category: 'Fashion',
      costPrice: Money.fromMinor(500),
      sellPrice: Money.fromMinor(1200),
      stockQty: 1,
      reorderLevel: 0,
      updatedAt: DateTime.now().toIso8601String(),
    ));
    replacementProductId = await db.upsertProduct(Product(
      name: 'Red dress',
      category: 'Fashion',
      costPrice: Money.fromMinor(700),
      sellPrice: Money.fromMinor(1500),
      stockQty: 1,
      reorderLevel: 0,
      updatedAt: DateTime.now().toIso8601String(),
    ));
  });

  tearDown(() => DatabaseHelper.resetForTests());

  test(
      'exchange links return, replacement sale and price difference atomically',
      () async {
    await db.recordSale(
      staffName: 'Amina',
      items: [
        SaleItem(
          saleId: 0,
          productId: originalProductId,
          productName: 'Blue dress',
          qty: 1,
          unitPrice: Money.fromMinor(1200),
          unitCost: Money.fromMinor(500),
        )
      ],
    );
    final original = await db.getSaleById(1);
    expect(original, isNotNull);
    final originalItem = original!.items.single;

    final replacementId = await db.recordExchange(
      originalSale: original,
      returnedLines: [
        ReturnLineDraft(
          saleItemId: originalItem.id!,
          qty: 1,
          restock: true,
        )
      ],
      replacementItems: [
        SaleItem(
          saleId: 0,
          productId: replacementProductId,
          productName: 'Red dress',
          qty: 1,
          unitPrice: Money.fromMinor(1500),
          unitCost: Money.fromMinor(700),
        )
      ],
      reason: 'Customer changed colour',
      paymentMethod: 'cash',
      staffName: 'Amina',
    );

    final database = await db.database;
    final exchanges = await database.query('exchanges');
    final returns = await database.query('sale_returns');
    final payments = await database.query('sale_payments',
        where: 'sale_id = ?', whereArgs: [replacementId], orderBy: 'id ASC');
    final originalProduct = (await db.getProducts())
        .firstWhere((product) => product.id == originalProductId);
    final replacementProduct = (await db.getProducts())
        .firstWhere((product) => product.id == replacementProductId);

    expect(exchanges.single['status'], 'completed');
    expect(exchanges.single['return_id'], returns.single['id']);
    expect(exchanges.single['replacement_sale_id'], replacementId);
    expect(exchanges.single['difference_minor'], 300);
    expect(exchanges.single['difference_direction'], 'customer_pays');
    expect(payments.map((row) => row['method']),
        containsAll(<String>['exchange_credit', 'cash']));
    expect(originalProduct.stockQty, 1);
    expect(replacementProduct.stockQty, 0);
  });
}
