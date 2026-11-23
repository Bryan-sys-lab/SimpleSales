import crypto from 'node:crypto';
import { Router } from 'express';
import { asyncHandler } from '../lib/http';
import { prisma } from '../lib/prisma';
import { buildPartnerProductCell, PartnerProductKind } from '../lib/partner_products';

const router = Router();
const products = new Set<PartnerProductKind>([
  'ngo_digitisation_pulse',
  'manufacturer_category_brand_demand',
  'supplier_replenishment_supply',
]);

router.get('/data-products/:productId', asyncHandler(async (req, res) => {
  const productId = String(req.params.productId);
  const snapshotId = typeof req.query.snapshotId === 'string' ? req.query.snapshotId : '';
  if (!products.has(productId as PartnerProductKind) || !snapshotId) {
    return res.status(400).json({ error: 'A fixed partner product and snapshot scope are required' });
  }
  const rawKey = req.header('x-partner-key')?.trim();
  if (!rawKey) return res.status(401).json({ error: 'Partner credential required' });
  const keyHash = crypto.createHash('sha256').update(rawKey).digest('hex');
  const credential = await prisma.partnerCredential.findUnique({ where: { keyHash } });
  if (!credential || credential.status !== 'active' || credential.expiresAt <= new Date()) {
    return res.status(403).json({ error: 'Partner credential is expired or revoked' });
  }

  const grant = await prisma.partnerGrant.findFirst({
    where: {
      partnerId: credential.partnerId,
      productId,
      snapshotId,
      status: 'active',
      expiresAt: { gt: new Date() },
    },
  });
  if (!grant) return res.status(403).json({ error: 'Product or snapshot is outside this partner grant' });

  const rows = await prisma.commercialContribution.findMany({
    where: { datasetSnapshotId: snapshotId, status: 'accepted', retentionState: 'active', deletedAt: null },
    select: {
      periodStart: true,
      periodEnd: true,
      categoryFamily: true,
      transactionCount: true,
      grossRevenueMinor: true,
      discountMinor: true,
      refundMinor: true,
      cogsMinor: true,
      stockoutCount: true,
    },
  });
  const contributingBusinesses = rows.length;
  const underlyingTransactions = rows.reduce((sum, row) => sum + row.transactionCount, 0);
  const periodStart = rows.reduce<string | null>((latest, row) => latest === null || row.periodStart.toISOString() < latest ? row.periodStart.toISOString() : latest, null);
  const periodEnd = rows.reduce<string | null>((latest, row) => latest === null || row.periodEnd.toISOString() > latest ? row.periodEnd.toISOString() : latest, null);
  const output = buildPartnerProductCell({
    productId: productId as PartnerProductKind,
    periodStartUtc: periodStart ?? '1970-01-01T00:00:00Z',
    periodEndUtc: periodEnd ?? '1970-01-01T00:00:01Z',
    geography: 'national',
    categoryCode: rows.length === 1 ? rows[0].categoryFamily : 'MULTI_CATEGORY',
    contributingBusinesses,
    underlyingTransactions,
    metrics: {
      transaction_count: underlyingTransactions,
      gross_sales_minor: rows.reduce((sum, row) => sum + row.grossRevenueMinor, 0),
      discount_minor: rows.reduce((sum, row) => sum + row.discountMinor, 0),
      refund_minor: rows.reduce((sum, row) => sum + row.refundMinor, 0),
      stockout_count: rows.reduce((sum, row) => sum + row.stockoutCount, 0),
    },
    methodology:
      'Backend aggregate snapshot; minimum 10 independent businesses and 100 underlying transactions; data may be suppressed.',
  });
  const responseHash = crypto.createHash('sha256').update(JSON.stringify(output)).digest('hex');
  await prisma.partnerDelivery.create({
    data: {
      partnerId: credential.partnerId,
      grantId: grant.id,
      snapshotId,
      productId,
      status: 'delivered',
      responseHash,
    },
  });
  return res.json(output);
}));

export default router;
