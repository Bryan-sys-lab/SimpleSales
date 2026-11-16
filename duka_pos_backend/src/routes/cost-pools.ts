/**
 * Open profile cost pool sync. Bulk upsert with idempotency by syncKey;
 * returns localId -> remoteId mapping.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, costPoolSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';

const router = Router();

router.post(
  '/sync',
  asyncHandler(async (req, res) => {
    const { costPools } = parseBody(costPoolSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const synced = await prisma.$transaction(async (tx) => {
      const result: Array<{ localId: number; remoteId: string }> = [];
      for (const pool of costPools) {
        if (!pool.syncKey) {
          throw new HttpError(400, 'Cost pool missing syncKey');
        }
        const saved = await tx.costPool.upsert({
          where: {
            tenantId_syncKey: { tenantId, syncKey: pool.syncKey },
          },
          create: {
            tenantId,
            syncKey: pool.syncKey,
            uuid: pool.uuid,
            name: pool.name,
            poolType: pool.poolType,
            investedMinor: pool.investedMinor,
            recoveredMinor: pool.recoveredMinor,
            status: pool.status,
          },
          update: {
            name: pool.name,
            poolType: pool.poolType,
            investedMinor: pool.investedMinor,
            recoveredMinor: pool.recoveredMinor,
            status: pool.status,
          },
        });
        result.push({ localId: pool.id, remoteId: saved.id });
      }
      return result;
    });
    return res.json({ synced });
  })
);

export default router;
