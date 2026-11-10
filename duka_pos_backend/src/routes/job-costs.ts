/**
 * Open profile job cost sync. Bulk upsert with idempotency by syncKey;
 * returns localId -> remoteId mapping.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, jobCostSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';

const router = Router();

router.post(
  '/sync',
  asyncHandler(async (req, res) => {
    const { jobCosts } = parseBody(jobCostSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const synced = await prisma.$transaction(async (tx) => {
      const result: Array<{ localId: number; remoteId: string }> = [];
      for (const cost of jobCosts) {
        if (!cost.syncKey) {
          throw new HttpError(400, 'Job cost missing syncKey');
        }
        const saved = await tx.jobCost.upsert({
          where: {
            tenantId_syncKey: { tenantId, syncKey: cost.syncKey },
          },
            create: {
            tenantId,
            syncKey: cost.syncKey,
            uuid: cost.uuid,
            jobId: cost.jobId,
            type: cost.type,
            amountMinor: cost.amountMinor,
            paymentMethod: cost.paymentMethod,
            reference: cost.reference ?? null,
            staffName: cost.staffName ?? null,
            staffId: cost.staffId ?? null,
          },
          update: {
            type: cost.type,
            amountMinor: cost.amountMinor,
            paymentMethod: cost.paymentMethod,
            reference: cost.reference ?? null,
            staffName: cost.staffName ?? null,
            staffId: cost.staffId ?? null,
          },
        });
        result.push({ localId: cost.id, remoteId: saved.id });
      }
      return result;
    });
    return res.json({ synced });
  })
);

export default router;
