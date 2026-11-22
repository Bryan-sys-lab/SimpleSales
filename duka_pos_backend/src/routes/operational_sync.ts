import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import {
  exchangeSyncSchema,
  laybySyncSchema,
  parseBody,
  operationalSyncSchema,
  purchaseSyncSchema,
  shotCupsSyncSchema,
  stockMovementsSyncSchema
} from '../lib/validation';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { requiredD1String } from '../lib/d1_results';
import { upsertSyncRecords } from '../lib/sync_records_d1';
import { requireRole } from '../middleware/auth';

const router = Router();

/**
 * Sales are applied by /api/sales/sync, which atomically creates the sale and
 * decrements stock. Their append-only movement is still mirrored here for the
 * audit timeline, but must not decrement the product a second time. Opening
 * rows are snapshots, not deltas, and are likewise never applied.
 */
export function stockMovementChangesProductBalance(movementType: string): boolean {
  return movementType !== 'opening' && movementType !== 'sale';
}

export function orderedStockMovements<T extends { productId?: string | null; localId: number; deviceId?: string }>(
  records: T[]
): T[] {
  return [...records].sort(
    (a, b) =>
      (a.productId ?? '').localeCompare(b.productId ?? '') ||
      (a.deviceId ?? 'legacy').localeCompare(b.deviceId ?? 'legacy') ||
      a.localId - b.localId
  );
}

router.get(
  ['/', '/sync'],
  requireRole('admin', 'manager', 'cashier'),
  asyncHandler(async (req, res) => {
    const user = requireUser(req);
    const pathKind = req.baseUrl.split('/').pop() ?? 'operational';
    const keyByPath: Record<string, string> = {
      shifts: 'shifts',
      'shot-cups': 'shotCups',
      returns: 'returns',
      purchases: 'purchases',
      expenses: 'expenses',
      'till-movements': 'tillMovements',
      'stock-movements': 'stockMovements',
      'drawer-events': 'drawerEvents',
      laybys: 'laybys',
      exchanges: 'exchanges'
    };
    const key = keyByPath[pathKind] ?? pathKind;
    const rawSince = typeof req.query.since === 'string' ? req.query.since : null;
    const [sinceValue, sinceId] = rawSince?.includes('|') ? rawSince.split('|', 2) : [rawSince, null];
    const since = sinceValue ? new Date(sinceValue) : null;
    if (since && !Number.isFinite(since.getTime())) {
      return res.status(400).json({ error: 'Invalid sync cursor' });
    }
    const cursorWhere = since
      ? sinceId
        ? {
            OR: [{ updatedAt: { gt: since } }, { updatedAt: since, id: { gt: sinceId } }]
          }
        : { updatedAt: { gt: since } }
      : {};
    const records = await prisma.syncRecord.findMany({
      where: {
        tenantId: user.tenantId,
        kind: pathKind,
        ...cursorWhere
      },
      // Cursor consumers advance through this stable pair. A timestamp alone is
      // insufficient: many records can share the same millisecond.
      orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
      take: 500,
      select: { id: true, payload: true, createdAt: true, updatedAt: true }
    });
    const last = records.at(-1);
    const nextCursor = last ? `${last.updatedAt.toISOString()}|${last.id}` : rawSince;
    return res.json({
      [key]: records.map((record) => ({
        ...(record.payload as Record<string, unknown>),
        remoteId: record.id,
        remoteCreatedAt: record.createdAt.toISOString(),
        remoteUpdatedAt: record.updatedAt.toISOString()
      })),
      nextCursor
    });
  })
);

/**
 * Receives the existing offline queues without making the app wait for a
 * network connection. New clients namespace local ids by their persistent
 * device id; legacy clients remain safely readable under the legacy namespace.
 */
router.post(
  ['/', '/sync'],
  requireRole('admin', 'manager', 'cashier'),
  asyncHandler(async (req, res) => {
    const user = requireUser(req);
    const pathKind = req.baseUrl.split('/').pop() ?? 'operational';
    const keyByPath: Record<string, string> = {
      shifts: 'shifts',
      'shot-cups': 'shotCups',
      expenses: 'expenses',
      'till-movements': 'tillMovements',
      'stock-movements': 'stockMovements',
      'drawer-events': 'drawerEvents',
      laybys: 'laybys',
      exchanges: 'exchanges'
    };
    const key = keyByPath[pathKind] ?? pathKind;
    const raw = req.body?.[key] ?? req.body;
    const records = Array.isArray(raw) ? raw : [raw];
    if (pathKind === 'laybys') {
      const { laybys } = parseBody(laybySyncSchema, { laybys: records });
      const customerUuids = [...new Set(laybys.map((layby) => layby.customerUuid))];
      const customers = await prisma.customer.findMany({
        where: {
          tenantId: user.tenantId,
          localUuid: { in: customerUuids }
        },
        select: { localUuid: true }
      });
      if (customers.length !== customerUuids.length) {
        throw new HttpError(409, 'Customer is not available in this shop');
      }
      const productIds = [
        ...new Set(
          laybys.flatMap((layby) =>
            layby.items.flatMap((item) => item.productId ? [item.productId] : [])
          )
        )
      ];
      if (productIds.length > 0) {
        const products = await prisma.product.findMany({
          where: {
            tenantId: user.tenantId,
            id: { in: productIds }
          },
          select: { id: true }
        });
        if (products.length !== productIds.length) {
          throw new HttpError(409, 'Product is not available in this shop');
        }
      }
      const synced = await upsertSyncRecords(laybys.map((layby) => ({
        tenantId: user.tenantId,
        kind: pathKind,
        deviceId: layby.deviceId ?? 'legacy',
        localId: layby.localId,
        payload: layby,
        createdAt: new Date(layby.createdAt),
        updatePayload: true,
      })));
      return res.json({ synced });
    }
    if (pathKind === 'exchanges') {
      const { exchanges } = parseBody(exchangeSyncSchema, {
        exchanges: records
      });
      const synced = await upsertSyncRecords(exchanges.map((exchange) => ({
        tenantId: user.tenantId,
        kind: pathKind,
        deviceId: exchange.deviceId ?? 'legacy',
        localId: exchange.localId,
        payload: exchange,
        createdAt: new Date(exchange.createdAt),
        updatePayload: true,
      })));
      return res.json({ synced });
    }
    if (pathKind === 'stock-movements') {
      const { stockMovements } = parseBody(stockMovementsSyncSchema, {
        stockMovements: records
      });
      const db = getD1DatabaseBinding();
      const ordered = orderedStockMovements(stockMovements);
      const statements = [];
      const resultIndexes: number[] = [];
      for (const record of ordered) {
        const deviceId = record.deviceId ?? 'legacy';
        const createdAt = new Date(record.createdAt).toISOString();
        const changesProduct = Boolean(
          record.productId &&
          !record.variantId &&
          stockMovementChangesProductBalance(record.movementType),
        );
        if (changesProduct) {
          statements.push(db.prepare(`
            UPDATE products
            SET stock_qty = stock_qty + ?, updated_at = ?
            WHERE id = ? AND tenant_id = ?
              AND NOT EXISTS (
                SELECT 1 FROM sync_records
                WHERE tenant_id = ? AND kind = ? AND device_id = ? AND local_id = ?
              )
          `).bind(
            record.qtyDelta,
            createdAt,
            record.productId,
            user.tenantId,
            user.tenantId,
            pathKind,
            deviceId,
            record.localId,
          ));
          statements.push(db.prepare(`
            INSERT INTO sync_records (
              id, tenant_id, kind, device_id, local_id, payload, created_at, updated_at
            )
            SELECT ?, ?, ?, ?, ?, ?, ?, ?
            WHERE changes() = 1
            ON CONFLICT (tenant_id, kind, device_id, local_id) DO NOTHING
          `).bind(
            globalThis.crypto.randomUUID(),
            user.tenantId,
            pathKind,
            deviceId,
            record.localId,
            JSON.stringify(record),
            createdAt,
            createdAt,
          ));
          statements.push(db.prepare(`
            INSERT INTO products (id, tenant_id, name)
            SELECT NULL, NULL, NULL
            WHERE changes() = 0
              AND NOT EXISTS (
                SELECT 1 FROM sync_records
                WHERE tenant_id = ? AND kind = ? AND device_id = ? AND local_id = ?
              )
          `).bind(user.tenantId, pathKind, deviceId, record.localId));
        } else {
          statements.push(db.prepare(`
            INSERT INTO sync_records (
              id, tenant_id, kind, device_id, local_id, payload, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (tenant_id, kind, device_id, local_id) DO NOTHING
          `).bind(
            globalThis.crypto.randomUUID(),
            user.tenantId,
            pathKind,
            deviceId,
            record.localId,
            JSON.stringify(record),
            createdAt,
            createdAt,
          ));
        }
        resultIndexes.push(statements.length);
        statements.push(db.prepare(`
          SELECT id FROM sync_records
          WHERE tenant_id = ? AND kind = ? AND device_id = ? AND local_id = ?
        `).bind(user.tenantId, pathKind, deviceId, record.localId));
      }
      const results = statements.length === 0 ? [] : await db.batch(statements);
      const synced = ordered.map((record, index) => ({
        localId: record.localId,
        remoteId: requiredD1String(results[resultIndexes[index]], 'id', 'stock movement'),
      }));
      return res.json({ synced });
    }
    if (pathKind === 'shot-cups') {
      const { shotCups } = parseBody(shotCupsSyncSchema, { shotCups: records });
      const productIds = [...new Set(shotCups.map((cup) => cup.productId))];
      const products = await prisma.product.findMany({
        where: {
          tenantId: user.tenantId,
          id: { in: productIds }
        },
        select: { id: true }
      });
      if (products.length !== productIds.length) {
        throw new HttpError(409, 'Product is not available in this shop');
      }
      const synced = await upsertSyncRecords(shotCups.map((cup) => ({
        tenantId: user.tenantId,
        kind: pathKind,
        deviceId: cup.deviceId ?? 'legacy',
        localId: cup.localId,
        payload: cup,
        createdAt: new Date(cup.createdAt),
        updatePayload: true,
      })));
      return res.json({ synced });
    }
    const { records: valid } = pathKind === 'purchases'
      ? parseBody(purchaseSyncSchema, { records })
      : parseBody(operationalSyncSchema, { records });
    const synced: Array<{ localId: number; remoteId: string }> = [];

    // Purchases and returns are historical tax/financial evidence. A retry may
    // acknowledge the original row, but must never replace its payload with a
    // later client mutation. Corrections are represented by a new document or
    // linked credit note, not an update to the original sync record.
    if (pathKind === 'purchases' || pathKind === 'returns') {
      synced.push(...await upsertSyncRecords(valid.map((record) => ({
        tenantId: user.tenantId,
        kind: pathKind,
        deviceId: record.deviceId ?? 'legacy',
        localId: record.localId,
        payload: record,
        createdAt: new Date(record.createdAt ?? new Date().toISOString()),
      }))));
      if (Array.isArray(raw)) return res.json({ synced });
      return res.json({
        localId: synced[0]?.localId,
        remoteId: synced[0]?.remoteId
      });
    }

    synced.push(...await upsertSyncRecords(valid.map((record) => ({
      tenantId: user.tenantId,
      kind: pathKind,
      deviceId: record.deviceId ?? 'legacy',
      localId: record.localId,
      payload: record,
      createdAt: new Date(record.createdAt ?? new Date().toISOString()),
      updatePayload: true,
      updateCreatedAt: true,
    }))));

    if (Array.isArray(raw)) return res.json({ synced });
    return res.json({
      localId: synced[0]?.localId,
      remoteId: synced[0]?.remoteId
    });
  })
);

export default router;
