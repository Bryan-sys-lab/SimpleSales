import crypto from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, requireUser } from '../lib/http';
import { parseBody } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { COMMERCIAL_POLICY } from '../lib/commercial_policy';
import { COMMERCIAL_CONSENT_SCOPES } from '../lib/commercial_consent';

const router = Router();

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(record[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

const batchSchema = z.object({
  batch_id: z.string().uuid(),
  schema_version: z.literal('ci-contribution-v1'),
  dictionary_version: z.literal('2.0.0'),
  period: z.object({
    from_utc: z.string().datetime({ offset: true }),
    to_utc: z.string().datetime({ offset: true }),
    grain: z.enum(['week', 'month', 'quarter']),
    reporting_timezone: z.literal('Africa/Nairobi'),
  }).strict(),
  app_profile: z.enum(['drinks', 'duka', 'fashion', 'open']),
  scope_codes: z.array(z.enum(COMMERCIAL_CONSENT_SCOPES)).min(1).max(COMMERCIAL_CONSENT_SCOPES.length),
  dimensions: z.object({
    product_taxonomy: z.literal('GS1-GPC').optional(),
    taxonomy_version: z.string().trim().max(32).optional(),
    category_code: z.string().trim().max(32).optional(),
    unit_scheme: z.enum(['UNECE-REC20', 'local']).optional(),
    unit_code: z.string().trim().max(16).optional(),
    currency: z.literal('KES'),
  }).strict(),
  metrics: z.object({
    transaction_count: z.number().int().nonnegative(),
    quantity_base_units: z.number().finite().nonnegative().optional(),
    gross_sales_minor: z.number().int().nonnegative(),
    discount_minor: z.number().int().nonnegative(),
    refund_minor: z.number().int().nonnegative(),
    net_sales_ex_tax_minor: z.number().int().nonnegative(),
    confirmed_payment_minor: z.number().int().nonnegative().optional(),
    receivable_minor: z.number().int().nonnegative().optional(),
    cash_received_minor: z.number().int().nonnegative().optional(),
    tax_collected_minor: z.number().int().nonnegative().optional(),
  }).strict(),
  quality: z.object({
    sale_line_coverage: z.number().min(0).max(1).nullable().optional(),
    category_mapping_coverage: z.number().min(0).max(1).nullable().optional(),
    unit_mapping_coverage: z.number().min(0).max(1).nullable().optional(),
    stock_tracking_coverage: z.number().min(0).max(1).nullable().optional(),
  }).strict(),
}).strict();

router.post('/batches', asyncHandler(async (req, res) => {
  const user = requireUser(req);
  if (user.role !== 'admin') return res.status(403).json({ error: 'Commercial contribution requires the shop owner or authorized representative' });
  if (COMMERCIAL_POLICY.collectionEnabled === false && process.env.NODE_ENV === 'production') {
    return res.status(423).json({ error: 'Commercial contribution is disabled pending legal release approval' });
  }

  const input = parseBody(batchSchema, req.body);
  const from = new Date(input.period.from_utc);
  const to = new Date(input.period.to_utc);
  if (from >= to) return res.status(400).json({ error: 'Invalid contribution period' });

  const grant = await prisma.commercialConsentGrant.findFirst({
    where: { tenantId: user.tenantId, status: 'active' },
    orderBy: { effectiveAt: 'desc' },
  });
  if (!grant) return res.status(403).json({ error: 'No active commercial contribution grant' });
  const grantedScopes = new Set(grant.scopes as string[]);
  if (input.scope_codes.some((scope) => !grantedScopes.has(scope))) {
    return res.status(403).json({ error: 'Batch includes a scope not covered by the active grant' });
  }

  const hash = crypto.createHash('sha256').update(canonicalJson(input)).digest('hex');
  const existing = await prisma.commercialContribution.findFirst({
    where: { tenantId: user.tenantId, batchId: input.batch_id },
  });
  if (existing) {
    if (existing.payloadChecksum !== hash) {
      return res.status(409).json({ error: 'Batch ID already used with a different payload' });
    }
    return res.status(200).json({
      batch_id: input.batch_id,
      status: 'accepted',
      idempotent: true,
      received: false,
    });
  }

  const gross = input.metrics.gross_sales_minor;
  const discount = input.metrics.discount_minor;
  const refund = input.metrics.refund_minor;
  const tax = input.metrics.tax_collected_minor ?? 0;
  const net = input.metrics.net_sales_ex_tax_minor;
  if (gross < discount + refund) {
    return res.status(422).json({ error: 'Gross sales cannot reconcile below discounts and refunds' });
  }
  const normalizedNet = gross - discount - refund - tax;
  if (normalizedNet < 0) return res.status(422).json({ error: 'Net sales reconciliation failed' });
  if (net !== normalizedNet) {
    return res.status(422).json({ error: 'Submitted net sales do not reconcile with gross, discounts and refunds' });
  }

  await prisma.commercialContribution.create({
    data: {
      tenantId: user.tenantId,
      batchId: input.batch_id,
      recordId: crypto.randomUUID(),
      policyVersion: COMMERCIAL_POLICY.version,
      schemaVersion: input.schema_version,
      businessProfile: input.app_profile,
      periodStart: from,
      periodEnd: to,
      currency: input.dimensions.currency,
      categoryFamily: input.dimensions.category_code ?? 'unmapped',
      unitKind: input.dimensions.unit_code ?? 'unknown',
      transactionCount: input.metrics.transaction_count,
      grossRevenueMinor: gross,
      discountMinor: discount,
      refundMinor: refund,
      cogsMinor: 0,
      stockoutCount: 0,
      paymentMethodMix: {},
      coverageLevel: input.quality.sale_line_coverage === null
        ? 'unknown'
        : input.quality.sale_line_coverage === undefined
          ? 'partial'
          : input.quality.sale_line_coverage >= 0.8 ? 'complete' : 'partial',
      normalizedVersion: 'commercial-normalizer-v1',
      status: 'accepted',
      consentPurposeVersion: COMMERCIAL_POLICY.version,
      qualityFlags: [],
      payloadChecksum: hash,
      retentionState: 'active',
      acceptedAt: new Date(),
    },
  });

  return res.status(201).json({
    batch_id: input.batch_id,
    status: 'accepted',
    idempotent: false,
    received: true,
  });
}));

export default router;
