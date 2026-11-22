import { Router } from 'express';
import { asyncHandler, requireUser } from '../lib/http';
import { parseBody, creditSyncSchema } from '../lib/validation';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { requireRole } from '../middleware/auth';

const router = Router();

router.post('/sync', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
  const { customers, entries } = parseBody(creditSyncSchema, req.body);
  const tenantId = requireUser(req).tenantId;
  const db = getD1DatabaseBinding();
  const statements = [];
  const now = new Date().toISOString();
  for (const input of customers) {
    const createdAt = new Date(input.createdAt).toISOString();
    statements.push(db.prepare(`
      INSERT INTO customers (
        id, tenant_id, local_uuid, name, phone, tin, notes, credit_limit_minor,
        balance_minor, active, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (tenant_id, local_uuid) DO UPDATE SET
        name = excluded.name,
        phone = excluded.phone,
        tin = excluded.tin,
        notes = excluded.notes,
        credit_limit_minor = excluded.credit_limit_minor,
        balance_minor = excluded.balance_minor,
        active = excluded.active,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at
    `).bind(
      globalThis.crypto.randomUUID(),
      tenantId,
      input.localUuid,
      input.name,
      input.phone ?? null,
      input.tin ?? null,
      input.notes ?? null,
      input.creditLimitMinor ?? null,
      input.balanceMinor,
      input.active ? 1 : 0,
      createdAt,
      now,
    ));
  }
  for (const input of entries) {
    const createdAt = new Date(input.createdAt).toISOString();
    statements.push(db.prepare(`
      INSERT INTO credit_ledger (
        id, tenant_id, local_uuid, customer_id, entry_type, amount_minor,
        sale_local_id, return_local_id, payment_method, reference, staff_name,
        note, created_at
      )
      SELECT ?, ?, ?, customers.id, ?, ?, ?, ?, ?, ?, ?, ?, ?
      FROM customers
      WHERE customers.tenant_id = ? AND customers.local_uuid = ?
      ON CONFLICT (tenant_id, local_uuid) DO UPDATE SET
        customer_id = excluded.customer_id,
        entry_type = excluded.entry_type,
        amount_minor = excluded.amount_minor,
        sale_local_id = excluded.sale_local_id,
        return_local_id = excluded.return_local_id,
        payment_method = excluded.payment_method,
        reference = excluded.reference,
        staff_name = excluded.staff_name,
        note = excluded.note,
        created_at = excluded.created_at
    `).bind(
      globalThis.crypto.randomUUID(),
      tenantId,
      input.localUuid,
      input.entryType,
      input.amountMinor,
      input.saleLocalId ?? null,
      input.returnLocalId ?? null,
      input.paymentMethod ?? null,
      input.reference ?? null,
      input.staffName,
      input.note ?? null,
      createdAt,
      tenantId,
      input.customerUuid,
    ));
  }
  if (statements.length > 0) await db.batch(statements);
  res.json({ syncedCustomers: customers.length, syncedEntries: entries.length });
}));

// Returns the tenant's customer and append-only credit snapshot for another
// till. PINs and identity data are not part of this payload.
router.get('/sync', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
  const tenantId = requireUser(req).tenantId;
  const customerLimit = Math.min(Math.max(Number(req.query.customerLimit) || 200, 1), 200);
  const customerOffset = Math.max(Number(req.query.customerOffset) || 0, 0);
  const entryLimit = Math.min(Math.max(Number(req.query.entryLimit) || 500, 1), 500);
  const entryOffset = Math.max(Number(req.query.entryOffset) || 0, 0);
  const includeCustomers = req.query.includeCustomers !== 'false';
  const includeEntries = req.query.includeEntries !== 'false';
  const [customers, entries, customerRefs] = await Promise.all([
    includeCustomers
      ? prisma.customer.findMany({ where: { tenantId }, orderBy: [{ createdAt: 'asc' }, { id: 'asc' }], skip: customerOffset, take: customerLimit })
      : Promise.resolve([]),
    includeEntries
      ? prisma.creditLedger.findMany({ where: { tenantId }, orderBy: [{ createdAt: 'asc' }, { id: 'asc' }], skip: entryOffset, take: entryLimit })
      : Promise.resolve([]),
    prisma.customer.findMany({ where: { tenantId }, select: { id: true, localUuid: true } }),
  ]);
  const customerUuidById = new Map(
    customerRefs.map((customer) => [customer.id, customer.localUuid]),
  );
  const syncedEntries = entries.flatMap((entry) => {
    const customerUuid = customerUuidById.get(entry.customerId);
    if (!customerUuid) return [];
    return [{
      localUuid: entry.localUuid,
      customerUuid,
      entryType: entry.entryType,
      amountMinor: entry.amountMinor,
      saleLocalId: entry.saleLocalId,
      returnLocalId: entry.returnLocalId,
      paymentMethod: entry.paymentMethod,
      reference: entry.reference,
      staffName: entry.staffName,
      note: entry.note,
      createdAt: entry.createdAt.toISOString(),
    }];
  });
  return res.json({
    customers: customers.map((customer) => ({
      localUuid: customer.localUuid,
      name: customer.name,
      phone: customer.phone,
      tin: customer.tin,
      notes: customer.notes,
      creditLimitMinor: customer.creditLimitMinor,
      balanceMinor: customer.balanceMinor,
      active: customer.active,
      createdAt: customer.createdAt.toISOString(),
    })),
    entries: syncedEntries,
    nextCustomerOffset: includeCustomers && customers.length === customerLimit ? customerOffset + customers.length : null,
    nextEntryOffset: includeEntries && entries.length === entryLimit ? entryOffset + entries.length : null,
  });
}));

export default router;
