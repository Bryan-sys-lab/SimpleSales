/**
 * Open-profile owner finance sync — capital, drawings, loans.
 *
 * Idempotent by (tenantId, kind='owner-transactions', deviceId, localId).
 */
import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { asyncHandler, requireUser } from '../lib/http';
import { parseBody } from '../lib/validation';
import { ownerTransactionsSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { requireRole } from '../middleware/auth';

const router = Router();

router.post('/sync', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
  const user = requireUser(req);
  const { transactions } = parseBody(ownerTransactionsSyncSchema, req.body);
  const synced: Array<{ localId: number; remoteId: string }> = [];

  await prisma.$transaction(async (tx) => {
    for (const txn of transactions) {
      const deviceId = txn.deviceId ?? 'legacy';
      const saved = await tx.syncRecord.upsert({
        where: {
          tenantId_kind_deviceId_localId: {
            tenantId: user.tenantId,
            kind: 'owner-transactions',
            deviceId,
            localId: txn.localId,
          },
        },
        create: {
          tenantId: user.tenantId,
          kind: 'owner-transactions',
          deviceId,
          localId: txn.localId,
          payload: txn as Prisma.InputJsonValue,
          createdAt: new Date(txn.occurredAt),
        },
        update: {
          payload: txn as Prisma.InputJsonValue,
          updatedAt: new Date(),
        },
        select: { id: true },
      });
      synced.push({ localId: txn.localId, remoteId: saved.id });
    }
  });

  return res.json({ synced });
}));

export default router;
