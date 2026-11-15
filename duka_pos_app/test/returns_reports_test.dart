import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/credit.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/analytics.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DatabaseHelper.openInMemoryForTests();
    await DatabaseHelper.instance.setCreditEnabled(true);
    await DatabaseHelper.instance.setVatRatePercent(0);
    await DatabaseHelper.instance.openShift(
      staffId: 7,
      staffName: 'Amina',
      startFloat: Money.fromMajor(1000),
    );
  });

  Future<int> seedProduct() => DatabaseHelper.instance.upsertProduct(Product(
        name: 'Tusker',
        category: 'Beer',
        costPrice: Money.fromMajor(60),
        sellPrice: Money.fromMajor(100),
        stockQty: 50,
        reorderLevel: 2,
        bottleMl: 500,
        updatedAt: DateTime.now().toIso8601String(),
      ));

  Future<Sale> sell({
    required int productId,
    double qty = 2,
    String paymentMethod = 'cash',
    int? customerId,
  }) async {
    final int saleId = await DatabaseHelper.instance.recordSale(
      staffName: 'Amina',
      staffId: 7,
      paymentMethod: paymentMethod,
      customerId: customerId,
      items: <SaleItem>[
        SaleItem(
          saleId: 0,
          productId: productId,
          productName: 'Tusker',
          qty: qty,
          unitPrice: Money.fromMajor(100),
          unitCost: Money.fromMajor(60),
        ),
      ],
    );
    return (await DatabaseHelper.instance.getSaleById(saleId))!;
  }

  Future<DailyTotals> today() {
    final DateTime start = DateTime.now().subtract(const Duration(days: 1));
    return DatabaseHelper.instance.salesTotalsFor(
      since: start,
      until: DateTime.now().add(const Duration(days: 1)),
    );
  }

  group('refunds come off the reports', () {
    test('takings and profit are net of a restocked return', () async {
      final int productId = await seedProduct();
      final Sale sale = await sell(productId: productId, qty: 2);
      final DailyTotals before = await today();

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
        ],
        reason: 'Changed mind',
        staffName: 'Amina',
        staffId: 7,
      );
      final DailyTotals after = await today();

      // One of two bottles at KSh 100 came back.
      expect(before.totalMinor - after.totalMinor, 10000);
      // It went back on the shelf, so the profit on it (100 - 60) is taken
      // back and the cost is not.
      expect(before.profitMinor - after.profitMinor, 4000);
    });

    test('a write-off takes back the whole net revenue', () async {
      final int productId = await seedProduct();
      final Sale sale = await sell(productId: productId, qty: 1);
      final DailyTotals before = await today();

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(
            saleItemId: sale.items.single.id!,
            qty: 1,
            restock: false,
            restockReason: 'Broken',
          ),
        ],
        reason: 'Broken',
        staffName: 'Amina',
        staffId: 7,
      );
      final DailyTotals after = await today();

      expect(before.totalMinor - after.totalMinor, 10000);
      expect(before.profitMinor - after.profitMinor, 10000);
    });

    test('a fully returned product drops out of the top sellers', () async {
      final int productId = await seedProduct();
      final Sale sale = await sell(productId: productId, qty: 2);
      final DateTime since = DateTime.now().subtract(const Duration(days: 1));

      expect(await DatabaseHelper.instance.topProducts(since: since),
          hasLength(1));

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 2),
        ],
        reason: 'Changed mind',
        staffName: 'Amina',
        staffId: 7,
      );
      expect(await DatabaseHelper.instance.topProducts(since: since), isEmpty);
    });

    test('a partial return reduces units and revenue', () async {
      final int productId = await seedProduct();
      final Sale sale = await sell(productId: productId, qty: 3);
      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
        ],
        reason: 'Changed mind',
        staffName: 'Amina',
        staffId: 7,
      );
      final rows = await DatabaseHelper.instance
          .topProducts(since: DateTime.now().subtract(const Duration(days: 1)));
      expect(rows.single.units, 2);
      expect(rows.single.revenueMinor, 20000);
    });
  });

  group('a sale on account is refunded to the account', () {
    Future<Customer> seedCustomer() async {
      final int id = await DatabaseHelper.instance.upsertCustomer(Customer(
        uuid: 'c-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Mary Wanjiku',
        creditLimitMinor: 999999,
        createdAt: DateTime.now().toIso8601String(),
      ));
      return (await DatabaseHelper.instance.getCustomerById(id))!;
    }

    test('a cash refund on a credit sale is refused', () async {
      final int productId = await seedProduct();
      final Customer mary = await seedCustomer();
      final Sale sale = await sell(
        productId: productId,
        qty: 1,
        paymentMethod: 'credit',
        customerId: mary.id,
      );
      for (final String method in <String>['cash', 'mpesa']) {
        await expectLater(
          DatabaseHelper.instance.recordReturn(
            sale: sale,
            lines: <ReturnLineDraft>[
              ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
            ],
            reason: 'Changed mind',
            refundMethod: method,
            staffName: 'Amina',
            staffId: 7,
          ),
          throwsStateError,
          reason: '$method refund on a credit sale must be refused',
        );
      }
    });

    test('refunding it to the account lowers the debt and opens no drawer',
        () async {
      final int productId = await seedProduct();
      final Customer mary = await seedCustomer();
      final Sale sale = await sell(
        productId: productId,
        qty: 1,
        paymentMethod: 'credit',
        customerId: mary.id,
      );
      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
        ],
        reason: 'Changed mind',
        refundMethod: 'credit_to_account',
        staffName: 'Amina',
        staffId: 7,
      );
      final Customer after =
          (await DatabaseHelper.instance.getCustomerById(mary.id!))!;
      expect(after.balanceMinor, 0);
    });
  });

  test('the same sale line listed twice cannot return more than was sold',
      () async {
    final int productId = await seedProduct();
    final Sale sale = await sell(productId: productId, qty: 1);
    final int lineId = sale.items.single.id!;
    await expectLater(
      DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: lineId, qty: 1),
          ReturnLineDraft(saleItemId: lineId, qty: 1),
        ],
        reason: 'Twice',
        staffName: 'Amina',
        staffId: 7,
      ),
      throwsStateError,
    );
  });
}
