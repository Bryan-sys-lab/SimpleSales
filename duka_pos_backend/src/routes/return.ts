/**
 * Returns and credit notes: money and stock going back to the shop.
 *
 * ## THE TWO KINDS
 *
 * A REFUND hands the money back. A CREDIT NOTE leaves the customer holding
 * the goods and the shop owing them — the sale comes off the books and the
 * customer comes back for it later. The till treats them differently, and so
 * does the tax authority, so the kind is recorded rather than inferred.
 *
 * ## WHY THE ORIGINAL SALE IS NAMED
 *
 * A return with no sale behind it is money the shop has invented. The sale's
 * local id is kept so the ledger can be read as a whole: what the shop took,
 * and what it gave back, and the difference.
 */
import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma.js';
import { asyncHandler } from '../lib/http.js';
import { parseBody, returnSchema } from '../lib/validation.js';
import { requireRole } from '../middleware/auth.js';
import { announceChange } from '../lib/live.js';
import { majorFromMinor, minorFromMajor } from '../lib/money.js';

const router = Router();

// ---------------------------------------------------------------------------
// Record a return
// ---------------------------------------------------------------------------

router.post('/', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const body = parseBody(returnSchema, req.body);
  const tenantId = req.user!.tenantId;

  // The sale being returned, when the server has it. The till names the sale
  // by its own id, because the till wrote the sale.
  const originalSale = body.originalSaleLocalId
    ? await prisma.sale.findFirst({
        where: { tenantId, localId: body.originalSaleLocalId },
        select: { id: true },
      })
    : null;

  const created = await prisma.$transaction(async (tx) => {
    // Idempotent by the till's own id: a re-push of the same return updates
    // it rather than making a second one.
    const existing = await tx.return.findFirst({
      where: { tenantId, localId: body.localId },
      select: { id: true },
    });

    const data = {
      originalSaleLocalId: body.originalSaleLocalId ?? null,
      kind: body.kind,
      reason: body.reason,
      total: majorFromMinor(body.total),
      profit: majorFromMinor(body.profit),
      staffId: body.staffProfileId ?? null,
      staffName: body.staffName,
      createdAt: new Date(body.createdAt),
    };

    const saved = existing
      ? await tx.return.update({ where: { id: existing.id }, data })
      : await tx.return.create({
          data: { ...data, tenantId, localId: body.localId },
        });

    await tx.returnItem.deleteMany({ where: { returnId: saved.id } });
    for (const item of body.items) {
      await tx.returnItem.create({
        data: {
          tenantId,
          returnId: saved.id,
          productId: item.productId ?? null,
          productName: item.productName,
          qty: item.qty,
          unitPrice: majorFromMinor(item.unitPrice),
          unitCost: majorFromMinor(item.unitCost),
          portion: item.portion,
          portionMl: item.portionMl,
        },
      });
    }

    return saved;
  });

  announceChange([tenantId], 'returns');

  return res.json({
    returnId: created.id,
    localId: body.localId,
    originalSaleRemoteId: originalSale?.id ?? null,
  });
}));

// ---------------------------------------------------------------------------
// Read the returns back
// ---------------------------------------------------------------------------

router.get('/', requireRole('admin', 'manager'), asyncHandler(async (req: Request, res: Response) => {
  const from = typeof req.query.from === 'string' ? new Date(req.query.from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const to = typeof req.query.to === 'string' ? new Date(req.query.to) : new Date();
  if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from > to) {
    return res.status(400).json({ error: 'Invalid report date range' });
  }
  const limit = Math.min(Math.max(Number(req.query.limit) || 200, 1), 500);

  const returns = await prisma.return.findMany({
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
    returns: returns.map((entry) => ({
      remoteId: entry.id,
      localId: entry.localId,
      originalSaleLocalId: entry.originalSaleLocalId,
      kind: entry.kind,
      reason: entry.reason,
      total: minorFromMajor(entry.total),
      profit: minorFromMajor(entry.profit),
      staffName: entry.staffName,
      createdAt: entry.createdAt.toISOString(),
      items: entry.items.map((item) => ({
        productName: item.productName,
        qty: Number(item.qty),
        unitPrice: minorFromMajor(item.unitPrice),
        unitCost: minorFromMajor(item.unitCost),
        portion: item.portion,
        portionMl: item.portionMl,
      })),
    })),
  });
}));

export default router;
