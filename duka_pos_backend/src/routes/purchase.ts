/**
 * Purchases: stock arriving at the shop, and what it cost.
 *
 * ## WHY THE COST IS THE POINT
 *
 * A shop that only remembers quantities cannot price what it sells. Stock
 * that arrived at 90 and stock that arrived at 110 are the same bottle and
 * different money, and the profit on every later sale is measured against
 * the price the shop paid.
 *
 * So each line carries the cost it arrived at, and the total carries the cost
 * of the whole delivery. The till's stock ledger can then value what is on
 * the shelf without asking the owner to remember a number from three weeks
 * ago.
 */
import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import { parseBody, purchaseSchema } from '../lib/validation';
import { requireRole } from '../middleware/auth';
import { announceChange } from '../lib/live';
import { majorFromMinor, minorFromMajor } from '../lib/money';

const router = Router();

// ---------------------------------------------------------------------------
// Record a purchase
// ---------------------------------------------------------------------------

router.post('/', requireRole('admin', 'manager'), asyncHandler(async (req: Request, res: Response) => {
  const body = parseBody(purchaseSchema, req.body);
  const tenantId = req.user!.tenantId;

  const created = await prisma.$transaction(async (tx) => {
    // Idempotent by the till's own id, like every other record the till
    // writes: a re-push of the same delivery must not double the stock.
    const existing = await tx.purchase.findFirst({
      where: { tenantId, localId: body.localId },
      select: { id: true },
    });

    const data = {
      supplierName: body.supplierName,
      invoiceNumber: body.invoiceNumber ?? null,
      total: majorFromMinor(body.total),
      staffId: body.staffProfileId ?? null,
      staffName: body.staffName,
      createdAt: new Date(body.createdAt),
    };

    const saved = existing
      ? await tx.purchase.update({ where: { id: existing.id }, data })
      : await tx.purchase.create({
          data: { ...data, tenantId, localId: body.localId },
        });

    await tx.purchaseItem.deleteMany({ where: { purchaseId: saved.id } });
    for (const item of body.items) {
      await tx.purchaseItem.create({
        data: {
          tenantId,
          purchaseId: saved.id,
          productId: item.productId ?? null,
          productName: item.productName,
          qty: item.qty,
          unitCost: majorFromMinor(item.unitCost),
        },
      });
    }

    return saved;
  });

  announceChange([tenantId], 'purchases');

  return res.json({ purchaseId: created.id, localId: body.localId });
}));

// ---------------------------------------------------------------------------
// Read the purchases back
// ---------------------------------------------------------------------------

router.get('/', requireRole('admin', 'manager'), asyncHandler(async (req: Request, res: Response) => {
  const from = typeof req.query.from === 'string' ? new Date(req.query.from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const to = typeof req.query.to === 'string' ? new Date(req.query.to) : new Date();
  if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from > to) {
    return res.status(400).json({ error: 'Invalid report date range' });
  }
  const limit = Math.min(Math.max(Number(req.query.limit) || 200, 1), 500);

  const purchases = await prisma.purchase.findMany({
    where: {
      tenantId: req.user!.tenantId,
      createdAt: { gte: from, lte: to },
    },
    include: { items: true },
    orderBy: { createdAt: 'asc' },
    take: limit,
  });

  return res.json({
    from: from.toISOString(),
    to: to.toISOString(),
    purchases: purchases.map((purchase) => ({
      remoteId: purchase.id,
      localId: purchase.localId,
      supplierName: purchase.supplierName,
      invoiceNumber: purchase.invoiceNumber,
      total: minorFromMajor(purchase.total),
      staffName: purchase.staffName,
      createdAt: purchase.createdAt.toISOString(),
      items: purchase.items.map((item) => ({
        productName: item.productName,
        qty: Number(item.qty),
        unitCost: minorFromMajor(item.unitCost),
      })),
    })),
  });
}));

export default router;
