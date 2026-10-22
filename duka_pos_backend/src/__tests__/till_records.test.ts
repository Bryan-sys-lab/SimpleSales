// The till's records: the pure arithmetic behind them.
//
// These are the figures a till pushes and the server stores, and the rule
// that makes the push safe: the same record arriving twice is ONE record.
//
// The tests here are the ones that would catch a double-counted week.

import { describe, expect, it } from 'vitest';
import {
  mergeByLocalId,
  rollUpShifts,
  totalsForReturn,
  type ShiftTotals,
} from '../lib/till_records.js';
import { majorFromMinor, minorFromMajor, sumMinor } from '../lib/money.js';

describe('the push is idempotent', () => {
  it('knows a re-push from a new record', () => {
    // The server already has record 7; the till pushed 7 and 9.
    const decisions = mergeByLocalId(
      [{ localId: 7 }, { localId: 9 }],
      new Set([7]),
    );
    expect(decisions).toEqual([
      { localId: 7, isUpdate: true },
      { localId: 9, isUpdate: false },
    ]);
  });

  it('a record pushed twice in one batch is one record', () => {
    // A batch assembled twice — the phone sent the same sale in two pushes
    // that arrived together. The LATER one wins, because the phone had newer
    // information when it sent it.
    const decisions = mergeByLocalId(
      [{ localId: 7 }, { localId: 7 }],
      new Set(),
    );
    expect(decisions).toEqual([{ localId: 7, isUpdate: false }]);
  });

  it('a record the server has is an update even when it is pushed twice', () => {
    const decisions = mergeByLocalId(
      [{ localId: 7 }, { localId: 7 }],
      new Set([7]),
    );
    expect(decisions).toEqual([{ localId: 7, isUpdate: true }]);
  });
});

describe('the drawers, added up', () => {
  const shift = (over: Partial<ShiftTotals>): ShiftTotals => ({
    localId: 1,
    staffName: 'Amina',
    status: 'closed',
    expectedCash: 0,
    countedCash: 0,
    ...over,
  });

  it('adds up the differences across the shifts', () => {
    // Two shifts, each KSh 50 short. One drawer short by KSh 50 is an
    // accident; a week's worth of them is a problem with the till, and it is
    // invisible until the differences are added up.
    const rollUp = rollUpShifts([
      shift({ localId: 1, expectedCash: 50000, countedCash: 49500 }),
      shift({ localId: 2, expectedCash: 30000, countedCash: 29500 }),
    ]);
    expect(rollUp.shifts).toBe(2);
    expect(rollUp.closed).toBe(2);
    expect(rollUp.counted).toBe(2);
    expect(rollUp.expected).toBe(80000);
    expect(rollUp.countedCash).toBe(79000);
    expect(rollUp.variance).toBe(-1000);
  });

  it('a drawer that came out over is over, not short', () => {
    const rollUp = rollUpShifts([
      shift({ expectedCash: 20000, countedCash: 20500 }),
    ]);
    expect(rollUp.variance).toBe(500);
  });

  it('a shift that was never counted is not counted as a zero', () => {
    // The dangerous reading: "KSh 0 difference" for a drawer nobody counted.
    // A shift with no figure at all — closed, but never counted — contributes
    // nothing, and the count says how many were really counted.
    const rollUp = rollUpShifts([
      shift({ localId: 1, expectedCash: 20000, countedCash: 19500 }),
      shift({ localId: 2, expectedCash: 0, countedCash: 0 }),
    ]);
    expect(rollUp.shifts).toBe(2);
    expect(rollUp.closed).toBe(2);
    // Only the shift that WAS counted is in the cash figures.
    expect(rollUp.counted).toBe(1);
    expect(rollUp.variance).toBe(-500);
  });

  it('a drawer counted at zero against a full expectation is a real shortage', () => {
    // NOT the same as the case above: the drawer WAS counted, and what was in
    // it was nothing. That is KSh 20,000 missing, and it must be reported as
    // such — rounding it away would hide the worst day in the week.
    const rollUp = rollUpShifts([
      shift({ expectedCash: 20000, countedCash: 0 }),
    ]);
    expect(rollUp.counted).toBe(1);
    expect(rollUp.variance).toBe(-20000);
  });

  it('an open shift is a shift, but not a closed one', () => {
    const rollUp = rollUpShifts([
      shift({ localId: 1, status: 'open', expectedCash: 10000, countedCash: 0 }),
    ]);
    expect(rollUp.shifts).toBe(1);
    expect(rollUp.closed).toBe(0);
  });
});

describe('a return, totalled from its lines', () => {
  it('takes the money and the margin from the lines', () => {
    // Two bottles at KSh 100 that cost KSh 60: the shop gives back KSh 200
    // and gives back KSh 120 of margin.
    const totals = totalsForReturn([
      { qty: 2, unitPrice: 10000, unitCost: 6000 },
    ]);
    expect(totals.total).toBe(20000);
    expect(totals.profit).toBe(12000);
  });

  it('a partial return takes part of the line', () => {
    const totals = totalsForReturn([
      { qty: 0.5, unitPrice: 10000, unitCost: 6000 },
    ]);
    expect(totals.total).toBe(5000);
    expect(totals.profit).toBe(3000);
  });
});

describe('money at the boundary', () => {
  it('minor units become major units exactly', () => {
    // 40.55 shillings is 4055 cents, and it is exactly that — not
    // 40.549999999999997, which is what a float would have given.
    expect(majorFromMinor(4055).toString()).toBe('40.55');
    expect(majorFromMinor(0).toString()).toBe('0');
    expect(majorFromMinor(-150).toString()).toBe('-1.5');
  });

  it('major units come back as minor units', () => {
    expect(minorFromMajor(majorFromMinor(4055))).toBe(4055);
    expect(minorFromMajor(null)).toBe(0);
    expect(minorFromMajor(undefined)).toBe(0);
  });

  it('a value with a third decimal is rounded, not truncated', () => {
    // 40.554 becomes 4055 and not 4055.4 truncated to 4055 — and, more to the
    // point, not 405.55 becoming 4055 by truncation.
    expect(minorFromMajor(40.555)).toBe(4056);
  });

  it('the sum of minor amounts stays in minor units', () => {
    expect(sumMinor([1000, 2000, 3000])).toBe(6000);
    expect(sumMinor([])).toBe(0);
  });
});
