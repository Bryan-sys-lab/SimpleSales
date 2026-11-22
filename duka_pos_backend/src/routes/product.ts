/**
 * Product routes: bulk sync, per-product stock adjustment, list.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody } from '../lib/validation';
import { productSyncSchema, stockAdjustSchema } from '../lib/validation';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { requiredD1String } from '../lib/d1_results';
import { log } from '../lib/observability';
import { z } from 'zod';

const router = Router();

const identityData = (product: z.infer<typeof productSyncSchema>['products'][number]) => ({
  productUuid: product.productUuid ?? undefined,
  itemKind: product.itemKind,
  gpcCode: product.gpcCode,
  gpcVersion: product.gpcVersion,
  gpcMappingStatus: product.gpcMappingStatus,
  gtin: product.gtin,
  merchantSku: product.merchantSku,
  brandEntityId: product.brandEntityId,
  brandLabelLocal: product.brandLabelLocal,
  manufacturerEntityId: product.manufacturerEntityId,
  variantAttributes: product.variantAttributes ?? undefined,
  externalUnitCode: product.externalUnitCode,
  unitScheme: product.unitScheme,
  unitVersion: product.unitVersion,
  unitMappingStatus: product.unitMappingStatus,
  packQuantity: product.packQuantity,
  packUnitCode: product.packUnitCode,
  identityProvenance: product.identityProvenance,
});

const identityColumnNames: Record<string, string> = {
  productUuid: 'product_uuid',
  itemKind: 'item_kind',
  gpcCode: 'gpc_code',
  gpcVersion: 'gpc_version',
  gpcMappingStatus: 'gpc_mapping_status',
  gtin: 'gtin',
  merchantSku: 'merchant_sku',
  brandEntityId: 'brand_entity_id',
  brandLabelLocal: 'brand_label_local',
  manufacturerEntityId: 'manufacturer_entity_id',
  variantAttributes: 'variant_attributes',
  externalUnitCode: 'external_unit_code',
  unitScheme: 'unit_scheme',
  unitVersion: 'unit_version',
  unitMappingStatus: 'unit_mapping_status',
  packQuantity: 'pack_quantity',
  packUnitCode: 'pack_unit_code',
  identityProvenance: 'identity_provenance',
};

function productIdentityFields(product: z.infer<typeof productSyncSchema>['products'][number]) {
  return Object.entries(identityData(product))
    .filter(([, value]) => value !== undefined)
    .map(([key, value]) => [
      identityColumnNames[key],
      key === 'variantAttributes' ? JSON.stringify(value) : value,
    ] as [string, unknown]);
}

// ---------------------------------------------------------------------------
// Bulk product sync (owner or manager)
// ---------------------------------------------------------------------------

router.post(
  '/sync',
  asyncHandler(async (req, res) => {
    const { products } = parseBody(productSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const remoteIds = [...new Set(products.flatMap((product) => product.remoteId ? [product.remoteId] : []))];
    if (remoteIds.length > 0) {
      const existing = await prisma.product.findMany({
        where: { id: { in: remoteIds }, tenantId },
        select: { id: true },
      });
      if (existing.length !== remoteIds.length) throw new Error('Product does not belong to this shop');
    }

    const db = getD1DatabaseBinding();
    const statements = [];
    const resultIndexes: number[] = [];
    const now = new Date().toISOString();
    for (const product of products) {
      const baseFields: Array<[string, unknown]> = [
        ['name', product.name],
        ['category', product.category],
        ['cost_price', product.costPrice],
        ['sell_price', product.sellPrice],
        ['reorder_level', product.reorderLevel],
        ['bottle_ml', product.bottleMl],
        ['unit', product.unit],
        ['ml_per_kg', product.mlPerKg],
        ['half_price', product.halfPrice],
        ['quarter_price', product.quarterPrice],
        ['excise_stamp_batch', product.exciseStampBatch],
        ['active', product.active === undefined ? undefined : product.active ? 1 : 0],
        ...productIdentityFields(product),
      ];
      const updateFields = baseFields.filter(([, value]) => value !== undefined);
      if (product.remoteId) {
        const assignments = updateFields.map(([column]) => `${column} = ?`);
        assignments.push('updated_at = ?');
        const statementIndex = statements.length;
        statements.push(db.prepare(`
          UPDATE products SET ${assignments.join(', ')}
          WHERE id = ? AND tenant_id = ?
          RETURNING id
        `).bind(
          ...updateFields.map(([, value]) => value),
          now,
          product.remoteId,
          tenantId,
        ));
        statements.push(db.prepare(`
          INSERT INTO products (id, tenant_id, name)
          SELECT NULL, NULL, NULL WHERE changes() <> 1
        `));
        resultIndexes.push(statementIndex);
        continue;
      }

      const createFields: Array<[string, unknown]> = [['tenant_id', tenantId]];
      if (product.syncKey) createFields.push(['sync_key', product.syncKey]);
      createFields.push(
        ...baseFields,
        ['stock_qty', product.openingStockQty ?? product.stockQty],
        ['created_at', now],
        ['updated_at', now],
      );
      const validCreateFields = createFields.filter(([, value]) => value !== undefined);
      const createColumns = validCreateFields.map(([column]) => column);
      const createValues = validCreateFields.map(([, value]) =>
        typeof value === 'boolean' ? (value ? 1 : 0) : value);

      if (product.syncKey) {
        const updateAssignments = updateFields.map(([column]) => `${column} = excluded.${column}`);
        updateAssignments.push('updated_at = excluded.updated_at');
        statements.push(db.prepare(`
          INSERT INTO products (id, ${createColumns.join(', ')})
          VALUES (?, ${createColumns.map(() => '?').join(', ')})
          ON CONFLICT (tenant_id, sync_key) DO UPDATE SET ${updateAssignments.join(', ')}
          RETURNING id
        `).bind(globalThis.crypto.randomUUID(), ...createValues));
      } else {
        statements.push(db.prepare(`
          INSERT INTO products (id, ${createColumns.join(', ')})
          VALUES (?, ${createColumns.map(() => '?').join(', ')})
          RETURNING id
        `).bind(globalThis.crypto.randomUUID(), ...createValues));
      }
      resultIndexes.push(statements.length - 1);
    }
    const results = statements.length === 0 ? [] : await db.batch(statements);
    const synced = products.map((product, index) => ({
      localId: product.id,
      remoteId: requiredD1String(results[resultIndexes[index]], 'id', 'product sync'),
    }));
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

    const now = new Date().toISOString();
    const db = getD1DatabaseBinding();
    const results = await db.batch([
      db.prepare(`
        UPDATE products
        SET stock_qty = stock_qty + ?, updated_at = ?
        WHERE id = ? AND tenant_id = ?
          AND (? >= 0 OR stock_qty >= ?)
      `).bind(delta, now, product_id, tenantId, delta, Math.abs(delta)),
      db.prepare(`
        INSERT INTO stock_adjustments (
          id, tenant_id, product_id, delta, reason, staff_id, created_at
        )
        SELECT ?, ?, ?, ?, ?, ?, ?
        WHERE changes() = 1
      `).bind(
        globalThis.crypto.randomUUID(),
        tenantId,
        product_id,
        delta,
        reason ?? null,
        staff_profile_id ?? null,
        now,
      ),
    ]);
    if ((results[0]?.meta.changes ?? 0) !== 1) {
      const exists = await prisma.product.findFirst({
        where: { id: product_id, tenantId },
        select: { id: true },
      });
      if (!exists) throw new HttpError(404, 'Product not found');
      throw new HttpError(409, 'Insufficient stock for this adjustment');
    }

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
