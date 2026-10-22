// A cashier's analytics are the cashier's OWN takings.
//
// ## WHAT THIS PINS
//
// The analytics screen used to be a whole-shop screen that cashiers could not
// open at all: the nav bar hid it, and the guard sent a deep link to the
// dashboard. The answer to "how am I doing?" was "you may not look".
//
// Now the screen is open to everybody and the FIGURES decide what it shows:
// the owner's and the manager's are the whole shop's, and a cashier's are the
// rows they sold. The scope lives in the query, not in the screen — so the
// assertion is on the query, because that is where the money is hidden.
//
// Three things are pinned:
//
//   * the scope is the cashier's own staff id, and it comes from the session;
//   * the aggregates honour it — another cashier's takings are not in them;
//   * the guard lets a cashier into the screen but not into the whole-shop
//     views underneath it.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/routing/app_redirect.dart';
import 'package:duka_pos/routing/app_stage_controller.dart';
import 'package:duka_pos/routing/routes.dart';
import 'package:duka_pos/services/analytics.dart';
import 'package:duka_pos/services/app_stage.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/roles.dart';
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
  });

  late DatabaseHelper db;

  setUp(() async {
    db = await DatabaseHelper.openInMemoryForTests();
  });

  /// A sale, written straight to the ledger.
  ///
  /// Not through [DatabaseHelper.recordSale]: that one moves stock, checks
  /// availability and stamps its own timestamps, and none of that is what is
  /// under test here. What is under test is the AGGREGATE and the scope it is
  /// asked with.
  Future<int> writeSale({
    required String staffName,
    required int staffId,
    required int totalMinor,
    required DateTime at,
  }) async {
    return (await db.database).insert('sales', <String, Object?>{
      'staff_name': staffName,
      'staff_id': staffId,
      'total': totalMinor,
      'profit': totalMinor ~/ 5,
      'payment_method': 'cash',
      'created_at': at.toIso8601String(),
      'etims_status': 'not_required',
      'payment_verified': 1,
    });
  }

  group('the scope comes from the session', () {
    test('a cashier is scoped to their own staff id', () {
      final AppState state = AppState();
      state.signInAsStaff(Staff(
        id: 7,
        name: 'Amina',
        pinHash: 'x',
        role: ShopRole.cashier.wire,
      ));

      expect(state.seesAllSales, isFalse);
      expect(state.analyticsStaffId, 7);
    });

    test('an owner and a manager are scoped to nothing', () {
      final AppState state = AppState();
      state.signInAsStaff(Staff(
        id: 7,
        name: 'Brian',
        pinHash: 'x',
        role: ShopRole.manager.wire,
      ));
      expect(state.seesAllSales, isTrue);
      expect(state.analyticsStaffId, isNull);

      state.signIn('Amina', asOwner: true, role: 'admin');
      expect(state.seesAllSales, isTrue);
      expect(state.analyticsStaffId, isNull);
    });
  });

  group('the aggregates honour the scope', () {
    test("a cashier's takings do not include another cashier's", () async {
      final DateTime at = DateTime.now().subtract(const Duration(hours: 2));

      await writeSale(staffName: 'Amina', staffId: 1, totalMinor: 100, at: at);
      await writeSale(staffName: 'Brian', staffId: 2, totalMinor: 250, at: at);

      final DateTime since = DateTime(2000);

      // Amina's own figures: her one sale, and only hers.
      final DailyTotals aminaTotals = await db.salesTotalsFor(
        since: since,
        staffId: 1,
      );
      expect(aminaTotals.transactions, 1);
      expect(aminaTotals.totalMinor, 100);

      // The whole shop's figures: both sales.
      final DailyTotals shopTotals = await db.salesTotalsFor(since: since);
      expect(shopTotals.transactions, 2);
      expect(shopTotals.totalMinor, 350);
    });

    test("the day's chart and the payment mix are scoped too", () async {
      final DateTime at = DateTime.now().subtract(const Duration(hours: 2));

      await writeSale(staffName: 'Amina', staffId: 1, totalMinor: 100, at: at);
      await writeSale(staffName: 'Brian', staffId: 2, totalMinor: 250, at: at);

      final DateTime since = DateTime.now().subtract(const Duration(days: 2));

      final List<DateBucket> days =
          await db.salesByDay(since: since, staffId: 1);
      final int aminaSales = days.fold<int>(
        0,
        (int sum, DateBucket day) => sum + day.salesMinor,
      );
      expect(aminaSales, 100);

      final List<PaymentMixRow> mix =
          await db.salesByPaymentMethod(since: since, staffId: 1);
      expect(
        mix.fold<int>(0, (int sum, PaymentMixRow row) => sum + row.salesMinor),
        100,
      );
    });
  });

  group('the door', () {
    AppStageSnapshot snapshot() => const AppStageSnapshot(
          stage: AppStage.ready,
          canManageStock: false,
          isAdmin: false,
        );

    test('a cashier may open the analytics screen', () {
      expect(
        appRedirect(snapshot: snapshot(), location: Routes.analytics),
        isNull,
      );
    });

    test('a cashier may not open the whole-shop views', () {
      expect(
        appRedirect(snapshot: snapshot(), location: Routes.reports),
        Routes.dashboard,
      );
      expect(
        appRedirect(snapshot: snapshot(), location: Routes.portfolio),
        Routes.dashboard,
      );
      expect(
        appRedirect(snapshot: snapshot(), location: Routes.inventory),
        Routes.dashboard,
      );
    });
  });
}
