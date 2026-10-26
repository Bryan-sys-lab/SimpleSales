import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody, salesSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { requireRole } from '../middleware/auth';

const router = Router();

const major = (minor: number): string => (minor / 100).toFixed(2);

type SaleInput = ReturnType<typeof salesSyncSchema.parse>['sales'][number];

export function orderedStockProductIds(required: ReadonlyMap<string, number>): string[] {
  return [...required.keys()].sort();
}

async function applySale(tx: Prisma.TransactionClient, tenantId: string, staffId: string, input: SaleInput, allowNegativeStock = false): Promise<string> {
  const deviceId = input.deviceId ?? 'legacy';
  const saleDate = new Date(input.createdAt);
  const existing = await tx.sale.findUnique({
    where: { tenantId_deviceId_localId: { tenantId, deviceId, localId: input.localId } },
    select: { id: true },
  });
  if (existing) return existing.id;
  const productIds = [...new Set(input.items.map((item) => item.productId)
    .filter((id): id is string => typeof id === 'string' && id.length > 0))];
  const products = productIds.length === 0 ? [] : await tx.product.findMany({
    where: { tenantId, id: { in: productIds } },
    select: { id: true, bottleMl: true },
  });
  if (products.length !== productIds.length) throw new HttpError(409, 'One or more sale products are not in this shop');
  const taxRuleIds = [...new Set(input.items.map((item) => item.taxRuleId).filter((id): id is string => Boolean(id)))];
  if (taxRuleIds.length > 0) {
    const mapping = await tx.shopTaxEntity.findFirst({
      where: {
        tenantId,
        effectiveFrom: { lte: saleDate },
        OR: [{ effectiveTo: null }, { effectiveTo: { gt: saleDate } }],
      },
      select: { taxEntityId: true },
      orderBy: { effectiveFrom: 'desc' },
    });
    if (!mapping) throw new HttpError(409, 'Sale tax snapshot has no matching tax entity');
    const rules = await tx.taxRule.findMany({
      where: {
        id: { in: taxRuleIds },
        taxEntityId: mapping.taxEntityId,
        status: { in: ['approved', 'active'] },
        effectiveFrom: { lte: saleDate },
        OR: [{ effectiveTo: null }, { effectiveTo: { gt: saleDate } }],
      },
      select: { id: true, version: true },
    });
    const byId = new Map(rules.map((rule) => [rule.id, rule]));
    for (const item of input.items) {
      if (!item.taxRuleId) continue;
      const rule = byId.get(item.taxRuleId);
      if (!rule || (item.taxRuleVersion != null && item.taxRuleVersion !== rule.version)) {
        throw new HttpError(409, 'Sale tax snapshot does not match the effective taxpayer rule');
      }
    }
  }
  const productById = new Map(products.map((product) => [product.id, product]));
  const required = new Map<string, number>();
  for (const item of input.items) {
    if (item.productId == null) continue;
    const product = productById.get(item.productId);
    if (!product) throw new HttpError(409, 'Sale product is not in this shop');
    const namedFactor = item.portion === 'half' ? 0.5 : item.portion === 'quarter' ? 0.25 : 1;
    const portionFactor = item.portion !== 'full' && item.portionMl > 0 && Number(product.bottleMl) > 0
      ? item.portionMl / Number(product.bottleMl) : namedFactor;
    required.set(item.productId, (required.get(item.productId) ?? 0) + item.qty * portionFactor);
  }
  // Every multi-product sale locks products in the same order on every till.
  for (const productId of orderedStockProductIds(required)) {
    const qty = required.get(productId)!;
    const updated = await tx.product.updateMany({
      where: { id: productId, tenantId, ...(allowNegativeStock ? {} : { stockQty: { gte: qty } }) },
      data: { stockQty: { decrement: qty } },
    });
    if (updated.count !== 1) throw new HttpError(409, 'Insufficient stock; another till recorded the sale first');
  }
  const sale = await tx.sale.create({
    data: {
      tenantId, localId: input.localId, deviceId, staffId, staffName: input.staffName,
      buyerName: input.buyerName ?? null, buyerTin: input.buyerTin ?? null,
      paymentMethod: input.paymentMethod, paymentReference: input.paymentReference ?? null,
      total: major(input.total), profit: major(input.profit), createdAt: new Date(input.createdAt),
      items: { create: input.items.map((item) => ({
        tenantId, productId: item.productId ?? null, productName: item.productName, qty: item.qty,
        unitPrice: major(item.unitPrice), unitCost: major(item.unitCost),
        vatAmount: item.vatMinor == null ? null : major(item.vatMinor),
        taxableAmount: item.taxableMinor == null ? null : major(item.taxableMinor),
        taxClass: item.taxClass ?? null,
        vatRateBps: item.vatRateBps ?? null,
        taxRuleId: item.taxRuleId ?? null,
        taxRuleVersion: item.taxRuleVersion ?? null,
        portion: item.portion, portionMl: item.portionMl,
      })) },
      salePayments: input.tenders ? { create: input.tenders.map((tender) => ({
        tenantId, localUuid: tender.localUuid, method: tender.method, amount: major(tender.amountMinor),
        tendered: tender.tenderedMinor == null ? null : major(tender.tenderedMinor),
        change: tender.changeMinor == null ? null : major(tender.changeMinor), reference: tender.reference ?? null,
        status: tender.status, createdAt: new Date(tender.createdAt),
      })) } : undefined,
    },
    select: { id: true },
  });
  return sale.id;
}

/**
 * Accepts offline sales in oldest-first batches. The local id is scoped to the
 * tenant and persistent till identity, so retries cannot confuse another
 * device's sale. Legacy clients omit deviceId and use the stable `legacy`
 * namespace.
 */
router.post('/sync', asyncHandler(async (req, res) => {
  const { sales } = parseBody(salesSyncSchema, req.body);
  const user = requireUser(req);
  const synced: Array<{ localId: number; remoteId: string }> = [];
  const conflicts: Array<{ localId: number; reason: string }> = [];

  // Each sale is its own transaction. A busy shop may have several tills
  // reconnecting after months offline; one exhausted item must not roll back
  // every other sale in the batch. The conditional stock update is the
  // concurrency boundary: the first committed sale gets the last unit, and a
  // concurrent loser is retained locally as an explicit stock conflict.
  for (const input of sales) {
    const deviceId = input.deviceId ?? 'legacy';
    try {
      const remoteId = await prisma.$transaction((tx) => applySale(tx, user.tenantId, user.id, input));
      synced.push({ localId: input.localId, remoteId });
    } catch (error) {
      // Two reconnecting requests for the same offline sale can pass the
      // initial lookup before either commits. The unique key is the final
      // idempotency boundary; recover the committed sale instead of turning
      // a harmless retry into a 500.
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        const existing = await prisma.sale.findUnique({
          where: {
            tenantId_deviceId_localId: {
              tenantId: user.tenantId,
              deviceId,
              localId: input.localId,
            },
          },
          select: { id: true },
        });
        if (existing) {
          synced.push({ localId: input.localId, remoteId: existing.id });
          continue;
        }
      }
      if (error instanceof HttpError && error.status === 409) {
        await prisma.saleSyncConflict.upsert({
          where: { tenantId_deviceId_localId: { tenantId: user.tenantId, deviceId, localId: input.localId } },
          create: { tenantId: user.tenantId, deviceId, localId: input.localId, payload: input as Prisma.InputJsonValue, reason: error.message },
          update: { payload: input as Prisma.InputJsonValue, reason: error.message, status: 'open', resolution: null, resolvedBy: null, resolvedAt: null },
        });
        conflicts.push({ localId: input.localId, reason: error.message });
        continue;
      }
      throw error;
    }
  }

  res.json({ synced, conflicts });
}));

/**
 * Resolves one retained offline sale after a manager reviews the stock race.
 * The original payload and tenant/device/local key make this idempotent and
 * prevent a staff member from resolving another shop's conflict.
 */
router.post('/sync/conflicts/resolve', requireRole('admin', 'manager'), asyncHandler(async (req, res) => {
  const body = z.object({
    device_id: z.string().trim().min(1).max(120),
    local_id: z.number().int().positive(),
    resolution: z.enum(['accept_negative_stock', 'void']),
  }).strict().parse(req.body);
  const user = requireUser(req);
  const key = { tenantId_deviceId_localId: { tenantId: user.tenantId, deviceId: body.device_id, localId: body.local_id } };
  const conflict = await prisma.saleSyncConflict.findUnique({ where: key });
  if (!conflict) throw new HttpError(404, 'Sale conflict was not found');
  if (conflict.status === 'resolved') {
    return res.json({ resolved: true, resolution: conflict.resolution });
  }
  const resolved = await prisma.$transaction(async (tx) => {
    let remoteId: string | null = null;
    if (body.resolution === 'accept_negative_stock') {
      const parsed = salesSyncSchema.parse({ sales: [conflict.payload] });
      remoteId = await applySale(tx, user.tenantId, user.id, parsed.sales[0], true);
    }
    await tx.saleSyncConflict.update({
      where: key,
      data: { status: 'resolved', resolution: body.resolution, resolvedBy: user.id, resolvedAt: new Date() },
    });
    return remoteId;
  });
  return res.json({ resolved: true, resolution: body.resolution, remoteId: resolved });
}));

export default router;
