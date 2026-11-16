/**
 * Open profile job payment sync. Bulk upsert with idempotency by syncKey;
 * returns localId -> remoteId mapping.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, jobPaymentSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';

const router = Router();

router.post(
  '/sync',
  asyncHandler(async (req, res) => {
    const { jobPayments } = parseBody(jobPaymentSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const synced = await prisma.$transaction(async (tx) => {
      const result: Array<{ localId: number; remoteId: string }> = [];
      for (const payment of jobPayments) {
        if (!payment.syncKey) {
          throw new HttpError(400, 'Job payment missing syncKey');
        }
        const saved = await tx.jobPayment.upsert({
          where: {
            tenantId_syncKey: { tenantId, syncKey: payment.syncKey },
          },
          create: {
            tenantId,
            syncKey: payment.syncKey,
            uuid: payment.uuid,
            jobId: payment.jobId,
            amountMinor: payment.amountMinor,
            paymentMethod: payment.paymentMethod,
            reference: payment.reference,
            staffName: payment.staffName,
            staffId: payment.staffId,
          },
          update: {
            amountMinor: payment.amountMinor,
            paymentMethod: payment.paymentMethod,
            reference: payment.reference,
            staffName: payment.staffName,
            staffId: payment.staffId,
          },
        });
        result.push({ localId: payment.id, remoteId: saved.id });
      }
      return result;
    });
    return res.json({ synced });
  })
);

export default router;
