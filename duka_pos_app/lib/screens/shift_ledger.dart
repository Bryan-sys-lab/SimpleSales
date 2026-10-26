// What the till knows about shifts, resolved into one value.
//
// The screen does not query anything itself. It asks for a [ShiftLedger] and
// renders it, which means:
//
//   * The rules that decide what a manager sees and what a cashier sees are unit
//     testable in plain Dart, with no widget, no fake-async zone, and no
//     `pumpAndSettle`.
//   * The presentation can be rendered in a test from a constructed ledger, so
//     the layout matrix never depends on a database being seeded correctly
//     first — which is the trap that makes a screen "untestable" and therefore
//     never tested at any scale above 1.0x.
//
// The alternative — a `staffLoader`-style seam on the widget — was tried on
// `LoginScreen` and is worse: it puts a production parameter that exists only
// for a test, and it still cannot cover the four other queries this screen makes.

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../utils/money.dart';
import 'shift_history_card.dart' show kShiftHistoryLimit;
import 'shift_variance.dart';

/// Everything the shift screen shows, as one immutable value.
@immutable
class ShiftLedger {
  const ShiftLedger({
    required this.open,
    required this.expected,
    required this.counted,
    required this.history,
    required this.historyTotal,
    required this.reconciliations,
    this.cashControls = const <CashControlEntry>[],
  });

  /// A till with no shift and no history. The value a failed load falls back to
  /// only when the screen has nothing else to keep.
  const ShiftLedger.empty()
      : open = null,
        expected = Money.zero,
        counted = null,
        history = const <Shift>[],
        historyTotal = 0,
        reconciliations = const <Reconciliation>[],
        cashControls = const <CashControlEntry>[];

  /// The signed-in person's open shift, or null.
  final Shift? open;

  /// What the drawer should hold in it.
  ///
  /// Composed by `DatabaseHelper.expectedTillBalance`, never here: forgetting the
  /// opening float produces a variance exactly equal to the float, which is a
  /// large, confident-looking, entirely wrong number.
  final Money expected;

  /// The most recent denomination count, or null when the drawer has never been
  /// counted this shift.
  ///
  /// Null is NOT zero. An uncounted drawer and a counted-and-empty drawer are
  /// different states, and rendering the first as the second would tell a cashier
  /// their empty drawer is KSh 5,000 short.
  final Money? counted;

  /// The newest [kShiftHistoryLimit] CLOSED shifts.
  final List<Shift> history;

  /// Every closed shift on record, so the card can say what it left out.
  final int historyTotal;

  final List<Reconciliation> reconciliations;
  final List<CashControlEntry> cashControls;

  bool get hasOpenShift => open != null;

  /// The difference between the last count and what should be there.
  ///
  /// [ShiftVariance.notCounted] rather than a zero difference whenever there is
  /// no count to compare, which is the state a naive `counted - expected` gets
  /// most dangerously wrong.
  ShiftVariance variance(AppLocalizations l10n) {
    final Money? count = counted;
    if (open == null || count == null) return ShiftVariance.notCounted(l10n);
    return ShiftVariance.between(l10n, count, expected);
  }
}

/// Reads every figure the shift screen needs, in one call.
///
/// [viewerStaffId] and [seesAllSales] decide the SCOPE, not the filter: a manager
/// and an owner see the whole shop's shifts, while a cashier sees only their own,
/// because "your shift balanced" is not a question anyone else gets to audit from
/// this screen.
Future<ShiftLedger> loadShiftLedger({
  required int? viewerStaffId,
  required bool seesAllSales,
}) async {
  final DatabaseHelper db = DatabaseHelper.instance;

  final List<Shift> shifts = await db.getShifts(
    staffId: seesAllSales ? null : viewerStaffId,
  );

  final Shift? open =
      shifts.where((Shift shift) => shift.status == 'open').firstOrNull;
  final List<Shift> closed = shifts
      .where((Shift shift) => shift.status != 'open')
      .toList(growable: false);

  // One round trip rather than a cascade of dependent ones: the three reads do
  // not depend on each other, and a shift screen that resolves in three dependent
  // frames is three frames of a wrong figure on a screen nobody re-reads.
  final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
    open == null
        ? Future<Object?>.value(Money.zero)
        : db.expectedTillBalance(open),
    open?.id == null
        ? Future<Object?>.value(Money.zero)
        : db.countedCashFromTillCounts(open!.id!),
    _reconciliationsFor(db, closed),
    open?.id == null
        ? Future<Object?>.value(const <CashControlEntry>[])
        : _cashControlsFor(db, open!.id!),
  ]);

  final Money counted = results[1]! as Money;

  return ShiftLedger(
    open: open,
    expected: results[0]! as Money,
    // Zero means "no piles were recorded", which is different from a recorded
    // count of nothing. Only a real row can make the drawer empty.
    counted: counted.isZero ? null : counted,
    history: closed.take(kShiftHistoryLimit).toList(growable: false),
    historyTotal: closed.length,
    reconciliations: results[2]! as List<Reconciliation>,
    cashControls: results[3]! as List<CashControlEntry>,
  );
}

@immutable
class CashControlEntry {
  const CashControlEntry({
    required this.label,
    required this.amountMinor,
    required this.isExpense,
  });

  final String label;
  final int amountMinor;
  final bool isExpense;
}

Future<List<CashControlEntry>> _cashControlsFor(
  DatabaseHelper db,
  int shiftId,
) async {
  final results = await Future.wait<List<Map<String, dynamic>>>(<Future<List<Map<String, dynamic>>>>[
    db.getExpensesForShift(shiftId),
    db.getTillMovementsForShift(shiftId),
    db.getDrawerEvents(shiftId: shiftId),
  ]);
  final entries = <CashControlEntry>[
    for (final row in results[0])
      CashControlEntry(
        label: (row['note'] as String?)?.trim().isNotEmpty == true
            ? row['note'] as String
            : 'Expense',
        amountMinor: -(row['amount_minor'] as num).toInt(),
        isExpense: true,
      ),
    for (final row in results[1])
      CashControlEntry(
        label: (row['movement_type'] as String?) == 'cash_in'
            ? 'Cash in'
            : 'Cash drop',
        amountMinor: (row['amount_minor'] as num).toInt(),
        isExpense: false,
      ),
    if (results[2].where((row) => row['event_type'] == 'no_sale').isNotEmpty)
      CashControlEntry(
        label:
            'No-sale drawer opens (${results[2].where((row) => row['event_type'] == 'no_sale').length})',
        amountMinor: 0,
        isExpense: false,
      ),
  ];
  return entries;
}

/// The reconciliation rows behind [closed], newest first.
///
/// Capped at the same [kShiftHistoryLimit] the ledger shows, so "reconciliations"
/// is never a longer list than "past shifts" describing the same days.
Future<List<Reconciliation>> _reconciliationsFor(
  DatabaseHelper db,
  List<Shift> closed,
) async {
  final List<Reconciliation> loaded = <Reconciliation>[];
  for (final Shift shift in closed.take(kShiftHistoryLimit)) {
    final int? id = shift.id;
    if (id == null) continue;
    loaded.addAll(await db.getReconciliationsForShift(id));
  }
  loaded.sort((Reconciliation a, Reconciliation b) =>
      b.recordedAt.compareTo(a.recordedAt));
  return loaded.take(kShiftHistoryLimit).toList(growable: false);
}
