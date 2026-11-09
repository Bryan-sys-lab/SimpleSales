import { createHash } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { Router } from 'express';
import { asyncHandler, requireUser } from '../lib/http';
import { financialEvidenceSyncSchema, parseBody } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { requireRole } from '../middleware/auth';

const router = Router();

// Separate from operational/customer and future commercial-intelligence sync.
router.post('/sync', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
  const input = parseBody(financialEvidenceSyncSchema, req.body);
  const tenantId = requireUser(req).tenantId;
  const synced: Array<{ localId: number; remoteId: string; serverIntegrityHash: string }> = [];

  await prisma.$transaction(async (tx) => {
    for (const event of input.events) {
      const canonical = {
        uuid: event.uuid,
        eventType: event.eventType,
        sourceType: event.sourceType,
        sourceId: event.sourceId ?? null,
        occurredAtUtc: event.occurredAtUtc,
        revenueMinor: event.revenueMinor,
        cashInMinor: event.cashInMinor,
        cashOutMinor: event.cashOutMinor,
        cogsMinor: event.cogsMinor,
        operatingExpenseMinor: event.operatingExpenseMinor,
        taxCollectedMinor: event.taxCollectedMinor,
        receivableDeltaMinor: event.receivableDeltaMinor,
        payableDeltaMinor: event.payableDeltaMinor,
        customerDepositDeltaMinor: event.customerDepositDeltaMinor,
        inventoryDeltaMilliunits: event.inventoryDeltaMilliunits,
        previousHash: event.previousHash ?? null,
      };
      const serverIntegrityHash = createHash('sha256')
        .update(JSON.stringify(canonical))
        .digest('hex');
      const saved = await tx.syncRecord.upsert({
        where: { tenantId_kind_deviceId_localId: {
          tenantId, kind: 'financial_evidence', deviceId: input.deviceId,
          localId: event.localId,
        } },
        create: {
          tenantId,
          kind: 'financial_evidence',
          deviceId: input.deviceId,
          localId: event.localId,
          createdAt: new Date(event.occurredAtUtc),
          payload: {
            ...canonical,
            clientIntegrityHash: event.integrityHash,
            serverIntegrityHash,
          } as Prisma.InputJsonValue,
        },
        update: {
          payload: {
            ...canonical,
            clientIntegrityHash: event.integrityHash,
            serverIntegrityHash,
          } as Prisma.InputJsonValue,
        },
        select: { id: true },
      });
      synced.push({ localId: event.localId, remoteId: saved.id, serverIntegrityHash });
    }
  });

  return res.json({ synced });
}));

export default router;
