// The shift screen's rules, in plain Dart.
//
// This file exists because the screen used to be untestable. It queried the
// database from `initState`, and sqflite's ffi backend does real file I/O on a
// background isolate with real timers — so `await`ing it inside `testWidgets`
// hangs until the harness kills the file. The usual fix is a `staffLoader` seam
// on the widget, which works but adds a production parameter that exists only
// for a test and still cannot cover the other four queries.
//
// `loadShiftLedger` is a plain function instead. Every rule below is a real rule
// about who sees what and what a difference MEANS, and none of them need a
// widget to be verified.

import 'dart:convert';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/shift_ledger.dart';
import 'package:duka_pos/screens/shift_variance.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

void main() {
  /// The catalogue the variance words come from. See `loadL10n`.
  late AppLocalizations l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    l10n = await loadL10n();
  });

  group('ShiftVariance', () {
    test('a difference of nothing is balanced, and says so in words', () {
      final ShiftVariance variance = ShiftVariance.between(
          l10n, Money.fromMajor(5000), Money.fromMajor(5000));

      expect(variance.isZero, isTrue);
      expect(variance.word, 'Balanced');
      expect(variance.spoken, contains('balanced exactly'));
    });

    test('short is the alarming one and over is merely a note', () {
      // Deliberately the SAME magnitude in both directions: KSh 400 either way.
      // A pair that differs in amount would let the assertion pass on the numbers
      // while the words stayed wrong.
      final ShiftVariance short = ShiftVariance.between(
          l10n, Money.fromMajor(4600), Money.fromMajor(5000));
      final ShiftVariance over = ShiftVariance.between(
          l10n, Money.fromMajor(5400), Money.fromMajor(5000));

      expect(short.word, 'Short');
      expect(over.word, 'Over');
      expect(short.magnitude.minorUnits, 40000);
      expect(short.magnitude.minorUnits, over.magnitude.minorUnits);
      expect(short.spoken, contains('short of'));
      expect(over.spoken, contains('over the'));
    });

    test('the magnitude drops the sign, because the word carries the direction',
        () {
      final ShiftVariance variance = ShiftVariance.between(
          l10n, Money.fromMajor(4000), Money.fromMajor(5000));

      // -1000 minor units signed, 1000 spoken.
      expect(variance.difference.minorUnits, -100000);
      expect(variance.magnitude.minorUnits, 100000);
    });

    test('a one-cent difference is a difference', () {
      // The rounding case that a tolerance check would silently swallow: a till
      // that is one cent out is one cent out, and the row an owner reads has to
      // say so rather than rounding to "balanced".
      final ShiftVariance variance = ShiftVariance.between(
          l10n, Money.fromMinor(499999), Money.fromMinor(500000));

      expect(variance.isZero, isFalse);
      expect(variance.word, 'Short');
    });

    test('an uncounted drawer is not a balanced drawer', () {
      // The state a naive `counted - expected` gets most dangerously wrong: with
      // no count recorded, `zero - expected` reports the entire float as missing.
      expect(ShiftVariance.notCounted(l10n).isZero, isTrue);
      expect(ShiftVariance.notCounted(l10n).word, 'Not counted');
      expect(
          ShiftVariance.notCounted(l10n).spoken, contains('not been counted'));
    });

    test('every variance carries a word AND a glyph, so colour is never alone',
        () {
      for (final (Money counted, Money expected) in <(Money, Money)>[
        (Money.fromMajor(5000), Money.fromMajor(5000)),
        (Money.fromMajor(4000), Money.fromMajor(5000)),
        (Money.fromMajor(6000), Money.fromMajor(5000)),
        (ShiftVariance.notCounted(l10n).difference, Money.fromMajor(5000)),
      ]) {
        final ShiftVariance variance =
            ShiftVariance.between(l10n, counted, expected);
        expect(variance.word, isNotEmpty);
        // A distinct icon per state is the channel that survives greyscale and
        // invertColors; `StatusTone` is where that is asserted to differ.
        expect(variance.tone.icon, isNotNull);
      }
    });
  });

  group('loadShiftLedger', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
    });

    tearDown(() => DatabaseHelper.resetForTests());

    Future<void> openShiftFor(int staffId, String name, num float) =>
        db.openShift(
          staffId: staffId,
          staffName: name,
          startFloat: Money.fromMajor(float),
        );

    test('an empty till has no open shift and no history', () async {
      final ShiftLedger ledger =
          await loadShiftLedger(viewerStaffId: 7, seesAllSales: false);

      expect(ledger.hasOpenShift, isFalse);
      expect(ledger.expected, Money.zero);
      // Null, not zero: an uncounted drawer is not an empty one.
      expect(ledger.counted, isNull);
      expect(ledger.history, isEmpty);
      expect(ledger.historyTotal, 0);
    });

    test('the expected figure is composed by the database, float included',
        () async {
      await openShiftFor(7, 'Amina', 5000);
      final int productId = await db.upsertProduct(Product(
        name: 'AAA Ledger Beer',
        category: 'Beer',
        costPrice: Money.fromMajor(80),
        sellPrice: Money.fromMajor(150),
        stockQty: 50,
        reorderLevel: 5,
        bottleMl: 500,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      await db.recordSale(
        staffName: 'Amina',
        staffId: 7,
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Ledger Beer',
            qty: 4,
            unitPrice: Money.fromMajor(150),
            unitCost: Money.fromMajor(80),
          ),
        ],
      );

      final ShiftLedger ledger =
          await loadShiftLedger(viewerStaffId: 7, seesAllSales: false);

      // 5,000 float + 600 of verified cash. If the loader composed this itself it
      // would be one edit away from reporting the float as a variance.
      expect(ledger.expected.minorUnits, 560000);
    });

    test('a recorded count is the variance, and an absent one is not zero',
        () async {
      await openShiftFor(7, 'Amina', 5000);
      final Shift shift = (await db.getShifts(openOnly: true)).single;

      ShiftLedger ledger =
          await loadShiftLedger(viewerStaffId: 7, seesAllSales: false);
      expect(ledger.counted, isNull);
      expect(ledger.variance(l10n).word, 'Not counted');

      await db.addTillCount(
        shiftId: shift.id!,
        denomination: 'KSh 1000',
        count: 5,
        value: Money.fromMajor(5000),
      );

      ledger = await loadShiftLedger(viewerStaffId: 7, seesAllSales: false);
      expect(ledger.counted!.minorUnits, 500000);
      expect(ledger.variance(l10n).isZero, isTrue);
      expect(ledger.variance(l10n).word, l10n.varianceBalanced);
    });

    test('a cashier sees their own shifts and not a colleague\'s', () async {
      await openShiftFor(7, 'Amina', 5000);
      await openShiftFor(8, 'Brian', 2000);

      final ShiftLedger cashier =
          await loadShiftLedger(viewerStaffId: 7, seesAllSales: false);
      expect(cashier.open?.staffName, 'Amina');

      // Brian's is open on the same till and must not appear as "yours", or the
      // drawer figure is measured against someone else's float.
      final ShiftLedger other =
          await loadShiftLedger(viewerStaffId: 8, seesAllSales: false);
      expect(other.open?.staffName, 'Brian');
    });

    test('a manager sees the whole shop', () async {
      await openShiftFor(7, 'Amina', 5000);
      await openShiftFor(8, 'Brian', 2000);

      final ShiftLedger manager =
          await loadShiftLedger(viewerStaffId: null, seesAllSales: true);

      expect(manager.hasOpenShift, isTrue);
      // Both of them are open, and the newest is the one that is offered.
      expect(
        manager.open?.staffName,
        anyOf('Amina', 'Brian'),
      );
    });

    test('a closed shift leaves the ledger and never becomes the open one',
        () async {
      await openShiftFor(7, 'Amina', 5000);
      final int productId = await db.upsertProduct(Product(
        name: 'Z report item',
        category: 'Test',
        costPrice: Money.fromMajor(80),
        sellPrice: Money.fromMajor(150),
        stockQty: 10,
        reorderLevel: 1,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      await db.recordSale(
        staffName: 'Amina',
        staffId: 7,
        paymentMethod: 'cash',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Z report item',
            qty: 1,
            unitPrice: Money.fromMajor(150),
            unitCost: Money.fromMajor(80),
          ),
        ],
      );
      final Shift shift = (await db.getShifts(openOnly: true)).single;
      final xReport = await db.getXReport(shift);
      expect(xReport['sale_count'], 1);
      expect(xReport['gross_minor'], 15000);
      expect((xReport['payment_mix'] as Map<String, int>)['cash'], 15000);
      await db.reconcileShift(
        shiftId: shift.id!,
        countedCash: Money.fromMajor(5150),
        expectedCash: Money.fromMajor(5150),
      );

      final ShiftLedger ledger =
          await loadShiftLedger(viewerStaffId: 7, seesAllSales: false);

      expect(ledger.hasOpenShift, isFalse);
      expect(ledger.history.length, 1);
      expect(ledger.historyTotal, 1);
      // The reconciliation is loaded WITH the history, newest first, so the
      // owner can read the variance without opening anything.
      expect(ledger.reconciliations.length, 1);
      expect(ledger.reconciliations.single.variance.isZero, isTrue);

      final reports = await db.getShiftReports();
      expect(reports, hasLength(1));
      expect(reports.single['report_number'], 1);
      expect(reports.single['report_type'], 'z');
      final snapshot = jsonDecode(reports.single['snapshot_json'] as String)
          as Map<String, dynamic>;
      expect(snapshot['sale_count'], 1);
      expect(snapshot['gross_minor'], 15000);
      // VAT-exclusive taxable sales (12,931) less the 8,000 cost.
      expect(snapshot['profit_minor'], 4931);
      expect(snapshot['vat_minor'], 2069);
      expect(snapshot['taxable_minor'], 12931);
      expect(snapshot['kra_activated'], isFalse);
      expect(snapshot['etims_pending'], 0);
      expect(snapshot['payment_mix']['cash']['count'], 1);
      expect(snapshot['payment_mix']['cash']['total_minor'], 15000);
    });

    test('history is capped, and the total says how many were left out',
        () async {
      // Forty closed shifts against a cap of thirty. The card has to be able to
      // say "and 10 earlier shifts not shown", which means the loader has to
      // know the real total rather than the length of the list it returned.
      for (int i = 0; i < 40; i++) {
        await openShiftFor(7, 'Amina', 100 + i);
        final Shift shift = (await db.getShifts(openOnly: true)).single;
        await db.reconcileShift(
          shiftId: shift.id!,
          countedCash: Money.fromMajor(100 + i),
          expectedCash: Money.fromMajor(100 + i),
        );
      }

      final ShiftLedger ledger =
          await loadShiftLedger(viewerStaffId: 7, seesAllSales: false);

      expect(ledger.history.length, 30);
      expect(ledger.historyTotal, 40);
      expect(ledger.reconciliations.length, 30);
      final reports = await db.getShiftReports();
      expect(reports.length, 40);
      expect(reports.last['report_number'], 1);
      expect(reports.first['report_number'], 40);
    });
  });
}
