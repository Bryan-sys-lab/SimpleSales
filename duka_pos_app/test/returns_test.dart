// Returns: goods going back to the shop, and money going back to the customer.
//
// ## THE RULES
//
// A return is the one thing in a till that gives money back, so every rule
// about it is about not giving back too much:
//
//   * the cumulative returned quantity per sale line never exceeds the sold
//     quantity — a bottle can be returned ONCE, and the check is against what
//     has already come back, not just against this return;
//   * the refund per line is the line total scaled by the returned fraction,
//     rounded HALF-UP, and the return's total is the SUM of the line refunds;
//   * restocking puts the goods back at the sale line's cost, and a write-off
//     does not — the shelf does not get back a broken bottle;
//   * a cash refund reduces the expected cash of the drawer that was OPEN at
//     the time, not the one the sale was rung in, and with no drawer open it
//     is refused;
//   * a sale whose mobile-money payment was never confirmed cannot be
//     returned, because the money may never have arrived.
//
// ## WHY THE HALF-UP ROUNDING
//
// Rounding a refund DOWN is how a shop quietly keeps a cent of every return.
// The rule is stated once, in one place, and every line goes through it.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/models/stock_movement.dart';
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
  });

  /// A product on the shelf.
  Future<int> seedProduct({
    String name = 'Tusker',
    double cost = 60,
    double price = 100,
    double stock = 20,
  }) async {
    final int id = await DatabaseHelper.instance.upsertProduct(Product(
      name: name,
      category: 'Beer',
      costPrice: Money.fromMajor(cost),
      sellPrice: Money.fromMajor(price),
      stockQty: stock,
      reorderLevel: 2,
      bottleMl: 500,
      updatedAt: DateTime.now().toIso8601String(),
    ));
    expect(id, greaterThan(0));
    return id;
  }

  /// A recorded sale, read back so its lines carry their ids.
  Future<Sale> seedSale({
    required int productId,
    double qty = 2,
    double price = 100,
    String paymentMethod = 'cash',
    int? staffId = 7,
    String staffName = 'Amina',
  }) async {
    await DatabaseHelper.instance.recordSale(
      staffName: staffName,
      staffId: staffId,
      paymentMethod: paymentMethod,
      items: <SaleItem>[
        SaleItem(
          saleId: 0,
          productId: productId,
          productName: 'Tusker',
          qty: qty,
          unitPrice: Money.fromMajor(price),
          unitCost: Money.fromMajor(price * 0.6),
        ),
      ],
    );
    final List<Sale> sales = await DatabaseHelper.instance.getSales();
    expect(sales, isNotEmpty);
    return sales.first;
  }

  /// An open drawer, with [float] in it.
  Future<int> openShift({int staffId = 7, double float = 1000}) {
    return DatabaseHelper.instance.openShift(
      staffId: staffId,
      staffName: 'Amina',
      startFloat: Money.fromMajor(float),
    );
  }

  group('the money', () {
    test('a split refund is allocated back to tenders by largest remainder',
        () async {
      final int productId = await seedProduct(price: 100);
      await DatabaseHelper.instance.recordSale(
        staffName: 'Amina',
        staffId: 7,
        tenders: <SaleTender>[
          SaleTender(method: 'cash', amount: Money.fromMinor(7000)),
          SaleTender(method: 'mpesa', amount: Money.fromMinor(3000)),
        ],
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Tusker',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
          ),
        ],
      );
      final Sale sale = (await DatabaseHelper.instance.getSales()).first;
      await openShift();

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 0.5),
        ],
        reason: 'Half returned',
        staffName: 'Amina',
        staffId: 7,
      );

      final SaleReturn returned =
          (await DatabaseHelper.instance.getReturnsForSale(sale.id!)).single;
      expect(returned.refundAllocations, hasLength(2));
      expect(returned.refundAllocations[0].method, 'cash');
      expect(returned.refundAllocations[0].amount, Money.fromMinor(3500));
      expect(returned.refundAllocations[1].method, 'mpesa');
      expect(returned.refundAllocations[1].amount, Money.fromMinor(1500));
      expect(
        returned.refundAllocations.fold<int>(
          0,
          (sum, allocation) => sum + allocation.amount.minorUnits,
        ),
        returned.total.minorUnits,
      );
    });

    test('a whole line refunds the line total', () async {
      final int productId = await seedProduct();
      final Sale sale =
          await seedSale(productId: productId, qty: 2, price: 100);
      await openShift();

      final int returnId = await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 2),
        ],
        reason: 'The customer changed their mind',
        staffName: 'Amina',
        staffId: 7,
      );
      expect(returnId, greaterThan(0));

      final List<SaleReturn> returns =
          await DatabaseHelper.instance.getReturnsForSale(sale.id!);
      expect(returns, hasLength(1));
      // Two bottles at KSh 100.
      expect(returns.single.total, Money.fromMajor(200));
    });

    test('a part of a line refunds that part', () async {
      final int productId = await seedProduct();
      final Sale sale =
          await seedSale(productId: productId, qty: 2, price: 100);
      await openShift();

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
        ],
        reason: 'One bottle only',
        staffName: 'Amina',
        staffId: 7,
      );

      final List<SaleReturn> returns =
          await DatabaseHelper.instance.getReturnsForSale(sale.id!);
      expect(returns.single.total, Money.fromMajor(100));
    });

    test('the total is the sum of the line refunds, not the sale scaled',
        () async {
      // Two lines with odd fractions: scaling the SALE's total and summing
      // the lines can differ by a cent, and the lines are what the customer
      // is refunded for.
      final int productId = await seedProduct();
      await DatabaseHelper.instance.recordSale(
        staffName: 'Amina',
        staffId: 7,
        paymentMethod: 'cash',
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Tusker',
            qty: 3,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
          ),
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Tusker',
            qty: 3,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
          ),
        ],
      );
      final Sale sale = (await DatabaseHelper.instance.getSales()).first;
      await openShift();

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items[0].id!, qty: 1),
          ReturnLineDraft(saleItemId: sale.items[1].id!, qty: 1),
        ],
        reason: 'Two bottles back',
        staffName: 'Amina',
        staffId: 7,
      );

      final List<SaleReturn> returns =
          await DatabaseHelper.instance.getReturnsForSale(sale.id!);
      expect(returns.single.total, Money.fromMajor(200));
      expect(returns.single.items, hasLength(2));
      expect(
        returns.single.items.fold<int>(
          0,
          (int sum, SaleReturnItem item) => sum + item.refund.minorUnits,
        ),
        20000,
      );
    });

    test('a half of a bottle refunds half of it', () async {
      final int productId = await seedProduct();
      final Sale sale =
          await seedSale(productId: productId, qty: 1, price: 100);
      await openShift();

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 0.5),
        ],
        reason: 'Half of it',
        staffName: 'Amina',
        staffId: 7,
      );

      final List<SaleReturn> returns =
          await DatabaseHelper.instance.getReturnsForSale(sale.id!);
      expect(returns.single.total, Money.fromMajor(50));
    });
  });

  group('the rules', () {
    test('a bottle can only be returned once', () async {
      final int productId = await seedProduct();
      final Sale sale =
          await seedSale(productId: productId, qty: 1, price: 100);
      await openShift();

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
        ],
        reason: 'First time',
        staffName: 'Amina',
        staffId: 7,
      );

      // The second attempt is refused: the bottle is already back.
      await expectLater(
        DatabaseHelper.instance.recordReturn(
          sale: sale,
          lines: <ReturnLineDraft>[
            ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
          ],
          reason: 'Second time',
          staffName: 'Amina',
          staffId: 7,
        ),
        throwsStateError,
      );
    });

    test('a return of nothing is refused', () async {
      final int productId = await seedProduct();
      final Sale sale = await seedSale(productId: productId);
      await openShift();

      await expectLater(
        DatabaseHelper.instance.recordReturn(
          sale: sale,
          lines: <ReturnLineDraft>[],
          reason: 'Nothing',
          staffName: 'Amina',
          staffId: 7,
        ),
        throwsStateError,
      );
    });

    test('a return must say why', () async {
      final int productId = await seedProduct();
      final Sale sale = await seedSale(productId: productId);
      await openShift();

      await expectLater(
        DatabaseHelper.instance.recordReturn(
          sale: sale,
          lines: <ReturnLineDraft>[
            ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
          ],
          reason: '   ',
          staffName: 'Amina',
          staffId: 7,
        ),
        throwsStateError,
      );
    });
  });

  group('the stock', () {
    test('a restock puts the goods back on the shelf', () async {
      final int productId = await seedProduct(stock: 10);
      final Sale sale = await seedSale(productId: productId, qty: 2);
      await openShift();

      final double afterSale = (await DatabaseHelper.instance.getProducts())
          .firstWhere((Product p) => p.id == productId)
          .stockQty;
      expect(afterSale, 8);

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 2),
        ],
        reason: 'Back on the shelf',
        staffName: 'Amina',
        staffId: 7,
      );

      final double afterReturn = (await DatabaseHelper.instance.getProducts())
          .firstWhere((Product p) => p.id == productId)
          .stockQty;
      expect(afterReturn, 10);
    });

    test('a write-off does not put the goods back', () async {
      final int productId = await seedProduct(stock: 10);
      final Sale sale = await seedSale(productId: productId, qty: 2);
      await openShift();

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(
            saleItemId: sale.items.single.id!,
            qty: 2,
            restock: false,
            restockReason: 'Broken in the box',
          ),
        ],
        reason: 'Damaged',
        staffName: 'Amina',
        staffId: 7,
      );

      final double afterReturn = (await DatabaseHelper.instance.getProducts())
          .firstWhere((Product p) => p.id == productId)
          .stockQty;
      // The shelf is unchanged: broken bottles are not sellable.
      expect(afterReturn, 8);
    });

    test('the ledger says what happened', () async {
      final int productId = await seedProduct(stock: 10);
      final Sale sale = await seedSale(productId: productId, qty: 2);
      await openShift();

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 2),
        ],
        reason: 'Back on the shelf',
        staffName: 'Amina',
        staffId: 7,
      );

      final List<StockMovement> movements =
          await DatabaseHelper.instance.getStockMovements(productId);
      expect(
        movements
            .any((StockMovement m) => m.type == StockMovementType.saleReturn),
        isTrue,
        reason: 'the goods coming back has to be in the ledger, or the count '
            'and the ledger stop agreeing',
      );
    });
  });

  group('the drawer', () {
    test('a cash refund with no drawer open is refused', () async {
      final int productId = await seedProduct();
      final Sale sale = await seedSale(productId: productId, qty: 1);
      // No shift open: there is no drawer to take the money out of.
      await expectLater(
        DatabaseHelper.instance.recordReturn(
          sale: sale,
          lines: <ReturnLineDraft>[
            ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
          ],
          reason: 'Cash back',
          refundMethod: 'cash',
          staffName: 'Amina',
          staffId: 7,
        ),
        throwsStateError,
      );
    });

    test('a cash refund takes the money out of the open drawer', () async {
      final int productId = await seedProduct();
      // The drawer opens FIRST: a sale rung before the drawer was open is not
      // in the drawer's window, and its cash is not in the drawer.
      final int shiftId = await openShift();
      final Sale sale =
          await seedSale(productId: productId, qty: 2, price: 100);

      final Shift shift = (await DatabaseHelper.instance.getShifts(staffId: 7))
          .firstWhere((Shift s) => s.id == shiftId);

      // The drawer should hold the two cash sales.
      final Money before =
          await DatabaseHelper.instance.expectedCashForShift(shift);
      expect(before, Money.fromMajor(200));

      await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
        ],
        reason: 'Cash back',
        refundMethod: 'cash',
        staffName: 'Amina',
        staffId: 7,
      );

      final Money after =
          await DatabaseHelper.instance.expectedCashForShift(shift);
      // The drawer is judged against money that has already gone out of it.
      expect(after, Money.fromMajor(100));
    });

    test('a mobile-money refund needs no drawer', () async {
      final int productId = await seedProduct();
      final Sale sale = await seedSale(
        productId: productId,
        qty: 1,
        paymentMethod: 'mpesa',
      );
      // No shift open, and the refund is not cash: there is no drawer to
      // take money out of.
      final int returnId = await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: <ReturnLineDraft>[
          ReturnLineDraft(saleItemId: sale.items.single.id!, qty: 1),
        ],
        reason: 'Reversed to the phone',
        refundMethod: 'mpesa',
        staffName: 'Amina',
        staffId: 7,
      );
      expect(returnId, greaterThan(0));
    });
  });
}
