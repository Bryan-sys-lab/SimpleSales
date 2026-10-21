/**
 * Shifts: a drawer, and the people who worked it.
 *
 * ## WHY THIS ENDPOINT EXISTS
 *
 * "We should allow offline shifts to open, so that if a shop only uses one
 * device with all staff on it they can open shifts and can be synced when
 * online together with the other sync."
 *
 * The till's half was already true — a shift opens on the phone, in the
 * phone's own database, with no server involved. What was missing was the
 * other half: the shift never left the phone, so the owner could not see a
 * drawer that had been counted on another device, and the week's shift
 * figures were whatever that one phone happened to know.
 *
 * So the shift is pushed, and the push is idempotent for the same reason the
 * ledger's is: a phone that was offline pushes the same shift again.
 *
 * ## THE FIGURE THIS IS FOR
 *
 * The difference between the cash the ledger says should have been in the
 * drawer and the cash that was actually counted. ONE drawer short by KSh 50 is
 * an accident. Every drawer short by KSh 50, every day, is a problem with
 * the till — and it is invisible until the differences are added up. That
 * addition is `rollUpShifts`, in lib/till_records.ts.
 */
import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import { parseBody, shiftSyncSchema } from '../lib/validation';
import { requireRole } from '../middleware/auth';
import { announceChange } from '../lib/live';
import { majorFromMinor, minorFromMajor } from '../lib/money';
import { mergeByLocalId, rollUpShifts, type ShiftTotals } from '../lib/till_records';

const router = Router();

// ---------------------------------------------------------------------------
// Push the till's shifts
// ---------------------------------------------------------------------------

router.post('/sync', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const { shifts } = parseBody(shiftSyncSchema, req.body);
  const tenantId = req.user!.tenantId;

  const localIds = shifts.map((shift) => shift.localId);
  const existing = await prisma.shift.findMany({
    where: { tenantId, localId: { in: localIds } },
    select: { id: true, localId: true },
  });
  const existingByLocalId = new Map<number, string>();
  for (const shift of existing) {
    existingByLocalId.set(shift.localId, shift.id);
  }
  const decisions = mergeByLocalId(shifts, new Set(existingByLocalId.keys()));
  const decisionByLocalId = new Map(decisions.map((d) => [d.localId, d]));

  const synced = await prisma.$transaction(async (tx) => {
    const result: Array<{ localId: number; remoteId: string }> = [];
    for (const shift of shifts) {
      const knownId = existingByLocalId.get(shift.localId);
      const isUpdate = decisionByLocalId.get(shift.localId)?.isUpdate === true;

      const data = {
        staffName: shift.staffName,
        staffId: shift.staffProfileId ?? null,
        startTime: new Date(shift.startTime),
        endTime: shift.endTime ? new Date(shift.endTime) : null,
        startFloat: majorFromMinor(shift.startFloat),
        endFloat: majorFromMinor(shift.endFloat),
        expectedCash: majorFromMinor(shift.expectedCash),
        countedCash: majorFromMinor(shift.countedCash),
        status: shift.status,
      };

      const saved = knownId && isUpdate
        ? await tx.shift.update({ where: { id: knownId }, data })
        : await tx.shift.create({
            data: { ...data, tenantId, localId: shift.localId },
          });

      result.push({ localId: shift.localId, remoteId: saved.id });
    }
    return result;
  });

  announceChange([tenantId], 'shifts');

  return res.json({ synced });
}));

// ---------------------------------------------------------------------------
// Read the shifts back
// ---------------------------------------------------------------------------

router.get('/', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const from = typeof req.query.from === 'string' ? new Date(req.query.from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const to = typeof req.query.to === 'string' ? new Date(req.query.to) : new Date();
  if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from > to) {
    return res.status(400).json({ error: 'Invalid report date range' });
  }
  const limit = Math.min(Math.max(Number(req.query.limit) || 200, 1), 500);

  const shifts = await prisma.shift.findMany({
    where: {
      tenantId: req.user!.tenantId,
      // A cashier reads their own shifts. "Your shift balanced" is not a
      // question anyone else gets to audit.
      ...(req.user!.role === 'cashier' ? { staffName: req.user!.name } : {}),
      startTime: { gte: from, lte: to },
    },
    orderBy: { startTime: 'asc' },
    take: limit,
  });

  // The same roll-up the app does locally, so the two never disagree about
  // "how the week went".
  const rollUp = rollUpShifts(
    shifts.map((shift) => ({
      localId: shift.localId,
      staffName: shift.staffName,
      status: shift.status,
      expectedCash: minorFromMajor(shift.expectedCash),
      countedCash: minorFromMajor(shift.countedCash),
    })),
  );

  return res.json({
    from: from.toISOString(),
    to: to.toISOString(),
    shifts: shifts.map((shift) => ({
      remoteId: shift.id,
      localId: shift.localId,
      staffName: shift.staffName,
      startTime: shift.startTime.toISOString(),
      endTime: shift.endTime ? shift.endTime.toISOString() : null,
      startFloat: minorFromMajor(shift.startFloat),
      endFloat: minorFromMajor(shift.endFloat),
      expectedCash: minorFromMajor(shift.expectedCash),
      countedCash: minorFromMajor(shift.countedCash),
      // The difference between what should have been in the drawer and what
      // was: the figure the shift analytics is about.
      variance: minorFromMajor(shift.countedCash) - minorFromMajor(shift.expectedCash),
      status: shift.status,
    })),
    totals: {
      shifts: rollUp.shifts,
      closed: rollUp.closed,
      counted: rollUp.counted,
      expected: rollUp.expected,
      countedCash: rollUp.countedCash,
      variance: rollUp.variance,
    },
  });
}));

export default router;
