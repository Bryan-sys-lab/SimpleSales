/**
 * Product variant sync (Fashion size/colour/SKU catalogue).
 * Bulk upsert with idempotency by syncKey; returns localId -> remoteId mapping.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, productVariantSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';

const router = Router();

export function missingVariantParentIds(
  requested: readonly string[],
  tenantProducts: readonly string[],
): string[] {
  const available = new Set(tenantProducts);
  return [...new Set(requested)].filter((id) => !available.has(id));
}

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const tenantId = requireUser(req).tenantId;
    const variants = await prisma.productVariant.findMany({
      where: { tenantId },
      orderBy: [{ productId: 'asc' }, { position: 'asc' }, { id: 'asc' }],
      select: {
        id: true,
        localId: true,
        productId: true,
        name: true,
        sku: true,
        unit: true,
        sizeMl: true,
        sellPrice: true,
        costPrice: true,
        stockQty: true,
        reservedQty: true,
        reorderLevel: true,
        position: true,
        active: true,
      },
    });
    return res.json({
      productVariants: variants.map((variant) => ({
        id: variant.localId,
        remoteId: variant.id,
        productId: variant.productId,
        name: variant.name,
        sku: variant.sku,
        unit: variant.unit,
        sizeMl: variant.sizeMl,
        sellPrice: Number(variant.sellPrice),
        costPrice: Number(variant.costPrice),
        stockQty: Number(variant.stockQty),
        reservedQty: Number(variant.reservedQty),
        reorderLevel: variant.reorderLevel,
        position: variant.position,
        active: variant.active,
      })),
    });
  }),
);

router.post(
  '/sync',
  asyncHandler(async (req, res) => {
    const { productVariants } = parseBody(productVariantSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const synced = await prisma.$transaction(async (tx) => {
      const productIds = [...new Set(productVariants.map((variant) => variant.productId))];
      const products = await tx.product.findMany({
        where: { tenantId, id: { in: productIds } },
        select: { id: true },
      });
      if (missingVariantParentIds(
        productIds,
        products.map((product) => product.id),
      ).length > 0) {
        throw new HttpError(409, 'One or more variant parent products are not in this shop');
      }
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
            reservedQty: variant.reservedQty,
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
            reservedQty: variant.reservedQty,
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
