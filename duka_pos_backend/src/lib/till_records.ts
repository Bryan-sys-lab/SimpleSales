// The till's records: the pure arithmetic, with no Prisma and no Express.
//
// The till's ledger, its drawers, its returns, its deliveries and its shot
// cups all have one thing in common: the till writes them OFFLINE, on the
// phone, and pushes them when the phone can reach the server. A phone that
// was offline pushes the same records again — that is the whole mechanism —
// so the server has to be able to tell a re-push from a new record, or a
// week's takings become two weeks of takings the moment the signal comes
// back.
//
// ## THE ONE RULE
//
// `localId` is the till's own id for the record, and it is unique WITHIN a
// shop. Every function here is about that rule:
//
//   * `mergeByLocalId` decides, for a batch of pushed records, which are NEW
//     and which are UPDATES to a record the server already has;
//   * `rollUpShifts` adds up the drawers, which is the figure the shift
//     analytics is about — the DIFFERENCE between the cash the ledger says
//     should have been in the drawer and the cash that was actually counted.
//
// The arithmetic lives here so it can be tested without a database, and so the
// route that reads rows stays a thin adapter over it — the same rule the
// portfolio roll-up follows.

/** One record the till pushed, in the shape the server stores it. */
export interface PushedRecord {
  /** The till's own id for this record. */
  localId: number;
}

/** What a merge decided about one pushed record. */
export interface MergeDecision {
  localId: number;
  /** True when the server already had this record. */
  isUpdate: boolean;
}

/**
 * Decides, for a batch of pushed records, which are new and which are
 * updates.
 *
 * The server's existing local ids come in as a set. A pushed record whose id
 * is in that set is an UPDATE — the server already has it, and the push
 * corrects the row rather than making a second one. A pushed record whose id
 * is NOT in that set is NEW.
 *
 * A batch that contains the same local id twice is a push that was assembled
 * twice, and the LATER one wins: the phone had newer information when it sent
 * it. That is why the last occurrence overwrites the earlier one in the map
 * below rather than the first one being kept.
 */
export function mergeByLocalId(
  pushed: PushedRecord[],
  existingLocalIds: ReadonlySet<number>,
): MergeDecision[] {
  const lastSeen = new Map<number, PushedRecord>();
  for (const record of pushed) {
    lastSeen.set(record.localId, record);
  }
  return [...lastSeen.values()].map((record) => ({
    localId: record.localId,
    isUpdate: existingLocalIds.has(record.localId),
  }));
}

/** One shift, in minor units, as the server holds it. */
export interface ShiftTotals {
  localId: number;
  staffName: string;
  status: string;
  expectedCash: number;
  countedCash: number;
}

/** The drawers, added up. */
export interface ShiftRollUp {
  /** How many shifts ran. */
  shifts: number;
  /** How many of them were closed. */
  closed: number;
  /** How many of them were counted. */
  counted: number;
  /** The cash the ledger says should have been in the drawers, in minor units. */
  expected: number;
  /** The cash that was actually counted, in minor units. */
  countedCash: number;
  /**
   * The difference: counted minus expected.
   *
   * Negative is short, and short is the direction that can mean money left
   * the shop. ONE drawer short by KSh 50 is an accident; every drawer short
   * by KSh 50 is a problem with the till, and it is invisible until the
   * differences are added up.
   */
  variance: number;
}

/**
 * Adds up the drawers.
 *
 * A shift that was never counted contributes NOTHING to the cash figures —
 * not a zero. A zero would say the drawer balanced, which is the worst
 * possible reading of a drawer nobody opened.
 */
export function rollUpShifts(shifts: ShiftTotals[]): ShiftRollUp {
  let expected = 0;
  let countedCash = 0;
  let counted = 0;
  let closed = 0;
  for (const shift of shifts) {
    if (shift.status !== 'open') closed += 1;
    // A shift that was closed but never counted has no figure, so it is not
    // in the totals — and `counted` says how many were.
    if (shift.expectedCash === 0 && shift.countedCash === 0) continue;
    expected += shift.expectedCash;
    countedCash += shift.countedCash;
    counted += 1;
  }
  return {
    shifts: shifts.length,
    closed,
    counted,
    expected,
    countedCash,
    variance: countedCash - expected,
  };
}

/** One line of a return, in minor units. */
export interface ReturnLine {
  qty: number;
  unitPrice: number;
  unitCost: number;
}

/** What a return costs the shop. */
export interface ReturnTotals {
  /** The money given back, in minor units. */
  total: number;
  /** The margin given back, in minor units — what the return actually cost. */
  profit: number;
}

/**
 * Totals a return from its lines.
 *
 * The money and the margin are computed from the LINES, not taken from the
 * body: a return that claims one figure and carries lines that add up to
 * another is a return the books cannot explain, and the lines are the part
 * that came from the till.
 *
 * The margin is the cost of the goods, times the quantity returned: what the
 * shop gave back in PROFIT is the margin on those goods, not the money.
 */
export function totalsForReturn(lines: ReturnLine[]): ReturnTotals {
  let total = 0;
  let profit = 0;
  for (const line of lines) {
    total += Math.round(line.qty * line.unitPrice);
    profit += Math.round(line.qty * line.unitCost);
  }
  return { total, profit };
}
