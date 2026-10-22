/**
 * Shot cups: a named serving poured from a drink.
 *
 * ## WHY THE SIZE IS OPTIONAL
 *
 * "Shot cup is set independently and does not require a ml setting (should be
 * optional for tracking profit per shot)."
 *
 * A shot cup is a NAME for a serving — "Single", "Double", "One shot" — and
 * the size in millilitres is the owner's business, not the app's. What the
 * size buys is exactness: with it, the app can work out what that much of the
 * drink cost to pour, so the profit on the shot is exact. Without it, the
 * shot is counted at its full price, because the drink that went into it is
 * not being measured.
 *
 * So zero means "not known", and it is a legal value.
 */
import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma.js';
import { asyncHandler } from '../lib/http.js';
import { parseBody, shotCupSyncSchema } from '../lib/validation.js';
import { requireRole } from '../middleware/auth.js';
import { announceChange } from '../lib/live.js';
import { majorFromMinor, minorFromMajor } from '../lib/money.js';
import { mergeByLocalId } from '../lib/till_records.js';

const router = Router();

// ---------------------------------------------------------------------------
// Push the till's shot cups
// ---------------------------------------------------------------------------

router.post('/sync', requireRole('admin', 'manager'), asyncHandler(async (req: Request, res: Response) => {
  const { shotCups } = parseBody(shotCupSyncSchema, req.body);
  const tenantId = req.user!.tenantId;

  const localIds = shotCups.map((cup) => cup.localId);
  const existing = await prisma.shotCup.findMany({
    where: { tenantId, localId: { in: localIds } },
    select: { id: true, localId: true },
  });
  const existingByLocalId = new Map<number, string>();
  for (const cup of existing) {
    existingByLocalId.set(cup.localId, cup.id);
  }
  const decisions = mergeByLocalId(shotCups, new Set(existingByLocalId.keys()));
  const decisionByLocalId = new Map(decisions.map((d) => [d.localId, d]));

  const synced = await prisma.$transaction(async (tx) => {
    const result: Array<{ localId: number; remoteId: string }> = [];
    for (const cup of shotCups) {
      const knownId = existingByLocalId.get(cup.localId);
      const isUpdate = decisionByLocalId.get(cup.localId)?.isUpdate === true;

      const data = {
        productId: cup.productId ?? '',
        productName: cup.productName,
        label: cup.label,
        capacityMl: cup.capacityMl,
        price: majorFromMinor(cup.price),
        active: cup.active,
      };

      const saved = knownId && isUpdate
        ? await tx.shotCup.update({ where: { id: knownId }, data })
        : await tx.shotCup.create({
            data: { ...data, tenantId, localId: cup.localId },
          });

      result.push({ localId: cup.localId, remoteId: saved.id });
    }
    return result;
  });

  announceChange([tenantId], 'shot-cups');

  return res.json({ synced });
}));

// ---------------------------------------------------------------------------
// Read the shot cups back
// ---------------------------------------------------------------------------

router.get('/', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const cups = await prisma.shotCup.findMany({
    where: { tenantId: req.user!.tenantId, active: true },
    orderBy: { productName: 'asc' },
  });

  return res.json({
    shotCups: cups.map((cup) => ({
      remoteId: cup.id,
      localId: cup.localId,
      productId: cup.productId,
      productName: cup.productName,
      label: cup.label,
      // Zero means the size is not known — and that is a legal answer, not a
      // missing one.
      capacityMl: cup.capacityMl,
      price: minorFromMajor(cup.price),
    })),
  });
}));

export default router;
