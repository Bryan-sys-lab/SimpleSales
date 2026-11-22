/**
 * Open profile owner transaction sync (capital / drawing / loan).
 * Bulk upsert with idempotency by syncKey; returns localId -> remoteId mapping.
 */
import { Router } from 'express';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, ownerTransactionSyncSchema } from '../lib/validation';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { requiredD1String } from '../lib/d1_results';

const router = Router();

router.get('/', asyncHandler(async (req, res) => {
  const transactions = await prisma.ownerTransaction.findMany({
    where: { tenantId: requireUser(req).tenantId },
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    select: {
      id: true,
      uuid: true,
      transactionType: true,
      amountMinor: true,
      shiftId: true,
      staffId: true,
      staffName: true,
      note: true,
      createdAt: true,
    },
  });
  return res.json({
    ownerTransactions: transactions.map((transaction) => ({
      remoteId: transaction.id,
      uuid: transaction.uuid,
      transactionType: transaction.transactionType,
      amountMinor: transaction.amountMinor,
      shiftId: transaction.shiftId,
      staffId: transaction.staffId,
      staffName: transaction.staffName,
      note: transaction.note,
      createdAt: transaction.createdAt.toISOString(),
    })),
  });
}));

router.post(
  '/sync',
  asyncHandler(async (req, res) => {
    const { ownerTransactions } = parseBody(ownerTransactionSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const records = ownerTransactions.map((txn) => {
      if (!txn.syncKey) throw new HttpError(400, 'Owner transaction missing syncKey');
      return txn;
    });
    const db = getD1DatabaseBinding();
    const now = new Date().toISOString();
    const results = records.length === 0 ? [] : await db.batch(records.map((txn) => db.prepare(`
      INSERT INTO owner_transactions (
        id, tenant_id, sync_key, uuid, transaction_type, amount_minor,
        shift_id, staff_id, staff_name, note, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (tenant_id, sync_key) DO UPDATE SET
        transaction_type = excluded.transaction_type,
        amount_minor = excluded.amount_minor,
        shift_id = excluded.shift_id,
        staff_id = excluded.staff_id,
        staff_name = excluded.staff_name,
        note = excluded.note
      RETURNING id
    `).bind(
      globalThis.crypto.randomUUID(),
      tenantId,
      txn.syncKey,
      txn.uuid,
      txn.transactionType,
      txn.amountMinor,
      txn.shiftId,
      txn.staffId,
      txn.staffName,
      txn.note,
      now,
    )));
    const synced = records.map((txn, index) => {
      const remoteId = requiredD1String(results[index], 'id', 'owner transaction');
      return { localId: txn.id, remoteId };
    });
    return res.json({ synced });
  })
);

export default router;
