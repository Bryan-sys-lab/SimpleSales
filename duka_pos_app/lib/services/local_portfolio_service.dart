// "How my shops are doing", read from the phone.
//
// ## THE PROBLEM
//
// "How my shops are doing, if the shops are in one device (a device has more
// than one shop under one owner), should work offline."
//
// The screen read the cross-shop KPIs from the BACKEND. With no signal — and
// a shop with no signal is a normal shop, not an unusual one — the screen
// showed its failure state: the one screen that reports on every shop at
// once was the one screen that needed a connection to work.
//
// ## THE FIX
//
// The figures are already on the phone. Each shop has its own database file,
// and a sale is written to the file of the shop it happened in, at the moment
// it happened. So the portfolio can be read from the device, and it is read
// from the device FIRST — with the backend as the thing that adds shops the
// device has never seen.
//
// A shop the phone knows about is read from its own file. A shop the backend
// knows about and the phone does not is the backend's to report, and the two
// are merged without double-counting: a shop is read from ONE place, and the
// local file wins for the shops the phone holds.
//
// ## WHY EACH FILE IS OPENED ON ITS OWN
//
// The database is a process-global singleton pointing at the active shop.
// Reading another shop's file through it would mean repointing the whole app
// at another shop's data — while the till is open, with sales being written.
// So each shop's file is opened with its own handle, read, and closed again.

import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../services/portfolio_kpis.dart';
import '../services/workspace_service.dart';
import '../utils/money.dart';
import '../profile/shop_profile.dart';

/// The cross-shop figures, read from the shops on this device.
class LocalPortfolioService {
  const LocalPortfolioService._();

  /// Every shop on this device, over the window.
  ///
  /// A shop that cannot be read is LEFT OUT rather than reported as empty:
  /// a file that will not open is a problem to say nothing about, and a zero
  /// row for it would be a lie about a shop the owner runs.
  static Future<PortfolioKpis> read({
    required DateTime from,
    required DateTime to,
  }) async {
    final List<LocalShop> shops = await WorkspaceServiceShops.localShops();
    final List<ShopKpi> kpis = <ShopKpi>[];
    for (final LocalShop shop in shops) {
      final ShopKpi? kpi = await _readShop(shop, from, to);
      if (kpi != null) kpis.add(kpi);
    }
    return PortfolioKpis(shops: kpis, windowStart: from, windowEnd: to);
  }

  /// One shop, from its own file.
  static Future<ShopKpi?> _readShop(
    LocalShop shop,
    DateTime from,
    DateTime to,
  ) async {
    Database? db;
    try {
      final String path =
          await DatabaseHelper.databasePathFor(shop.workspaceKey);
      db = await openDatabase(
        path,
        options: OpenDatabaseOptions(
          readOnly: true,
          // Its OWN handle, not the cached one.
          //
          // `sqflite` hands back the SAME database object for a path it has
          // already opened, and the app's own connection to that shop's file
          // is in that cache. Closing what we opened would therefore close the
          // app's connection — and the till would find its shop gone the
          // moment the owner opened this screen.
          //
          // `singleInstance: false` says: give me a separate connection to
          // that file, and closing mine touches nothing else.
          singleInstance: false,
        ),
      );
      final List<Map<String, Object?>> rows = await db.rawQuery(
        '''
        SELECT
          CAST(COALESCE(SUM(total), 0) AS INTEGER) AS total_minor,
          CAST(COALESCE(SUM(profit), 0) AS INTEGER) AS profit_minor,
          COUNT(*) AS transactions
        FROM sales
        WHERE created_at >= ? AND created_at <= ?
        ''',
        <Object?>[from.toIso8601String(), to.toIso8601String()],
      );
      if (rows.isEmpty) return null;
      final Map<String, Object?> row = rows.first;
      ShopProfile businessProfile = ShopProfile.duka;
      try {
        final List<Map<String, Object?>> profileRows = await db.query(
          'shop_profile',
          columns: <String>['profile'],
          limit: 1,
        );
        if (profileRows.isNotEmpty) {
          businessProfile = ShopProfile.fromWire(
            profileRows.first['profile'] as String?,
          );
        }
      } catch (_) {
        // A pre-profile legacy database is the Duka baseline.
      }

      // These are the canonical shared financial events used by the shop's
      // own statement. Read the same columns here so the All shops view is a
      // projection of the existing ledger, not a second accounting formula.
      var financialDataComplete = true;
      var operatingExpensesMinor = 0;
      var cashInMinor = 0;
      var cashOutMinor = 0;
      var receivableDeltaMinor = 0;
      var payableDeltaMinor = 0;
      try {
        final eventRows = await db.rawQuery('''
          SELECT COALESCE(SUM(operating_expense_minor), 0) AS expenses,
                 COALESCE(SUM(cash_in_minor), 0) AS cash_in,
                 COALESCE(SUM(cash_out_minor), 0) AS cash_out,
                 COALESCE(SUM(receivable_delta_minor), 0) AS receivable,
                 COALESCE(SUM(payable_delta_minor), 0) AS payable
            FROM financial_events
           WHERE occurred_at_utc >= ? AND occurred_at_utc < ?
        ''', <Object?>[
          from.toUtc().toIso8601String(),
          to.toUtc().toIso8601String()
        ]);
        final event = eventRows.first;
        operatingExpensesMinor = (event['expenses'] as num?)?.toInt() ?? 0;
        cashInMinor = (event['cash_in'] as num?)?.toInt() ?? 0;
        cashOutMinor = (event['cash_out'] as num?)?.toInt() ?? 0;
        receivableDeltaMinor = (event['receivable'] as num?)?.toInt() ?? 0;
        payableDeltaMinor = (event['payable'] as num?)?.toInt() ?? 0;
      } catch (_) {
        financialDataComplete = false;
      }
      var stockValueMinor = 0;
      try {
        final stockRows = await db.rawQuery('''
          SELECT COALESCE(SUM(stock_qty * cost_price), 0) AS stock_value
            FROM products
           WHERE active = 1
        ''');
        stockValueMinor =
            (stockRows.first['stock_value'] as num?)?.round() ?? 0;
      } catch (_) {
        financialDataComplete = false;
      }

      final List<Map<String, Object?>> tenders = await db.rawQuery(
        '''
        SELECT payment_method AS method, COUNT(*) AS count
        FROM sales
        WHERE created_at >= ? AND created_at <= ?
        GROUP BY payment_method
        ORDER BY count DESC
        LIMIT 1
        ''',
        <Object?>[from.toIso8601String(), to.toIso8601String()],
      );
      String? topPaymentMethod;
      if (tenders.isNotEmpty) {
        final Object? method = tenders.first['method'];
        if (method != null && method.toString().trim().isNotEmpty) {
          topPaymentMethod = method.toString();
        }
      }

      // The shifts, from the same file, so "how are my shops doing" answers
      // about the drawer and not only about takings. A shop's shift is where
      // the cash is reconciled: a busy shop and a shop whose drawer has been
      // short for days look identical on revenue alone.
      //
      // Counted against expected, both already in minor units on the row —
      // the close wrote them, so this is the same figure the shop's own shift
      // report shows.
      // The drawer figures do NOT live on `shifts`: a shift is opened with a
      // float and closed with a COUNT, and the count-plus-variance is written
      // to `reconciliations`. Reading them off the shift row is a query that
      // throws, and this method treats a throwing shop as a shop to leave out —
      // so the whole portfolio silently emptied.
      //
      // The latest count per shift, not a join: a drawer can be counted twice,
      // and a join would count the earlier count as well.
      final List<Map<String, Object?>> closedShifts = await db.rawQuery(
        '''
        SELECT
          COUNT(*) AS closed,
          CAST(COALESCE(SUM(
            (SELECT r.counted_cash - r.expected_cash
             FROM reconciliations r
             WHERE r.shift_id = shifts.id
             ORDER BY r.recorded_at DESC, r.id DESC
             LIMIT 1)
          ), 0) AS INTEGER) AS variance_minor
        FROM shifts
        WHERE status = 'closed' AND start_time >= ? AND start_time <= ?
        ''',
        <Object?>[from.toIso8601String(), to.toIso8601String()],
      );
      // Open shifts are counted NOW, not in the window: a drawer that is open
      // is open whether it was opened this morning or last week, and hiding it
      // because it falls outside a report window would be the one thing an
      // owner most needs to see.
      final List<Map<String, Object?>> openShifts = await db.rawQuery(
        "SELECT COUNT(*) AS open_count FROM shifts WHERE status = 'open'",
      );

      return ShopKpi(
        // The local shop's own identifier. It is not the backend's tenant id,
        // and it never is: a shop that has never been online has no tenant.
        // The screen shows names and figures, and the id is only ever a key.
        tenantId: shop.workspaceKey,
        shopName: shop.shopName,
        businessProfile: businessProfile,
        revenue: Money.fromMinor((row['total_minor'] as num?)?.toInt() ?? 0),
        profit: Money.fromMinor((row['profit_minor'] as num?)?.toInt() ?? 0),
        transactions: (row['transactions'] as num?)?.toInt() ?? 0,
        topPaymentMethod: topPaymentMethod,
        shiftsClosed: closedShifts.isEmpty
            ? 0
            : (closedShifts.first['closed'] as num?)?.toInt() ?? 0,
        shiftsOpen: openShifts.isEmpty
            ? 0
            : (openShifts.first['open_count'] as num?)?.toInt() ?? 0,
        cashVariance: Money.fromMinor(closedShifts.isEmpty
            ? 0
            : (closedShifts.first['variance_minor'] as num?)?.toInt() ?? 0),
        operatingExpenses: Money.fromMinor(operatingExpensesMinor),
        cashIn: Money.fromMinor(cashInMinor),
        cashOut: Money.fromMinor(cashOutMinor),
        receivableDelta: Money.fromMinor(receivableDeltaMinor),
        payableDelta: Money.fromMinor(payableDeltaMinor),
        stockValue: Money.fromMinor(stockValueMinor),
        financialDataComplete: financialDataComplete,
      );
    } catch (_) {
      // A shop whose file will not open is left out, not reported as empty.
      return null;
    } finally {
      await db?.close();
    }
  }
}
