import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/analytics.dart';
import 'package:duka_pos/utils/money.dart';

/// The aggregate queries behind the dashboard and the analytics screen.
///
/// These exist because the old dashboard folded a `List<Sale>` in Dart, which
/// meant the boundary between "SQL returned rows" and "SQL reduced them" was
/// nowhere, and so neither the exactness of the money nor the scoping of the
/// figures had anything holding them in place. Every test below pins one of
/// those two properties down.
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

  // ---- Fixtures ------------------------------------------------------------

  Future<int> addProduct({
    required String name,
    int costMinor = 1000,
    int priceMinor = 1500,
    double stock = 50,
    int reorder = 5,
    bool active = true,
  }) async {
    return db.upsertProduct(Product(
      id: null,
      name: name,
      category: 'General',
      costPrice: Money.fromMinor(costMinor),
      sellPrice: Money.fromMinor(priceMinor),
      stockQty: stock,
      reorderLevel: reorder,
      updatedAt: DateTime.now().toIso8601String(),
      active: active,
    ));
  }

  Future<int> addStaff(String name, {String role = 'cashier'}) => db.addStaff(
        Staff(id: null, name: name, pinHash: 'hash', role: role),
      );

  /// Writes a sale directly.
  ///
  /// Not through [DatabaseHelper.recordSale]: that stamps `created_at` with
  /// `DateTime.now()`, and a range-boundary test has to place sales on exact
  /// instants — the day boundary, the end of the window — which the checkout
  /// path gives no way to do.
  Future<int> writeSale({
    required String staffName,
    int? staffId,
    required int totalMinor,
    int? profitMinor,
    required DateTime at,
    String paymentMethod = 'cash',
    bool paymentVerified = true,
    String etimsStatus = EtimsStatus.notRequired,
  }) async {
    final saleId = await (await db.database).insert('sales', {
      'staff_name': staffName,
      'staff_id': staffId,
      'total': totalMinor,
      'profit': profitMinor ?? (totalMinor ~/ 5),
      'payment_method': paymentMethod,
      'created_at': at.toIso8601String(),
      'etims_status': etimsStatus,
      'payment_verified': paymentVerified ? 1 : 0,
    });
    return saleId;
  }

  Future<void> writeSaleItem({
    required int saleId,
    required int productId,
    required String productName,
    required double qty,
    required int unitPriceMinor,
    required int unitCostMinor,
  }) async {
    await (await db.database).insert('sale_items', {
      'sale_id': saleId,
      'product_id': productId,
      'product_name': productName,
      'qty': qty,
      'unit_price': unitPriceMinor,
      'unit_cost': unitCostMinor,
    });
  }

  final today = DateTime.now();
  final midnight = DateTime(today.year, today.month, today.day);

  // ---- salesTotalsFor ------------------------------------------------------

  group('salesTotalsFor', () {
    test('sums totals, profit and receipts across the range', () async {
      await writeSale(
          staffName: 'Amina',
          totalMinor: 1500,
          profitMinor: 500,
          at: midnight.add(const Duration(hours: 9)));
      await writeSale(
          staffName: 'Amina',
          totalMinor: 2500,
          profitMinor: 1000,
          at: midnight.add(const Duration(hours: 11)));
      await writeSale(
          staffName: 'Amina',
          totalMinor: 1000,
          profitMinor: 200,
          at: midnight.add(const Duration(hours: 14)));

      final totals = await db.salesTotalsFor(since: midnight, staffId: null);

      expect(totals.transactions, 3);
      expect(totals.totalMinor, 5000);
      expect(totals.profitMinor, 1700);
      expect(totals.averageMinor, 1667); // 5000 / 3 = 1666.67, rounded half up
      expect(totals.hasSales, isTrue);
      expect(totals.total, Money.fromMinor(5000));
    });

    test('returns integer minor units, never a float', () async {
      // The exactness rule from utils/money.dart, asserted at the SQL
      // boundary: a `double` here would make the dashboard's figure drift from
      // the sum of the receipts behind it. `isA<int>()` rather than a value
      // check, because 5000.0 == 5000 in Dart and would pass one.
      await writeSale(
          staffName: 'Amina',
          totalMinor: 3333,
          profitMinor: 1111,
          at: midnight.add(const Duration(hours: 8)));
      await writeSale(
          staffName: 'Amina',
          totalMinor: 6667,
          profitMinor: 2222,
          at: midnight.add(const Duration(hours: 9)));

      final totals = await db.salesTotalsFor(since: midnight);

      expect(totals.totalMinor, isA<int>());
      expect(totals.profitMinor, isA<int>());
      expect(totals.averageMinor, isA<int>());
      expect(totals.transactions, isA<int>());
      expect(totals.totalMinor, 10000);
      // 10000 / 2 = 5000 exactly; the point is the *type*, not the figure.
      expect(totals.averageMinor, isA<int>());
      expect(totals.total.asMajor, isA<double>());
      expect(totals.total.asMajor, 100.0);
    });

    test('an empty range reads as zero rather than null', () async {
      final totals = await db.salesTotalsFor(since: midnight);

      expect(totals.transactions, 0);
      expect(totals.totalMinor, 0);
      expect(totals.profitMinor, 0);
      expect(totals.averageMinor, 0);
      expect(totals.hasSales, isFalse);
      expect(DailyTotals.empty.total, Money.zero);
    });

    test('a range boundary is inclusive at the start', () async {
      await writeSale(
          staffName: 'Amina',
          totalMinor: 1000,
          at: midnight.add(const Duration(hours: 8)));

      // The start instant itself must be inside the window: the till opens at
      // midnight and a sale recorded one second later is still "today".
      final totals = await db.salesTotalsFor(since: midnight);

      expect(totals.transactions, 1);
      expect(totals.totalMinor, 1000);
    });

    test('excludes sales before the start of the window', () async {
      await writeSale(
          staffName: 'Amina',
          totalMinor: 1000,
          at: midnight.subtract(const Duration(seconds: 1)));
      await writeSale(
          staffName: 'Amina',
          totalMinor: 2000,
          at: midnight.add(const Duration(seconds: 1)));

      final totals = await db.salesTotalsFor(since: midnight);

      expect(totals.transactions, 1);
      expect(totals.totalMinor, 2000);
    });

    test('the end of a window is exclusive, so a boundary sale counts once',
        () async {
      // 09:00 on the second day belongs to the second day. Counting it in
      // both days would make the two ranges disagree by exactly one receipt.
      final secondDay = midnight.add(const Duration(days: 1));
      await writeSale(
          staffName: 'Amina',
          totalMinor: 4000,
          at: secondDay.add(const Duration(hours: 9)));

      final first = await db.salesTotalsFor(since: midnight, until: secondDay);
      final second = await db.salesTotalsFor(
          since: secondDay, until: secondDay.add(const Duration(days: 1)));

      expect(first.transactions, 0);
      expect(second.transactions, 1);
      expect(second.totalMinor, 4000);
    });
  });

  // ---- staffId scoping -----------------------------------------------------

  group('staffId scoping', () {
    test('excludes other cashiers from totals', () async {
      final amina = await addStaff('Amina');
      final joseph = await addStaff('Joseph');
      await writeSale(
          staffName: 'Amina',
          staffId: amina,
          totalMinor: 1500,
          at: midnight.add(const Duration(hours: 9)));
      await writeSale(
          staffName: 'Joseph',
          staffId: joseph,
          totalMinor: 9000,
          at: midnight.add(const Duration(hours: 9)));
      await writeSale(
          staffName: 'Joseph',
          staffId: joseph,
          totalMinor: 9000,
          at: midnight.add(const Duration(hours: 10)));

      final mine = await db.salesTotalsFor(since: midnight, staffId: amina);
      final theirs = await db.salesTotalsFor(since: midnight, staffId: joseph);
      final shop = await db.salesTotalsFor(since: midnight);

      expect(mine.transactions, 1);
      expect(mine.totalMinor, 1500);
      expect(theirs.totalMinor, 18000);
      // The shop figure is still the sum of both, which is what a manager sees.
      expect(shop.totalMinor, 19500);
    });

    test('scoping by staff_id keeps a renamed cashier separate', () async {
      // Removing a cashier rewrites their ledger rows to 'Deleted cashier'.
      // A name-based filter would therefore merge every cashier the shop has
      // ever employed into one bucket — the failure staff_id cannot have.
      final amina = await addStaff('Amina');
      final joseph = await addStaff('Joseph');
      await writeSale(
          staffName: 'Amina', staffId: amina, totalMinor: 1500, at: midnight);
      await writeSale(
          staffName: 'Joseph', staffId: joseph, totalMinor: 2500, at: midnight);

      final removed = await db.getStaff(activeOnly: false);
      await db.deleteStaffWithTombstone(
          removed.firstWhere((s) => s.name == 'Amina'));

      final exAmina = await db.salesTotalsFor(since: midnight, staffId: amina);
      final josephs = await db.salesTotalsFor(since: midnight, staffId: joseph);

      expect(exAmina.totalMinor, 1500);
      expect(josephs.totalMinor, 2500);
    });

    test('resolves a cashier name to exactly one staff id', () async {
      final staff = [
        Staff(id: 7, name: 'Amina', pinHash: 'x'),
        Staff(id: 8, name: 'Joseph', pinHash: 'x'),
      ];
      expect(staffIdForCashier(staff, 'Amina'), 7);
      expect(staffIdForCashier(staff, 'Nobody'), isNull);
      expect(staffIdForCashier(staff, null), isNull);
      expect(staffIdForCashier(staff, '  '), isNull);
      // An ambiguous name resolves to nothing rather than to an arbitrary
      // person: over-reporting someone else's takings is worse than showing
      // none.
      expect(
          staffIdForCashier([
            Staff(id: 1, name: 'Amina', pinHash: 'x'),
            Staff(id: 2, name: 'Amina', pinHash: 'x'),
          ], 'Amina'),
          isNull);
    });
  });

  // ---- topProducts ---------------------------------------------------------

  group('topProducts', () {
    test('groups by product with units, revenue and profit', () async {
      final soda = await addProduct(name: 'Soda 350ml');
      final water = await addProduct(name: 'Water 500ml');
      final first =
          await writeSale(staffName: 'Amina', totalMinor: 3000, at: midnight);
      final second =
          await writeSale(staffName: 'Amina', totalMinor: 2000, at: midnight);

      await writeSaleItem(
          saleId: first,
          productId: soda,
          productName: 'Soda 350ml',
          qty: 2,
          unitPriceMinor: 1500,
          unitCostMinor: 1000);
      await writeSaleItem(
          saleId: second,
          productId: soda,
          productName: 'Soda 350ml',
          qty: 1,
          unitPriceMinor: 1500,
          unitCostMinor: 1000);
      await writeSaleItem(
          saleId: second,
          productId: water,
          productName: 'Water 500ml',
          qty: 1,
          unitPriceMinor: 2000,
          unitCostMinor: 1200);

      final rows = await db.topProducts(
        since: midnight,
        until: midnight.add(const Duration(days: 1)),
      );

      expect(rows.length, 2);
      // Ranked by revenue, so the two sodas (KSh 45) outrank the water (KSh 20).
      expect(rows.first.productId, soda);
      expect(rows.first.productName, 'Soda 350ml');
      expect(rows.first.units, 3.0);
      expect(rows.first.revenueMinor, 4500);
      expect(rows.first.profitMinor, 1500); // (1500 - 1000) * 3
      expect(rows.first.marginPct, closeTo(33.33, 0.01));

      final waterRow = rows.firstWhere((r) => r.productId == water);
      expect(waterRow.revenueMinor, 2000);
      expect(waterRow.profitMinor, 800);
    });

    test('money comes back as int minor units', () async {
      final soda = await addProduct(name: 'Soda 350ml');
      final sale =
          await writeSale(staffName: 'Amina', totalMinor: 1011, at: midnight);
      await writeSaleItem(
          saleId: sale,
          productId: soda,
          productName: 'Soda 350ml',
          qty: 1,
          unitPriceMinor: 1011,
          unitCostMinor: 707);

      final row = (await db.topProducts(since: midnight)).single;

      expect(row.revenueMinor, isA<int>());
      expect(row.profitMinor, isA<int>());
      expect(row.revenueMinor, 1011);
      expect(row.profitMinor, 304);
      // `units` is a quantity, not an amount: it is legitimately a double.
      expect(row.units, isA<double>());
    });

    test('honours the staff filter through the join', () async {
      final soda = await addProduct(name: 'Soda 350ml');
      final amina = await addStaff('Amina');
      final joseph = await addStaff('Joseph');
      final mine = await writeSale(
          staffName: 'Amina', staffId: amina, totalMinor: 1500, at: midnight);
      final theirs = await writeSale(
          staffName: 'Joseph', staffId: joseph, totalMinor: 9999, at: midnight);
      await writeSaleItem(
          saleId: mine,
          productId: soda,
          productName: 'Soda 350ml',
          qty: 1,
          unitPriceMinor: 1500,
          unitCostMinor: 1000);
      await writeSaleItem(
          saleId: theirs,
          productId: soda,
          productName: 'Soda 350ml',
          qty: 6,
          unitPriceMinor: 1500,
          unitCostMinor: 1000);

      final scoped = await db.topProducts(since: midnight, staffId: amina);
      final shop = await db.topProducts(since: midnight);

      expect(scoped.single.units, 1.0);
      expect(shop.single.units, 7.0);
    });

    test('a renamed product stays one row, not two', () async {
      // The name on a line is what the receipt said, so a catalogue rename
      // would otherwise split one product across two ranks.
      final soda = await addProduct(name: 'Soda 350ml');
      final before =
          await writeSale(staffName: 'Amina', totalMinor: 1500, at: midnight);
      final after =
          await writeSale(staffName: 'Amina', totalMinor: 1500, at: midnight);
      await writeSaleItem(
          saleId: before,
          productId: soda,
          productName: 'Soda 350ml',
          qty: 1,
          unitPriceMinor: 1500,
          unitCostMinor: 1000);
      await writeSaleItem(
          saleId: after,
          productId: soda,
          productName: 'Fizzy 350ml',
          qty: 1,
          unitPriceMinor: 1500,
          unitCostMinor: 1000);

      final rows = await db.topProducts(since: midnight);

      expect(rows.length, 1);
      expect(rows.single.units, 2.0);
    });

    test('the end of the range is exclusive', () async {
      final soda = await addProduct(name: 'Soda 350ml');
      final secondDay = midnight.add(const Duration(days: 1));
      final sale =
          await writeSale(staffName: 'Amina', totalMinor: 1500, at: secondDay);
      await writeSaleItem(
          saleId: sale,
          productId: soda,
          productName: 'Soda 350ml',
          qty: 1,
          unitPriceMinor: 1500,
          unitCostMinor: 1000);

      final first = await db.topProducts(since: midnight, until: secondDay);
      final second = await db.topProducts(since: secondDay);

      expect(first, isEmpty);
      expect(second.length, 1);
    });
  });

  // ---- salesByHour ---------------------------------------------------------

  group('salesByHour', () {
    test('returns all twenty-four hours with zeros for the quiet ones',
        () async {
      await writeSale(
          staffName: 'Amina',
          totalMinor: 2000,
          at: midnight.add(const Duration(hours: 9, minutes: 30)));
      await writeSale(
          staffName: 'Amina',
          totalMinor: 3000,
          at: midnight.add(const Duration(hours: 9, minutes: 45)));
      // Strictly the busiest, not a tie with the 09:00 hour. Two equal
      // buckets made "busiest" a coin flip and the assertion was picking a
      // winner out of one.
      await writeSale(
          staffName: 'Amina',
          totalMinor: 8000,
          at: midnight.add(const Duration(hours: 18)));

      final buckets = await db.salesByHour(day: midnight);

      expect(buckets.length, 24);
      expect(buckets.map((b) => b.hour).toList(),
          List<int>.generate(24, (i) => i));
      expect(buckets[3].salesMinor, 0);
      expect(buckets[9].salesMinor, 5000);
      expect(buckets[9].transactions, 2);
      expect(buckets[9].hourLabel, '9am');
      expect(buckets[12].hourLabel, '12pm');
      expect(buckets[18].hourLabel, '6pm');
      expect(buckets[18].salesMinor, 8000);
      expect(buckets[0].hourLabel, '12am');
      // A day with a sale in it has a peak.
      expect(busiestHour(buckets)?.hour, 18);
    });

    test('is scoped to the requested day and to the cashier', () async {
      final amina = await addStaff('Amina');
      final joseph = await addStaff('Joseph');
      await writeSale(
          staffName: 'Amina',
          staffId: amina,
          totalMinor: 1000,
          at: midnight.add(const Duration(hours: 10)));
      await writeSale(
          staffName: 'Joseph',
          staffId: joseph,
          totalMinor: 7000,
          at: midnight.add(const Duration(hours: 10)));
      await writeSale(
          staffName: 'Amina',
          staffId: amina,
          totalMinor: 4000,
          at: midnight.add(const Duration(days: 1, hours: 10)));

      final buckets = await db.salesByHour(day: midnight, staffId: amina);

      expect(buckets[10].salesMinor, 1000);
      final total = buckets.fold<int>(0, (sum, b) => sum + b.salesMinor);
      expect(total, 1000);
    });

    test('an all-zero day has no peak hour', () async {
      // Otherwise the chart would confidently tell the owner to staff up at
      // midnight, because twelve zeros tie at the top.
      final buckets = await db.salesByHour(day: midnight);

      expect(buckets.every((b) => b.salesMinor == 0), isTrue);
      expect(busiestHour(buckets), isNull);
    });
  });

  // ---- salesByDay ----------------------------------------------------------

  group('salesByDay', () {
    test('fills every day in the range, including the empty ones', () async {
      await writeSale(
          staffName: 'Amina',
          totalMinor: 1000,
          at: midnight.add(const Duration(hours: 9)));
      // Two days *back*, not forward: the range deliberately stops at today,
      // because a bar for takings that have not happened yet is not a fact.
      // Subtracting the days and then subtracting the hours would land on the
      // day before the start of the range and be correctly excluded.
      await writeSale(
          staffName: 'Amina',
          totalMinor: 3000,
          at: midnight
              .subtract(const Duration(days: 2))
              .add(const Duration(hours: 9)));

      final buckets = await db.salesByDay(
          since: midnight.subtract(const Duration(days: 2)));

      // Midnight minus two days through today inclusive.
      expect(buckets.length, 3);
      // All three parts from the SAME date. Deriving the year from one day and
      // the month and day from another silently produces a different day
      // whenever the range crosses a month boundary.
      final firstDay = midnight.subtract(const Duration(days: 2));
      expect(
          buckets.first.day,
          '${firstDay.year.toString().padLeft(4, '0')}-'
          '${firstDay.month.toString().padLeft(2, '0')}-'
          '${firstDay.day.toString().padLeft(2, '0')}');
      // Range is day-2, day-1, today. The gap is a zero bar, not a missing
      // one: "we shut yesterday" is exactly what an owner is looking for.
      expect(buckets[0].salesMinor, 3000, reason: 'two days ago');
      expect(buckets[0].hasSales, isTrue);
      expect(buckets[1].salesMinor, 0, reason: 'yesterday, shut');
      expect(buckets[1].hasSales, isFalse);
      expect(buckets[2].salesMinor, 1000, reason: 'today');
    });

    test('is scoped to the cashier', () async {
      final amina = await addStaff('Amina');
      final joseph = await addStaff('Joseph');
      await writeSale(
          staffName: 'Amina',
          staffId: amina,
          totalMinor: 1500,
          at: midnight.add(const Duration(hours: 9)));
      await writeSale(
          staffName: 'Joseph',
          staffId: joseph,
          totalMinor: 6000,
          at: midnight.add(const Duration(hours: 9)));

      final mine = await db.salesByDay(since: midnight, staffId: amina);
      final shop = await db.salesByDay(since: midnight);

      expect(mine.single.salesMinor, 1500);
      expect(shop.single.salesMinor, 7500);
    });

    test('merging keeps every shilling and shortens the axis', () async {
      final buckets = List<DateBucket>.generate(
        30,
        (i) => DateBucket(
          day: '2026-01-${(i + 1).toString().padLeft(2, '0')}',
          label: '${i + 1}',
          salesMinor: 100,
          profitMinor: 40,
          transactions: 2,
        ),
      );

      final merged = mergeDateBuckets(buckets, 6);

      expect(merged.length, 6);
      expect(merged.fold<int>(0, (sum, b) => sum + b.salesMinor), 3000);
      expect(merged.fold<int>(0, (sum, b) => sum + b.transactions), 60);
      expect(merged.first.label, contains('–'));
    });

    test('a range that already fits is returned untouched', () {
      final buckets = List<DateBucket>.generate(
        3,
        (i) => DateBucket(
            day: '2026-01-0${i + 1}',
            label: '${i + 1}',
            salesMinor: 1,
            profitMinor: 0,
            transactions: 1),
      );
      expect(mergeDateBuckets(buckets, 14), same(buckets));
    });
  });

  // ---- salesByPaymentMethod ------------------------------------------------

  group('salesByPaymentMethod', () {
    test('groups by tender, biggest first', () async {
      await writeSale(
          staffName: 'Amina',
          totalMinor: 5000,
          at: midnight.add(const Duration(hours: 9)),
          paymentMethod: 'cash');
      await writeSale(
          staffName: 'Amina',
          totalMinor: 3000,
          at: midnight.add(const Duration(hours: 10)),
          paymentMethod: 'mpesa');
      await writeSale(
          staffName: 'Amina',
          totalMinor: 1000,
          at: midnight.add(const Duration(hours: 11)),
          paymentMethod: 'mpesa');

      final rows = await db.salesByPaymentMethod(since: midnight);

      expect(rows.length, 2);
      expect(rows.first.method, 'cash');
      expect(rows.first.salesMinor, 5000);
      expect(rows.first.label(), 'Cash');
      expect(rows.first.transactions, 1);
      expect(rows.last.method, 'mpesa');
      expect(rows.last.salesMinor, 4000);
      expect(rows.last.transactions, 2);
      expect(rows.last.label(), 'M-Pesa');
      expect(rows.last.sharePct(9000), closeTo(44.44, 0.01));
      // A share of nothing is zero, not a NaN that renders as "NaN%".
      expect(rows.first.sharePct(0), 0);
      expect(rows.last.label(), isNot('mobile_money_manual'));
    });
  });

  // ---- countLowStockProducts ----------------------------------------------

  group('countLowStockProducts', () {
    test('matches the Dart-side filter it replaces', () async {
      // The count used to be `getProducts().where((p) => p.isLow).length` —
      // the whole catalogue loaded and folded to get one integer. These are the
      // same predicate, stated once in each language, so a change to one that
      // is not made to the other fails here.
      await addProduct(name: 'Well stocked', stock: 40, reorder: 5);
      await addProduct(name: 'Exactly at level', stock: 5, reorder: 5);
      await addProduct(name: 'Below level', stock: 2, reorder: 5);
      await addProduct(name: 'Sold out', stock: 0, reorder: 5);
      await addProduct(
          name: 'Inactive and empty', stock: 0, reorder: 5, active: false);

      final fromSql = await db.countLowStockProducts();
      final fromDart = (await db.getProducts()).where((p) => p.isLow).length;

      expect(fromSql, 3);
      expect(fromSql, fromDart);
    });

    test('a well-stocked catalogue is zero', () async {
      await addProduct(name: 'Soda', stock: 100, reorder: 5);
      expect(await db.countLowStockProducts(), 0);
    });

    test('is not affected by variants or history', () async {
      await addProduct(name: 'Soda', stock: 1, reorder: 5);
      // A variant row is its own stock; the KPI counts products, and the
      // inventory screen is where a variant is reordered from.
      await (await db.database).insert('product_variants', {
        'product_id': 1,
        'name': 'Big',
        'sell_price': 2000,
        'cost_price': 1200,
        'stock_qty': 0,
      });

      expect(await db.countLowStockProducts(), 1);
    });
  });

  // ---- attention counts ----------------------------------------------------

  group('attention counts', () {
    test('counts rejected eTIMS receipts, not merely queued ones', () async {
      final queued = await writeSale(
          staffName: 'Amina',
          totalMinor: 1000,
          at: midnight.add(const Duration(hours: 9)),
          etimsStatus: EtimsStatus.pending);
      final rejected = await writeSale(
          staffName: 'Amina',
          totalMinor: 2000,
          at: midnight.add(const Duration(hours: 9)),
          etimsStatus: EtimsStatus.rejected);

      await (await db.database).insert('pending_etims', {
        'sale_id': queued,
        'receipt_number': 'POS-000001',
        'created_at': midnight.toIso8601String(),
        'updated_at': midnight.toIso8601String(),
      });
      // markEtimsRejected leaves the queue row behind, so the queue alone
      // cannot tell "waiting for a network" from "refused forever". Rejected
      // receipts are excluded from the pending count so one refused sale never
      // blocks every newer one.
      await (await db.database).insert('pending_etims', {
        'sale_id': rejected,
        'receipt_number': 'POS-000002',
        'created_at': midnight.toIso8601String(),
        'updated_at': midnight.toIso8601String(),
      });

      expect(await db.countPendingEtimsReceipts(), 1);
      expect(await db.countRejectedEtimsReceipts(), 1);
    });

    test('counts unverified payments and lists them', () async {
      await writeSale(
          staffName: 'Amina',
          totalMinor: 1000,
          at: midnight.add(const Duration(hours: 9)));
      await writeSale(
          staffName: 'Amina',
          totalMinor: 2500,
          at: midnight.add(const Duration(hours: 10)),
          paymentVerified: false,
          paymentMethod: 'mpesa');

      expect(await db.countUnverifiedPayments(), 1);
      final rows = await db.getUnverifiedSales();
      expect(rows.length, 1);
      expect(rows.single.$1.total.minorUnits, 2500);
      expect(rows.single.$2['payment_method'], 'mpesa');
    });

    test('a quiet till reports nothing needing attention', () async {
      final summary = await db.attentionSummary();

      expect(summary.isEmpty, isTrue);
      expect(summary.total, 0);
      expect(AttentionSummary.empty.isEmpty, isTrue);
    });

    test('the summary gathers all four counts', () async {
      await writeSale(
          staffName: 'Amina',
          totalMinor: 1000,
          at: midnight,
          etimsStatus: EtimsStatus.rejected,
          paymentVerified: false);
      await db.recordImportProblem(
        source: 'excel',
        rowNumber: 4,
        rawName: 'Kwancheri',
        rawRow: const ['Kwancheri', 120],
        problem: 'No price in the file',
      );

      final summary = await db.attentionSummary();

      expect(summary.rejectedEtims, 1);
      expect(summary.unverifiedPayments, 1);
      expect(summary.openImportProblems, 1);
      expect(summary.isEmpty, isFalse);
      expect(summary.total, 3);
    });
  });
}
