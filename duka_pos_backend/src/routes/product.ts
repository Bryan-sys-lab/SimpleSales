/**
 * Product routes: bulk sync, per-product stock adjustment, list.
 */
import { Router } from 'express';
import { asyncHandler } from '../lib/http';
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
    const tenantId = req.user.tenantId;
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
              stockQty: product.stockQty,
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
          const created = await tx.product.create({
            data: {
              tenantId,
              name: product.name,
              category: product.category,
              costPrice: product.costPrice,
              sellPrice: product.sellPrice,
              stockQty: product.stockQty,
              reorderLevel: product.reorderLevel,
              bottleMl: product.bottleMl,
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
    const tenantId = req.user.tenantId;

    const product = await prisma.product.findFirst({ where: { id: product_id, tenantId } });
    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }

    const newQty = Number(product.stockQty) + delta;
    if (newQty < 0) {
      return res.status(409).json({ error: 'Insufficient stock for this adjustment' });
    }

    await prisma.$transaction(async (tx) => {
      await tx.product.update({
        where: { id: product_id },
        data: { stockQty: newQty },
      });
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

    return res.json({ product_id, stockQty: newQty, delta });
  })
);

// ---------------------------------------------------------------------------
// List products for the tenant
// ---------------------------------------------------------------------------

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const products = await prisma.product.findMany({
      where: { tenantId: req.user.tenantId },
      orderBy: { name: 'asc' },
    });
    return res.json(products);
  })
);

export default router;
