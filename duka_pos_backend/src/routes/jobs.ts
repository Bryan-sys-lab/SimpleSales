/**
 * Open profile job sync. Bulk upsert with idempotency by syncKey;
 * returns localId -> remoteId mapping.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, jobSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';

const router = Router();

router.post(
  '/sync',
  asyncHandler(async (req, res) => {
    const { jobs } = parseBody(jobSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const synced = await prisma.$transaction(async (tx) => {
      const result: Array<{ localId: number; remoteId: string }> = [];
      for (const job of jobs) {
        if (!job.syncKey) {
          throw new HttpError(400, 'Job missing syncKey');
        }
        const saved = await tx.job.upsert({
          where: {
            tenantId_syncKey: { tenantId, syncKey: job.syncKey },
          },
          create: {
            tenantId,
            syncKey: job.syncKey,
            uuid: job.uuid,
            title: job.title,
            customerName: job.customerName,
            customerPhone: job.customerPhone ?? null,
            quoteMinor: job.quoteMinor,
            finalPriceMinor: job.finalPriceMinor ?? null,
            status: job.status,
            dueAt: job.dueAt ? new Date(job.dueAt) : null,
            costPoolId: job.costPoolId ?? null,
            staffName: job.staffName,
            staffId: job.staffId,
          },
          update: {
            title: job.title,
            customerName: job.customerName,
            customerPhone: job.customerPhone ?? null,
            quoteMinor: job.quoteMinor,
            finalPriceMinor: job.finalPriceMinor ?? null,
            status: job.status,
            dueAt: job.dueAt ? new Date(job.dueAt) : null,
            costPoolId: job.costPoolId ?? null,
            staffName: job.staffName,
            staffId: job.staffId,
          },
        });
        result.push({ localId: job.id, remoteId: saved.id });
      }
      return result;
    });
    return res.json({ synced });
  })
);

export default router;
