import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { exchangeSyncSchema, laybySyncSchema, parseBody, operationalSyncSchema, stockMovementsSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
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

export function orderedStockMovements<T extends { productId?: string | null; localId: number; deviceId?: string }>(records: T[]): T[] {
  return [...records].sort((a, b) =>
    (a.productId ?? '').localeCompare(b.productId ?? '') ||
    (a.deviceId ?? 'legacy').localeCompare(b.deviceId ?? 'legacy') ||
    a.localId - b.localId);
}

router.get(['/', '/sync'], requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
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
    exchanges: 'exchanges',
  };
  const key = keyByPath[pathKind] ?? pathKind;
  const rawSince = typeof req.query.since === 'string' ? req.query.since : null;
  const [sinceValue, sinceId] = rawSince?.includes('|')
    ? rawSince.split('|', 2)
    : [rawSince, null];
  const since = sinceValue ? new Date(sinceValue) : null;
  if (since && !Number.isFinite(since.getTime())) {
    return res.status(400).json({ error: 'Invalid sync cursor' });
  }
  const cursorWhere = since
    ? sinceId
      ? { OR: [{ updatedAt: { gt: since } }, { updatedAt: since, id: { gt: sinceId } }] }
      : { updatedAt: { gt: since } }
    : {};
  const records = await prisma.syncRecord.findMany({
    where: {
      tenantId: user.tenantId,
      kind: pathKind,
      ...cursorWhere,
    },
    // Cursor consumers advance through this stable pair. A timestamp alone is
    // insufficient: many records can share the same millisecond.
    orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
    take: 500,
    select: { id: true, payload: true, createdAt: true, updatedAt: true },
  });
  const last = records.at(-1);
  const nextCursor = last
    ? `${last.updatedAt.toISOString()}|${last.id}`
    : rawSince;
  return res.json({
    [key]: records.map((record) => ({
      ...(record.payload as Record<string, unknown>),
      remoteId: record.id,
      remoteCreatedAt: record.createdAt.toISOString(),
      remoteUpdatedAt: record.updatedAt.toISOString(),
    })),
    nextCursor,
  });
}));

/**
 * Receives the existing offline queues without making the app wait for a
 * network connection. New clients namespace local ids by their persistent
 * device id; legacy clients remain safely readable under the legacy namespace.
 */
router.post(['/', '/sync'], requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
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
    exchanges: 'exchanges',
  };
  const key = keyByPath[pathKind] ?? pathKind;
  const raw = req.body?.[key] ?? req.body;
  const records = Array.isArray(raw) ? raw : [raw];
  if (pathKind === 'laybys') {
    const { laybys } = parseBody(laybySyncSchema, { laybys: records });
    const synced: Array<{ localId: number; remoteId: string }> = [];
    await prisma.$transaction(async (tx) => {
      for (const layby of laybys) {
        const deviceId = layby.deviceId ?? 'legacy';
        const saved = await tx.syncRecord.upsert({
          where: {
            tenantId_kind_deviceId_localId: {
              tenantId: user.tenantId,
              kind: pathKind,
              deviceId,
              localId: layby.localId,
            },
          },
          create: {
            tenantId: user.tenantId,
            kind: pathKind,
            deviceId,
            localId: layby.localId,
            payload: layby as Prisma.InputJsonValue,
            createdAt: new Date(layby.createdAt),
          },
          update: {
            payload: layby as Prisma.InputJsonValue,
          },
          select: { id: true },
        });
        synced.push({ localId: layby.localId, remoteId: saved.id });
      }
    });
    return res.json({ synced });
  }
  if (pathKind === 'exchanges') {
    const { exchanges } = parseBody(exchangeSyncSchema, { exchanges: records });
    const synced: Array<{ localId: number; remoteId: string }> = [];
    await prisma.$transaction(async (tx) => {
      for (const exchange of exchanges) {
        const deviceId = exchange.deviceId ?? 'legacy';
        const saved = await tx.syncRecord.upsert({
          where: { tenantId_kind_deviceId_localId: {
            tenantId: user.tenantId, kind: pathKind, deviceId, localId: exchange.localId,
          } },
          create: { tenantId: user.tenantId, kind: pathKind, deviceId, localId: exchange.localId,
            payload: exchange as Prisma.InputJsonValue, createdAt: new Date(exchange.createdAt) },
          update: { payload: exchange as Prisma.InputJsonValue },
          select: { id: true },
        });
        synced.push({ localId: exchange.localId, remoteId: saved.id });
      }
    });
    return res.json({ synced });
  }
  if (pathKind === 'stock-movements') {
    const { stockMovements } = parseBody(stockMovementsSyncSchema, {
      stockMovements: records,
    });
    const synced: Array<{ localId: number; remoteId: string }> = [];
    await prisma.$transaction(async (tx) => {
      for (const record of orderedStockMovements(stockMovements)) {
        const deviceId = record.deviceId ?? 'legacy';
        const keyValue = {
          tenantId_kind_deviceId_localId: {
            tenantId: user.tenantId,
            kind: pathKind,
            deviceId,
            localId: record.localId,
          },
        };
        // INSERT ... ON CONFLICT DO NOTHING closes the check-then-create
        // race when two tills retry the same movement at the same time.
        // Only the transaction that inserted the row may apply its stock
        // delta; the other transaction is an idempotent acknowledgement.
        const inserted = await tx.syncRecord.createMany({
          data: {
            tenantId: user.tenantId,
            kind: pathKind,
            deviceId,
            localId: record.localId,
            payload: record as Prisma.InputJsonValue,
            createdAt: new Date(record.createdAt),
          },
          skipDuplicates: true,
        });
        const saved = await tx.syncRecord.findUnique({
          where: keyValue,
          select: { id: true },
        });
        if (!saved) throw new HttpError(409, 'Movement could not be recorded');
        // Variant rows explain the variant balance, while the parent row is
        // the one canonical product-stock delta. Opening is already included
        // when the product is first created and must not be counted twice.
        if (
          inserted.count === 1 &&
          record.productId &&
          !record.variantId &&
          stockMovementChangesProductBalance(record.movementType)
        ) {
          const updated = await tx.product.updateMany({
            where: { id: record.productId, tenantId: user.tenantId },
            data: { stockQty: { increment: record.qtyDelta } },
          });
          if (updated.count !== 1) {
            // Roll back the ledger row as well. The client keeps this movement
            // pending and retries after catalogue sync has established the
            // product in this tenant.
            throw new HttpError(409, 'Product is not available in this shop');
          }
        }
        synced.push({ localId: record.localId, remoteId: saved.id });
      }
    });
    return res.json({ synced });
  }
  const { records: valid } = parseBody(operationalSyncSchema, { records });
  const synced: Array<{ localId: number; remoteId: string }> = [];

  // Purchases and returns are historical tax/financial evidence. A retry may
  // acknowledge the original row, but must never replace its payload with a
  // later client mutation. Corrections are represented by a new document or
  // linked credit note, not an update to the original sync record.
  if (pathKind === 'purchases' || pathKind === 'returns') {
    await prisma.$transaction(async (tx) => {
      for (const record of valid) {
        const deviceId = record.deviceId ?? 'legacy';
        await tx.syncRecord.createMany({
          data: {
            tenantId: user.tenantId,
            kind: pathKind,
            deviceId,
            localId: record.localId,
            payload: record as Prisma.InputJsonValue,
            createdAt: new Date(record.createdAt ?? new Date().toISOString()),
          },
          skipDuplicates: true,
        });
        const saved = await tx.syncRecord.findUnique({
          where: {
            tenantId_kind_deviceId_localId: {
              tenantId: user.tenantId,
              kind: pathKind,
              deviceId,
              localId: record.localId,
            },
          },
          select: { id: true },
        });
        if (!saved) throw new HttpError(409, 'Operational record could not be recorded');
        synced.push({ localId: record.localId, remoteId: saved.id });
      }
    });
    if (Array.isArray(raw)) return res.json({ synced });
    return res.json({ localId: synced[0]?.localId, remoteId: synced[0]?.remoteId });
  }

  await prisma.$transaction(async (tx) => {
    for (const record of valid) {
      const deviceId = record.deviceId ?? 'legacy';
      const saved = await tx.syncRecord.upsert({
        where: { tenantId_kind_deviceId_localId: { tenantId: user.tenantId, kind: pathKind, deviceId, localId: record.localId } },
        create: {
          tenantId: user.tenantId,
          kind: pathKind,
          deviceId,
          localId: record.localId,
          payload: record as Prisma.InputJsonValue,
          createdAt: new Date(record.createdAt ?? new Date().toISOString()),
        },
        update: { payload: record as Prisma.InputJsonValue, createdAt: new Date(record.createdAt ?? new Date().toISOString()) },
        select: { id: true },
      });
      synced.push({ localId: record.localId, remoteId: saved.id });
    }
  });

  if (Array.isArray(raw)) return res.json({ synced });
  return res.json({ localId: synced[0]?.localId, remoteId: synced[0]?.remoteId });
}));

export default router;
