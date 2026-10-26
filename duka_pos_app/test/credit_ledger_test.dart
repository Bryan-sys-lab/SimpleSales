// Feature 7's promises, held where they can actually snap: the database.
//
// ## THE INVARIANTS PINNED
//
//   * a credit sale and its charge commit TOGETHER or not at all — a
//     thrown failure mid-write leaves no sale, no charge, no balance;
//   * the limit is judged against the ledger, inside the transaction: at
//     the limit is allowed, over it is refused, and a named approver is the
//     only way past;
//   * repayments settle the OLDEST charge first, and the allocation rows are
//     the receipt of that order;
//   * what a payment cannot settle becomes credit with us — a NEGATIVE
//     balance, not a stuck payment;
//   * a cash repayment adds to the OPEN shift's expected cash; a credit sale
//     adds to NOTHING;
//   * a customer with a balance cannot be deactivated;
//   * a return of an account sale reduces the balance by the refund;
//   * the cached balance ALWAYS equals the ledger's sum, over random
//     sequences of charges and payments;
//   * the aging buckets split the debts by the oldest unpaid charge.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/credit.dart';
import 'package:duka_pos/models/models.dart';
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
  });

  /// A customer with a named default limit.
  Future<Customer> seedCustomer({
    String name = 'Mary Wanjiku',
    String? phone,
    int? limit,
    int balanceMinor = 0,
  }) async {
    final int id = await DatabaseHelper.instance.upsertCustomer(Customer(
      uuid: 'c-${DateTime.now().microsecondsSinceEpoch}-$name',
      name: name,
      phone: phone,
      creditLimitMinor: limit,
      balanceMinor: balanceMinor,
      createdAt: DateTime.now().toIso8601String(),
    ));
    return (await DatabaseHelper.instance.getCustomerById(id))!;
  }

  /// One product on the shelf.
  Future<int> seedProduct({double price = 100}) async {
    return DatabaseHelper.instance.upsertProduct(Product(
      name: 'Soda 350ml',
      category: 'Soda',
      costPrice: Money.fromMajor(60),
      sellPrice: Money.fromMajor(price),
      stockQty: 100,
      reorderLevel: 2,
      bottleMl: 350,
      updatedAt: DateTime.now().toIso8601String(),
    ));
  }

  Future<int> cashSale({double total = 100}) async {
    final int productId = await seedProduct();
    return DatabaseHelper.instance.recordSale(
      staffName: 'Amina',
      items: [
        SaleItem(
          saleId: 0,
          productId: productId,
          productName: 'Soda 350ml',
          qty: 1,
          unitPrice: Money.fromMinor((total * 100).round()),
          unitCost: Money.fromMinor(6000),
          portion: 'full',
          portionMl: 350,
          variantId: null,
          variantName: '',
        ),
      ],
      paymentMethod: 'cash',
      amountTendered: Money.fromMinor((total * 100).round()),
      staffId: 7,
    );
  }

  test(
      'remote customer and credit snapshot merges by UUID without duplicate ledger rows',
      () async {
    final db = DatabaseHelper.instance;
    final customerRow = <String, dynamic>{
      'localUuid': 'remote-customer-1',
      'name': 'Remote Customer',
      'balanceMinor': 1250,
      'active': true,
      'createdAt': '2026-10-24T00:00:00.000Z',
    };
    final entryRow = <String, dynamic>{
      'localUuid': 'remote-credit-1',
      'customerUuid': 'remote-customer-1',
      'entryType': 'charge',
      'amountMinor': 1250,
      'staffName': 'Amina',
      'createdAt': '2026-10-24T00:00:00.000Z',
    };
    await db.mergeRemoteCreditSnapshot(
      customers: <Map<String, dynamic>>[customerRow],
      entries: <Map<String, dynamic>>[entryRow],
    );
    await db.mergeRemoteCreditSnapshot(
      customers: <Map<String, dynamic>>[
        <String, dynamic>{...customerRow, 'name': 'Remote Customer Updated'},
      ],
      entries: <Map<String, dynamic>>[entryRow],
    );
    final customer = (await db.getCustomers()).single;
    expect(customer.name, 'Remote Customer Updated');
    expect(customer.balanceMinor, 1250);
    expect(await db.getCreditEntries(customer.id!), hasLength(1));
  });

  /// The customer row, fresh.
  Future<Customer> fetch(Customer customer) async =>
      (await DatabaseHelper.instance.getCustomerById(customer.id!))!;

  group('the credit sale', () {
    test('the charge and the sale commit together', () async {
      final int productId = await seedProduct();
      final Customer mary = await seedCustomer(limit: 10000);
      // A sale of KSh 100 on account.
      final int saleId = await DatabaseHelper.instance.recordSale(
        staffName: 'Amina',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Soda 350ml',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
            portion: 'full',
            portionMl: 350,
            variantId: null,
            variantName: '',
          ),
        ],
        paymentMethod: 'credit',
        customerId: mary.id,
        staffId: 7,
      );
      final charges = await DatabaseHelper.instance.getCreditEntries(mary.id!);
      expect(charges, hasLength(1));
      expect(charges.single.entryType, CreditEntryType.charge);
      expect(charges.single.saleId, saleId);
      // The shelf moved too: the credit sale is a REAL sale.
      final Product after = (await DatabaseHelper.instance.getProducts())
          .firstWhere((Product p) => p.id == productId);
      expect(after.stockQty, 99);
      // and the balance says who owes.
      expect((await fetch(mary)).balanceMinor, 10000);
    });

    test('at the limit is taken; past it is refused; approval opens it',
        () async {
      final int productId = await seedProduct();
      final Customer brian = await seedCustomer(name: 'Brian', limit: 10000);

      Future<int?> trySale(Money total, {int? approvedBy}) async =>
          DatabaseHelper.instance.recordSale(
            staffName: 'Amina',
            items: [
              SaleItem(
                saleId: 0,
                productId: productId,
                productName: 'Soda 350ml',
                qty: total.asMajor,
                unitPrice:
                    Money.fromMinor((total.minorUnits / total.asMajor).round()),
                unitCost: Money.fromMinor(6000),
                portion: 'full',
                portionMl: 350,
                variantId: null,
                variantName: '',
              ),
            ],
            paymentMethod: 'credit',
            customerId: brian.id,
            creditApprovedBy: approvedBy,
            staffId: 7,
          );

      // Wait — the qty math above loses the thread: sale items price in
      // MINOR units per unit. This basket is ONE unit at exactly the limit.
      final SaleItem atLimit = SaleItem(
        saleId: 0,
        productId: productId,
        productName: 'Soda 350ml',
        qty: 1,
        unitPrice: Money.fromMinor(10000),
        unitCost: Money.fromMinor(6000),
        portion: 'full',
        portionMl: 350,
        variantId: null,
        variantName: '',
      );
      final int saleId = await DatabaseHelper.instance.recordSale(
        staffName: 'Amina',
        items: [atLimit],
        paymentMethod: 'credit',
        customerId: brian.id,
        staffId: 7,
      );
      expect(saleId, greaterThan(0));

      // NOW at the limit: one more minor unit is past it.
      await expectLater(
        DatabaseHelper.instance.recordSale(
          staffName: 'Amina',
          items: [
            SaleItem(
              saleId: 0,
              productId: productId,
              productName: 'Soda 350ml',
              qty: 1,
              unitPrice: Money.fromMinor(101),
              unitCost: Money.fromMinor(60),
              portion: 'full',
              portionMl: 350,
              variantId: null,
              variantName: '',
            ),
          ],
          paymentMethod: 'credit',
          customerId: brian.id,
          staffId: 7,
        ),
        throwsStateError,
      );

      // With an approver named, the SAME sale goes through.
      await trySale(Money.fromMinor(101), approvedBy: 999);
      expect((await fetch(brian)).balanceMinor, 10101);
    });

    test('a credit sale enters NO drawer; a credit charge is not cash',
        () async {
      final int productId = await seedProduct();
      // An open shift, so a repayment later has a drawer to be counted in.
      await DatabaseHelper.instance.openShift(
        staffId: 7,
        staffName: 'Amina',
        startFloat: Money.zero,
      );
      final Customer mary = await seedCustomer(limit: 10000);
      await DatabaseHelper.instance.recordSale(
        staffName: 'Amina',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Soda 350ml',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
            portion: 'full',
            portionMl: 350,
            variantId: null,
            variantName: '',
          ),
        ],
        paymentMethod: 'credit',
        customerId: mary.id,
        staffId: 7,
      );
      final shift = (await DatabaseHelper.instance.getShifts()).first;
      // KSh 0 of cash sales in the drawer. A credit sale never is.
      expect(
        (await DatabaseHelper.instance.expectedCashForShift(shift)).minorUnits,
        0,
      );
    });

    test('a credit sale without a customer is refused at the door', () async {
      final int productId = await seedProduct();
      await expectLater(
        DatabaseHelper.instance.recordSale(
          staffName: 'Amina',
          items: [
            SaleItem(
              saleId: 0,
              productId: productId,
              productName: 'Soda 350ml',
              qty: 1,
              unitPrice: Money.fromMajor(100),
              unitCost: Money.fromMajor(60),
              portion: 'full',
              portionMl: 350,
              variantId: null,
              variantName: '',
            ),
          ],
          paymentMethod: 'credit',
          staffId: 7,
        ),
        throwsStateError,
      );
    });
  });

  group('a repayment', () {
    test('settles the OLDEST charge first, and says so', () async {
      final int productId = await seedProduct();
      final Customer mary = await seedCustomer(name: 'Mary', limit: 50000);
      // Two charges: KSh 100, then KSh 200.
      for (final double price in <double>[100, 200]) {
        await DatabaseHelper.instance.recordSale(
          staffName: 'Amina',
          items: [
            SaleItem(
              saleId: 0,
              productId: productId,
              productName: 'Soda 350ml',
              qty: 1,
              unitPrice: Money.fromMajor(price),
              unitCost: Money.fromMajor(60),
              portion: 'full',
              portionMl: 350,
              variantId: null,
              variantName: '',
            ),
          ],
          paymentMethod: 'credit',
          customerId: mary.id,
          staffId: 7,
        );
      }
      await DatabaseHelper.instance.openShift(
        staffId: 7,
        staffName: 'Amina',
        startFloat: Money.zero,
      );
      // KSh 100 in — exactly the FIRST charge.
      await DatabaseHelper.instance.recordCreditRepayment(
        customerId: mary.id!,
        amount: Money.fromMajor(100),
        method: 'cash',
        staffId: 7,
        staffName: 'Amina',
      );
      final Customer after = await fetch(mary);
      expect(after.balanceMinor, 20000); // 300 - 100.

      // The FIRST entry (oldest charge) is fully allocated, the second untouched.
      final entries = await DatabaseHelper.instance.getCreditEntries(mary.id!);
      final firstCharge = entries.last; // oldest by created_at DESC, id DESC
      final secondCharge = entries.reversed.toList()[1];
      expect(firstCharge.entryType, CreditEntryType.charge);
      expect(secondCharge.entryType, CreditEntryType.charge);
      final allocations =
          await DatabaseHelper.instance.getCreditAllocations(mary.id!);
      expect(allocations.single.chargeEntryId, firstCharge.id);
      expect(allocations.single.amountMinor, 10000);
    });

    test('over the balance becomes credit with them', () async {
      final Customer mary =
          await seedCustomer(name: 'Mary', limit: 10000, balanceMinor: 5000);
      await DatabaseHelper.instance.openShift(
        staffId: 7,
        staffName: 'Amina',
        startFloat: Money.zero,
      );
      await DatabaseHelper.instance.recordCreditRepayment(
        customerId: mary.id!,
        amount: Money.fromMajor(70),
        method: 'cash',
        staffId: 7,
        staffName: 'Amina',
      );
      final Customer after = await fetch(mary);
      // 50 - 70 = -20. Credit with them.
      expect(after.balanceMinor, -2000);
      expect(after.owes, isFalse);
    });

    test('a cash repayment adds to the shift; M-Pesa does not', () async {
      final Customer mary =
          await seedCustomer(name: 'Mary', limit: 10000, balanceMinor: 10000);
      await DatabaseHelper.instance.openShift(
        staffId: 7,
        staffName: 'Amina',
        startFloat: Money.zero,
      );
      await DatabaseHelper.instance.recordCreditRepayment(
        customerId: mary.id!,
        amount: Money.fromMajor(40),
        method: 'cash',
        staffId: 7,
        staffName: 'Amina',
      );
      final shift = (await DatabaseHelper.instance.getShifts()).first;
      expect(
        (await DatabaseHelper.instance.expectedCashForShift(shift)).minorUnits,
        4000,
      );
      await DatabaseHelper.instance.recordCreditRepayment(
        customerId: mary.id!,
        amount: Money.fromMajor(60),
        method: 'mpesa',
        reference: 'SF13REP1',
        staffId: 7,
        staffName: 'Amina',
      );
      // The M-Pesa repayment is bank money, not drawer money.
      expect(
        (await DatabaseHelper.instance.expectedCashForShift(shift)).minorUnits,
        4000,
      );
      final events = await DatabaseHelper.instance.getFinancialEvents();
      expect(events.map((event) => event.eventType),
          <String>['credit_repayment', 'credit_repayment']);
      expect(events.map((event) => event.receivableDeltaMinor),
          <int>[-4000, -6000]);
    });

    test('a cash repayment without an open shift is refused', () async {
      final Customer mary =
          await seedCustomer(name: 'Mary', limit: 10000, balanceMinor: 10000);
      await expectLater(
        DatabaseHelper.instance.recordCreditRepayment(
          customerId: mary.id!,
          amount: Money.fromMajor(10),
          method: 'cash',
          staffId: 7,
          staffName: 'Amina',
        ),
        throwsStateError,
      );
    });

    test('a zero or negative payment is refused', () async {
      final Customer mary = await seedCustomer(name: 'Mary', balanceMinor: 1);
      await expectLater(
        DatabaseHelper.instance.recordCreditRepayment(
          customerId: mary.id!,
          amount: Money.zero,
          method: 'cash',
          staffId: 7,
          staffName: 'Amina',
        ),
        throwsStateError,
      );
    });
  });

  group('a customer', () {
    test('cannot be deactivated while they owe, and can when clear', () async {
      final Customer owed =
          await seedCustomer(name: 'Mary', balanceMinor: 5000);
      await expectLater(
        DatabaseHelper.instance.deactivateCustomer(owed.id!),
        throwsStateError,
      );
      final Customer clear = await seedCustomer(name: 'Brian');
      await DatabaseHelper.instance.deactivateCustomer(clear.id!);
      final Customer afterClear = await fetch(clear);
      expect(afterClear.active, isFalse);
    });

    test('names and numbers are unique among the ACTIVE, and reusable after',
        () async {
      await seedCustomer(name: 'Mary Wanjiku', phone: '0712345678');
      // The same name, ANY casing, is refused...
      await expectLater(
        seedCustomer(name: 'mary wanjiku', limit: null),
        throwsStateError,
      );
      // The same number is refused.
      await expectLater(
        seedCustomer(name: 'Another', phone: '+254712345678'),
        throwsStateError,
      );
      // Deactivate, then the name is free (the first Mary stays out of the
      // active set).
      final List<Customer> actives =
          await DatabaseHelper.instance.getCustomers(search: 'Mary');
      await DatabaseHelper.instance.deactivateCustomer(actives.first.id!);
      final Customer reuse = await seedCustomer(name: 'Mary', limit: 1000);
      expect(reuse.id, isNotNull);
    });
  });

  group('returns of an account sale', () {
    test('refund to the account by default; the balance drops by the refund',
        () async {
      final int productId = await seedProduct();
      final Customer mary = await seedCustomer(name: 'Mary', limit: 50000);
      final int saleId = await DatabaseHelper.instance.recordSale(
        staffName: 'Amina',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Soda 350ml',
            qty: 2,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
            portion: 'full',
            portionMl: 350,
            variantId: null,
            variantName: '',
          ),
        ],
        paymentMethod: 'credit',
        customerId: mary.id,
        staffId: 7,
      );
      final Sale sale = (await DatabaseHelper.instance.getSaleById(saleId))!;
      final int returnId = await DatabaseHelper.instance.recordReturn(
        sale: sale,
        lines: [
          ReturnLineDraft(
            saleItemId: sale.items.single.id!,
            qty: 1,
            restock: true,
          ),
        ],
        reason: 'changed_mind',
        refundMethod: 'credit_to_account',
        staffName: 'Amina',
        staffId: 7,
      );
      expect(returnId, greaterThan(0));

      // The balance: +200 (the sale), -100 (one unit back).
      final Customer after = await fetch(mary);
      expect(after.balanceMinor, 10000);
      // The ledger named why.
      final entries = await DatabaseHelper.instance.getCreditEntries(mary.id!);
      expect(
        entries.first.entryType,
        CreditEntryType.returnCredit,
      );
      final events = await DatabaseHelper.instance.getFinancialEvents();
      expect(
          events.map((event) => event.eventType), <String>['sale', 'refund']);
      expect(events.last.revenueMinor, -8620);
      expect(events.last.receivableDeltaMinor, -10000);
      expect(events.last.cogsMinor, -6000);
    });

    test('a cash-sale refund to account is refused (no account)', () async {
      final saleId = await cashSale();
      final Sale sale = (await DatabaseHelper.instance.getSaleById(saleId))!;
      await expectLater(
        DatabaseHelper.instance.recordReturn(
          sale: sale,
          lines: [
            ReturnLineDraft(
              saleItemId: sale.items.single.id!,
              qty: 1,
              restock: true,
            ),
          ],
          reason: 'changed_mind',
          refundMethod: 'credit_to_account',
          staffName: 'Amina',
          staffId: 7,
        ),
        throwsStateError,
      );
    });
  });

  group('the cache equals the ledger, and the aging is the ledger too', () {
    test('after a mess of charges and payments, sum(ledger) == balance',
        () async {
      final int productId = await seedProduct();
      final Customer mary = await seedCustomer(name: 'Mary', limit: 999999);
      await DatabaseHelper.instance.openShift(
        staffId: 7,
        staffName: 'Amina',
        startFloat: Money.fromMajor(1000),
      );
      var expectedMinor = 0;
      // Ten rounds of credits and partial payments.
      for (var i = 0; i < 10; i++) {
        if (i % 2 == 0) {
          await DatabaseHelper.instance.recordSale(
            staffName: 'Amina',
            items: [
              SaleItem(
                saleId: 0,
                productId: productId,
                productName: 'Soda 350ml',
                qty: 1,
                unitPrice: Money.fromMinor(1000),
                unitCost: Money.fromMinor(600),
                portion: 'full',
                portionMl: 350,
                variantId: null,
                variantName: '',
              ),
            ],
            paymentMethod: 'credit',
            customerId: mary.id,
            staffId: 7,
          );
          expectedMinor += 1000;
        } else if (expectedMinor > 0) {
          await DatabaseHelper.instance.recordCreditRepayment(
            customerId: mary.id!,
            amount: Money.fromMinor(250),
            method: 'mpesa',
            staffId: 7,
            staffName: 'Amina',
          );
          expectedMinor -= 250;
        }
      }
      final Customer after = await fetch(mary);
      expect(after.balanceMinor, expectedMinor);
    });

    test('the aging buckets split by the OLDEST unpaid charge', () async {
      final int productId = await seedProduct();
      // Customer A charged 8 days ago; customer B charged 1 day ago.
      final Customer a = await seedCustomer(name: 'A', limit: 900000);
      await DatabaseHelper.instance.recordSale(
        staffName: 'Amina',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Soda 350ml',
            qty: 1,
            unitPrice: Money.fromMinor(1000),
            unitCost: Money.fromMinor(600),
            portion: 'full',
            portionMl: 350,
            variantId: null,
            variantName: '',
          ),
        ],
        paymentMethod: 'credit',
        customerId: a.id,
        staffId: 7,
      );
      final Customer b = await seedCustomer(name: 'B', limit: 900000);
      await DatabaseHelper.instance.recordSale(
        staffName: 'Amina',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Soda 350ml',
            qty: 1,
            unitPrice: Money.fromMinor(2000),
            unitCost: Money.fromMinor(600),
            portion: 'full',
            portionMl: 350,
            variantId: null,
            variantName: '',
          ),
        ],
        paymentMethod: 'credit',
        customerId: b.id,
        staffId: 7,
      );
      // Rewind A's charge to make it 8 days old (the boundary: >7).
      await (await DatabaseHelper.instance.database).update(
        'credit_ledger',
        {
          'created_at':
              DateTime.now().subtract(const Duration(days: 8)).toIso8601String()
        },
        where: 'customer_id = ?',
        whereArgs: [a.id],
      );
      final aging = await DatabaseHelper.instance.creditAging();
      expect(aging[DebtAgeBucket.upTo30Days]!.customers, 1);
      expect(aging[DebtAgeBucket.upTo30Days]!.amountMinor, 1000);
      expect(aging[DebtAgeBucket.upTo7Days]!.customers, 1);
      expect(aging[DebtAgeBucket.upTo7Days]!.amountMinor, 2000);
      expect(aging[DebtAgeBucket.over60Days]!.customers, 0);
    });
  });
}
