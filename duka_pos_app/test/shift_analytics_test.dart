// The shifts over a window, and what the drawers did.
//
// ## WHY THIS IS HERE
//
// "Make sure in cross shop the shifts are shown and also in analytics too
// (shift analytics)."
//
// A shift screen answers "how is MY drawer doing" — one shift, one drawer,
// one count. It does not answer the question an owner has after a week: "were
// my drawers coming out right?"
//
// A week of shifts has a figure in it that no single shift has — the
// DIFFERENCE between the cash the ledger says should have been in the drawer
// and the cash that was actually counted. One drawer being short by KSh 50 is
// an accident. Every drawer being short by KSh 50, every day, is a problem
// with the till, and it is invisible until the differences are added up.
//
// ## WHAT IS PINNED
//
//   * the shifts in the window are counted, and only those;
//   * the expected and counted cash are added up ACROSS shifts, so a week of
//     small shortages is a week of shortage rather than a week of nothing;
//   * a shift that was closed but never counted is not treated as a zero —
//     the figure says so instead of inventing a variance;
//   * a cashier's own shifts are their own.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/services/shift_analytics.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    await DatabaseHelper.openInMemoryForTests();
  });

  /// A shift that ran and was counted.
  ///
  /// [expected] and [counted] are minor units, and [counted] being lower is a
  /// drawer that came up short.
  Future<int> closedShift({
    int staffId = 1,
    String staffName = 'Amina',
    required int expected,
    required int counted,
    bool reconcile = true,
  }) async {
    final DatabaseHelper db = DatabaseHelper.instance;
    final int id = await db.openShift(
      staffId: staffId,
      staffName: staffName,
      startFloat: Money.fromMinor(10000),
    );
    if (reconcile) {
      await db.reconcileShift(
        shiftId: id,
        countedCash: Money.fromMinor(counted),
        expectedCash: Money.fromMinor(expected),
      );
    }
    return id;
  }

  test('a window with no shifts says so', () async {
    final ShiftAnalytics analytics = await loadShiftAnalytics(
      from: DateTime.now().subtract(const Duration(days: 7)),
      to: DateTime.now(),
    );
    expect(analytics.hasShifts, isFalse);
    expect(analytics.shifts, 0);
    expect(analytics.variance, Money.zero);
  });

  test('the differences are added up across the shifts', () async {
    // Two shifts, each KSh 500 short. One shift's variance is an accident; a
    // week's worth of them is a problem with the till, and the figure only
    // exists once they are added together.
    await closedShift(expected: 50000, counted: 49500);
    await closedShift(expected: 30000, counted: 29500);

    final ShiftAnalytics analytics = await loadShiftAnalytics(
      from: DateTime.now().subtract(const Duration(days: 7)),
      to: DateTime.now().add(const Duration(minutes: 1)),
    );

    expect(analytics.shifts, 2);
    expect(analytics.closed, 2);
    expect(analytics.reconciled, 2);
    expect(analytics.expected, Money.fromMinor(80000));
    expect(analytics.counted, Money.fromMinor(79000));
    expect(analytics.variance, Money.fromMinor(-1000));
  });

  test('a drawer that came out over is over, not short', () async {
    await closedShift(expected: 20000, counted: 20500);

    final ShiftAnalytics analytics = await loadShiftAnalytics(
      from: DateTime.now().subtract(const Duration(days: 7)),
      to: DateTime.now().add(const Duration(minutes: 1)),
    );
    expect(analytics.variance, Money.fromMinor(500));
    expect(analytics.variance.isNegative, isFalse);
  });

  test('a shift that was never counted is not counted as a zero', () async {
    // The dangerous reading: "KSh 0 difference" for a drawer nobody counted.
    // The card has to be able to say "not counted" instead.
    await closedShift(expected: 20000, counted: 19500);
    await closedShift(expected: 10000, counted: 9000, reconcile: false);

    final ShiftAnalytics analytics = await loadShiftAnalytics(
      from: DateTime.now().subtract(const Duration(days: 7)),
      to: DateTime.now().add(const Duration(minutes: 1)),
    );

    expect(analytics.shifts, 2);
    expect(analytics.reconciled, 1);
    expect(analytics.hasCounts, isTrue);
    // The variance covers the shift that WAS counted, and says how many were.
    expect(analytics.variance, Money.fromMinor(-500));
  });

  test('a cashier sees their own shifts only', () async {
    await closedShift(
        staffId: 1, staffName: 'Amina', expected: 20000, counted: 20000);
    await closedShift(
        staffId: 2, staffName: 'Brian', expected: 90000, counted: 90000);

    final ShiftAnalytics mine = await loadShiftAnalytics(
      from: DateTime.now().subtract(const Duration(days: 7)),
      to: DateTime.now().add(const Duration(minutes: 1)),
      staffId: 1,
    );
    expect(mine.shifts, 1);
    expect(mine.expected, Money.fromMinor(20000));

    final ShiftAnalytics all = await loadShiftAnalytics(
      from: DateTime.now().subtract(const Duration(days: 7)),
      to: DateTime.now().add(const Duration(minutes: 1)),
    );
    expect(all.shifts, 2);
    expect(all.expected, Money.fromMinor(110000));
  });

  test('a shift outside the window is not in the window', () async {
    // A shift from last year, in a database that still has it.
    final DatabaseHelper db = DatabaseHelper.instance;
    await (await db.database).insert('shifts', <String, Object?>{
      'staff_id': 1,
      'staff_name': 'Amina',
      'start_time':
          DateTime.now().subtract(const Duration(days: 400)).toIso8601String(),
      'end_time':
          DateTime.now().subtract(const Duration(days: 400)).toIso8601String(),
      'start_float': 0,
      'end_float': 0,
      'status': 'closed',
    });

    final ShiftAnalytics analytics = await loadShiftAnalytics(
      from: DateTime.now().subtract(const Duration(days: 7)),
      to: DateTime.now().add(const Duration(minutes: 1)),
    );
    expect(analytics.shifts, 0);
  });

  test('the model reads the window from the shifts themselves', () {
    // The value is a value: it can be built and read without a database.
    const ShiftAnalytics empty = ShiftAnalytics.empty();
    expect(empty.hasShifts, isFalse);
    expect(empty.variance, Money.zero);

    final ShiftAnalytics some = ShiftAnalytics(
      shifts: 3,
      closed: 2,
      reconciled: 2,
      expected: Money.fromMinor(1000),
      counted: Money.fromMinor(900),
    );
    expect(some.hasShifts, isTrue);
    expect(some.hasCounts, isTrue);
    expect(some.variance, Money.fromMinor(-100));
  });
}
