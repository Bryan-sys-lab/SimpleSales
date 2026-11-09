/**
 * Open-profile cost pool sync — pools and their entries.
 *
 * Idempotent by (tenantId, kind='cost-pools', deviceId, localId). Entries
 * are carried inline in the payload so a second till sees complete pool
 * state without cross-device foreign-key ambiguity.
 */
import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { asyncHandler, requireUser } from '../lib/http';
import { parseBody } from '../lib/validation';
import { costPoolsSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { requireRole } from '../middleware/auth';

const router = Router();

router.post('/sync', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
  const user = requireUser(req);
  const { pools } = parseBody(costPoolsSyncSchema, req.body);
  const synced: Array<{ localId: number; remoteId: string }> = [];

  await prisma.$transaction(async (tx) => {
    for (const pool of pools) {
      const deviceId = pool.deviceId ?? 'legacy';
      const saved = await tx.syncRecord.upsert({
        where: {
          tenantId_kind_deviceId_localId: {
            tenantId: user.tenantId,
            kind: 'cost-pools',
            deviceId,
            localId: pool.localId,
          },
        },
        create: {
          tenantId: user.tenantId,
          kind: 'cost-pools',
          deviceId,
          localId: pool.localId,
          payload: pool as Prisma.InputJsonValue,
          createdAt: new Date(pool.createdAt ?? new Date().toISOString()),
        },
        update: {
          payload: pool as Prisma.InputJsonValue,
          updatedAt: new Date(),
        },
        select: { id: true },
      });
      synced.push({ localId: pool.localId, remoteId: saved.id });
    }
  });

  return res.json({ synced });
}));

export default router;
