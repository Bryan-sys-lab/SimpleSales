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

      return ShopKpi(
        // The local shop's own identifier. It is not the backend's tenant id,
        // and it never is: a shop that has never been online has no tenant.
        // The screen shows names and figures, and the id is only ever a key.
        tenantId: shop.workspaceKey,
        shopName: shop.shopName,
        revenue: Money.fromMinor((row['total_minor'] as num?)?.toInt() ?? 0),
        profit: Money.fromMinor((row['profit_minor'] as num?)?.toInt() ?? 0),
        transactions: (row['transactions'] as num?)?.toInt() ?? 0,
        topPaymentMethod: topPaymentMethod,
      );
    } catch (_) {
      // A shop whose file will not open is left out, not reported as empty.
      return null;
    } finally {
      await db?.close();
    }
  }
}
