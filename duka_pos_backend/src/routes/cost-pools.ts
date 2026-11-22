/**
 * Open profile cost pool sync. Bulk upsert with idempotency by syncKey;
 * returns localId -> remoteId mapping.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, costPoolSyncSchema } from '../lib/validation';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { requiredD1String } from '../lib/d1_results';

const router = Router();

router.get('/', asyncHandler(async (req, res) => {
  const pools = await prisma.costPool.findMany({
    where: { tenantId: requireUser(req).tenantId },
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    select: {
      id: true,
      uuid: true,
      name: true,
      poolType: true,
      investedMinor: true,
      recoveredMinor: true,
      status: true,
      createdAt: true,
      updatedAt: true,
    },
  });
  return res.json({
    costPools: pools.map((pool) => ({
      remoteId: pool.id,
      uuid: pool.uuid,
      name: pool.name,
      poolType: pool.poolType,
      investedMinor: pool.investedMinor,
      recoveredMinor: pool.recoveredMinor,
      status: pool.status,
      createdAt: pool.createdAt.toISOString(),
      updatedAt: pool.updatedAt.toISOString(),
    })),
  });
}));

router.post(
  '/sync',
  asyncHandler(async (req, res) => {
    const { costPools } = parseBody(costPoolSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const records = costPools.map((pool) => {
      if (!pool.syncKey) throw new HttpError(400, 'Cost pool missing syncKey');
      return pool;
    });
    const db = getD1DatabaseBinding();
    const now = new Date().toISOString();
    const results = records.length === 0 ? [] : await db.batch(records.map((pool) => db.prepare(`
      INSERT INTO cost_pools (
        id, tenant_id, sync_key, uuid, name, pool_type, invested_minor,
        recovered_minor, status, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (tenant_id, sync_key) DO UPDATE SET
        name = excluded.name,
        pool_type = excluded.pool_type,
        invested_minor = excluded.invested_minor,
        recovered_minor = excluded.recovered_minor,
        status = excluded.status,
        updated_at = excluded.updated_at
      RETURNING id
    `).bind(
      globalThis.crypto.randomUUID(),
      tenantId,
      pool.syncKey,
      pool.uuid,
      pool.name,
      pool.poolType,
      pool.investedMinor,
      pool.recoveredMinor,
      pool.status,
      now,
      now,
    )));
    const synced = records.map((pool, index) => {
      const remoteId = requiredD1String(results[index], 'id', 'cost pool');
      return { localId: pool.id, remoteId };
    });
    return res.json({ synced });
  })
);

export default router;
