/**
 * Open-profile job sync — jobs, job costs, and job payments.
 *
 * Idempotent by (tenantId, kind='jobs', deviceId, localId). The payload is
 * the full offline job snapshot (including nested costs and payments) so a
 * second till can rebuild the job without cross-device foreign-key ambiguity.
 */
import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { asyncHandler, requireUser } from '../lib/http';
import { parseBody } from '../lib/validation';
import { jobsSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { requireRole } from '../middleware/auth';

const router = Router();

router.post('/sync', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
  const user = requireUser(req);
  const { jobs } = parseBody(jobsSyncSchema, req.body);
  const synced: Array<{ localId: number; remoteId: string }> = [];

  await prisma.$transaction(async (tx) => {
    for (const job of jobs) {
      const deviceId = job.deviceId ?? 'legacy';
      const saved = await tx.syncRecord.upsert({
        where: {
          tenantId_kind_deviceId_localId: {
            tenantId: user.tenantId,
            kind: 'jobs',
            deviceId,
            localId: job.localId,
          },
        },
        create: {
          tenantId: user.tenantId,
          kind: 'jobs',
          deviceId,
          localId: job.localId,
          payload: job as Prisma.InputJsonValue,
          createdAt: new Date(job.createdAt ?? new Date().toISOString()),
        },
        update: {
          payload: job as Prisma.InputJsonValue,
          updatedAt: new Date(),
        },
        select: { id: true },
      });
      synced.push({ localId: job.localId, remoteId: saved.id });
    }
  });

  return res.json({ synced });
}));

export default router;
