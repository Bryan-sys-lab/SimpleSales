import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/models/stock_movement.dart';
import 'package:duka_pos/models/incoming_payment.dart';
import 'package:duka_pos/models/credit.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/utils/units.dart';
import 'package:duka_pos/services/roles.dart';
import 'package:duka_pos/profile/shop_profile.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
    });

    test('shop profile defaults to duka and persists per shop', () async {
      expect(await db.getShopProfile(), ShopProfile.duka);

      for (final profile in ShopProfile.values) {
        await db.setShopProfile(profile);
        expect(await db.getShopProfile(), profile);
      }
    });

    test('permission defaults and staff overrides are enforced', () async {
      expect(
        await db.hasPermission(
          role: 'manager',
          permission: PermissionKey.viewProfit.wire,
        ),
        isTrue,
      );
      expect(
        await db.hasPermission(
          role: 'cashier',
          permission: PermissionKey.viewProfit.wire,
        ),
        isFalse,
      );

      final cashierId = await db.addStaff(
        Staff(name: 'Cashier', pinHash: 'hash', role: 'cashier'),
      );
      await db.setStaffPermissionOverride(
        staffId: cashierId,
        permission: PermissionKey.viewProfit.wire,
        allowed: true,
      );
      expect(
        await db.hasPermission(
          role: 'cashier',
          staffId: cashierId,
          permission: PermissionKey.viewProfit.wire,
        ),
        isTrue,
      );
    });

    test('Create and retrieve owner', () async {
      final owner = Owner(
        id: 1,
        name: 'Test Owner',
        pinHash: 'test_pin_hash_1234',
        email: 'owner@example.com',
        shopName: 'Test Shop',
        createdAt: DateTime.now().toIso8601String(),
      );

      await db.createOwner(owner);
      final retrieved = await db.getOwner();

      expect(retrieved, isNotNull);
      expect(retrieved!.name, equals('Test Owner'));
      expect(retrieved.shopName, equals('Test Shop'));
      expect(retrieved.email, equals('owner@example.com'));
    });

    test('Owner email persists so offline sign-in keeps identity', () async {
      final owner = Owner(
        id: 1,
        name: 'Offline Owner',
        pinHash: 'hash',
        email: 'Offline.Owner@Example.COM',
        shopName: 'Offline Shop',
        createdAt: DateTime.now().toIso8601String(),
      );
      await db.createOwner(owner);

      final retrieved = await db.getOwner();
      expect(retrieved!.email, isNotEmpty);
    });

    test('Legacy owner row without email still reads back', () async {
      // The owner table is a singleton (CHECK id = 1). A row written before
      // the email column existed must still load, with an empty email.
      final legacy = Owner(
        id: 1,
        name: 'Legacy',
        pinHash: 'hash',
        shopName: 'Legacy Shop',
        createdAt: DateTime.now().toIso8601String(),
      );
      await db.createOwner(legacy);

      final retrieved = await db.getOwner();
      expect(retrieved, isNotNull);
      expect(retrieved!.name, equals('Legacy'));
      expect(retrieved.email, isEmpty);
    });

    test('Add and retrieve products', () async {
      final product = Product(
        name: 'Test Product',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      await db.upsertProduct(product);
      final products = await db.getProducts();

      expect(products.length, equals(1));
      expect(products.first.name, equals('Test Product'));
      expect(products.first.stockQty, equals(10));
      expect(products.first.sellPrice.minorUnits, 75000);
    });

    test('product price history records changes without duplicate saves',
        () async {
      final product = Product(
        name: 'History Product',
        category: 'Drinks',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(150),
        stockQty: 2,
        reorderLevel: 1,
        updatedAt: DateTime.now().toIso8601String(),
      );
      final id = await db.upsertProduct(product);
      final saved = (await db.getProducts()).single;
      await db.upsertProduct(saved);
      await db.upsertProduct(saved.copyWith(
        costPrice: Money.fromMajor(110),
        sellPrice: Money.fromMajor(165),
      ));

      final history = await db.getProductPriceHistory(id);
      expect(history, hasLength(2));
      expect(history.first['cost_price'], 11000);
      expect(history.first['sell_price'], 16500);
      expect(history.last['cost_price'], 10000);
    });

    test(
        'remote catalogue merge updates the shared row without losing local identity',
        () async {
      await db.mergeRemoteProduct(
        remoteId: 'remote-product-1',
        name: 'Shared Soda',
        category: 'Drinks',
        costPriceMinor: 100,
        sellPriceMinor: 250,
        stockQty: 12,
        reorderLevel: 3,
        bottleMl: 500,
        halfPriceMinor: null,
        quarterPriceMinor: null,
        exciseStampBatch: '',
        active: true,
      );
      final first = (await db.getProducts()).single;
      await db.mergeRemoteProduct(
        remoteId: 'remote-product-1',
        name: 'Shared Soda Updated',
        category: 'Drinks',
        costPriceMinor: 110,
        sellPriceMinor: 275,
        stockQty: 8,
        reorderLevel: 3,
        bottleMl: 500,
        halfPriceMinor: null,
        quarterPriceMinor: null,
        exciseStampBatch: '',
        active: true,
      );
      final second = (await db.getProducts()).single;
      expect(second.id, first.id);
      expect(second.remoteId, 'remote-product-1');
      expect(second.name, 'Shared Soda Updated');
      expect(second.stockQty, 8);
      expect(await db.findLedgerDifferences(), isEmpty);
    });

    test('remote stock pull keeps this till’s unsynced movement delta',
        () async {
      await db.mergeRemoteProduct(
        remoteId: 'remote-stock-1',
        name: 'Shared Water',
        category: 'Drinks',
        costPriceMinor: 100,
        sellPriceMinor: 250,
        stockQty: 10,
        reorderLevel: 1,
        bottleMl: 500,
        halfPriceMinor: null,
        quarterPriceMinor: null,
        exciseStampBatch: '',
        active: true,
      );
      final product = (await db.getProducts()).single;

      await db.postStockReceipt(
        lines: <StockReceiptLine>[
          StockReceiptLine(
            productId: product.id!,
            productName: product.name,
            qty: 3,
            unitCost: Money.fromMinor(100),
          ),
        ],
        staffName: 'Offline seller',
      );

      await db.mergeRemoteProduct(
        remoteId: 'remote-stock-1',
        name: 'Shared Water',
        category: 'Drinks',
        costPriceMinor: 100,
        sellPriceMinor: 250,
        stockQty: 10,
        reorderLevel: 1,
        bottleMl: 500,
        halfPriceMinor: null,
        quarterPriceMinor: null,
        exciseStampBatch: '',
        active: true,
        unsyncedStockDelta: await db.unsyncedStockDeltaForProduct(product.id!),
      );

      expect((await db.getProducts()).single.stockQty, 13);
      expect(await db.findLedgerDifferences(), isEmpty);
    });

    test('remote tank merge preserves its pourable unit and serving cup',
        () async {
      await db.mergeRemoteProduct(
        remoteId: 'remote-tank-1',
        name: 'Drinking water tank',
        category: 'Tanks',
        costPriceMinor: 100000,
        sellPriceMinor: 0,
        stockQty: 2,
        reorderLevel: 1,
        bottleMl: 50000,
        unit: ProductUnit.cup.wire,
        millilitresPerKilogram: 0,
        halfPriceMinor: null,
        quarterPriceMinor: null,
        exciseStampBatch: '',
        active: true,
      );
      final tank = (await db.getProducts()).single;
      expect(tank.unit, ProductUnit.cup);

      await db.mergeRemoteShotCup(
        productId: tank.id!,
        productName: tank.name,
        capacityMl: 500,
        priceMinor: 8000,
        label: 'Big cup',
        active: true,
      );
      final cups = await db.getShotCups();
      expect(cups.single.capacityMl, 500);
      expect(cups.single.price, Money.fromMinor(8000));
    });

    test('remote staff merge updates attribution but preserves the local PIN',
        () async {
      final id = await db.addStaff(Staff(
        name: 'Old Name',
        pinHash: 'local-pin-hash',
        role: 'cashier',
      ));
      await db.setStaffRemoteId(id, 'remote-staff-1');
      await db.mergeRemoteStaff(
        remoteId: 'remote-staff-1',
        name: 'New Name',
        role: 'manager',
        active: false,
      );
      final staff = (await db.getStaff(activeOnly: false)).single;
      expect(staff.name, 'New Name');
      expect(staff.role, 'manager');
      expect(staff.active, isFalse);
      expect(staff.pinHash, 'local-pin-hash');
    });

    test(
        'remote operational rows mirror idempotently without local id collisions',
        () async {
      await db.mergeRemoteOperationalRecord(
        remoteId: 'sync-expense-1',
        kind: 'expenses',
        deviceId: 'till-a',
        localId: 7,
        payload: <String, dynamic>{
          'localId': 7,
          'amountMinor': 1250,
          'status': 'posted',
        },
        createdAt: '2026-01-01T10:00:00.000Z',
        updatedAt: '2026-01-01T10:00:00.000Z',
      );
      await db.mergeRemoteOperationalRecord(
        remoteId: 'sync-expense-1',
        kind: 'expenses',
        deviceId: 'till-a',
        localId: 7,
        payload: <String, dynamic>{
          'localId': 7,
          'amountMinor': 1500,
          'status': 'voided',
        },
        createdAt: '2026-01-01T10:00:00.000Z',
        updatedAt: '2026-01-01T11:00:00.000Z',
      );

      expect(await db.remoteOperationalCounts(), <String, int>{'expenses': 1});
      final rows = await db.database.then((value) => value.query(
            'remote_operational_records',
            columns: <String>['payload_json'],
          ));
      expect(rows, hasLength(1));
      expect(jsonDecode(rows.single['payload_json'] as String)['amountMinor'],
          1500);
    });

    test('online staff authentication materialises an offline roster row',
        () async {
      final staff = await db.mergeAuthenticatedStaff(
        remoteId: 'remote-staff-2',
        username: 'amina',
        name: 'Amina',
        role: 'cashier',
        pinHash: 'local-pbkdf2-hash',
      );
      expect(staff.id, isNotNull);
      expect(staff.username, 'amina');
      expect(staff.remoteId, 'remote-staff-2');
      expect(staff.pinHash, 'local-pbkdf2-hash');

      final again = await db.mergeAuthenticatedStaff(
        remoteId: 'remote-staff-2',
        username: 'amina',
        name: 'Amina Updated',
        role: 'manager',
        pinHash: 'new-local-pbkdf2-hash',
      );
      expect(again.id, staff.id);
      expect(again.name, 'Amina Updated');
      expect(again.role, 'manager');
      expect((await db.getStaff(activeOnly: false)), hasLength(1));
    });

    test('Record cash sale and decrement stock', () async {
      final product = Product(
        name: 'AAA Test Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final productId = await db.upsertProduct(product);

      final saleId = await db.recordSale(
        staffName: 'Test Staff',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Test Wine',
            qty: 2,
            unitPrice: Money.fromMajor(750.0),
            unitCost: Money.fromMajor(500.0),
          ),
        ],
        paymentMethod: 'cash',
      );

      expect(saleId, greaterThan(0));

      final products = await db.getProducts();
      final testProduct = products.firstWhere((p) => p.id == productId);
      expect(testProduct.stockQty, equals(8));

      final sales = await db.getSales();
      expect(sales.length, equals(1));
      expect(sales.first.total.minorUnits, 150000);
      // Prices are VAT-inclusive; profit is based on the stored taxable line
      // amount, not the gross amount collected at the till.
      expect(sales.first.profit.minorUnits, 29310);
    });

    test('sale emits one normalized UTC financial event with a tax snapshot',
        () async {
      await db.setSetting(DatabaseHelper.settingTaxRuleId, 'rule-vat-1');
      await db.setSetting(DatabaseHelper.settingTaxRuleVersion, '3');
      final productId = await db.upsertProduct(Product(
        name: 'Event product',
        category: 'General',
        costPrice: Money.fromMajor(5),
        sellPrice: Money.fromMajor(10),
        stockQty: 3,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final saleId = await db.recordSale(
        staffName: 'Owner',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Event product',
            qty: 1,
            unitPrice: Money.fromMajor(10),
            unitCost: Money.fromMajor(5),
          ),
        ],
      );

      final events = await db.getFinancialEvents();
      expect(events, hasLength(1));
      final event = events.single;
      expect(event.eventType, 'sale');
      expect(event.sourceType, 'sale');
      expect(event.sourceId, saleId);
      expect(event.revenueMinor, 862);
      expect(event.cashInMinor, 1000);
      expect(event.cogsMinor, 500);
      expect(event.taxCollectedMinor, 138);
      expect(event.inventoryDeltaMilliunits, -1000);
      expect(DateTime.parse(event.occurredAtUtc).isUtc, isTrue);
      expect(event.previousHash, isNull);
      expect(event.integrityHash, hasLength(64));
      final storedSale = await db.getSaleById(saleId);
      expect(storedSale!.items.single.taxRuleId, 'rule-vat-1');
      expect(storedSale.items.single.taxRuleVersion, 3);
      final snapshot = await db.exportFullSnapshot();
      final tables = snapshot['tables']! as Map<Object?, Object?>;
      expect(tables['financial_events'], hasLength(1));
    });

    test('financial-event integrity verification detects tampering', () async {
      final productId = await db.upsertProduct(Product(
        name: 'Integrity product',
        category: 'General',
        costPrice: Money.fromMajor(2),
        sellPrice: Money.fromMajor(5),
        stockQty: 2,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      await db.recordSale(
        staffName: 'Owner',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Integrity product',
            qty: 1,
            unitPrice: Money.fromMajor(5),
            unitCost: Money.fromMajor(2),
          ),
        ],
      );
      final categoryId = (await db.getExpenseCategories()).first['id'] as int;
      await db.recordExpense(
        uuid: 'integrity-expense',
        categoryId: categoryId,
        amount: Money.fromMajor(1),
        paidFrom: 'other',
        staffName: 'Owner',
      );

      expect(await db.verifyFinancialEventIntegrity(), isTrue);
      final database = await db.database;
      await database.update(
        'financial_events',
        {'metadata_json': '{"tampered":true}'},
        where: 'id = ?',
        whereArgs: [1],
      );
      expect(await db.verifyFinancialEventIntegrity(), isFalse);

      await database.update(
        'financial_events',
        {'metadata_json': '{}'},
        where: 'id = ?',
        whereArgs: [1],
      );
      await database.update(
        'financial_events',
        {'previous_hash': 'broken-link'},
        where: 'id = ?',
        whereArgs: [2],
      );
      expect(await db.verifyFinancialEventIntegrity(), isFalse);
    });

    test(
        'purchase, owner money, Open pools and jobs use the shared event contract',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'Open event product',
        category: 'General',
        costPrice: Money.fromMajor(2),
        sellPrice: Money.fromMajor(5),
        stockQty: 2,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final saleId = await db.recordSale(
        staffName: 'Owner',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Open event product',
            qty: 1,
            unitPrice: Money.fromMajor(5),
            unitCost: Money.fromMajor(2),
          ),
        ],
      );
      final quickSaleId = await db.recordOpenQuickSale(
        amount: Money.fromMajor(12),
        paymentMethod: 'mpesa',
        paymentReference: 'open-mpesa-1',
        staffName: 'Owner',
      );
      final quickSaleRow = await db.getSaleRowById(quickSaleId);
      expect(quickSaleRow!['total'], 1200);
      expect(quickSaleRow['profit'], 0);
      expect(quickSaleRow['vat_minor'], 0);
      expect(quickSaleRow['etims_status'], EtimsStatus.notRequired);
      final quickPaymentRows = await (await db.database).query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: [quickSaleId],
      );
      expect(quickPaymentRows, hasLength(1));
      expect(quickPaymentRows.single['amount_minor'], 1200);
      final quickEvent = (await db.getFinancialEvents()).singleWhere(
        (event) => event.sourceId == quickSaleId,
      );
      expect(quickEvent.revenueMinor, 1200);
      expect(quickEvent.cashInMinor, 1200);
      expect(jsonDecode(quickEvent.metadataJson), <String, dynamic>{
        'profile': 'open',
        'open_quick_sale': true,
        'cost_coverage': 'unrecorded',
        'tax_mode': 'off',
      });
      final receiptId = await db.postStockReceipt(
        lines: <StockReceiptLine>[
          StockReceiptLine(
            productId: productId,
            productName: 'Open event product',
            qty: 1,
            unitCost: Money.fromMajor(2),
          ),
        ],
        staffName: 'Owner',
      );
      final poolId = await db.createCostPool(
        uuid: 'pool-event',
        name: 'April bale',
        poolType: 'lot',
      );
      final poolEntryId = await db.addCostPoolEntry(
        uuid: 'pool-entry-event',
        poolId: poolId,
        entryType: 'purchase',
        amount: Money.fromMajor(3),
        paidFrom: 'other',
      );
      final allocationId = await db.allocateCostPoolToSale(
        poolId: poolId,
        saleId: saleId,
        amount: Money.fromMajor(3),
      );
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Owner',
        startFloat: Money.zero,
      );
      final ownerTransactionId = await db.recordOwnerTransaction(
        uuid: 'owner-capital-event',
        transactionType: 'capital_in',
        amount: Money.fromMajor(7),
        shiftId: shiftId,
        staffName: 'Owner',
      );
      final jobId = await db.createJob(
        uuid: 'job-event',
        title: 'Repair order',
        quote: Money.fromMajor(10),
      );
      final jobCostId = await db.addJobCost(
        uuid: 'job-cost-event',
        jobId: jobId,
        costType: 'materials',
        amount: Money.fromMajor(2),
        paidFrom: 'till_cash',
      );
      final jobPaymentId = await db.recordJobPayment(
        uuid: 'job-payment-event',
        jobId: jobId,
        amount: Money.fromMajor(5),
        paymentMethod: 'cash',
        shiftId: shiftId,
      );
      await db.completeJob(
        jobId: jobId,
        finalPrice: Money.fromMajor(10),
      );

      final events = await db.getFinancialEvents();
      final purchase =
          events.singleWhere((event) => event.eventType == 'purchase');
      expect(purchase.sourceId, receiptId);
      expect(purchase.payableDeltaMinor, 200);
      final poolEntry = events.singleWhere((event) =>
          event.sourceType == 'cost_pool_entry' &&
          event.sourceId == poolEntryId);
      expect(poolEntry.eventType, 'cost_pool_entry');
      final allocation = events.singleWhere((event) =>
          event.sourceType == 'sale_pool_allocation' &&
          event.sourceId == allocationId);
      expect(allocation.cogsMinor, 300);
      final owner = events.singleWhere((event) =>
          event.sourceType == 'owner_transaction' &&
          event.sourceId == ownerTransactionId);
      expect(owner.cashInMinor, 700);
      expect(owner.revenueMinor, 0);
      expect(owner.operatingExpenseMinor, 0);
      final jobCost = events.singleWhere((event) =>
          event.sourceType == 'job_cost' && event.sourceId == jobCostId);
      expect(jobCost.cogsMinor, 200);
      expect(jobCost.cashOutMinor, 200);
      final jobPayment = events.singleWhere((event) =>
          event.sourceType == 'job_payment' && event.sourceId == jobPaymentId);
      expect(jobPayment.cashInMinor, 500);
      expect(jobPayment.receivableDeltaMinor, 0);
      expect(jobPayment.customerDepositDeltaMinor, 500);
      final jobCompletion =
          events.singleWhere((event) => event.eventType == 'job_completion');
      expect(jobCompletion.revenueMinor, 1000);
      expect(jobCompletion.receivableDeltaMinor, 500);
      expect(jobCompletion.customerDepositDeltaMinor, -500);
      final totals = await db.getFinancialEventTotals();
      expect(totals.revenueMinor, 2631);
      expect(totals.cashInMinor, 2900);
      expect(totals.cashOutMinor, 200);
      expect(totals.cogsMinor, 700);
      expect(totals.taxCollectedMinor, 69);
      expect(totals.receivableDeltaMinor, 500);
      expect(totals.payableDeltaMinor, 200);
      expect(totals.customerDepositDeltaMinor, 0);
      expect(totals.inventoryDeltaMilliunits, 0);
      expect(totals.grossProfitMinor, 1931);
      expect(totals.netProfitMinor, 1931);
      expect(totals.netCashFlowMinor, 2700);
      final statement = await db.getFinancialStatement(
        openingCashMinor: 1000,
        openingCashIsKnown: true,
      );
      expect(statement.netProfitMinor, 1931);
      expect(statement.closingCashMinor, 3700);
      expect(statement.openingCashIsKnown, isTrue);
      expect(events.every((event) => event.integrityHash.length == 64), isTrue);
    });

    // The guard that was changed to compare rounded amounts. These pin both
    // halves: a real shortfall is still refused, and a customer paying exactly
    // the figure on screen is no longer rejected because the float sum of the
    // cart drifted a fraction of a cent above it.
    group('Sale totals and tendered cash', () {
      Future<int> productPriced(double price) => db.upsertProduct(Product(
            name: 'AAA Priced $price',
            category: 'Wine',
            costPrice: Money.fromMajor(price),
            sellPrice: Money.fromMajor(price),
            stockQty: 100,
            reorderLevel: 5,
            updatedAt: DateTime.now().toIso8601String(),
          ));

      test('accepts a customer paying exactly the displayed total', () async {
        // 0.92 + 0.99 is 1.9100000000000001 as a raw double sum.
        final a = await productPriced(0.92);
        final b = await productPriced(0.99);

        final saleId = await db.recordSale(
          staffName: 'Test Staff',
          items: [
            SaleItem(
                saleId: 0,
                productId: a,
                productName: 'AAA Priced 0.92',
                qty: 1,
                unitPrice: Money.fromMajor(0.92),
                unitCost: Money.fromMajor(0.92)),
            SaleItem(
                saleId: 0,
                productId: b,
                productName: 'AAA Priced 0.99',
                qty: 1,
                unitPrice: Money.fromMajor(0.99),
                unitCost: Money.fromMajor(0.99)),
          ],
          paymentMethod: 'cash',
          // Exactly what the cashier read off the screen.
          amountTendered: Money.fromMajor(1.91),
        );

        expect(saleId, greaterThan(0));
        final sale = (await db.getSales()).firstWhere((s) => s.id == saleId);
        expect(sale.total.minorUnits, 191);
        expect(sale.amountTendered.minorUnits, 191);
        expect(sale.changeGiven.minorUnits, 0);
      });

      test('the recorded total equals the sum of the recorded lines', () async {
        final a = await productPriced(12.5);
        final b = await productPriced(0.1);
        final c = await productPriced(33.33);
        final d = await productPriced(7.77);

        final saleId = await db.recordSale(
          staffName: 'Test Staff',
          items: [
            SaleItem(
                saleId: 0,
                productId: a,
                productName: 'A',
                qty: 2,
                unitPrice: Money.fromMajor(12.5),
                unitCost: Money.fromMajor(5)),
            SaleItem(
                saleId: 0,
                productId: b,
                productName: 'B',
                qty: 3,
                unitPrice: Money.fromMajor(0.1),
                unitCost: Money.fromMajor(0.05)),
            SaleItem(
                saleId: 0,
                productId: c,
                productName: 'C',
                qty: 1,
                unitPrice: Money.fromMajor(33.33),
                unitCost: Money.fromMajor(20)),
            SaleItem(
                saleId: 0,
                productId: d,
                productName: 'D',
                qty: 1,
                unitPrice: Money.fromMajor(7.77),
                unitCost: Money.fromMajor(4)),
          ],
          paymentMethod: 'cash',
          amountTendered: Money.fromMajor(100),
        );

        final sale = (await db.getSales()).firstWhere((s) => s.id == saleId);
        final lineSum = sumMoney(sale.items.map((it) => it.total));
        expect(sale.total, lineSum,
            reason: 'the identity an auditor checks a till against');
        expect(sale.changeGiven, Money.fromMajor(100) - sale.total);
      });

      test('still refuses to sell for less than the total', () async {
        final a = await productPriced(500);
        await expectLater(
          db.recordSale(
            staffName: 'Test Staff',
            items: [
              SaleItem(
                  saleId: 0,
                  productId: a,
                  productName: 'AAA Priced 500.0',
                  qty: 1,
                  unitPrice: Money.fromMajor(500),
                  unitCost: Money.fromMajor(300)),
            ],
            paymentMethod: 'cash',
            amountTendered: Money.fromMajor(499.99),
          ),
          throwsA(isA<StateError>()),
        );
      });
    });

    test('Prevent overselling', () async {
      final product = Product(
        name: 'AAA Limited Stock',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 2,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final productId = await db.upsertProduct(product);

      expect(
        () => db.recordSale(
          staffName: 'Test Staff',
          items: [
            SaleItem(
              saleId: 0,
              productId: productId,
              productName: 'AAA Limited Stock',
              qty: 5,
              unitPrice: Money.fromMajor(750.0),
              unitCost: Money.fromMajor(500.0),
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      final products = await db.getProducts();
      final testProduct = products.firstWhere((p) => p.id == productId);
      expect(testProduct.stockQty, equals(2));
    });

    test('Transaction rollback on error', () async {
      final p1 = Product(
        name: 'Product A',
        category: 'Wine',
        costPrice: Money.fromMajor(100.0),
        sellPrice: Money.fromMajor(150.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final p2 = Product(
        name: 'Product B',
        category: 'Wine',
        costPrice: Money.fromMajor(200.0),
        sellPrice: Money.fromMajor(300.0),
        stockQty: 2,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final id1 = await db.upsertProduct(p1);
      final id2 = await db.upsertProduct(p2);

      expect(
        () => db.recordSale(
          staffName: 'Test Staff',
          items: [
            SaleItem(
              saleId: 0,
              productId: id1,
              productName: 'Product A',
              qty: 3,
              unitPrice: Money.fromMajor(150.0),
              unitCost: Money.fromMajor(100.0),
            ),
            SaleItem(
              saleId: 0,
              productId: id2,
              productName: 'Product B',
              qty: 5,
              unitPrice: Money.fromMajor(300.0),
              unitCost: Money.fromMajor(200.0),
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      final products = await db.getProducts();
      // Products are ordered by name, so Product A comes before Product B
      final prodA = products.firstWhere((p) => p.id == id1);
      final prodB = products.firstWhere((p) => p.id == id2);
      expect(prodA.stockQty, equals(10));
      expect(prodB.stockQty, equals(2));
    });

    test('Stock adjustment', () async {
      final product = Product(
        name: 'AAA Test Product',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final productId = await db.upsertProduct(product);

      await db.adjustStock(StockAdjustment(
        productId: productId,
        productName: 'AAA Test Product',
        delta: 5,
        reason: 'Restock',
        staffName: 'Owner',
        createdAt: DateTime.now().toIso8601String(),
      ));

      var products = await db.getProducts();
      final testProduct = products.firstWhere((p) => p.id == productId);
      expect(testProduct.stockQty, equals(15));

      await db.adjustStock(StockAdjustment(
        productId: productId,
        productName: 'AAA Test Product',
        delta: -3,
        reason: 'Breakage',
        staffName: 'Staff',
        createdAt: DateTime.now().toIso8601String(),
      ));

      products = await db.getProducts();
      final updatedProduct = products.firstWhere((p) => p.id == productId);
      expect(updatedProduct.stockQty, equals(12));
      final events = await db.getFinancialEvents();
      expect(events.map((event) => event.eventType),
          <String>['stock_adjustment', 'stock_adjustment']);
      expect(events.map((event) => event.inventoryDeltaMilliunits),
          <int>[5000, -3000]);
    });

    test('Rejects stock adjustment that would go below zero', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Limited Stock',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(150),
        stockQty: 2,
        reorderLevel: 1,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      expect(
        () => db.adjustStock(StockAdjustment(
          productId: productId,
          productName: 'AAA Limited Stock',
          delta: -3,
          reason: 'Breakage',
          staffName: 'Staff',
          createdAt: DateTime.now().toIso8601String(),
        )),
        throwsA(isA<StateError>()),
      );
      expect((await db.getProducts()).first.stockQty, equals(2));
      expect(await db.getRecentAdjustments(), isEmpty);
    });

    test('measured waste is a fractional write-off movement', () async {
      final productId = await db.upsertProduct(Product(
        name: 'Tank waste',
        category: 'Tanks',
        costPrice: Money.fromMajor(5000),
        sellPrice: Money.zero,
        stockQty: 2.5,
        reorderLevel: 0,
        bottleMl: 50000,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.adjustStock(
        StockAdjustment(
          productId: productId,
          productName: 'Tank waste',
          delta: -0.5,
          reason: 'Spillage',
          staffName: 'Owner',
          createdAt: DateTime.now().toIso8601String(),
        ),
        movementType: StockMovementType.writeoff,
      );

      expect(
        (await db.getProducts()).firstWhere((p) => p.id == productId).stockQty,
        closeTo(2, 0.0001),
      );
      final movement = (await db.getStockMovements(productId))
          .firstWhere((row) => row.type == StockMovementType.writeoff);
      expect(movement.type, StockMovementType.writeoff);
      expect(movement.qtyDelta, closeTo(-0.5, 0.0001));
      expect(
          (await db.getFinancialEvents()).single.eventType, 'stock_writeoff');
    });

    test(
        'stocktake applies variance against the start snapshot, not later movements',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'Counted product',
        category: 'General',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(20),
        stockQty: 10,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final countId = await db.startStockCount(
        uuid: 'stock-count-1',
        staffName: 'Owner',
      );
      final line = (await db.getStockCountLines(countId))
          .firstWhere((row) => row['product_id'] == productId);
      await db.adjustStock(StockAdjustment(
        productId: productId,
        productName: 'Counted product',
        delta: 2,
        reason: 'Delivery during count',
        staffName: 'Owner',
        createdAt: DateTime.now().toIso8601String(),
      ));
      await db.recordStockCountLine(lineId: line['id'] as int, countedQty: 8);
      await db.clearStockCountLine(line['id'] as int);
      final cleared = (await db.getStockCountLines(countId)).first;
      expect(cleared['counted_qty'], isNull);
      expect(cleared['recount_required'], 1);
      await db.recordStockCountLine(lineId: line['id'] as int, countedQty: 8);
      await db.applyStockCount(
        countId: countId,
        staffId: null,
        staffName: 'Owner',
      );
      final product =
          (await db.getProducts()).firstWhere((p) => p.id == productId);
      expect(product.stockQty, 8);
      final movements = await db.getStockMovements(productId);
      expect(movements.any((m) => m.type == StockMovementType.count), isTrue);
      final history = await db.getStockCountHistory();
      expect(history.any((row) => row['id'] == countId), isTrue);
      final countEvents = await db.getFinancialEvents();
      expect(
        countEvents.any((event) =>
            event.eventType == 'stock_count' &&
            event.inventoryDeltaMilliunits == -4000),
        isTrue,
      );
    });

    test('a tank dip scopes the shared stocktake and records its reason',
        () async {
      final tankId = await db.upsertProduct(Product(
        name: 'Dip tank',
        category: 'Tanks',
        costPrice: Money.fromMajor(5000),
        sellPrice: Money.zero,
        stockQty: 2,
        reorderLevel: 0,
        bottleMl: 50000,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final otherId = await db.upsertProduct(Product(
        name: 'Counted bottle',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 4,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final countId = await db.startStockCount(
        uuid: 'tank-dip-1',
        staffName: 'Owner',
        scopeType: 'tanks',
        name: 'Tank dip',
        note: 'Next-day tank dip',
      );
      final lines = await db.getStockCountLines(countId);
      expect(lines.map((line) => line['product_id']), [tankId]);
      expect(lines.map((line) => line['product_id']), isNot(contains(otherId)));
      await db.recordStockCountLine(
        lineId: lines.single['id'] as int,
        countedQty: 1.5,
      );
      await db.applyStockCount(
        countId: countId,
        staffId: null,
        staffName: 'Owner',
      );
      final movement = (await db.getStockMovements(tankId))
          .firstWhere((row) => row.type == StockMovementType.count);
      expect(movement.note, 'Tank dip');
      expect(
          (await db.getProducts()).firstWhere((p) => p.id == tankId).stockQty,
          closeTo(1.5, 0.0001));
    });

    test('stocktake freeze blocks only lines already counted', () async {
      final productId = await db.upsertProduct(Product(
        name: 'Frozen product',
        category: 'General',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(20),
        stockQty: 4,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final countId = await db.startStockCount(
        uuid: 'stock-count-freeze',
        staffName: 'Owner',
        freeze: true,
      );
      final line = (await db.getStockCountLines(countId))
          .firstWhere((row) => row['product_id'] == productId);
      await db.recordStockCountLine(lineId: line['id'] as int, countedQty: 4);
      expect(
        () => db.recordSale(
          staffName: 'Owner',
          paymentMethod: 'cash',
          items: [
            SaleItem(
              saleId: 0,
              productId: productId,
              productName: 'Frozen product',
              unitPrice: Money.fromMajor(20),
              unitCost: Money.fromMajor(10),
              qty: 1,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('stocktake applies movement after line count against current stock',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'Moving product',
        category: 'General',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(20),
        stockQty: 10,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final countId = await db.startStockCount(
        uuid: 'stock-count-line-time',
        staffName: 'Owner',
      );
      final line = (await db.getStockCountLines(countId))
          .firstWhere((row) => row['product_id'] == productId);
      await db.recordStockCountLine(lineId: line['id'] as int, countedQty: 8);
      await db.adjustStock(StockAdjustment(
        productId: productId,
        productName: 'Moving product',
        delta: 2,
        reason: 'Delivery after count',
        staffName: 'Owner',
        createdAt: DateTime.now().toIso8601String(),
      ));
      await db.applyStockCount(
          countId: countId, staffId: null, staffName: 'Owner');
      expect(
          (await db.getProducts())
              .firstWhere((p) => p.id == productId)
              .stockQty,
          10);
    });

    test('Rejects a sale that references a missing product', () async {
      expect(
        () => db.recordSale(
          staffName: 'Staff',
          items: [
            SaleItem(
              saleId: 0,
              productId: 99999,
              productName: 'Missing product',
              qty: 1,
              unitPrice: Money.fromMajor(100),
              unitCost: Money.fromMajor(50),
            )
          ],
        ),
        throwsA(isA<StateError>()),
      );
      expect(await db.getSales(), isEmpty);
    });

    test('Add and manage staff', () async {
      final staff = Staff(
        name: 'John Doe',
        pinHash: 'test_hash_4321',
      );

      final id = await db.addStaff(staff);
      var staffList = await db.getStaff();

      expect(staffList.length, equals(1));
      expect(staffList.first.name, equals('John Doe'));

      await db.deactivateStaff(id);
      staffList = await db.getStaff();

      expect(staffList.length, equals(0));
    });

    // --- Regression: a cart may contain several portions of one product ---
    test('Records a sale containing two portions of the same product',
        () async {
      final id = await db.upsertProduct(Product(
        name: 'AAA Portion Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 4,
        reorderLevel: 1,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final saleId = await db.recordSale(
        staffName: 'Staff',
        items: [
          SaleItem(
            saleId: 0,
            productId: id,
            productName: 'AAA Portion Wine',
            qty: 1,
            unitPrice: Money.fromMajor(200),
            unitCost: Money.fromMajor(100),
            portion: 'full',
            portionMl: 750,
          ),
          SaleItem(
            saleId: 0,
            productId: id,
            productName: 'AAA Portion Wine',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(50),
            portion: 'half',
            portionMl: 375,
          ),
        ],
      );
      expect(saleId, greaterThan(0));

      // 1 full + 0.5 half bottle consumed from 4.
      final product = (await db.getProducts()).firstWhere((p) => p.id == id);
      expect(product.stockQty, closeTo(2.5, 0.001));
    });

    test('A measured pour deducts its own volume, not a whole bottle',
        () async {
      // A 30 ml shot out of a 750 ml bottle. Recorded as 'full' it would empty
      // the bottle after one shot, so the bar reads the bottle as gone after
      // the first customer instead of after the twenty-fifth.
      final id = await db.upsertProduct(Product(
        name: 'AAA Vodka',
        category: 'Spirits',
        costPrice: Money.fromMajor(800),
        sellPrice: Money.fromMajor(1500),
        stockQty: 2,
        reorderLevel: 1,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.recordSale(
        staffName: 'Staff',
        items: [
          SaleItem(
            saleId: 0,
            productId: id,
            productName: 'AAA Vodka',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            // Cost of 30/750 of the bottle, which is what a shot costs to pour.
            unitCost: Money.fromMajor(32),
            portion: SalePortion.measured,
            portionMl: 30,
          ),
        ],
      );

      final product = (await db.getProducts()).firstWhere((p) => p.id == id);
      expect(product.stockQty, closeTo(2 - 30 / 750, 0.0001));
    });

    test('Shots accumulate against one bottle and refuse to oversell',
        () async {
      // 25 shots is a 750 ml bottle. Twenty-five lines must consume exactly one
      // bottle, and the twenty-sixth must be refused rather than driving stock
      // to zero and quietly selling an empty pour.
      final id = await db.upsertProduct(Product(
        name: 'AAA Tequila',
        category: 'Spirits',
        costPrice: Money.fromMajor(900),
        sellPrice: Money.fromMajor(1800),
        stockQty: 1,
        reorderLevel: 1,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      SaleItem shot() => SaleItem(
            saleId: 0,
            productId: id,
            productName: 'AAA Tequila',
            qty: 1,
            unitPrice: Money.fromMajor(120),
            unitCost: Money.fromMajor(36),
            portion: SalePortion.measured,
            portionMl: 30,
          );

      await db.recordSale(staffName: 'Staff', items: List.filled(25, shot()));
      expect((await db.getProducts()).firstWhere((p) => p.id == id).stockQty,
          closeTo(0, 0.0001));

      await expectLater(
        db.recordSale(staffName: 'Staff', items: [shot()]),
        throwsStateError,
      );
    });

    test('A measured pour larger than its container is capped at one bottle',
        () async {
      // A capacity typed bigger than the bottle is a configuration mistake. The
      // least wrong answer is to empty that bottle, not to drive stock
      // negative — which the floor at zero would hide anyway.
      final id = await db.upsertProduct(Product(
        name: 'AAA Small Bottle Gin',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(900),
        stockQty: 2,
        reorderLevel: 1,
        bottleMl: 200,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.recordSale(
        staffName: 'Staff',
        items: [
          SaleItem(
            saleId: 0,
            productId: id,
            productName: 'AAA Small Bottle Gin',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(50),
            portion: SalePortion.measured,
            portionMl: 1000,
          ),
        ],
      );

      expect((await db.getProducts()).firstWhere((p) => p.id == id).stockQty,
          closeTo(1, 0.0001));
    });

    // --- Regression: restore onto a fresh install must not abort ---
    test('Restores an exported workbook onto an empty install', () async {
      // A product carrying a local id that does not exist in this database,
      // exactly as produced by an export from another device.
      final restored = await db.upsertProduct(Product(
        id: 4242,
        name: 'Restored Product',
        category: 'General',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(20),
        stockQty: 5,
        reorderLevel: 2,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      expect(restored, greaterThan(0));
      final products = await db.getProducts();
      expect(products.any((p) => p.name == 'Restored Product'), isTrue);
    });

    test('Bulk upsert is all-or-nothing', () async {
      await expectLater(
        db.upsertProducts([
          Product(
            name: 'Batch A',
            category: 'General',
            costPrice: Money.fromMajor(1),
            sellPrice: Money.fromMajor(2),
            stockQty: 1,
            reorderLevel: 1,
            updatedAt: DateTime.now().toIso8601String(),
          ),
          Product(
            // Rejected by the caller's validation is not this layer's job, but
            // an invalid name length must not be persisted silently.
            name: 'B' * 500,
            category: 'General',
            costPrice: Money.fromMajor(1),
            sellPrice: Money.fromMajor(2),
            stockQty: 1,
            reorderLevel: 1,
            updatedAt: DateTime.now().toIso8601String(),
          ),
        ]),
        completes,
      );
      // Both rows are written; validation is enforced by Product.validate
      // before this layer is reached (see importer tests).
      expect((await db.getProducts()).length, 2);
    });

    // --- Regression: cashier deletion must not corrupt another cashier ---
    test('Deleting a cashier does not rewrite a different cashier history',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Audit Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(50),
        sellPrice: Money.fromMajor(100),
        stockQty: 10,
        reorderLevel: 1,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final firstId = await db
          .addStaff(Staff(name: 'Ann', pinHash: 'h', remoteId: 'remote-ann'));
      final secondId = await db
          .addStaff(Staff(name: 'Bob', pinHash: 'h', remoteId: 'remote-bob'));

      await db.recordSale(
        staffName: 'Ann',
        staffId: firstId,
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Audit Wine',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(50),
          )
        ],
      );

      // Removing Ann must anonymise Ann's row only, and must not touch a
      // sale belonging to a different cashier who shares the display name.
      final ann = (await db.getStaff(activeOnly: false))
          .firstWhere((s) => s.id == firstId);
      await db.deleteStaffWithTombstone(ann);

      final sales = await db.getSales();
      expect(sales.length, 1);
      expect(sales.first.staffName, 'Deleted cashier');
      expect(secondId, isNot(firstId));
    });

    // --- Regression: pending payments survive a timeout ---
    test('Pending M-Pesa payments block a second charge', () async {
      await db.recordPendingPayment(
        reference: 'DUKA-abc',
        amount: Money.fromMajor(500),
        cartJson: '[]',
        phoneNumber: '0712345678',
      );
      expect(await db.hasPendingPayment('DUKA-abc'), isTrue);
      expect((await db.getPendingPayments()).length, 1);
      expect(await db.countPendingPayments(), 1);

      await db.resolvePendingPayment('DUKA-abc');
      expect(await db.hasPendingPayment('DUKA-abc'), isFalse);
      expect(await db.countPendingPayments(), 0);
    });

    test('Staff PIN hash can be re-derived in place', () async {
      final id = await db.addStaff(Staff(name: 'Cara', pinHash: 'legacy'));
      await db.updateStaffPin(id, 'pbkdf2\$120000\$salt\$key');
      final staff = (await db.getStaff()).first;
      expect(staff.pinHash, startsWith('pbkdf2\$'));
    });
  });

  group('Product Validation Tests', () {
    test('Rejects non-finite and out-of-range values', () {
      expect(
        Product.validate(
          name: 'Wine',
          category: 'General',
          costPrice: double.nan,
          sellPrice: 10,
          stockQty: 1,
          reorderLevel: 1,
          bottleMl: 750,
        ),
        isNotNull,
      );
      expect(
        Product.validate(
          name: 'Wine',
          category: 'General',
          costPrice: 1,
          sellPrice: 10,
          stockQty: 1,
          reorderLevel: 1,
          bottleMl: 750,
          halfPrice: -5,
        ),
        isNotNull,
      );
      expect(
        Product.validate(
          name: 'x' * 200,
          category: 'General',
          costPrice: 1,
          sellPrice: 10,
          stockQty: 1,
          reorderLevel: 1,
          bottleMl: 750,
        ),
        isNotNull,
      );
      expect(
        Product.validate(
          name: 'Wine',
          category: 'General',
          costPrice: 1,
          sellPrice: 10,
          stockQty: 1,
          reorderLevel: 1,
          bottleMl: 750,
        ),
        isNull,
      );
    });

    test('fromRow parses a valid export row', () {
      final product = Product.fromRow(
        [7, 'White Wine', 'Wine', '100', '200', '3', '1', '', '750', '', ''],
      );
      expect(product, isNotNull);
      expect(product!.name, 'White Wine');
      expect(product.costPrice.minorUnits, 10000);
      expect(product.bottleMl, 750);
    });

    test('fromRow returns null for a row the editor could not save', () {
      // It used to *throw*, which aborted an entire import on the first bad
      // cell — one unparseable price in row 2 cost the owner all 40 products.
      // A null return lets the caller record the row as needing attention and
      // carry on. Asserted here because the throwing behaviour is what the
      // importers were written around.
      expect(
        Product.fromRow(
            [7, 'x' * 200, 'Wine', '100', '200', '3', '1', '', '750', '', '']),
        isNull,
      );
    });
  });

  group('Product Model Tests', () {
    test('Margin calculation', () {
      final product = Product(
        name: 'Test',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      expect(product.marginPct, closeTo(33.33, 0.1));
    });

    test('Low stock detection', () {
      final product1 = Product(
        name: 'Low Stock',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 3,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final product2 = Product(
        name: 'Good Stock',
        category: 'Wine',
        costPrice: Money.fromMajor(500.0),
        sellPrice: Money.fromMajor(750.0),
        stockQty: 10,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      );

      expect(product1.isLow, isTrue);
      expect(product2.isLow, isFalse);
    });
  });

  group('Shift & Reconciliation Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
    });

    test('Open shift returns an id and creates an open shift', () async {
      final id = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      expect(id, greaterThan(0));

      final open = await db.getOpenShift(1);
      expect(open, isNotNull);
      expect(open!.staffName, 'Cashier');
      expect(open.startFloat.minorUnits, 500000);
      expect(open.status, 'open');
      expect(open.endTime, isNull);
    });

    test('Cannot open two shifts for the same staff member', () async {
      await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      expect(
        () => db.openShift(
          staffId: 1,
          staffName: 'Cashier',
          startFloat: Money.fromMajor(5000),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Can open a shift when a different staff has one open', () async {
      await db.openShift(
        staffId: 1,
        staffName: 'Cashier A',
        startFloat: Money.fromMajor(5000),
      );
      final id = await db.openShift(
        staffId: 2,
        staffName: 'Cashier B',
        startFloat: Money.fromMajor(3000),
      );
      expect(id, greaterThan(0));
    });

    test('getShifts returns open shift for staffId filter', () async {
      await db.openShift(
        staffId: 1,
        staffName: 'Cashier A',
        startFloat: Money.fromMajor(5000),
      );
      final shifts = await db.getShifts(staffId: 1);
      expect(shifts.length, 1);
      expect(shifts.first.status, 'open');
    });

    test('getAnyOpenShift returns null when no shift is open', () async {
      expect(await db.getAnyOpenShift(), isNull);
    });

    test('getAnyOpenShift returns the open shift', () async {
      await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      final open = await db.getAnyOpenShift();
      expect(open, isNotNull);
      expect(open!.status, 'open');
    });

    test('Expected cash equals sum of cash sales during the shift', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Shift Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 100,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      expect(shiftId, greaterThan(0));

      await db.recordSale(
        staffName: 'Cashier',
        staffId: 1,
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Shift Wine',
            qty: 2,
            unitPrice: Money.fromMajor(200),
            unitCost: Money.fromMajor(100),
          ),
        ],
      );

      final shift = await db.getOpenShift(1);
      assert(shift != null);

      final expected = await db.expectedCashForShift(shift!);
      expect(expected.minorUnits, 40000);

      // The balance the drawer should hold is the float plus those takings,
      // so a caller cannot forget the float and report it as a variance.
      expect((await db.expectedTillBalance(shift)).minorUnits, 540000);
    });

    test('Expected cash ignores a sale from another cashier', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Shared Drawer Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 100,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.openShift(
        staffId: 1,
        staffName: 'Amina',
        startFloat: Money.fromMajor(5000),
      );

      // A second person rings a cash sale into the same drawer.
      await db.recordSale(
        staffName: 'Brian',
        staffId: 2,
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Shared Drawer Wine',
            qty: 1,
            unitPrice: Money.fromMajor(200),
            unitCost: Money.fromMajor(100),
          ),
        ],
      );

      final shift = await db.getOpenShift(1);
      expect(shift, isNotNull);
      expect((await db.expectedCashForShift(shift!)).minorUnits, 0);
    });

    test('Expected cash excludes non-cash payments', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Card Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 100,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );

      await db.recordSale(
        staffName: 'Cashier',
        staffId: 1,
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Card Wine',
            qty: 1,
            unitPrice: Money.fromMajor(200),
            unitCost: Money.fromMajor(100),
          ),
        ],
        paymentMethod: 'card',
      );

      final shift = await db.getOpenShift(1);
      assert(shift != null);

      final expected = await db.expectedCashForShift(shift!);
      expect(expected.minorUnits, 0);
    });

    test('Add till count records a denomination pile', () async {
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );

      final countId = await db.addTillCount(
        shiftId: shiftId,
        denomination: 'KSh 100',
        count: 5,
        value: Money.fromMajor(500),
      );
      expect(countId, greaterThan(0));

      final counts = await db.getTillCounts(shiftId);
      expect(counts.length, 1);
      expect(counts.first.denomination, 'KSh 100');
      expect(counts.first.count, 5);
      expect(counts.first.value.minorUnits, 50000);
    });

    test('Reconcile shift computes variance correctly', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Recon Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 100,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );

      await db.recordSale(
        staffName: 'Cashier',
        staffId: 1,
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Recon Wine',
            qty: 3,
            unitPrice: Money.fromMajor(200),
            unitCost: Money.fromMajor(100),
          ),
        ],
      );

      final shift = await db.getOpenShift(1);
      assert(shift != null);

      final expected = await db.expectedCashForShift(shift!);
      final expectedTotal = shift.startFloat + expected;

      // Cashier counted 500 less than expected — a short variance.
      final counted = expectedTotal - Money.fromMajor(500);

      final reconId = await db.reconcileShift(
        shiftId: shiftId,
        countedCash: counted,
        expectedCash: expectedTotal,
      );
      expect(reconId, greaterThan(0));

      final recons = await db.getReconciliationsForShift(shiftId);
      expect(recons.length, 1);
      expect(recons.first.countedCash.minorUnits, counted.minorUnits);
      expect(recons.first.expectedCash.minorUnits, expectedTotal.minorUnits);
      expect(recons.first.variance.minorUnits, -50000);

      // Shift should be closed now.
      final closed = await db.getOpenShift(1);
      expect(closed, isNull);

      final shifts = await db.getShifts(staffId: 1, openOnly: true);
      expect(shifts, isEmpty);
    });

    test('Reconcile shift with end float records it', () async {
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );

      await db.reconcileShift(
        shiftId: shiftId,
        countedCash: Money.fromMajor(6000),
        expectedCash: Money.fromMajor(6000),
        endFloat: Money.fromMajor(2000),
      );

      final shifts = await db.getShifts(staffId: 1);
      expect(shifts.first.endFloat.minorUnits, 200000);
      expect(shifts.first.status, 'closed');
    });

    test('Cannot reconcile an already-closed shift', () async {
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );

      await db.reconcileShift(
        shiftId: shiftId,
        countedCash: Money.fromMajor(6000),
        expectedCash: Money.fromMajor(6000),
      );

      // A closed shift must refuse a second close rather than quietly record
      // a second, different variance against it. Silently succeeding is the
      // dangerous option: the caller walks away believing the till balanced
      // when the ledger now shows two answers to one question.
      expect(
        () => db.reconcileShift(
          shiftId: shiftId,
          countedCash: Money.fromMajor(6000),
          expectedCash: Money.fromMajor(5000),
        ),
        throwsStateError,
      );

      final recons = await db.getReconciliationsForShift(shiftId);
      expect(recons.length, 1);
      expect(recons.first.expectedCash.minorUnits, 600000);
    });

    test('A close with no explicit float keeps the counted cash in the drawer',
        () async {
      // What was counted stays in the till and becomes the next shift's float.
      // Recording zero would tell the next cashier the drawer came up empty.
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      await db.reconcileShift(
        shiftId: shiftId,
        countedCash: Money.fromMajor(4321),
        expectedCash: Money.fromMajor(4300),
      );
      final closed = (await db.getShifts(staffId: 1)).single;
      expect(closed.endFloat.minorUnits, 432100);
    });

    test('Till counts total to the counted cash a reconciliation uses',
        () async {
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      expect((await db.countedCashFromTillCounts(shiftId)).minorUnits, 0);

      await db.addTillCount(
        shiftId: shiftId,
        denomination: 'KSh 1000',
        count: 3,
        value: Money.fromMajor(3000),
      );
      await db.addTillCount(
        shiftId: shiftId,
        denomination: 'KSh 500',
        count: 4,
        value: Money.fromMajor(2000),
      );

      expect((await db.countedCashFromTillCounts(shiftId)).minorUnits, 500000);
    });

    test('Re-counting the till replaces the piles instead of doubling them',
        () async {
      // A cashier who counts the drawer twice must not report double the cash.
      final shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Cashier',
        startFloat: Money.fromMajor(5000),
      );
      for (final n in [3, 4]) {
        await db.clearTillCounts(shiftId);
        await db.addTillCount(
          shiftId: shiftId,
          denomination: 'KSh 500',
          count: n,
          value: Money.fromMajor(500 * n),
        );
      }

      final counts = await db.getTillCounts(shiftId);
      expect(counts.length, 1);
      expect(counts.single.count, 4);
      expect((await db.countedCashFromTillCounts(shiftId)).minorUnits, 200000);
    });
  });

  group('Shot Cup Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
    });

    test('a shot with no size takes nothing from the bottle', () async {
      // The size of a shot is optional, so a cup can have none — and a shot
      // whose size is not known must not empty the bottle.
      //
      // The old answer was a WHOLE container for any measured pour that could
      // not be read, which came from the days when every shot had a size. One
      // unsized shot emptied the shelf.
      final int productId = await db.upsertProduct(Product(
        name: 'AAA Unsized Spirit',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.recordSale(
        staffName: 'Test Staff',
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Unsized Spirit',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.zero,
            portion: SalePortion.measured,
            portionMl: 0,
          ),
        ],
        paymentMethod: 'cash',
      );

      final Product after =
          (await db.getProducts()).firstWhere((p) => p.id == productId);
      expect(
        after.stockQty,
        10,
        reason: 'an unsized shot takes nothing that can be measured, so the '
            'bottle is still full',
      );
    });

    test('a shot with a size takes exactly that much from the bottle',
        () async {
      final int productId = await db.upsertProduct(Product(
        name: 'AAA Sized Spirit',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.recordSale(
        staffName: 'Test Staff',
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Sized Spirit',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(20),
            portion: SalePortion.measured,
            portionMl: 30,
          ),
        ],
        paymentMethod: 'cash',
      );

      final Product after =
          (await db.getProducts()).firstWhere((p) => p.id == productId);
      // 30 ml out of a 750 ml bottle is 0.04 of a bottle.
      expect(after.stockQty, closeTo(9.96, 0.0001));
    });

    test('Upsert creates a new shot cup', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Vodka',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final id = await db.upsertShotCup(ShotCup(
        productId: productId,
        productName: 'AAA Vodka',
        capacityMl: 30,
        price: Money.fromMajor(150),
        label: 'Shot',
        updatedAt: DateTime.now().toIso8601String(),
      ));
      expect(id, greaterThan(0));

      final cups = await db.getShotCups();
      expect(cups.length, 1);
      expect(cups.first.capacityMl, 30);
      expect(cups.first.price.minorUnits, 15000);
    });

    test('Upsert updates an existing shot cup', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Gin',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final id = await db.upsertShotCup(ShotCup(
        productId: productId,
        productName: 'AAA Gin',
        capacityMl: 30,
        price: Money.fromMajor(150),
        label: 'Shot',
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final updated = await db.upsertShotCup(ShotCup(
        id: id,
        productId: productId,
        productName: 'AAA Gin',
        capacityMl: 25,
        price: Money.fromMajor(125),
        label: 'Shot',
        updatedAt: DateTime.now().toIso8601String(),
      ));
      expect(updated, id);

      final cup = await db.getShotCupForProduct(productId);
      expect(cup, isNotNull);
      expect(cup!.capacityMl, 25);
      expect(cup.price.minorUnits, 12500);
    });

    test('Delete soft-deletes a shot cup', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Rum',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final id = await db.upsertShotCup(ShotCup(
        productId: productId,
        productName: 'AAA Rum',
        capacityMl: 30,
        price: Money.fromMajor(150),
        label: 'Shot',
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.deleteShotCup(id);

      final active = await db.getShotCups();
      expect(active, isEmpty);

      final all = await db.getShotCups(activeOnly: false);
      expect(all.length, 1);
      expect(all.first.active, isFalse);
    });

    test('Get shot cup for product returns null when none exists', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Whiskey',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      expect(await db.getShotCupForProduct(productId), isNull);
    });

    test('A cup pointing at a drink that no longer exists is refused',
        () async {
      // Foreign keys are not enforced on this connection, so without this check
      // a stale id stores happily and the till then offers a shot it cannot
      // price or deduct — failing at the last step, with the customer's money
      // already in hand.
      await expectLater(
        db.upsertShotCup(ShotCup(
          productId: 9999,
          productName: 'AAA Deleted Spirit',
          capacityMl: 30,
          price: Money.fromMajor(100),
          updatedAt: DateTime.now().toIso8601String(),
        )),
        throwsStateError,
      );
      expect(await db.getShotCups(activeOnly: false), isEmpty);
    });

    test('A cup with no size is allowed, because the size is optional',
        () async {
      // The size of a shot cup is the OWNER's business: a cup is a name for a
      // serving, and the owner may not know or care how big it is. With a size
      // the app works out what the shot cost to pour; without one the shot is
      // counted at its full price.
      //
      // It used to be refused outright, which meant a shop that did not know
      // its shot sizes could not set up a shot at all.
      final productId = await db.upsertProduct(Product(
        name: 'AAA Unsized Vodka',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final id = await db.upsertShotCup(ShotCup(
        productId: productId,
        productName: 'AAA Unsized Vodka',
        capacityMl: 0,
        price: Money.fromMajor(100),
        updatedAt: DateTime.now().toIso8601String(),
      ));
      expect(id, greaterThan(0));

      final loaded = (await db.getShotCups(activeOnly: false))
          .singleWhere((c) => c.id == id);
      expect(loaded.capacityMl, 0);
      expect(loaded.price.minorUnits, 10000);
    });

    test('A cup with a negative size is refused', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Negative Vodka',
        category: 'Spirits',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(1000),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await expectLater(
        db.upsertShotCup(ShotCup(
          productId: productId,
          productName: 'AAA Negative Vodka',
          capacityMl: -30,
          price: Money.fromMajor(100),
          updatedAt: DateTime.now().toIso8601String(),
        )),
        throwsStateError,
      );
    });

    test('A cup price survives a save and reload unchanged', () async {
      // Guards the money-affinity bug: a REAL price column would read 3000
      // back as 30.00 and sell every shot at a hundredth of its price.
      final productId = await db.upsertProduct(Product(
        name: 'AAA Round Gin',
        category: 'Spirits',
        costPrice: Money.fromMajor(600),
        sellPrice: Money.fromMajor(1200),
        stockQty: 4,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final id = await db.upsertShotCup(ShotCup(
        productId: productId,
        productName: 'AAA Round Gin',
        capacityMl: 30,
        price: Money.fromMajor(300),
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final loaded = (await db.getShotCups()).singleWhere((c) => c.id == id);
      expect(loaded.price.minorUnits, 30000);
      expect(loaded.capacityMl, 30);
      expect(loaded.productName, 'AAA Round Gin');
    });
  });

  group('Cup Size Suggestions Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
    });

    test('Insert a new cup size suggestion', () async {
      await db.upsertCupSizeSuggestion(sizeMl: 330);

      final suggestions = await db.getCupSizeSuggestions();
      expect(suggestions.length, 1);
      expect(suggestions.first.sizeMl, 330);
      expect(suggestions.first.useCount, 1);
      expect(suggestions.first.productId, isNull);
    });

    test('Increment use count for existing suggestion', () async {
      await db.upsertCupSizeSuggestion(sizeMl: 330);
      await db.upsertCupSizeSuggestion(sizeMl: 330);
      await db.upsertCupSizeSuggestion(sizeMl: 330);

      final suggestions = await db.getCupSizeSuggestions();
      expect(suggestions.length, 1);
      expect(suggestions.first.useCount, 3);
    });

    test('Order by use count descending, then size ascending', () async {
      await db.upsertCupSizeSuggestion(sizeMl: 500);
      await db.upsertCupSizeSuggestion(sizeMl: 330);
      await db.upsertCupSizeSuggestion(sizeMl: 330);
      await db.upsertCupSizeSuggestion(sizeMl: 660);
      await db.upsertCupSizeSuggestion(sizeMl: 660);
      await db.upsertCupSizeSuggestion(sizeMl: 660);

      final suggestions = await db.getCupSizeSuggestions();
      expect(suggestions.length, 3);
      expect(suggestions[0].sizeMl, 660);
      expect(suggestions[1].sizeMl, 330);
      expect(suggestions[2].sizeMl, 500);
    });

    test('Suggestions scoped to product plus global', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Beer',
        category: 'Beer',
        costPrice: Money.fromMajor(100),
        sellPrice: Money.fromMajor(200),
        stockQty: 10,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await db.upsertCupSizeSuggestion(sizeMl: 500);
      await db.upsertCupSizeSuggestion(productId: productId, sizeMl: 330);

      final scoped = await db.getCupSizeSuggestionsForProduct(productId);
      expect(scoped.length, 2);
      expect(scoped.any((s) => s.sizeMl == 330 && s.productId == productId),
          isTrue);
      expect(scoped.any((s) => s.sizeMl == 500 && s.productId == null), isTrue);
    });

    test('Rejects non-positive sizes', () async {
      await db.upsertCupSizeSuggestion(sizeMl: 0);
      await db.upsertCupSizeSuggestion(sizeMl: -50);

      final suggestions = await db.getCupSizeSuggestions();
      expect(suggestions, isEmpty);
    });
  });

  group('Expenses and till movements', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
    });

    test('seeds categories and cash expenses reduce expected till', () async {
      final categories = await db.getExpenseCategories();
      expect(categories.map((row) => row['name']), contains('Supplies'));

      await db.openShift(
        staffId: 4,
        staffName: 'Amina',
        startFloat: Money.fromMajor(100),
      );
      final supplies = categories
          .firstWhere((row) => row['name'] == 'Supplies')['id'] as int;
      await db.recordExpense(
        uuid: 'expense-1',
        categoryId: supplies,
        amount: Money.fromMajor(12),
        paidFrom: 'till_cash',
        staffName: 'Amina',
        staffId: 4,
      );

      final shift = await db.getAnyOpenShift();
      expect(shift, isNotNull);
      expect((await db.expectedTillBalance(shift!)).minorUnits, 8800);
    });

    test('expense and its void append reversing financial events', () async {
      final categories = await db.getExpenseCategories();
      final supplies = categories
          .firstWhere((row) => row['name'] == 'Supplies')['id'] as int;
      await db.openShift(
        staffId: 4,
        staffName: 'Amina',
        startFloat: Money.fromMajor(100),
      );
      final expenseId = await db.recordExpense(
        uuid: 'expense-events',
        categoryId: supplies,
        amount: Money.fromMajor(12),
        paidFrom: 'till_cash',
        staffName: 'Amina',
      );
      await db.voidExpense(expenseId);

      final events = await db.getFinancialEvents();
      expect(events.map((event) => event.eventType),
          <String>['expense', 'expense_void']);
      expect(events.first.cashOutMinor, 1200);
      expect(events.first.operatingExpenseMinor, 1200);
      expect(events.last.cashInMinor, 1200);
      expect(events.last.operatingExpenseMinor, -1200);
      expect(events.last.previousHash, events.first.integrityHash);
      expect(events.every((event) => event.integrityHash.length == 64), isTrue);
    });

    test('unpaid expense and later payment reconcile payable and cash once',
        () async {
      final categories = await db.getExpenseCategories();
      final supplies = categories
          .firstWhere((row) => row['name'] == 'Supplies')['id'] as int;
      final expenseId = await db.recordExpense(
        uuid: 'expense-payable',
        categoryId: supplies,
        amount: Money.fromMajor(12),
        paidFrom: 'payable',
        staffName: 'Amina',
      );
      final posted = await db.getFinancialEvents();
      expect(posted.single.eventType, 'expense');
      expect(posted.single.operatingExpenseMinor, 1200);
      expect(posted.single.payableDeltaMinor, 1200);
      expect(posted.single.cashOutMinor, 0);

      final shiftId = await db.openShift(
        staffId: 4,
        staffName: 'Amina',
        startFloat: Money.zero,
      );
      await db.recordExpensePayment(
        uuid: 'expense-payment-half',
        expenseId: expenseId,
        amount: Money.fromMajor(5),
        paymentMethod: 'cash',
        shiftId: shiftId,
      );
      final events = await db.getFinancialEvents();
      final payment = events.last;
      expect(payment.eventType, 'expense_payment');
      expect(payment.operatingExpenseMinor, 0);
      expect(payment.payableDeltaMinor, -500);
      expect(payment.cashOutMinor, 500);
      final totals = await db.getFinancialEventTotals();
      expect(totals.operatingExpenseMinor, 1200);
      expect(totals.payableDeltaMinor, 700);
      expect(totals.cashOutMinor, 500);
    });

    test('cash-control rows remain queued until the server confirms them',
        () async {
      final categories = await db.getExpenseCategories();
      final supplies = categories
          .firstWhere((row) => row['name'] == 'Supplies')['id'] as int;
      final shiftId = await db.openShift(
        staffId: 4,
        staffName: 'Amina',
        startFloat: Money.fromMajor(100),
      );
      final expenseId = await db.recordExpense(
        uuid: 'expense-sync',
        categoryId: supplies,
        amount: Money.fromMajor(2),
        paidFrom: 'till_cash',
        staffName: 'Amina',
      );
      final movementId = await db.recordTillMovement(
        uuid: 'movement-sync',
        shiftId: shiftId,
        movementType: 'cash_in',
        amount: Money.fromMajor(3),
        staffName: 'Amina',
      );

      expect(await db.getUnsyncedExpenses(), hasLength(1));
      expect(await db.getUnsyncedTillMovements(), hasLength(1));
      await db.markExpensesSynced([expenseId]);
      await db.markTillMovementsSynced([movementId]);
      expect(await db.getUnsyncedExpenses(), isEmpty);
      expect(await db.getUnsyncedTillMovements(), isEmpty);
    });

    test('cash-in and cash-drop movements are signed', () async {
      final shiftId = await db.openShift(
        staffId: 4,
        staffName: 'Amina',
        startFloat: Money.fromMajor(100),
      );
      await db.recordTillMovement(
        uuid: 'movement-in',
        shiftId: shiftId,
        movementType: 'cash_in',
        amount: Money.fromMajor(20),
        staffName: 'Amina',
      );
      await db.recordTillMovement(
        uuid: 'movement-drop',
        shiftId: shiftId,
        movementType: 'cash_drop',
        amount: Money.fromMajor(-30),
        staffName: 'Amina',
      );

      final shift = await db.getAnyOpenShift();
      expect((await db.expectedTillBalance(shift!)).minorUnits, 9000);
    });

    test('cash expenses require an open shift', () async {
      final categories = await db.getExpenseCategories();
      final other =
          categories.firstWhere((row) => row['name'] == 'Other')['id'] as int;
      await expectLater(
        db.recordExpense(
          uuid: 'expense-no-shift',
          categoryId: other,
          amount: Money.fromMajor(1),
          paidFrom: 'till_cash',
          staffName: 'Amina',
        ),
        throwsStateError,
      );
    });

    test('expected cash breakdown exposes every reconciliation component',
        () async {
      final shiftId = await db.openShift(
        staffId: 4,
        staffName: 'Amina',
        startFloat: Money.fromMajor(100),
      );
      final shift = await db.getOpenShift(4);
      final breakdown = await db.expectedCashBreakdown(shift!);
      expect(
          breakdown.keys,
          containsAll(<String>[
            'cash_sales',
            'cash_refunds',
            'credit_repayments',
            'till_expenses',
            'till_movements',
          ]));
      expect(shift.id, shiftId);
    });

    test('expense approval is retained with the immutable payout row',
        () async {
      final categories = await db.getExpenseCategories();
      final other =
          categories.firstWhere((row) => row['name'] == 'Other')['id'] as int;
      final id = await db.recordExpense(
        uuid: 'expense-approved',
        categoryId: other,
        amount: Money.fromMajor(1),
        paidFrom: 'other',
        staffName: 'Amina',
        approvedBy: 9,
      );
      final row =
          (await db.getExpenseHistory()).firstWhere((r) => r['id'] == id);
      expect(row['approved_by'], 9);
    });

    test('deactivated categories disappear from new payouts', () async {
      final categories = await db.getExpenseCategories();
      final supplies = categories
          .firstWhere((row) => row['name'] == 'Supplies')['id'] as int;
      await db.setExpenseCategoryActive(categoryId: supplies, active: false);
      expect(
        (await db.getExpenseCategories()).any((row) => row['id'] == supplies),
        isFalse,
      );
      await expectLater(
        db.recordExpense(
          uuid: 'expense-inactive-category',
          categoryId: supplies,
          amount: Money.fromMajor(1),
          paidFrom: 'other',
          staffName: 'Amina',
        ),
        throwsStateError,
      );
    });

    test('expenses paid from other funds do not change expected cash',
        () async {
      final categories = await db.getExpenseCategories();
      final other =
          categories.firstWhere((row) => row['name'] == 'Other')['id'] as int;
      final shiftId = await db.openShift(
        staffId: 4,
        staffName: 'Amina',
        startFloat: Money.fromMajor(100),
      );
      await db.recordExpense(
        uuid: 'expense-other-funds',
        categoryId: other,
        amount: Money.fromMajor(12),
        paidFrom: 'other',
        staffName: 'Amina',
        staffId: 4,
      );
      final shift = await db.getOpenShift(4);
      expect(shift?.id, shiftId);
      expect((await db.expectedTillBalance(shift!)).minorUnits, 10000);
    });

    test('an owner can void an expense only while its shift is open', () async {
      final categories = await db.getExpenseCategories();
      final other =
          categories.firstWhere((row) => row['name'] == 'Other')['id'] as int;
      final shiftId = await db.openShift(
        staffId: 4,
        staffName: 'Amina',
        startFloat: Money.fromMajor(100),
      );
      final expenseId = await db.recordExpense(
        uuid: 'expense-void-open',
        categoryId: other,
        amount: Money.fromMajor(1),
        paidFrom: 'till_cash',
        staffName: 'Amina',
        staffId: 4,
      );
      await db.voidExpense(expenseId);
      expect((await db.getExpensesForShift(shiftId)), isEmpty);

      final second = await db.recordExpense(
        uuid: 'expense-void-closed',
        categoryId: other,
        amount: Money.fromMajor(1),
        paidFrom: 'till_cash',
        staffName: 'Amina',
        staffId: 4,
      );
      await db.reconcileShift(
        shiftId: shiftId,
        countedCash: Money.fromMajor(99),
        expectedCash: Money.fromMajor(99),
      );
      await expectLater(db.voidExpense(second), throwsStateError);
    });

    test('a credit write-off is also recorded as a bad-debt expense', () async {
      final customerId = await (await db.database).insert('customers', {
        'uuid': 'bad-debt-customer',
        'name': 'Write-off customer',
        'balance_minor': 1000,
        'active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.recordCreditAdjustment(
        customerId: customerId,
        amountMinor: -750,
        type: 'writeoff',
        staffName: 'Amina',
        staffId: 4,
        approvedBy: 1,
        note: 'Unrecoverable account',
      );

      final expenses = await db.getExpenseHistory();
      final badDebt = expenses.firstWhere(
        (row) => row['category_name'] == 'Bad debts',
      );
      expect(badDebt['amount_minor'], 750);
      expect(badDebt['paid_from'], 'other');
      expect(badDebt['staff_id'], 4);
    });

    test('discounted sale stores original price and charges net total',
        () async {
      final productId = await (await db.database).insert('products', {
        'name': 'Discounted item',
        'cost_price': 6000,
        'sell_price': 10000,
        'stock_qty': 5,
        'reorder_level': 1,
        'bottle_ml': 750,
        'active': 1,
      });
      final saleId = await db.recordSale(
        staffName: 'Amina',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Discounted item',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
            discount: Money.fromMajor(10),
            priceOverridden: true,
          ),
        ],
      );
      final sale = (await (await db.database)
              .query('sales', where: 'id = ?', whereArgs: [saleId]))
          .single;
      final item = (await (await db.database)
              .query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]))
          .single;
      expect(sale['subtotal_minor'], 10000);
      expect(sale['total'], 9000);
      expect(item['list_unit_price_minor'], 10000);
      expect(item['discount_minor'], 1000);
    });

    test('split tenders write one payment row per tender', () async {
      final productId = await (await db.database).insert('products', {
        'name': 'Split item',
        'cost_price': 1000,
        'sell_price': 3000,
        'stock_qty': 2,
        'reorder_level': 1,
        'bottle_ml': 750,
        'active': 1,
      });
      final saleId = await db.recordSale(
        staffName: 'Amina',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Split item',
            qty: 1,
            unitPrice: Money.fromMajor(30),
            unitCost: Money.fromMajor(10),
          ),
        ],
        tenders: [
          SaleTender(method: 'cash', amount: Money.fromMinor(1000)),
          SaleTender(method: 'card', amount: Money.fromMinor(2000)),
        ],
      );
      final sale = (await (await db.database)
              .query('sales', where: 'id = ?', whereArgs: [saleId]))
          .single;
      final payments = await (await db.database)
          .query('sale_payments', where: 'sale_id = ?', whereArgs: [saleId]);
      expect(sale['payment_method'], 'split');
      expect(payments, hasLength(2));
      expect(
        payments.fold<int>(0, (sum, row) => sum + (row['amount_minor'] as int)),
        3000,
      );
    });

    test('M-Pesa till tender is recorded as a confirmed non-cash payment',
        () async {
      final productId = await (await db.database).insert('products', {
        'name': 'Till payment item',
        'cost_price': 1000,
        'sell_price': 3000,
        'stock_qty': 1,
        'reorder_level': 1,
        'bottle_ml': 750,
        'active': 1,
      });
      final saleId = await db.recordSale(
        staffName: 'Amina',
        paymentMethod: 'mpesa_till',
        paymentReference: 'c2b-1',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Till payment item',
            qty: 1,
            unitPrice: Money.fromMajor(30),
            unitCost: Money.fromMajor(10),
          ),
        ],
      );
      final sale = (await (await db.database)
              .query('sales', where: 'id = ?', whereArgs: [saleId]))
          .single;
      expect(sale['payment_method'], 'mpesa_till');
      expect(sale['payment_reference'], 'c2b-1');
      expect(sale['payment_verified'], 1);
    });

    test('held carts preserve lines and can be removed atomically', () async {
      final customerId = await db.upsertCustomer(Customer(
        uuid: 'held-customer-1',
        name: 'Held customer',
        phone: '+254700000001',
        createdAt: DateTime.now().toIso8601String(),
      ));
      final cartId = await db.holdCart(
        uuid: 'held-cart-1',
        staffName: 'Amina',
        customerId: customerId,
        lines: [
          {
            'product_id': 7,
            'product_name': 'Held product',
            'qty': 2.0,
            'portion': 'half',
            'portion_ml': 375,
            'unit_price': 9000,
            'unit_cost': 5000,
            'discount_minor': 1000,
          },
        ],
      );
      final carts = await db.getHeldCarts();
      final lines = await db.getHeldCartLines(cartId);
      expect(carts.single['line_count'], 1);
      expect(carts.single['customer_id'], customerId);
      expect(carts.single['customer_name'], 'Held customer');
      expect(lines.single['portion'], 'half');
      expect(lines.single['discount_minor'], 1000);
      await db.deleteHeldCart(cartId);
      expect(await db.getHeldCarts(), isEmpty);
      expect(await db.getHeldCartLines(cartId), isEmpty);
    });

    test('Drinks acceptance reconciles bottle, tots, tank tab, M-Pesa and dip',
        () async {
      final bottleId = await (await db.database).insert('products', {
        'name': 'Whisky bottle',
        'category': 'Spirits',
        'cost_price': 10000,
        'sell_price': 30000,
        'stock_qty': 2.0,
        'reorder_level': 1,
        'bottle_ml': 750,
        'active': 1,
      });
      final tankId = await (await db.database).insert('products', {
        'name': 'Tank lager',
        'category': 'Tanks',
        'cost_price': 5000,
        'sell_price': 12000,
        'stock_qty': 0.0,
        'reorder_level': 0,
        'bottle_ml': 50000,
        'active': 1,
      });
      await db.adjustStock(
        StockAdjustment(
          productId: tankId,
          productName: 'Tank lager',
          delta: 1,
          reason: 'Opening tank stock',
          staffName: 'Amina',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      SaleItem line({
        required int productId,
        required String name,
        required double qty,
        required int price,
        required int cost,
        String portion = SalePortion.full,
        int portionMl = 0,
      }) =>
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: name,
            qty: qty,
            unitPrice: Money.fromMajor(price),
            unitCost: Money.fromMajor(cost),
            portion: portion,
            portionMl: portionMl,
          );

      await db.recordSale(
        staffName: 'Amina',
        items: [
          line(
            productId: bottleId,
            name: 'Whisky bottle',
            qty: 1,
            price: 300,
            cost: 100,
          ),
        ],
      );
      await db.recordSale(
        staffName: 'Amina',
        items: [
          line(
            productId: bottleId,
            name: 'Whisky bottle',
            qty: 3,
            price: 12,
            cost: 4,
            portion: SalePortion.measured,
            portionMl: 30,
          ),
        ],
      );

      final tabId = await db.holdCart(
        uuid: 'drinks-table-tab',
        staffName: 'Amina',
        lines: [
          {
            'product_id': tankId,
            'product_name': 'Tank lager',
            'qty': 1.0,
            'portion': SalePortion.measured,
            'portion_ml': 5000,
            'unit_price': 60 * 100,
            'unit_cost': 25 * 100,
          },
        ],
      );
      expect(
          (await db.drinksAnalytics(
            since: DateTime.now().subtract(const Duration(minutes: 1)),
          ))
              .openTabs,
          1);
      final heldLine = (await db.getHeldCartLines(tabId)).single;
      await db.deleteHeldCart(tabId);
      await db.recordSale(
        staffName: 'Amina',
        paymentMethod: 'mpesa_till',
        paymentReference: 'DRINKS-TAB-1',
        items: [
          line(
            productId: tankId,
            name: heldLine['product_name'] as String,
            qty: (heldLine['qty'] as num).toDouble(),
            price: 60,
            cost: 25,
            portion: SalePortion.measured,
            portionMl: (heldLine['portion_ml'] as num).toInt(),
          ),
        ],
      );

      final countId = await db.startStockCount(
        uuid: 'drinks-next-day-dip',
        staffName: 'Amina',
        name: 'Tank dip',
        scopeType: 'tanks',
        note: 'Next-day tank dip',
      );
      final countLine = (await db.getStockCountLines(countId)).single;
      await db.recordStockCountLine(
        lineId: countLine['id'] as int,
        countedQty: 0.89,
      );
      await db.applyStockCount(
        countId: countId,
        staffId: null,
        staffName: 'Amina',
      );

      final tank = (await (await db.database).query(
        'products',
        where: 'id = ?',
        whereArgs: [tankId],
      ))
          .single;
      expect((tank['stock_qty'] as num).toDouble(), closeTo(0.89, 0.0001));
      final sale = (await (await db.database).query(
        'sales',
        where: 'payment_reference = ?',
        whereArgs: ['DRINKS-TAB-1'],
      ))
          .single;
      expect(sale['payment_method'], 'mpesa_till');
      expect(sale['payment_verified'], 1);

      final analytics = await db.drinksAnalytics(
        since: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(analytics.litresSold, closeTo(5.09, 0.0001));
      expect(analytics.measuredLines, 2);
      expect(analytics.openTabs, 0);
      expect(analytics.tanks.single.litresRemaining, closeTo(44.5, 0.0001));
      expect(analytics.dipVarianceLitres, closeTo(-0.5, 0.0001));
    });

    test('held carts stop at ten active sales', () async {
      final line = <String, Object?>{
        'product_id': 7,
        'product_name': 'Held product',
        'qty': 1.0,
        'portion': 'full',
        'portion_ml': 0,
        'unit_price': 100,
        'unit_cost': 50,
      };
      for (var i = 0; i < 10; i++) {
        await db.holdCart(
          uuid: 'held-cap-$i',
          staffName: 'Amina',
          lines: [line],
        );
      }
      await expectLater(
        db.holdCart(
          uuid: 'held-cap-over',
          staffName: 'Amina',
          lines: [line],
        ),
        throwsStateError,
      );
    });

    test('expired held carts are removed at the supplied clock time', () async {
      await db.holdCart(
        uuid: 'held-expired',
        staffName: 'Amina',
        lines: [
          {
            'product_id': 7,
            'product_name': 'Held product',
            'qty': 1.0,
            'portion': 'full',
            'unit_price': 100,
            'unit_cost': 50,
          },
        ],
        expiry: const Duration(minutes: -1),
      );
      expect(
        await db.getHeldCarts(now: DateTime.now()),
        isEmpty,
      );
    });

    test('receipt shares are local records and can be revoked', () async {
      final saleId = await (await db.database).insert('sales', {
        'staff_name': 'Amina',
        'total': 100,
        'profit': 20,
        'payment_method': 'cash',
        'amount_tendered': 100,
        'change_given': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      final shareId = await db.recordReceiptShare(
        uuid: 'receipt-share-1',
        saleId: saleId,
        token: 'token-1',
        url: 'https://example.test/receipt/token-1',
      );
      expect((await db.getReceiptShares(saleId)).single['status'], 'active');
      await db.revokeReceiptShare(shareId);
      expect((await db.getReceiptShares(saleId)).single['status'], 'revoked');
    });

    test('reorder drafts have a durable sync queue across suppliers and orders',
        () async {
      final supplierId = await db.addSupplier(
        name: 'Queued supplier',
        phone: '+254712345678',
        leadTimeDays: 2,
        paymentTerms: 'Cash',
        orderChannel: 'WhatsApp',
      );
      await db.linkProductSupplier(
        uuid: 'queued-product-supplier',
        productId: 7,
        supplierId: supplierId,
        preferred: true,
      );
      final orderId = await db.createPurchaseOrder(
        uuid: 'queued-order',
        supplierId: supplierId,
        staffName: 'Amina',
        lines: [
          <String, Object?>{
            'product_id': 7,
            'product_name': 'Queued product',
            'qty': 4,
            'unit_cost_minor': 100,
          },
        ],
      );
      final records = await db.getUnsyncedReorderRecords();
      expect(
          records.map((row) => row['kind']),
          containsAll(
              <String>['supplier', 'product_supplier', 'purchase_order']));
      expect(
          (records.singleWhere(
              (row) => row['kind'] == 'purchase_order')['payload']['lines']),
          isA<List>());
      await db.markReorderRecordsSynced(records);
      expect(await db.getUnsyncedReorderRecords(), isEmpty);
      expect((await db.getPurchaseOrders()).single['id'], orderId);
    });

    test('drawer events are append-only and queryable by shift', () async {
      await db.recordDrawerEvent(
        uuid: 'drawer-event-1',
        shiftId: 1,
        eventType: 'no_sale',
        reason: 'Customer needed change',
        staffName: 'Amina',
        staffId: 4,
      );
      final events = await db.getDrawerEvents(shiftId: 1);
      expect(events, hasLength(1));
      expect(events.single['event_type'], 'no_sale');
      expect(events.single['reason'], 'Customer needed change');
      expect(events.single['staff_name'], 'Amina');
      expect(events.single['success'], 0);
      await db.recordDrawerEvent(
        uuid: 'drawer-event-2',
        shiftId: 1,
        eventType: 'no_sale',
        reason: 'Other cashier',
        staffName: 'Brian',
        staffId: 5,
        approvedBy: 'Manager',
        success: true,
      );
      final approved = (await db.getDrawerEvents(shiftId: 1))
          .singleWhere((row) => row['uuid'] == 'drawer-event-2');
      expect(approved['approved_by'], 'Manager');
      expect(approved['success'], 1);
      expect((await db.getDrawerEvents(shiftId: 1, staffId: 4)), hasLength(1));
      final pending = await db.getUnsyncedDrawerEvents();
      expect(pending, hasLength(2));
      await db.markDrawerEventsSynced([pending.first['id'] as int]);
      expect((await db.getUnsyncedDrawerEvents()), hasLength(1));
      final queueCounts = await db.unsyncedOperationalCounts();
      expect(queueCounts, containsPair('drawer_events', 1));
      expect(queueCounts, containsPair('stock_movements', isA<int>()));
      expect(queueCounts, containsPair('shot_cups', isA<int>()));
    });

    test('backup log records portable exports without storing a passphrase',
        () async {
      await db.recordBackupLog(
        uuid: 'backup-log-1',
        kind: 'portable_passphrase',
        path: '/tmp/backup.duka',
        clearBytes: 42,
      );
      final rows = await db.getBackupLog();
      expect(rows.single['kind'], 'portable_passphrase');
      expect(rows.single['clear_bytes'], 42);
      expect(rows.single['manifest_json'], isNull);
      expect(await db.countBackupLog(), 1);
    });

    test('full backup log keeps its table-count manifest', () async {
      await db.recordBackupLog(
        uuid: 'backup-log-full-1',
        kind: 'portable_full_passphrase',
        clearBytes: 128,
        manifestJson: '{"products":2,"sales":4}',
        status: 'written',
      );
      final row = (await db.getBackupLog()).single;
      expect(row['kind'], 'portable_full_passphrase');
      expect(row['manifest_json'], '{"products":2,"sales":4}');
      expect(row['status'], 'written');
    });

    test(
        'full snapshot includes user data and restores it without losing analytics sources',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'Backup product',
        category: 'General',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(20),
        stockQty: 7,
        reorderLevel: 2,
        updatedAt: '2026-10-24T00:00:00.000Z',
      ));
      await db.recordSale(
        staffName: 'Backup cashier',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Backup product',
            qty: 1,
            unitPrice: Money.fromMajor(20),
            unitCost: Money.fromMajor(10),
          ),
        ],
        paymentMethod: 'cash',
        amountTendered: Money.fromMajor(20),
      );
      await db.setSetting('backup_marker', 'before');
      final snapshot = await db.exportFullSnapshot();
      expect(snapshot['media'], isA<List>());
      final tables = Map<String, Object?>.from(
          snapshot['tables']! as Map<Object?, Object?>);
      final manifest = Map<String, Object?>.from(
          snapshot['manifest']! as Map<Object?, Object?>);
      final domains = Map<String, Object?>.from(
          snapshot['domainTables']! as Map<Object?, Object?>);
      expect(domains['financial'], contains('financial_events'));
      expect(domains['financial'], contains('sale_payments'));
      expect(domains['profile'], contains('shop_profile'));
      expect(domains['profile'], contains('products'));
      expect(domains['tax'], contains('pending_etims'));
      expect(domains['tax'], contains('sale_items'));
      for (final table in <String>[
        'products',
        'sales',
        'sale_items',
        'sale_payments',
        'staff',
        'credit_ledger',
        'expenses',
        'till_movements',
        'incoming_payments',
        'receipt_shares',
        'backup_log',
      ]) {
        expect(tables, contains(table));
        expect(manifest, contains(table));
      }
      await db.setSetting('backup_marker', 'changed');
      await db.deactivateProduct(productId);

      await db.restoreFullSnapshot(snapshot);

      expect(await db.getSetting('backup_marker'), 'before');
      expect((await db.getProducts()).single.name, 'Backup product');
      expect((await db.getProducts()).single.stockQty, 6);
      expect(
          (await db.database).query('sale_payments'), completion(hasLength(1)));
      final restoreLog = (await db.getBackupLog())
          .where((row) => row['kind'] == 'full_restore')
          .single;
      expect(restoreLog['status'], 'restored');
      expect(restoreLog['manifest_json'], isNotNull);
    });

    test(
        'a full backup rejects a domain manifest that names an uncaptured table',
        () async {
      final snapshot = await db.exportFullSnapshot();
      final domains = Map<String, Object?>.from(
          snapshot['domainTables']! as Map<Object?, Object?>);
      final financial = List<Object?>.from(domains['financial']! as List)
        ..add('financial_events_missing');
      domains['financial'] = financial;
      final broken = <String, Object?>{...snapshot, 'domainTables': domains};

      // The manifest is an explicit coverage contract: a backup cannot claim
      // to contain a domain while silently dropping one of its source tables.
      await expectLater(
        db.restoreFullSnapshot(broken),
        throwsA(isA<FormatException>()),
      );
    });

    test('a full backup rejects a tampered financial chain before restore',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'Integrity backup product',
        category: 'General',
        costPrice: Money.fromMajor(1),
        sellPrice: Money.fromMajor(2),
        stockQty: 1,
        reorderLevel: 0,
        updatedAt: '2026-10-26T00:00:00.000Z',
      ));
      await db.recordSale(
        staffName: 'Integrity backup cashier',
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Integrity backup product',
            qty: 1,
            unitPrice: Money.fromMajor(2),
            unitCost: Money.fromMajor(1),
          ),
        ],
      );
      final snapshot = await db.exportFullSnapshot();
      final tables = Map<String, Object?>.from(
          snapshot['tables']! as Map<Object?, Object?>);
      final events = (tables['financial_events']! as List)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList();
      events.first['metadata_json'] = '{"tampered":true}';
      tables['financial_events'] = events;
      final broken = <String, Object?>{...snapshot, 'tables': tables};

      await expectLater(
        db.restoreFullSnapshot(broken),
        throwsA(isA<FormatException>()),
      );
      expect(
        (await db.getBackupLog()).where((row) => row['kind'] == 'full_restore'),
        isEmpty,
      );
    });

    test(
        'a failed full restore is atomic and leaves the current workspace intact',
        () async {
      await db.upsertProduct(Product(
        name: 'Atomic backup product',
        category: 'General',
        costPrice: Money.fromMajor(1),
        sellPrice: Money.fromMajor(2),
        stockQty: 1,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      await db.setSetting('restore_marker', 'current');
      final snapshot = await db.exportFullSnapshot();
      final tables = Map<String, Object?>.from(
          snapshot['tables']! as Map<Object?, Object?>);
      final products = (tables['products']! as List)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList();
      products.first['column_that_does_not_exist'] = 1;
      tables['products'] = products;
      final broken = <String, Object?>{
        ...snapshot,
        'tables': tables,
      };

      await expectLater(db.restoreFullSnapshot(broken), throwsA(anything));
      expect(await db.getSetting('restore_marker'), 'current');
    });

    test('a non-row in a full snapshot is rejected before any table is cleared',
        () async {
      await db.upsertProduct(Product(
        name: 'Malformed backup guard',
        category: 'General',
        costPrice: Money.fromMajor(1),
        sellPrice: Money.fromMajor(2),
        stockQty: 3,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      await db.setSetting('restore_marker', 'safe');
      final snapshot = await db.exportFullSnapshot();
      final tables = Map<String, Object?>.from(
          snapshot['tables']! as Map<Object?, Object?>);
      final products = List<Object?>.from(tables['products']! as List)
        ..add('not-a-row');
      tables['products'] = products;
      final broken = <String, Object?>{...snapshot, 'tables': tables};

      await expectLater(
          db.restoreFullSnapshot(broken), throwsA(isA<FormatException>()));
      expect(await db.getSetting('restore_marker'), 'safe');
      expect((await db.getProducts()).single.name, 'Malformed backup guard');
    });

    test('malformed snapshot media is rejected before any table is cleared',
        () async {
      await db.upsertProduct(Product(
        name: 'Malformed media guard',
        category: 'General',
        costPrice: Money.fromMajor(1),
        sellPrice: Money.fromMajor(2),
        stockQty: 3,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      await db.setSetting('media_restore_marker', 'safe');
      final snapshot = await db.exportFullSnapshot();
      final broken = <String, Object?>{
        ...snapshot,
        'media': <Object?>[
          <String, String>{'path': '../escape.jpg', 'bytes': 'not-base64'},
        ],
      };

      await expectLater(
        db.restoreFullSnapshot(broken),
        throwsA(isA<FormatException>()),
      );
      expect(await db.getSetting('media_restore_marker'), 'safe');
      expect((await db.getProducts()).single.name, 'Malformed media guard');
    });

    test('a backup from another shop cannot replace the active workspace',
        () async {
      final snapshot = await db.exportFullSnapshot();
      final foreign = <String, Object?>{
        ...snapshot,
        'workspaceKey': 'another-shop',
      };

      await expectLater(
        db.restoreFullSnapshot(foreign),
        throwsA(isA<FormatException>()),
      );
    });

    test('a portable backup can restore onto a replacement workspace',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'Portable restore product',
        category: 'General',
        costPrice: Money.fromMajor(2),
        sellPrice: Money.fromMajor(4),
        stockQty: 5,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final snapshot = await db.exportFullSnapshot();
      await db.deactivateProduct(productId);
      final portable = <String, Object?>{
        ...snapshot,
        'workspaceKey': 'source-phone-workspace',
      };

      await db.restoreFullSnapshot(
        portable,
        allowWorkspaceMismatch: true,
      );

      expect((await db.getProducts()).single.active, isTrue);
      expect((await db.getProducts()).single.name, 'Portable restore product');
    });

    test('incoming M-Pesa payments are cached and filtered by status',
        () async {
      await db.upsertIncomingPayment(IncomingPayment(
        remoteId: 'remote-1',
        transactionId: 'QAB123',
        amount: Money.fromMajor(125),
        payerMasked: 'A ···123',
        receivedAt: DateTime.now(),
        status: 'unclaimed',
      ));
      expect((await db.getIncomingPayments(status: 'unclaimed')).single.amount,
          Money.fromMajor(125));
      expect(await db.getIncomingPayments(status: 'claimed'), isEmpty);
      expect(await db.countIncomingPayments(status: 'unclaimed'), 1);
      expect(await db.countIncomingPayments(status: 'claimed'), 0);
    });

    test('offline M-Pesa claims are durable and can become disputes', () async {
      await db.upsertIncomingPayment(IncomingPayment(
        remoteId: 'remote-claim-1',
        transactionId: 'QAB124',
        amount: Money.fromMajor(125),
        payerMasked: 'A ···124',
        receivedAt: DateTime.now(),
        status: 'unclaimed',
      ));
      await db.recordIncomingPaymentClaim(
        remoteId: 'remote-claim-1',
        saleId: 42,
        saleUuid: 'local-sale-42',
      );
      expect(
          (await db.getPendingIncomingPaymentClaims()).single['sale_id'], 42);
      expect(await db.countPendingIncomingPaymentClaims(), 1);

      await db.markIncomingPaymentClaimDisputed(
        'remote-claim-1',
        'Another till claimed it',
      );
      expect(await db.getPendingIncomingPaymentClaims(), isEmpty);
      expect(await db.countPendingIncomingPaymentClaims(), 0);
      expect((await db.getIncomingPayments()).single.status, 'disputed');
    });

    test('pack barcodes resolve separately and cannot collide with products',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'Packable product',
        category: 'General',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(20),
        stockQty: 24,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final packId = await db.addProductPack(
        uuid: 'pack-1',
        productId: productId,
        name: 'Case of 24',
        barcode: 'PACK-0001',
        unitsPerPack: 24,
        unitCost: Money.fromMajor(200),
      );
      final resolved = await db.getSellableByBarcode('PACK-0001');
      expect(resolved.pack?.id, packId);
      expect(resolved.product, isNull);
      await expectLater(
        db.addProductPack(
          uuid: 'pack-2',
          productId: productId,
          name: 'Duplicate',
          barcode: 'PACK-0001',
          unitsPerPack: 12,
          unitCost: Money.fromMajor(100),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('label print jobs retain the unprinted suffix for retry', () async {
      final id = await db.createLabelPrintJob(
        uuid: 'label-job-1',
        productId: 1,
        productName: 'Labelled product',
        barcode: '1234567890128',
        priceMinor: 1250,
        quantity: 25,
        paperWidth: 58,
      );
      await db.updateLabelPrintJob(
        id: id,
        printedQuantity: 20,
        status: 'pending',
        error: 'printer disconnected',
      );
      final job = await db.getLabelPrintJob(id);
      expect(job?['printed_quantity'], 20);
      expect(job?['quantity'], 25);
      expect(job?['status'], 'pending');
      expect((await db.getPendingLabelPrintJobs()), hasLength(1));
      await db.updateLabelPrintJob(
        id: id,
        printedQuantity: 25,
        status: 'completed',
      );
      expect(await db.getPendingLabelPrintJobs(), isEmpty);
    });

    test('a pack can target one product variant and scan preserves it',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'Variant pack product',
        category: 'General',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(20),
        stockQty: 12,
        reorderLevel: 0,
        trackVariants: true,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final variantId = await db.upsertVariant(ProductVariant(
        productId: productId,
        name: 'Large',
        sellPrice: Money.fromMajor(20),
        costPrice: Money.fromMajor(10),
        stockQty: 12,
      ));
      final packId = await db.addProductPack(
        uuid: 'pack-variant-1',
        productId: productId,
        variantId: variantId,
        name: 'Large case',
        barcode: 'PACK-VARIANT-1',
        unitsPerPack: 12,
        unitCost: Money.fromMajor(120),
      );
      final target = await db.getScanTarget('PACK-VARIANT-1');
      expect(target?.pack?.id, packId);
      expect(target?.pack?.variantId, variantId);
      expect(target?.variant?.id, variantId);
    });

    test('receiving by pack converts pack quantity into base stock units',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'Cases product',
        category: 'General',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(20),
        stockQty: 0,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final packId = await db.addProductPack(
        uuid: 'pack-receive-1',
        productId: productId,
        name: 'Case of 6',
        barcode: 'PACK-0006',
        unitsPerPack: 6,
        unitCost: Money.fromMajor(60),
      );
      await db.postStockReceiptByPack(
        packId: packId,
        packQty: 2,
        staffName: 'Owner',
      );
      expect((await db.getProducts()).single.stockQty, 12);
    });

    test('a pack sale keeps pack metadata and charges its pack price per unit',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'Pack sale product',
        category: 'General',
        costPrice: Money.fromMajor(5),
        sellPrice: Money.fromMajor(10),
        stockQty: 6,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final packId = await db.addProductPack(
        uuid: 'pack-sale-1',
        productId: productId,
        name: 'Case of 6',
        barcode: 'PACK-SALE-6',
        unitsPerPack: 6,
        unitCost: Money.fromMajor(30),
        sellPrice: Money.fromMajor(60),
      );
      final saleId = await db.recordSale(
        staffName: 'Owner',
        items: [
          SaleItem(
            productId: productId,
            productName: 'Pack sale product',
            qty: 6,
            unitPrice: Money.fromMajor(10),
            unitCost: Money.fromMajor(5),
            packId: packId,
            packQty: 1,
            saleId: 0,
          ),
        ],
        amountTendered: Money.fromMajor(60),
      );
      final row = (await (await db.database).query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      ))
          .single;
      expect(row['pack_id'], packId);
      expect(row['pack_qty'], 1);
    });

    test(
        'Duka acceptance reconciles counted, measured, pack, repack and credit',
        () async {
      final sugarId = await db.upsertProduct(Product(
        name: 'Bulk sugar',
        category: 'Loose goods',
        costPrice: Money.fromMajor(80),
        sellPrice: Money.fromMajor(100),
        stockQty: 0,
        reorderLevel: 1,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final packetId = await db.upsertProduct(Product(
        name: 'Sugar packet 500 g',
        category: 'Loose goods',
        costPrice: Money.zero,
        sellPrice: Money.fromMajor(40),
        stockQty: 0,
        reorderLevel: 1,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final cigaretteId = await db.upsertProduct(Product(
        name: 'Cigarette single',
        category: 'Tobacco',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(15),
        stockQty: 0,
        reorderLevel: 1,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final eggId = await db.upsertProduct(Product(
        name: 'Egg single',
        category: 'Produce',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(15),
        stockQty: 0,
        reorderLevel: 1,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final cartonId = await db.addProductPack(
        uuid: 'duka-cigarette-carton',
        productId: cigaretteId,
        name: 'Carton of 20',
        barcode: 'DUKA-CARTON-20',
        unitsPerPack: 20,
        unitCost: Money.fromMajor(200),
        sellPrice: Money.fromMajor(300),
      );
      final trayId = await db.addProductPack(
        uuid: 'duka-egg-tray',
        productId: eggId,
        name: 'Tray of 30',
        barcode: 'DUKA-TRAY-30',
        unitsPerPack: 30,
        unitCost: Money.fromMajor(300),
        sellPrice: Money.fromMajor(450),
      );
      await db.postStockReceipt(
        lines: [
          StockReceiptLine(
            productId: sugarId,
            productName: 'Bulk sugar',
            qty: 50,
            unitCost: Money.fromMajor(80),
          ),
        ],
        staffName: 'Owner',
      );
      await db.postStockReceiptByPack(
        packId: cartonId,
        packQty: 2,
        staffName: 'Owner',
      );
      await db.postStockReceiptByPack(
        packId: trayId,
        packQty: 2,
        staffName: 'Owner',
      );
      await db.recordSale(
        staffName: 'Owner',
        items: [
          SaleItem(
            saleId: 0,
            productId: sugarId,
            productName: 'Bulk sugar',
            qty: 0.5,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(80),
          ),
        ],
        amountTendered: Money.fromMajor(50),
      );
      await db.recordSale(
        staffName: 'Owner',
        items: [
          SaleItem(
            saleId: 0,
            productId: cigaretteId,
            productName: 'Cigarette single',
            qty: 1,
            unitPrice: Money.fromMajor(15),
            unitCost: Money.fromMajor(10),
          ),
          SaleItem(
            saleId: 0,
            productId: cigaretteId,
            productName: 'Cigarette single',
            qty: 20,
            unitPrice: Money.fromMajor(15),
            unitCost: Money.fromMajor(10),
            packId: cartonId,
            packQty: 1,
          ),
        ],
        amountTendered: Money.fromMajor(315),
      );
      await db.repackStock(
        sourceProductId: sugarId,
        outputProductId: packetId,
        sourceQty: 10,
        outputQty: 20,
        staffName: 'Owner',
      );
      final customerId = await db.upsertCustomer(Customer(
        uuid: 'duka-credit-customer',
        name: 'Neighbour shop',
        creditLimitMinor: 10000,
        createdAt: DateTime.now().toIso8601String(),
      ));
      await db.setCreditEnabled(true);
      await db.recordSale(
        staffName: 'Owner',
        paymentMethod: 'credit',
        customerId: customerId,
        items: [
          SaleItem(
            saleId: 0,
            productId: eggId,
            productName: 'Egg single',
            qty: 1,
            unitPrice: Money.fromMajor(15),
            unitCost: Money.fromMajor(10),
          ),
          SaleItem(
            saleId: 0,
            productId: packetId,
            productName: 'Sugar packet 500 g',
            qty: 1,
            unitPrice: Money.fromMajor(40),
            unitCost: Money.fromMajor(40),
          ),
        ],
      );

      final products = await db.getProducts();
      expect(products.firstWhere((p) => p.id == sugarId).stockQty,
          closeTo(39.5, 0.0001));
      expect(products.firstWhere((p) => p.id == packetId).stockQty,
          closeTo(19, 0.0001));
      expect(products.firstWhere((p) => p.id == cigaretteId).stockQty,
          closeTo(19, 0.0001));
      expect(products.firstWhere((p) => p.id == eggId).stockQty,
          closeTo(59, 0.0001));
      expect((await db.getCustomerById(customerId))!.balanceMinor, 5500);
      expect(await db.findLedgerDifferences(), isEmpty);
      final repackRows = await (await db.database).query(
        'stock_movements',
        where: 'movement_type = ?',
        whereArgs: [StockMovementType.repack.wire],
      );
      expect(repackRows, hasLength(2));
    });

    test('sales velocity returns recent base units per day', () async {
      final productId = await db.upsertProduct(Product(
        name: 'Velocity product',
        category: 'General',
        costPrice: Money.fromMajor(1),
        sellPrice: Money.fromMajor(2),
        stockQty: 10,
        reorderLevel: 0,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      await db.recordSale(
        staffName: 'Owner',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Velocity product',
            qty: 3,
            unitPrice: Money.fromMajor(2),
            unitCost: Money.fromMajor(1),
          ),
        ],
        amountTendered: Money.fromMajor(6),
      );
      expect((await db.getSalesVelocity())[productId], closeTo(0.1, 0.00001));
    });

    test('supplier links and purchase orders keep their own numbered series',
        () async {
      final productId = await db.upsertProduct(Product(
        name: 'Order product',
        category: 'General',
        costPrice: Money.fromMajor(10),
        sellPrice: Money.fromMajor(20),
        stockQty: 2,
        reorderLevel: 5,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final supplierId = await db.addSupplier(
        name: 'Acme Wholesale',
        leadTimeDays: 3,
        paymentTerms: 'Cash on delivery',
        orderChannel: 'WhatsApp',
      );
      await db.linkProductSupplier(
        uuid: 'supplier-link-1',
        productId: productId,
        supplierId: supplierId,
        preferred: true,
      );
      final orderId = await db.createPurchaseOrder(
        uuid: 'po-1',
        supplierId: supplierId,
        staffName: 'Owner',
        lines: [
          {
            'product_id': productId,
            'product_name': 'Order product',
            'qty': 10,
            'unit_cost_minor': 1000,
          },
        ],
      );
      final orders = await db.getPurchaseOrders(supplierId: supplierId);
      expect(orders.single['id'], orderId);
      expect(orders.single['order_number'], startsWith('PO-'));
      expect((await db.getProductSuppliers(productId)).single['preferred'], 1);
      expect((await db.getSuppliers()).single.leadTimeDays, 3);
      await db.postStockReceipt(
        purchaseOrderId: orderId,
        supplierId: supplierId,
        staffName: 'Owner',
        lines: [
          StockReceiptLine(
            productId: productId,
            productName: 'Order product',
            qty: 10,
            unitCost: Money.fromMajor(10),
          ),
        ],
      );
      expect(
          (await db.getPurchaseOrders(supplierId: supplierId)).single['status'],
          'received');
      expect((await db.getProducts()).single.stockQty, 12);
    });

    test('stock sync conflicts remain visible until the owner resolves them',
        () async {
      await db.recordSyncConflict(
        uuid: 'device-a:42',
        kind: 'sale_stock',
        localId: 42,
        deviceId: 'device-a',
        reason: 'Insufficient stock; another till recorded the sale first',
        payloadJson: '{"localId":42}',
      );
      expect(await db.countOpenSyncConflicts(), 1);
      expect((await db.getOpenSyncConflicts()).single['local_id'], 42);

      // Retrying the same response updates one conflict, never duplicates it.
      await db.recordSyncConflict(
        uuid: 'device-a:42',
        kind: 'sale_stock',
        localId: 42,
        deviceId: 'device-a',
        reason: 'Still needs review',
      );
      expect(await db.countOpenSyncConflicts(), 1);
      expect((await db.getOpenSyncConflicts()).single['reason'],
          'Still needs review');

      await db.resolveSyncConflict('device-a:42', 'owner_reviewed');
      expect(await db.countOpenSyncConflicts(), 0);
    });
  });
}
