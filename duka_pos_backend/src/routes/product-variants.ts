/**
 * Product variant sync (Fashion size/colour/SKU catalogue).
 * Bulk upsert with idempotency by syncKey; returns localId -> remoteId mapping.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, productVariantSyncSchema } from '../lib/validation';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { requiredD1String } from '../lib/d1_results';

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
    const productIds = [...new Set(productVariants.map((variant) => variant.productId))];
    const products = await prisma.product.findMany({
        where: { tenantId, id: { in: productIds } },
        select: { id: true },
      });
    if (missingVariantParentIds(
      productIds,
      products.map((product) => product.id),
    ).length > 0) {
      throw new HttpError(409, 'One or more variant parent products are not in this shop');
    }
    const records = productVariants.map((variant) => {
      if (!variant.syncKey) throw new HttpError(400, 'Variant missing syncKey');
      return variant;
    });
    const db = getD1DatabaseBinding();
    const now = new Date().toISOString();
    const results = records.length === 0 ? [] : await db.batch(records.map((variant) => db.prepare(`
      INSERT INTO product_variants (
        id, tenant_id, sync_key, product_id, variant_name, sku, unit, size_ml,
        sell_price, cost_price, stock_qty, reserved_qty, reorder_level,
        position, active, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (tenant_id, sync_key) DO UPDATE SET
        variant_name = excluded.variant_name,
        sku = excluded.sku,
        unit = excluded.unit,
        size_ml = excluded.size_ml,
        sell_price = excluded.sell_price,
        cost_price = excluded.cost_price,
        stock_qty = excluded.stock_qty,
        reserved_qty = excluded.reserved_qty,
        reorder_level = excluded.reorder_level,
        position = excluded.position,
        active = excluded.active,
        updated_at = excluded.updated_at
      RETURNING id
    `).bind(
      globalThis.crypto.randomUUID(),
      tenantId,
      variant.syncKey,
      variant.productId,
      variant.name,
      variant.sku,
      variant.unit,
      variant.sizeMl,
      variant.sellPrice,
      variant.costPrice,
      variant.stockQty,
      variant.reservedQty,
      variant.reorderLevel,
      variant.position,
      variant.active ? 1 : 0,
      now,
      now,
    )));
    const synced = records.map((variant, index) => {
      const remoteId = requiredD1String(results[index], 'id', 'product variant');
      return { localId: variant.id, remoteId };
    });
    return res.json({ synced });
  })
);

export default router;
