/**
 * Product routes: bulk sync, per-product stock adjustment, list.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody } from '../lib/validation';
import { productSyncSchema, stockAdjustSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { log } from '../lib/observability';

const router = Router();

// ---------------------------------------------------------------------------
// Bulk product sync (owner or manager)
// ---------------------------------------------------------------------------

router.post(
  '/sync',
  asyncHandler(async (req, res) => {
    const { products } = parseBody(productSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const synced = await prisma.$transaction(async (tx) => {
      const result: any[] = [];
      for (const product of products) {
        if (product.remoteId) {
          const existing = await tx.product.findFirst({ where: { id: product.remoteId, tenantId } });
          if (!existing) {
            throw new Error('Product does not belong to this shop');
          }
          const updated = await tx.product.update({
            where: { id: existing.id },
            data: {
              name: product.name,
              category: product.category,
              costPrice: product.costPrice,
              sellPrice: product.sellPrice,
              // Once a product exists remotely, stock is the sum of the
              // append-only movement stream. A cached offline snapshot must
              // never overwrite another till's movements.
              reorderLevel: product.reorderLevel,
              bottleMl: product.bottleMl,
              unit: product.unit,
              mlPerKg: product.mlPerKg,
              halfPrice: product.halfPrice,
              quarterPrice: product.quarterPrice,
              exciseStampBatch: product.exciseStampBatch,
              active: product.active,
            },
          });
          result.push({ localId: product.id, remoteId: updated.id });
        } else if (product.syncKey) {
          // The client key is stable across a lost response and a retry. The
          // upsert makes concurrent retries converge on one catalogue row;
          // stock is deliberately absent from update so only the first create
          // establishes the opening snapshot.
          const synced = await tx.product.upsert({
            where: {
              tenantId_syncKey: {
                tenantId,
                syncKey: product.syncKey,
              },
            },
            create: {
              tenantId,
              syncKey: product.syncKey,
              name: product.name,
              category: product.category,
              costPrice: product.costPrice,
              sellPrice: product.sellPrice,
              stockQty: product.openingStockQty ?? product.stockQty,
              reorderLevel: product.reorderLevel,
              bottleMl: product.bottleMl,
              unit: product.unit,
              mlPerKg: product.mlPerKg,
              halfPrice: product.halfPrice,
              quarterPrice: product.quarterPrice,
              exciseStampBatch: product.exciseStampBatch,
              active: product.active,
            },
            update: {
              name: product.name,
              category: product.category,
              costPrice: product.costPrice,
              sellPrice: product.sellPrice,
              reorderLevel: product.reorderLevel,
              bottleMl: product.bottleMl,
              unit: product.unit,
              mlPerKg: product.mlPerKg,
              halfPrice: product.halfPrice,
              quarterPrice: product.quarterPrice,
              exciseStampBatch: product.exciseStampBatch,
              active: product.active,
            },
          });
          result.push({ localId: product.id, remoteId: synced.id });
        } else {
          const created = await tx.product.create({
            data: {
              tenantId,
              name: product.name,
              category: product.category,
              costPrice: product.costPrice,
              sellPrice: product.sellPrice,
              stockQty: product.openingStockQty ?? product.stockQty,
              reorderLevel: product.reorderLevel,
              bottleMl: product.bottleMl,
              unit: product.unit,
              mlPerKg: product.mlPerKg,
              halfPrice: product.halfPrice,
              quarterPrice: product.quarterPrice,
              exciseStampBatch: product.exciseStampBatch,
              active: product.active,
            },
          });
          result.push({ localId: product.id, remoteId: created.id });
        }
      }
      return result;
    });
    return res.json({ synced });
  })
);

// ---------------------------------------------------------------------------
// Per-product stock adjustment (immediate, single write)
// ---------------------------------------------------------------------------

router.post(
  '/stock-adjust',
  asyncHandler(async (req, res) => {
    const { product_id, delta, reason, staff_profile_id } = parseBody(stockAdjustSchema, req.body);
    const tenantId = requireUser(req).tenantId;

    await prisma.$transaction(async (tx) => {
      // Do not read stock, calculate a new value, then overwrite it: two tills
      // can both read the same quantity and silently lose one adjustment.
      // PostgreSQL applies this conditional arithmetic update atomically, so a
      // decrement either reserves the remaining stock or loses the race.
      const updated = await tx.product.updateMany({
        where: {
          id: product_id,
          tenantId,
          ...(delta < 0 ? { stockQty: { gte: Math.abs(delta) } } : {}),
        },
        data: { stockQty: { increment: delta } },
      });
      if (updated.count !== 1) {
        const exists = await tx.product.findFirst({
          where: { id: product_id, tenantId },
          select: { id: true },
        });
        if (!exists) throw new HttpError(404, 'Product not found');
        throw new HttpError(409, 'Insufficient stock for this adjustment');
      }
      await tx.stockAdjustment.create({
        data: {
          tenantId,
          productId: product_id,
          delta,
          reason,
          staffId: staff_profile_id,
          createdAt: new Date(),
        },
      });
    });

    log('info', 'product.stock_adjusted', {
      tenantId,
      productId: product_id,
      delta,
      reason,
      staff_profile_id,
    });

    const current = await prisma.product.findFirst({
      where: { id: product_id, tenantId },
      select: { stockQty: true },
    });
    return res.json({ product_id, stockQty: current?.stockQty ?? 0, delta });
  })
);

// ---------------------------------------------------------------------------
// List products for the tenant
// ---------------------------------------------------------------------------

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const limit = Math.min(Math.max(Number(req.query.limit) || 200, 1), 200);
    const offset = Math.max(Number(req.query.offset) || 0, 0);
    const products = await prisma.product.findMany({
      where: { tenantId: requireUser(req).tenantId },
      orderBy: [{ name: 'asc' }, { id: 'asc' }],
      skip: offset,
      take: limit,
    });
    return res.json({
      products,
      nextOffset: products.length === limit ? offset + products.length : null,
    });
  })
);

export default router;
