import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import { parseBody, productSyncSchema, stockAdjustmentSchema } from '../lib/validation';
import { requireRole } from '../middleware/auth';
import { announceChange } from '../lib/live';

const router = Router();

router.post('/sync', requireRole('admin', 'manager'), asyncHandler(async (req: Request, res: Response) => {
  const { products } = parseBody(productSyncSchema, req.body);
  const tenantId = req.user!.tenantId;

  // Stock is owned by the server: it is decremented by M-Pesa finalization and
  // adjusted through explicit endpoints. A till's cached count can be stale the
  // moment a sale is confirmed, so accepting it here would resurrect units that
  // have already been sold and re-enable overselling. Only the catalogue is
  // synced; `stockQty` is honoured on first insert only.
  const remoteIds = products
    .map((product) => product.remoteId)
    .filter((id): id is string => typeof id === 'string' && id.length > 0);

  // One lookup for the whole batch instead of a findFirst per product.
  const existing = remoteIds.length
    ? await prisma.product.findMany({ where: { id: { in: remoteIds }, tenantId }, select: { id: true } })
    : [];
  const existingIds = new Set(existing.map((product) => product.id));

  const owned = remoteIds.filter((id) => !existingIds.has(id));
  if (owned.length) {
    return res.status(400).json({ error: 'One or more products do not belong to this shop' });
  }

  const synced = await prisma.$transaction(async (tx) => {
    const result: Array<{ localId?: number; remoteId: string }> = [];
    for (const product of products) {
      if (product.remoteId) {
        const updated = await tx.product.update({
          where: { id: product.remoteId },
          data: {
            name: product.name,
            category: product.category,
            costPrice: product.costPrice,
            sellPrice: product.sellPrice,
            reorderLevel: product.reorderLevel,
            bottleMl: product.bottleMl,
            halfPrice: product.halfPrice,
            quarterPrice: product.quarterPrice,
            exciseStampBatch: product.exciseStampBatch,
            active: product.active,
          },
        });
        result.push({ localId: product.id, remoteId: updated.id });
      } else {
        const created = await tx.product.create({ data: { tenantId, name: product.name, category: product.category, costPrice: product.costPrice, sellPrice: product.sellPrice, stockQty: product.stockQty, reorderLevel: product.reorderLevel, bottleMl: product.bottleMl, halfPrice: product.halfPrice, quarterPrice: product.quarterPrice, exciseStampBatch: product.exciseStampBatch, active: product.active } });
        result.push({ localId: product.id, remoteId: created.id });
      }
    }
    return result;
  });
  // After the write, and only because it succeeded: a stream told about a
  // catalogue that failed to save is a stream chasing a change that never
  // happened. See lib/live.ts.
  announceChange([tenantId], 'products');
  return res.json({ synced });
}));

router.get('/', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const products = await prisma.product.findMany({ where: { tenantId: req.user!.tenantId }, orderBy: { name: 'asc' } });
  return res.json(products);
}));

// Records a stock correction made at the till.
//
// This is the only way stock moves on the server apart from M-Pesa
// finalization. `/products/sync` no longer carries `stockQty` for existing
// rows, so without this endpoint a break, a delivery or a stock count would
// only ever exist on the till that made it.
//
// The update is conditional on sufficient stock, matching `finalizeSale`, so a
// correction can never drive stock negative — the local `adjustStock` enforces
// the same rule, and this keeps the server honest if a second device races it.
router.post('/stock-adjust', requireRole('admin', 'manager'), asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(stockAdjustmentSchema, req.body);
  const tenantId = req.user!.tenantId;

  // The cashier label is resolved server-side, never taken from the request.
  const staffId = input.staff_profile_id ?? req.user!.id;
  const staff = await prisma.profile.findFirst({
    where: { id: staffId, tenantId, active: true, deletedAt: null },
  });
  if (!staff) return res.status(403).json({ error: 'Cashier profile is not active' });
  if (req.user!.role === 'cashier' && staff.id !== req.user!.id) {
    return res.status(403).json({ error: 'A cashier may only record adjustments under their own profile' });
  }

  // Read first so a missing product or an impossible correction gets a
  // meaningful status rather than a generic 500 from inside the transaction.
  const product = await prisma.product.findFirst({
    where: { id: input.product_id, tenantId },
    select: { id: true, name: true, stockQty: true },
  });
  if (!product) return res.status(404).json({ error: 'Product not found' });
  if (Number(product.stockQty) + input.delta < 0) {
    return res.status(409).json({ error: `Stock cannot go below zero for ${product.name}` });
  }

  const result = await prisma.$transaction(async (tx) => {
    // The predicate repeats the stock check so a concurrent sale or a second
    // device cannot drive the count negative between the read and the write.
    const updated = await tx.product.updateMany({
      where: { id: product.id, tenantId, stockQty: { gte: -input.delta } },
      data: { stockQty: { increment: input.delta } },
    });
    if (updated.count !== 1) {
      const conflict = Object.assign(new Error('Stock conflict'), { status: 409 });
      throw conflict;
    }
    const adjustment = await tx.stockAdjustment.create({
      data: {
        tenantId,
        productId: product.id,
        productName: product.name,
        delta: input.delta,
        reason: input.reason,
        staffId: staff.id,
      },
    });
    return { adjustmentId: adjustment.id, stockQty: Number(product.stockQty) + input.delta };
  });
  announceChange([tenantId], 'stock');

  return res.status(201).json(result);
}));

export default router;
