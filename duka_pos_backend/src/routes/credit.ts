import { Router } from 'express';
import { asyncHandler, requireUser } from '../lib/http';
import { parseBody, creditSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { requireRole } from '../middleware/auth';

const router = Router();

router.post('/sync', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
  const { customers, entries } = parseBody(creditSyncSchema, req.body);
  const tenantId = requireUser(req).tenantId;
  await prisma.$transaction(async (tx) => {
    for (const input of customers) {
      await tx.customer.upsert({
        where: { tenantId_localUuid: { tenantId, localUuid: input.localUuid } },
        create: { tenantId, localUuid: input.localUuid, name: input.name, phone: input.phone ?? null, tin: input.tin ?? null, notes: input.notes ?? null, creditLimitMinor: input.creditLimitMinor ?? null, balanceMinor: input.balanceMinor, active: input.active, createdAt: new Date(input.createdAt) },
        update: { name: input.name, phone: input.phone ?? null, tin: input.tin ?? null, notes: input.notes ?? null, creditLimitMinor: input.creditLimitMinor ?? null, balanceMinor: input.balanceMinor, active: input.active, createdAt: new Date(input.createdAt) },
      });
    }
    for (const input of entries) {
      const customer = await tx.customer.findUnique({ where: { tenantId_localUuid: { tenantId, localUuid: input.customerUuid } }, select: { id: true } });
      if (!customer) continue;
      await tx.creditLedger.upsert({
        where: { tenantId_localUuid: { tenantId, localUuid: input.localUuid } },
        create: { tenantId, localUuid: input.localUuid, customerId: customer.id, entryType: input.entryType, amountMinor: input.amountMinor, saleLocalId: input.saleLocalId ?? null, returnLocalId: input.returnLocalId ?? null, paymentMethod: input.paymentMethod ?? null, reference: input.reference ?? null, staffName: input.staffName, note: input.note ?? null, createdAt: new Date(input.createdAt) },
        update: { customerId: customer.id, entryType: input.entryType, amountMinor: input.amountMinor, saleLocalId: input.saleLocalId ?? null, returnLocalId: input.returnLocalId ?? null, paymentMethod: input.paymentMethod ?? null, reference: input.reference ?? null, staffName: input.staffName, note: input.note ?? null, createdAt: new Date(input.createdAt) },
      });
    }
  });
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
