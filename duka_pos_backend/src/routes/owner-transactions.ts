/**
 * Open profile owner transaction sync (capital / drawing / loan).
 * Bulk upsert with idempotency by syncKey; returns localId -> remoteId mapping.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, ownerTransactionSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';

const router = Router();

router.post(
  '/sync',
  asyncHandler(async (req, res) => {
    const { ownerTransactions } = parseBody(ownerTransactionSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const synced = await prisma.$transaction(async (tx) => {
      const result: Array<{ localId: number; remoteId: string }> = [];
      for (const txn of ownerTransactions) {
        if (!txn.syncKey) {
          throw new HttpError(400, 'Owner transaction missing syncKey');
        }
        const saved = await tx.ownerTransaction.upsert({
          where: {
            tenantId_syncKey: { tenantId, syncKey: txn.syncKey },
          },
          create: {
            tenantId,
            syncKey: txn.syncKey,
            uuid: txn.uuid,
            transactionType: txn.transactionType,
            amountMinor: txn.amountMinor,
            shiftId: txn.shiftId,
            staffName: txn.staffName,
            staffId: txn.staffId,
            note: txn.note,
          },
          update: {
            transactionType: txn.transactionType,
            amountMinor: txn.amountMinor,
            shiftId: txn.shiftId,
            staffName: txn.staffName,
            staffId: txn.staffId,
            note: txn.note,
          },
        });
        result.push({ localId: txn.id, remoteId: saved.id });
      }
      return result;
    });
    return res.json({ synced });
  })
);

export default router;
