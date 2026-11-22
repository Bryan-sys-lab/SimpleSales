import { createHash } from 'node:crypto';
import { Router } from 'express';
import { asyncHandler, requireUser } from '../lib/http';
import { financialEvidenceSyncSchema, parseBody } from '../lib/validation';
import { upsertSyncRecords } from '../lib/sync_records_d1';
import { requireRole } from '../middleware/auth';

const router = Router();

// Separate from operational/customer and future commercial-intelligence sync.
router.post('/sync', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
  const input = parseBody(financialEvidenceSyncSchema, req.body);
  const tenantId = requireUser(req).tenantId;
  const records = input.events.map((event) => {
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
    return {
      event,
      serverIntegrityHash,
      payload: {
        ...canonical,
        clientIntegrityHash: event.integrityHash,
        serverIntegrityHash,
      },
    };
  });
  const syncedRecords = await upsertSyncRecords(records.map(({ event, payload }) => ({
    tenantId,
    kind: 'financial_evidence',
    deviceId: input.deviceId,
    localId: event.localId,
    payload,
    createdAt: new Date(event.occurredAtUtc),
    updatePayload: true,
  })));
  const synced = syncedRecords.map((record, index) => ({
    ...record,
    serverIntegrityHash: records[index].serverIntegrityHash,
  }));
  return res.json({ synced });
}));

export default router;
