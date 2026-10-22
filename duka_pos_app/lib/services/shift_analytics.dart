// The shifts in a window, and what the drawers did.
//
// ## WHY THIS IS HERE
//
// "Make sure in cross shop the shifts are shown and also in analytics too
// (shift analytics)."
//
// The shift screen answers "how is MY drawer doing" — one shift, one drawer,
// one count. It does not answer the question an owner has after a week: "were
// my drawers coming out right?"
//
// A week of shifts has a figure in it that no single shift has — the
// DIFFERENCE between the cash the ledger says should have been in the drawer
// and the cash that was actually counted. One drawer being short by KSh 50 is
// an accident. Every drawer being short by KSh 50, every day, is a problem
// with the till, and it is invisible until the figures are added up.
//
// ## THE SCOPE
//
// A cashier's own shifts, or the whole shop's — the same rule as the rest of
// the analytics, and for the same reason: "your shift balanced" is not a
// question anyone else gets to audit from this screen.
//
// ## WHAT IS COUNTED
//
// The shifts that STARTED in the window, and the reconciliations recorded
// against them. A shift that started before the window and closed inside it
// is counted by when it CLOSED, because the money that was counted is the
// money of the closing — a week that ends mid-shift has to include that
// shift's count, or the week's total silently excludes the day the drawer was
// short.

import '../db/database_helper.dart';
import '../models/models.dart';
import '../utils/money.dart';

/// The shifts over a window, and what the drawers did.
class ShiftAnalytics {
  const ShiftAnalytics({
    required this.shifts,
    required this.closed,
    required this.reconciled,
    required this.expected,
    required this.counted,
  });

  /// No shifts at all.
  const ShiftAnalytics.empty()
      : shifts = 0,
        closed = 0,
        reconciled = 0,
        expected = Money.zero,
        counted = Money.zero;

  /// How many shifts ran in the window.
  final int shifts;

  /// How many of them were closed.
  final int closed;

  /// How many of them were reconciled — counted and signed off.
  final int reconciled;

  /// The cash the ledger says should have been in the drawers, in total.
  final Money expected;

  /// The cash that was actually counted, in total.
  final Money counted;

  /// The difference, counted minus expected.
  ///
  /// Negative is short. It is the figure the whole card exists for: a drawer
  /// that is short by KSh 50 every day is a till that is losing money, and
  /// adding the differences up is the only way to see it.
  Money get variance => counted - expected;

  /// Whether there is anything to say.
  ///
  /// A window with no shifts says nothing, which is different from a window
  /// whose shifts balanced: one is "no shifts", the other is "KSh 0
  /// difference", and the card says which.
  bool get hasShifts => shifts > 0;

  /// Whether anything was reconciled at all.
  ///
  /// A shift that was closed but never counted has no figure, and the card
  /// must not present a variance that only covers part of the shifts.
  bool get hasCounts => reconciled > 0;
}

/// Reads the shifts over a window.
Future<ShiftAnalytics> loadShiftAnalytics({
  required DateTime from,
  required DateTime to,
  int? staffId,
}) async {
  final DatabaseHelper db = DatabaseHelper.instance;
  final List<Shift> all = await db.getShifts(staffId: staffId);

  final DateTime start = from;
  final DateTime end = to;
  bool startedIn(Shift shift) {
    final DateTime? started = DateTime.tryParse(shift.startTime);
    return started != null && !started.isBefore(start) && !started.isAfter(end);
  }

  bool closedIn(Shift shift) {
    if (shift.status == 'open') return false;
    final DateTime? ended = DateTime.tryParse(shift.endTime ?? '');
    if (ended == null) return false;
    return !ended.isBefore(start) && !ended.isAfter(end);
  }

  // A shift that ran across the window belongs to it — counted by when it
  // closed, because the count is what happened at the close.
  final List<Shift> inWindow = all
      .where((Shift shift) => startedIn(shift) || closedIn(shift))
      .toList(growable: false);

  int expectedMinor = 0;
  int countedMinor = 0;
  int reconciled = 0;
  for (final Shift shift in inWindow) {
    final int? id = shift.id;
    if (id == null) continue;
    final List<Reconciliation> rows = await db.getReconciliationsForShift(id);
    if (rows.isEmpty) continue;
    // The LAST reconciliation is the one that was signed off: a drawer can be
    // counted twice while the person checks the figure, and the later count
    // replaces the earlier one.
    final Reconciliation last = rows.first;
    expectedMinor += last.expectedCash.minorUnits;
    countedMinor += last.countedCash.minorUnits;
    reconciled++;
  }

  return ShiftAnalytics(
    shifts: inWindow.length,
    closed: inWindow.where((Shift shift) => shift.status != 'open').length,
    reconciled: reconciled,
    expected: Money.fromMinor(expectedMinor),
    counted: Money.fromMinor(countedMinor),
  );
}
