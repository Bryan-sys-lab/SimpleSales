import { Router } from 'express';
import { Prisma } from '../generated/prisma/client';
import { z } from 'zod';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, salesSyncSchema } from '../lib/validation';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { requireRole } from '../middleware/auth';

const router = Router();

const major = (minor: number): string => (minor / 100).toFixed(2);

type SaleInput = ReturnType<typeof salesSyncSchema.parse>['sales'][number];
type SaleConflictResolution = {
  deviceId: string;
  localId: number;
  resolvedBy: string;
};

export function orderedStockProductIds(required: ReadonlyMap<string, number>): string[] {
  return [...required.keys()].sort();
}

async function applySale(
  tenantId: string,
  staffId: string,
  input: SaleInput,
  allowNegativeStock = false,
  conflictResolution?: SaleConflictResolution,
): Promise<string> {
  const deviceId = input.deviceId ?? 'legacy';
  const saleDate = new Date(input.createdAt);
  const existing = await prisma.sale.findUnique({
    where: { tenantId_deviceId_localId: { tenantId, deviceId, localId: input.localId } },
    select: { id: true },
  });
  if (existing) {
    if (conflictResolution) {
      await resolveSaleConflict(tenantId, conflictResolution, 'accept_negative_stock');
    }
    return existing.id;
  }
  const productIds = [...new Set(input.items.map((item) => item.productId)
    .filter((id): id is string => typeof id === 'string' && id.length > 0))];
  const products = productIds.length === 0 ? [] : await prisma.product.findMany({
    where: { tenantId, id: { in: productIds } },
    select: { id: true, bottleMl: true },
  });
  if (products.length !== productIds.length) throw new HttpError(409, 'One or more sale products are not in this shop');
  const taxRuleIds = [...new Set(input.items.map((item) => item.taxRuleId).filter((id): id is string => Boolean(id)))];
  if (taxRuleIds.length > 0) {
    const mapping = await prisma.shopTaxEntity.findFirst({
      where: {
        tenantId,
        effectiveFrom: { lte: saleDate },
        OR: [{ effectiveTo: null }, { effectiveTo: { gt: saleDate } }],
      },
      select: { taxEntityId: true },
      orderBy: { effectiveFrom: 'desc' },
    });
    if (!mapping) throw new HttpError(409, 'Sale tax snapshot has no matching tax entity');
    const rules = await prisma.taxRule.findMany({
      where: {
        id: { in: taxRuleIds },
        taxEntityId: mapping.taxEntityId,
        status: { in: ['approved', 'active'] },
        effectiveFrom: { lte: saleDate },
        OR: [{ effectiveTo: null }, { effectiveTo: { gt: saleDate } }],
      },
      select: { id: true, version: true },
    });
    const byId = new Map(rules.map((rule) => [rule.id, rule]));
    for (const item of input.items) {
      if (!item.taxRuleId) continue;
      const rule = byId.get(item.taxRuleId);
      if (!rule || (item.taxRuleVersion != null && item.taxRuleVersion !== rule.version)) {
        throw new HttpError(409, 'Sale tax snapshot does not match the effective taxpayer rule');
      }
    }
  }
  const productById = new Map(products.map((product) => [product.id, product]));
  const required = new Map<string, number>();
  for (const item of input.items) {
    if (item.productId == null) continue;
    const product = productById.get(item.productId);
    if (!product) throw new HttpError(409, 'Sale product is not in this shop');
    const namedFactor = item.portion === 'half' ? 0.5 : item.portion === 'quarter' ? 0.25 : 1;
    const portionFactor = item.portion !== 'full' && item.portionMl > 0 && Number(product.bottleMl) > 0
      ? item.portionMl / Number(product.bottleMl) : namedFactor;
    required.set(item.productId, (required.get(item.productId) ?? 0) + item.qty * portionFactor);
  }
  const saleId = globalThis.crypto.randomUUID();
  const db = getD1DatabaseBinding();
  const statements = [];
  if (conflictResolution) {
    statements.push(db.prepare(`
      UPDATE sale_sync_conflicts
      SET status = 'resolving'
      WHERE tenant_id = ? AND device_id = ? AND local_id = ? AND status = 'open'
    `).bind(tenantId, conflictResolution.deviceId, conflictResolution.localId));
  }

  if (required.size > 0) {
    const orderedIds = orderedStockProductIds(required);
    const stockPayload = JSON.stringify(orderedIds.map((id) => ({ id, qty: required.get(id) })));
    statements.push(db.prepare(`
      WITH required AS (
        SELECT json_extract(value, '$.id') AS id,
               CAST(json_extract(value, '$.qty') AS REAL) AS qty
        FROM json_each(?)
      )
      UPDATE products
      SET stock_qty = stock_qty - (SELECT qty FROM required WHERE required.id = products.id),
          updated_at = ?
      WHERE tenant_id = ?
        AND id IN (SELECT id FROM required)
        AND (
          SELECT COUNT(*)
          FROM products AS available
          JOIN required ON required.id = available.id
          WHERE available.tenant_id = ?
          ${allowNegativeStock ? '' : 'AND available.stock_qty >= required.qty'}
        ) = (SELECT COUNT(*) FROM required)
        ${conflictResolution ? `AND EXISTS (
          SELECT 1 FROM sale_sync_conflicts
          WHERE tenant_id = ? AND device_id = ? AND local_id = ? AND status = 'resolving'
        )` : ''}
    `).bind(
      stockPayload,
      new Date().toISOString(),
      tenantId,
      tenantId,
      ...(conflictResolution ? [tenantId, conflictResolution.deviceId, conflictResolution.localId] : []),
    ));
  }

  const saleGate = required.size > 0
    ? `changes() = ${required.size}`
    : conflictResolution ? 'changes() = 1' : '1 = 1';
  statements.push(db.prepare(`
    INSERT INTO sales (
      id, tenant_id, local_id, device_id, staff_id, staff_name, buyer_name,
      buyer_tin, payment_method, payment_reference, total, profit, created_at
    )
    SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
    WHERE ${saleGate}
  `).bind(
    saleId,
    tenantId,
    input.localId,
    deviceId,
    staffId,
    input.staffName,
    input.buyerName ?? null,
    input.buyerTin ?? null,
    input.paymentMethod,
    input.paymentReference ?? null,
    major(input.total),
    major(input.profit),
    new Date(input.createdAt).toISOString(),
  ));

  for (const item of input.items) {
    statements.push(db.prepare(`
      INSERT INTO sale_items (
        id, tenant_id, sale_id, product_id, product_name, qty, unit_price,
        unit_cost, vat_amount, taxable_amount, tax_class, vat_rate_bps,
        tax_rule_id, tax_rule_version, portion, portion_ml
      )
      SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
      WHERE EXISTS (SELECT 1 FROM sales WHERE id = ? AND tenant_id = ?)
    `).bind(
      globalThis.crypto.randomUUID(),
      tenantId,
      saleId,
      item.productId ?? null,
      item.productName,
      item.qty,
      major(item.unitPrice),
      major(item.unitCost),
      item.vatMinor == null ? null : major(item.vatMinor),
      item.taxableMinor == null ? null : major(item.taxableMinor),
      item.taxClass ?? null,
      item.vatRateBps ?? null,
      item.taxRuleId ?? null,
      item.taxRuleVersion ?? null,
      item.portion,
      item.portionMl,
      saleId,
      tenantId,
    ));
  }

  for (const tender of input.tenders ?? []) {
    statements.push(db.prepare(`
      INSERT INTO sale_payments (
        id, tenant_id, sale_id, local_uuid, method, amount, tendered,
        "change", reference, status, created_at
      )
      SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
      WHERE EXISTS (SELECT 1 FROM sales WHERE id = ? AND tenant_id = ?)
    `).bind(
      globalThis.crypto.randomUUID(),
      tenantId,
      saleId,
      tender.localUuid,
      tender.method,
      major(tender.amountMinor),
      tender.tenderedMinor == null ? null : major(tender.tenderedMinor),
      tender.changeMinor == null ? null : major(tender.changeMinor),
      tender.reference ?? null,
      tender.status,
      new Date(tender.createdAt).toISOString(),
      saleId,
      tenantId,
    ));
  }

  if (conflictResolution) {
    statements.push(db.prepare(`
      UPDATE sale_sync_conflicts
      SET status = 'resolved',
          resolution = 'accept_negative_stock',
          resolved_by = ?,
          resolved_at = ?
      WHERE tenant_id = ? AND device_id = ? AND local_id = ? AND status = 'resolving'
        AND EXISTS (SELECT 1 FROM sales WHERE id = ? AND tenant_id = ?)
    `).bind(
      conflictResolution.resolvedBy,
      new Date().toISOString(),
      tenantId,
      conflictResolution.deviceId,
      conflictResolution.localId,
      saleId,
      tenantId,
    ));
    statements.push(db.prepare(`
      UPDATE sale_sync_conflicts
      SET status = 'open'
      WHERE tenant_id = ? AND device_id = ? AND local_id = ? AND status = 'resolving'
        AND NOT EXISTS (SELECT 1 FROM sales WHERE id = ? AND tenant_id = ?)
    `).bind(
      tenantId,
      conflictResolution.deviceId,
      conflictResolution.localId,
      saleId,
      tenantId,
    ));
  }

  const results = await db.batch(statements);
  if (conflictResolution && (results[0]?.meta.changes ?? 0) !== 1) {
    throw new HttpError(409, 'Sale conflict was already resolved');
  }
  const saleResult = results[(conflictResolution ? 1 : 0) + (required.size > 0 ? 1 : 0)];
  if ((saleResult?.meta.changes ?? 0) !== 1) {
    throw new HttpError(409, 'Insufficient stock; another till recorded the sale first');
  }
  if (conflictResolution) {
    const resolveIndex = results.length - 2;
    if ((results[resolveIndex]?.meta.changes ?? 0) !== 1) {
      throw new Error('Sale conflict resolution did not complete');
    }
  }
  return saleId;
}

async function resolveSaleConflict(
  tenantId: string,
  conflict: SaleConflictResolution,
  resolution: 'accept_negative_stock' | 'void',
): Promise<void> {
  const result = await getD1DatabaseBinding().batch([
    getD1DatabaseBinding().prepare(`
      UPDATE sale_sync_conflicts
      SET status = 'resolved', resolution = ?, resolved_by = ?, resolved_at = ?
      WHERE tenant_id = ? AND device_id = ? AND local_id = ? AND status = 'open'
    `).bind(
      resolution,
      conflict.resolvedBy,
      new Date().toISOString(),
      tenantId,
      conflict.deviceId,
      conflict.localId,
    ),
  ]);
  if ((result[0]?.meta.changes ?? 0) !== 1) {
    throw new HttpError(409, 'Sale conflict was already resolved');
  }
}

/**
 * Accepts offline sales in oldest-first batches. The local id is scoped to the
 * tenant and persistent till identity, so retries cannot confuse another
 * device's sale. Legacy clients omit deviceId and use the stable `legacy`
 * namespace.
 */
router.post('/sync', asyncHandler(async (req, res) => {
  const { sales } = parseBody(salesSyncSchema, req.body);
  const user = requireUser(req);
  const synced: Array<{ localId: number; remoteId: string }> = [];
  const conflicts: Array<{ localId: number; reason: string }> = [];

  // Each sale is its own D1 batch, so one stock conflict cannot roll back
  // unrelated sales in the same sync request.
  for (const input of sales) {
    const deviceId = input.deviceId ?? 'legacy';
    try {
      const remoteId = await applySale(user.tenantId, user.id, input);
      synced.push({ localId: input.localId, remoteId });
    } catch (error) {
      // Two reconnecting requests for the same offline sale can pass the
      // initial lookup before either commits. The unique key is the final
      // idempotency boundary; recover the committed sale instead of turning
      // a harmless retry into a 500.
      const existing = await prisma.sale.findUnique({
        where: {
          tenantId_deviceId_localId: {
            tenantId: user.tenantId,
            deviceId,
            localId: input.localId,
          },
        },
        select: { id: true },
      });
      if (existing) {
        synced.push({ localId: input.localId, remoteId: existing.id });
        continue;
      }
      if (error instanceof HttpError && error.status === 409) {
        await prisma.saleSyncConflict.upsert({
          where: { tenantId_deviceId_localId: { tenantId: user.tenantId, deviceId, localId: input.localId } },
          create: { tenantId: user.tenantId, deviceId, localId: input.localId, payload: input as Prisma.InputJsonValue, reason: error.message },
          update: { payload: input as Prisma.InputJsonValue, reason: error.message, status: 'open', resolution: null, resolvedBy: null, resolvedAt: null },
        });
        conflicts.push({ localId: input.localId, reason: error.message });
        continue;
      }
      throw error;
    }
  }

  res.json({ synced, conflicts });
}));

/**
 * Resolves one retained offline sale after a manager reviews the stock race.
 * The original payload and tenant/device/local key make this idempotent and
 * prevent a staff member from resolving another shop's conflict.
 */
router.post('/sync/conflicts/resolve', requireRole('admin', 'manager'), asyncHandler(async (req, res) => {
  const body = z.object({
    device_id: z.string().trim().min(1).max(120),
    local_id: z.number().int().positive(),
    resolution: z.enum(['accept_negative_stock', 'void']),
  }).strict().parse(req.body);
  const user = requireUser(req);
  const key = { tenantId_deviceId_localId: { tenantId: user.tenantId, deviceId: body.device_id, localId: body.local_id } };
  const conflict = await prisma.saleSyncConflict.findUnique({ where: key });
  if (!conflict) throw new HttpError(404, 'Sale conflict was not found');
  if (conflict.status === 'resolved') {
    return res.json({ resolved: true, resolution: conflict.resolution });
  }
  let remoteId: string | null = null;
  if (body.resolution === 'accept_negative_stock') {
    const parsed = salesSyncSchema.parse({ sales: [conflict.payload] });
    const resolution = { deviceId: body.device_id, localId: body.local_id, resolvedBy: user.id };
    try {
      remoteId = await applySale(user.tenantId, user.id, parsed.sales[0], true, resolution);
    } catch (error) {
      const existing = await prisma.sale.findUnique({
        where: {
          tenantId_deviceId_localId: {
            tenantId: user.tenantId,
            deviceId: body.device_id,
            localId: body.local_id,
          },
        },
        select: { id: true },
      });
      if (!existing) throw error;
      await resolveSaleConflict(user.tenantId, resolution, 'accept_negative_stock');
      remoteId = existing.id;
    }
  } else {
    await resolveSaleConflict(user.tenantId, {
      deviceId: body.device_id,
      localId: body.local_id,
      resolvedBy: user.id,
    }, 'void');
  }
  return res.json({ resolved: true, resolution: body.resolution, remoteId });
}));

export default router;
