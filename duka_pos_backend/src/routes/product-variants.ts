/**
 * Product variant sync (Fashion size/colour/SKU catalogue).
 * Bulk upsert with idempotency by syncKey; returns localId -> remoteId mapping.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, productVariantSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';

const router = Router();

router.post(
  '/sync',
  asyncHandler(async (req, res) => {
    const { productVariants } = parseBody(productVariantSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const synced = await prisma.$transaction(async (tx) => {
      const result: Array<{ localId: number; remoteId: string }> = [];
      for (const variant of productVariants) {
        if (!variant.syncKey) {
          throw new HttpError(400, 'Variant missing syncKey');
        }
        const saved = await tx.productVariant.upsert({
          where: {
            tenantId_syncKey: { tenantId, syncKey: variant.syncKey },
          },
          create: {
            tenantId,
            syncKey: variant.syncKey,
            productId: variant.productId,
            name: variant.name,
            sku: variant.sku,
            unit: variant.unit,
            sizeMl: variant.sizeMl,
            sellPrice: variant.sellPrice,
            costPrice: variant.costPrice,
            stockQty: variant.stockQty,
            reorderLevel: variant.reorderLevel,
            position: variant.position,
            active: variant.active,
          },
          update: {
            name: variant.name,
            sku: variant.sku,
            unit: variant.unit,
            sizeMl: variant.sizeMl,
            sellPrice: variant.sellPrice,
            costPrice: variant.costPrice,
            stockQty: variant.stockQty,
            reorderLevel: variant.reorderLevel,
            position: variant.position,
            active: variant.active,
          },
        });
        result.push({ localId: variant.id, remoteId: saved.id });
      }
      return result;
    });
    return res.json({ synced });
  })
);

export default router;
