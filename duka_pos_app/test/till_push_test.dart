// What the till pushes to the server, and what it does not push twice.
//
// ## WHAT WENT WRONG
//
// "For every added feature in the app make sure the backend is updated too."
//
// The backend had no way to learn about the till's own records. The only
// sales that ever reached it were the M-Pesa ones, written by the payment
// callback — so CASH SALES, which are most of a shop's sales, never left the
// phone. The owner's account, the reports and the all-shops view were reading
// a ledger with holes in it.
//
// ## THE RULE
//
// A phone that was offline pushes the same records again the next time it is
// online — that is the whole mechanism. So the app has to know which records
// the server already has, and the server has to be able to tell a re-push
// from a new one.
//
// The app's half is a flag on the row: a record is marked pushed only when
// the server has CONFIRMED it. A record the server did not accept is still
// pending, and the next push tries it again — which is the whole point of
// keeping the flag on the row rather than deleting the record.
//
// The server's half is the till's own id for the record, unique within a
// shop. Both halves are pinned here.

import 'package:duka_pos/db/database_helper.dart';
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
  });

  /// A product with stock on the shelf.
  ///
  /// A sale needs one: the till checks the stock before it records, and a
  /// sale of something that was never on the shelf is not a sale.
  Future<int> seedProduct() async {
    final int id = await DatabaseHelper.instance.upsertProduct(Product(
      name: 'Tusker',
      category: 'Beer',
      costPrice: Money.fromMajor(50),
      sellPrice: Money.fromMajor(100),
      stockQty: 50,
      reorderLevel: 5,
      bottleMl: 500,
      updatedAt: DateTime.now().toIso8601String(),
    ));
    expect(id, greaterThan(0));
    return id;
  }

  /// A sale in the ledger.
  Future<int> seedSale({
    required double total,
    required String paymentMethod,
    String staffName = 'Amina',
  }) async {
    final DatabaseHelper db = DatabaseHelper.instance;
    await seedProduct();
    final int saleId = await db.recordSale(
      staffName: staffName,
      staffId: 1,
      paymentMethod: paymentMethod,
      items: <SaleItem>[
        SaleItem(
          saleId: 0,
          productId: 1,
          productName: 'Tusker',
          qty: 1,
          unitPrice: Money.fromMajor(total),
          unitCost: Money.fromMajor(total / 2),
        ),
      ],
    );
    expect(saleId, greaterThan(0));
    return saleId;
  }

  group('the ledger', () {
    test('a new sale is pending', () async {
      final int id = await seedSale(total: 100, paymentMethod: 'cash');
      final List<Sale> pending =
          await DatabaseHelper.instance.getUnsyncedSales();
      expect(pending.map((Sale s) => s.id), contains(id));
    });

    test('a confirmed sale is not pushed again', () async {
      final int first = await seedSale(total: 100, paymentMethod: 'cash');
      final int second = await seedSale(total: 200, paymentMethod: 'cash');

      // The server confirmed only the first — the second failed, so it stays
      // pending and is tried again next time.
      await DatabaseHelper.instance.markSalesSynced(<int>[first]);

      final List<Sale> pending =
          await DatabaseHelper.instance.getUnsyncedSales();
      expect(pending.map((Sale s) => s.id), <int?>[second]);
      expect(pending.map((Sale s) => s.id), isNot(contains(first)));
    });

    test('the pending sales come out oldest first', () async {
      await seedSale(total: 100, paymentMethod: 'cash');
      await seedSale(total: 200, paymentMethod: 'mpesa');

      final List<Sale> pending =
          await DatabaseHelper.instance.getUnsyncedSales();
      expect(pending.length, 2);
      // The ledger is a story, and a story read from the end is not a story.
      expect(pending.first.total, Money.fromMajor(100));
      expect(pending.last.total, Money.fromMajor(200));
    });

    test('a pushed sale carries its lines', () async {
      await seedSale(total: 100, paymentMethod: 'cash');
      final List<Sale> pending =
          await DatabaseHelper.instance.getUnsyncedSales();
      expect(pending.single.items, isNotEmpty);
      expect(pending.single.items.single.productName, 'Tusker');
      expect(pending.single.items.single.unitPrice, Money.fromMajor(100));
    });

    test('a cash sale and an M-Pesa sale are both pushed', () async {
      // The whole point: CASH SALES were the ones that never left the phone.
      await seedSale(total: 100, paymentMethod: 'cash');
      await seedSale(total: 250, paymentMethod: 'mpesa');
      final List<Sale> pending =
          await DatabaseHelper.instance.getUnsyncedSales();
      expect(pending.length, 2);
      expect(
        pending.map((Sale s) => s.paymentMethod).toSet(),
        <String>{'cash', 'mpesa'},
      );
    });
  });

  group('the drawers', () {
    test('a shift carries the cash it was counted at', () async {
      final DatabaseHelper db = DatabaseHelper.instance;
      final int shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Amina',
        startFloat: Money.fromMajor(1000),
      );
      await db.reconcileShift(
        shiftId: shiftId,
        countedCash: Money.fromMajor(950),
        expectedCash: Money.fromMajor(1000),
      );

      final List<Map<String, dynamic>> pending = await db.getUnsyncedShifts();
      expect(pending, hasLength(1));
      expect(pending.single['id'], shiftId);
      expect(pending.single['expected_cash'], 100000);
      expect(pending.single['counted_cash'], 95000);
    });

    test('a confirmed shift is not pushed again', () async {
      final DatabaseHelper db = DatabaseHelper.instance;
      final int shiftId = await db.openShift(
        staffId: 1,
        staffName: 'Amina',
        startFloat: Money.fromMajor(1000),
      );
      await db.markShiftsSynced(<int>[shiftId]);
      expect(await db.getUnsyncedShifts(), isEmpty);
    });
  });

  group('the shot cups', () {
    test('a new cup is pending, and a confirmed one is not', () async {
      final DatabaseHelper db = DatabaseHelper.instance;
      final int productId = await seedProduct();
      final int id = await db.upsertShotCup(ShotCup(
        productId: productId,
        productName: 'Tusker',
        capacityMl: 30,
        price: Money.fromMajor(50),
        label: 'Single',
        updatedAt: DateTime.now().toIso8601String(),
      ));
      expect(id, greaterThan(0));

      final List<ShotCup> pending = await db.getUnsyncedShotCups();
      expect(pending.map((ShotCup c) => c.id), contains(id));

      await db.markShotCupsSynced(<int>[id]);
      expect(await db.getUnsyncedShotCups(), isEmpty);
    });

    test('a cup with no size is a legal cup', () async {
      // The size is optional: a cup with a size earns its cost exactly, and a
      // cup without one is counted at its full price.
      final DatabaseHelper db = DatabaseHelper.instance;
      final int productId = await seedProduct();
      final int id = await db.upsertShotCup(ShotCup(
        productId: productId,
        productName: 'Tusker',
        capacityMl: 0,
        price: Money.fromMajor(50),
        label: 'One shot',
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final List<ShotCup> pending = await db.getUnsyncedShotCups();
      final ShotCup cup = pending.firstWhere((ShotCup c) => c.id == id);
      expect(cup.capacityMl, 0);
    });
  });
}
