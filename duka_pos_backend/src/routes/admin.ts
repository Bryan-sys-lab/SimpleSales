/**
 * System administration routes.
 *
 * Mounted at /api/admin. Every route is protected by systemAdminMiddleware
 * (OIDC JWT + SYSTEM_ADMIN_SUBJECTS allowlist). A system admin sees ALL tenants.
 */
import { Request, Response, Router } from 'express';
import crypto from 'node:crypto';
import { z } from 'zod';
import { asyncHandler } from '../lib/http';
import { parseBody } from '../lib/validation';
import { adminAuditSchema, adminListQuerySchema, commercialLedgerQuerySchema, platformAnnouncementSchema, taxRuleSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { runRetention } from '../lib/retention';
import { log } from '../lib/observability';
import { systemAdminMiddleware } from '../middleware/auth';
import { COMMERCIAL_POLICY } from '../lib/commercial_policy';
import { commercialContributionSelect, projectCommercialContribution } from '../lib/commercial_ledger';
import { aggregateCommercialRows, COMMERCIAL_DISCLOSURE_THRESHOLDS, commercialRetentionCutoff, isEligibleForCommercialOutput, prepareCommercialAggregateOutput } from '../lib/commercial_controls';
import { buildCommercialQualityReport, dedupeCommercialRows } from '../lib/commercial_quality';

const router = Router();

let platformAnnouncementNotifier: ((announcement: {
  id: string;
  title: string;
  body: string;
}) => void) | null = null;

export function setPlatformAnnouncementNotifier(
  notifier: typeof platformAnnouncementNotifier,
): void {
  platformAnnouncementNotifier = notifier;
}

// All admin routes require a system-admin OIDC subject.
router.use(systemAdminMiddleware);

// Policy disclosure is visible only in the existing system-admin console.
// This endpoint exposes no contribution rows and cannot enable collection.
router.get('/commercial/policy', asyncHandler(async (_req: Request, res: Response) => {
  return res.json({ policy: COMMERCIAL_POLICY });
}));

// Restricted source-of-truth view. This is deliberately under the existing
// system-admin boundary; no merchant, analyst, or partner route is mounted.
router.get('/commercial/ledger', asyncHandler(async (req: Request, res: Response) => {
  const query = commercialLedgerQuerySchema.parse(req.query);
  const where: Record<string, unknown> = {};
  if (query.profile) where.businessProfile = query.profile;
  if (query.categoryFamily) where.categoryFamily = query.categoryFamily;
  if (query.batchId) where.batchId = query.batchId;
  if (query.status) where.status = query.status;
  if (query.from || query.to) {
    where.periodStart = {
      ...(query.from ? { gte: new Date(query.from) } : {}),
      ...(query.to ? { lte: new Date(query.to) } : {}),
    };
  }
  const rows = await prisma.commercialContribution.findMany({
    where,
    select: commercialContributionSelect,
    orderBy: [{ acceptedAt: 'desc' }, { recordId: 'desc' }],
    ...(query.cursor ? { cursor: { recordId: query.cursor }, skip: 1 } : {}),
    take: query.limit + 1,
  });
  const hasNextPage = rows.length > query.limit;
  const page = hasNextPage ? rows.slice(0, query.limit) : rows;
  await prisma.adminAuditLog.create({
    data: {
      adminId: req.auth?.sub ?? 'unknown',
      action: 'view_commercial_ledger',
      targetType: 'commercial_contribution',
      targetId: query.batchId ?? null,
      tenantId: null,
    },
  });
  return res.json({
    policy: {
      policyId: COMMERCIAL_POLICY.policyId,
      version: COMMERCIAL_POLICY.version,
      collectionEnabled: COMMERCIAL_POLICY.collectionEnabled,
      access: 'restricted_system_admin',
    },
    contributions: page.map(projectCommercialContribution),
    nextCursor: hasNextPage ? page[page.length - 1]?.recordId ?? null : null,
  });
}));

// Internal quality/reconciliation view. It is intentionally not mounted as a
// partner endpoint and returns suppressed cohorts as metadata, never as data.
router.get('/commercial/aggregate-preview', asyncHandler(async (req: Request, res: Response) => {
  const query = commercialLedgerQuerySchema.parse(req.query);
  const rows = await prisma.commercialContribution.findMany({
    where: {
      status: 'accepted',
      retentionState: 'active',
      deletedAt: null,
      ...(query.profile ? { businessProfile: query.profile } : {}),
      ...(query.categoryFamily ? { categoryFamily: query.categoryFamily } : {}),
      ...(query.from || query.to ? { periodStart: { ...(query.from ? { gte: new Date(query.from) } : {}), ...(query.to ? { lte: new Date(query.to) } : {}) } } : {}),
    },
    select: commercialContributionSelect,
    orderBy: { periodStart: 'asc' },
    take: 5000,
  });
  const eligible = rows.filter(isEligibleForCommercialOutput);
  const aggregates = aggregateCommercialRows(dedupeCommercialRows(eligible));
  const partnerSafeAggregates = prepareCommercialAggregateOutput('approved_aggregate_dataset', aggregates);
  await prisma.adminAuditLog.create({
    data: { adminId: req.auth?.sub ?? 'unknown', action: 'view_commercial_aggregate_preview', targetType: 'commercial_aggregate', tenantId: null },
  });
  return res.json({
    policy: { collectionEnabled: COMMERCIAL_POLICY.collectionEnabled, access: 'restricted_system_admin' },
    aggregates,
    // This is the same disclosure-controlled shape a future licensed partner
    // product must receive; no partner route is enabled in the disabled state.
    partnerSafeAggregates,
    eligibleContributionCount: eligible.length,
    suppressedGroupCount: aggregates.filter((aggregate) => aggregate.suppressed).length,
  });
}));

// Internal data-quality view. It returns definitions and reconciliation
// metadata, never the contribution rows themselves, and remains inside the
// system-admin boundary while collection is disabled.
router.get('/commercial/quality', asyncHandler(async (req: Request, res: Response) => {
  const query = commercialLedgerQuerySchema.parse(req.query);
  const rows = await prisma.commercialContribution.findMany({
    where: {
      ...(query.profile ? { businessProfile: query.profile } : {}),
      ...(query.categoryFamily ? { categoryFamily: query.categoryFamily } : {}),
      ...(query.batchId ? { batchId: query.batchId } : {}),
      ...(query.status ? { status: query.status } : {}),
      ...(query.from || query.to ? { periodStart: { ...(query.from ? { gte: new Date(query.from) } : {}), ...(query.to ? { lte: new Date(query.to) } : {}) } } : {}),
    },
    select: commercialContributionSelect,
    orderBy: [{ periodStart: 'asc' }, { recordId: 'asc' }],
    take: 5000,
  });
  const report = buildCommercialQualityReport(rows);
  await prisma.adminAuditLog.create({
    data: { adminId: req.auth?.sub ?? 'unknown', action: 'view_commercial_quality', targetType: 'commercial_quality', targetId: query.batchId ?? null, tenantId: null },
  });
  return res.json({
    policy: { collectionEnabled: COMMERCIAL_POLICY.collectionEnabled, access: 'restricted_system_admin' },
    definitions: {
      currency: 'ISO-4217 uppercase code; cohorts never mix currencies',
      money: 'integer minor units',
      coverage: 'complete, partial or unknown source coverage',
      freshnessThresholdDays: report.freshness.thresholdDays,
      suppression: COMMERCIAL_DISCLOSURE_THRESHOLDS,
      reproducibility: 'SHA-256 fingerprint over sorted eligible normalized contribution inputs',
    },
    report,
  });
}));

const commercialWithdrawalSchema = z.object({
  reason: z.string().trim().min(1).max(500),
}).strict();

// Withdrawal is an append-only state transition. It makes the contribution
// ineligible for every future aggregate while retaining a minimal audit trail.
router.post('/commercial/ledger/:recordId/withdraw', asyncHandler(async (req: Request, res: Response) => {
  const input = commercialWithdrawalSchema.parse(req.body);
  const recordId = Array.isArray(req.params.recordId) ? req.params.recordId[0] : req.params.recordId;
  const existing = await prisma.commercialContribution.findUnique({ where: { recordId } });
  if (!existing) return res.status(404).json({ error: 'Commercial contribution not found' });
  const updated = await prisma.$transaction(async (tx) => {
    const row = await tx.commercialContribution.update({
      where: { recordId },
      data: { status: 'withdrawn', retentionState: 'withdrawn' },
      select: commercialContributionSelect,
    });
    await tx.adminAuditLog.create({
      data: {
        adminId: req.auth?.sub ?? 'unknown',
        action: 'withdraw_commercial_contribution',
        targetType: 'commercial_contribution',
        targetId: recordId,
        tenantId: null,
      },
    });
    return row;
  });
  log('info', 'commercial.contribution_withdrawn', { recordId, reason: input.reason, adminId: req.auth?.sub ?? 'unknown' });
  return res.json({ contribution: projectCommercialContribution(updated), withdrawn: true });
}));

const commercialRetentionSchema = z.object({
  olderThanDays: z.coerce.number().int().min(30).max(3650).default(365),
  dryRun: z.boolean().default(true),
}).strict();

// Retention expires eligible source rows rather than silently rewriting them;
// all output queries exclude expired/deleted rows through the eligibility gate.
router.post('/commercial/retention/run', asyncHandler(async (req: Request, res: Response) => {
  const input = commercialRetentionSchema.parse(req.body ?? {});
  const cutoff = commercialRetentionCutoff(new Date(), input.olderThanDays);
  const where = { retentionState: 'active', acceptedAt: { lt: cutoff } };
  const expiredCount = await prisma.commercialContribution.count({ where });
  if (!input.dryRun && expiredCount > 0) {
    await prisma.commercialContribution.updateMany({
      where,
      data: { status: 'deleted', retentionState: 'expired', deletedAt: new Date() },
    });
  }
  await prisma.adminAuditLog.create({
    data: {
      adminId: req.auth?.sub ?? 'unknown',
      action: input.dryRun ? 'dry_run_commercial_retention' : 'expire_commercial_contributions',
      targetType: 'commercial_contribution',
      tenantId: null,
    },
  });
  return res.json({ expiredCount, olderThanDays: input.olderThanDays, dryRun: input.dryRun, cutoff: cutoff.toISOString() });
}));

// ---------------------------------------------------------------------------
// Platform announcements — delivered by the public update manifest on the
// next app check. They contain no tenant data and are still audit logged.
// ---------------------------------------------------------------------------

router.get('/announcement', asyncHandler(async (_req: Request, res: Response) => {
  const rows = await prisma.systemSettings.findMany({
    where: { key: { in: ['platform_announcement_id', 'platform_announcement_title', 'platform_announcement_body', 'platform_announcement_active'] } },
  });
  const values = Object.fromEntries(rows.map((row) => [row.key, row.value]));
  if (values.platform_announcement_active !== 'true' || !values.platform_announcement_id) {
    return res.json({ announcement: null });
  }
  return res.json({ announcement: {
    id: values.platform_announcement_id,
    title: values.platform_announcement_title ?? '',
    body: values.platform_announcement_body ?? '',
  } });
}));

router.post('/announcement', asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(platformAnnouncementSchema, req.body);
  const id = crypto.randomUUID();
  await prisma.$transaction([
    prisma.systemSettings.upsert({ where: { key: 'platform_announcement_id' }, update: { value: id }, create: { key: 'platform_announcement_id', value: id } }),
    prisma.systemSettings.upsert({ where: { key: 'platform_announcement_title' }, update: { value: input.title }, create: { key: 'platform_announcement_title', value: input.title } }),
    prisma.systemSettings.upsert({ where: { key: 'platform_announcement_body' }, update: { value: input.body }, create: { key: 'platform_announcement_body', value: input.body } }),
    prisma.systemSettings.upsert({ where: { key: 'platform_announcement_active' }, update: { value: String(input.active) }, create: { key: 'platform_announcement_active', value: String(input.active) } }),
    prisma.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: 'publish_platform_announcement', targetType: 'platform_announcement', targetId: id, tenantId: null } }),
  ]);
  platformAnnouncementNotifier?.({ id, title: input.title, body: input.body });
  return res.status(201).json({ id, title: input.title, body: input.body, active: input.active });
}));

router.delete('/announcement', asyncHandler(async (req: Request, res: Response) => {
  await prisma.systemSettings.updateMany({ where: { key: 'platform_announcement_active' }, data: { value: 'false' } });
  await prisma.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: 'clear_platform_announcement', targetType: 'platform_announcement', tenantId: null } });
  platformAnnouncementNotifier?.({ id: '', title: '', body: '' });
  return res.status(204).send();
}));

// ---------------------------------------------------------------------------
// GET /api/admin/dashboard — platform overview
// ---------------------------------------------------------------------------

router.get(
  '/dashboard',
  asyncHandler(async (_req: Request, res: Response) => {
    const [tenantCount, activeUserCount, sales, profileRows] = await Promise.all([
      prisma.tenant.count(),
      prisma.profile.count({ where: { active: true, deletedAt: null } }),
      prisma.sale.aggregate({ _count: true, _sum: { total: true, profit: true } }),
      prisma.tenant.groupBy({ by: ['businessProfile'], _count: { _all: true } }),
    ]);
    const churnByRisk = await prisma.churnSnapshot.groupBy({
      by: ['risk'],
      _count: { risk: true },
    });
    const distribution: Record<string, number> = {};
    for (const row of churnByRisk as Array<{ risk: string; _count: { risk: number } }>) {
      distribution[row.risk] = row._count.risk;
    }
    return res.json({
      tenants: tenantCount,
      activeUsers: activeUserCount,
      sales: {
        count: sales._count,
        total: Number(sales._sum.total ?? 0),
        profit: Number(sales._sum.profit ?? 0),
      },
      churnByRisk: distribution,
      businessProfiles: Object.fromEntries(
        ['drinks', 'duka', 'fashion', 'open'].map((profile) => [
          profile,
          (profileRows as Array<{ businessProfile: string; _count: { _all: number } }>)
              .find((row) => row.businessProfile === profile)?._count._all ?? 0,
        ]),
      ),
    });
  })
);

// ---------------------------------------------------------------------------
// GET /api/admin/churn — churn snapshots across all tenants
// ---------------------------------------------------------------------------

router.get(
  '/churn',
  asyncHandler(async (req: Request, res: Response) => {
    const { from, to, tenantId, limit } = parseBody(adminListQuerySchema, req.query);
    const where: Record<string, unknown> = {};
    if (tenantId) where.tenantId = tenantId;
    if (from || to) {
      where.date = {};
      if (from) (where.date as Record<string, unknown>).gte = from;
      if (to) (where.date as Record<string, unknown>).lte = to;
    }
    const snapshots = await prisma.churnSnapshot.findMany({
      where,
      include: { tenant: { select: { id: true, shopName: true } } },
      orderBy: { computedAt: 'desc' },
      take: limit,
    });
    return res.json({ snapshots });
  })
);

// ---------------------------------------------------------------------------
// GET /api/admin/sales — sales across all tenants
// ---------------------------------------------------------------------------

router.get(
  '/sales',
  asyncHandler(async (req: Request, res: Response) => {
    const { from, to, tenantId, limit } = parseBody(adminListQuerySchema, req.query);
    const fromDate = from ? new Date(from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const toDate = to ? new Date(to) : new Date();
    if (!Number.isFinite(fromDate.getTime()) || !Number.isFinite(toDate.getTime()) || fromDate > toDate) {
      return res.status(400).json({ error: 'Invalid report date range' });
    }
    const where: Record<string, unknown> = { createdAt: { gte: fromDate, lte: toDate } };
    if (tenantId) where.tenantId = tenantId;
    const sales = await prisma.sale.findMany({
      where,
      include: { tenant: { select: { id: true, shopName: true } } },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    return res.json({ sales });
  })
);

// GET /api/admin/laybys — current lay-by snapshots across all shops.
router.get(
  '/laybys',
  asyncHandler(async (req: Request, res: Response) => {
    const { tenantId, limit } = parseBody(adminListQuerySchema, req.query);
    const records = await prisma.syncRecord.findMany({
      where: { kind: 'laybys', ...(tenantId ? { tenantId } : {}) },
      orderBy: { updatedAt: 'desc' },
      take: limit,
      include: { tenant: { select: { id: true, shopName: true, businessProfile: true } } },
    });
    return res.json({
      laybys: records.map((record) => ({
        ...(record.payload as Record<string, unknown>),
        remoteId: record.id,
        remoteUpdatedAt: record.updatedAt.toISOString(),
        tenant: record.tenant,
      })),
    });
  }),
);

router.get('/exchanges', asyncHandler(async (req: Request, res: Response) => {
  const { tenantId, limit } = parseBody(adminListQuerySchema, req.query);
  const records = await prisma.syncRecord.findMany({
    where: { kind: 'exchanges', ...(tenantId ? { tenantId } : {}) },
    orderBy: { updatedAt: 'desc' }, take: limit,
    include: { tenant: { select: { id: true, shopName: true, businessProfile: true } } },
  });
  return res.json({ exchanges: records.map((record) => ({
    ...(record.payload as Record<string, unknown>), remoteId: record.id,
    remoteUpdatedAt: record.updatedAt.toISOString(), tenant: record.tenant,
  })) });
}));

// ---------------------------------------------------------------------------
// GET /api/admin/sessions — app sessions across all tenants
// ---------------------------------------------------------------------------

router.get(
  '/sessions',
  asyncHandler(async (req: Request, res: Response) => {
    const { from, tenantId, limit } = parseBody(adminListQuerySchema, req.query);
    const fromDate = from ? new Date(from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    if (!Number.isFinite(fromDate.getTime())) {
      return res.status(400).json({ error: 'Invalid report date range' });
    }
    const where: Record<string, unknown> = { createdAt: { gte: fromDate } };
    if (tenantId) where.tenantId = tenantId;
    const sessions = await prisma.appSession.findMany({
      where,
      include: { tenant: { select: { id: true, shopName: true } } },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    return res.json({ sessions });
  })
);

// ---------------------------------------------------------------------------
// GET /api/admin/tenants — all tenants with profile and sale counts
// ---------------------------------------------------------------------------

router.get(
  '/tenants',
  asyncHandler(async (_req: Request, res: Response) => {
    const tenants = await prisma.tenant.findMany({
      include: { _count: { select: { profiles: true, sales: true } } },
      orderBy: { createdAt: 'desc' },
    });
    return res.json({ tenants });
  })
);

router.get(
  '/tax-entities',
  asyncHandler(async (_req: Request, res: Response) => {
    const entities = await prisma.taxEntity.findMany({
      include: {
        shops: { select: { tenantId: true, outletReference: true } },
      },
      orderBy: { displayLabel: 'asc' },
    });
    return res.json({
      entities: entities.map((entity) => ({
        id: entity.id,
        display_label: entity.displayLabel,
        legal_form: entity.legalForm,
        status: entity.status,
        linked_shop_count: entity.shops.length,
      })),
    });
  }),
);

router.get(
  '/tax-compliance',
  asyncHandler(async (req: Request, res: Response) => {
    const query = z.object({
      taxEntityId: z.string().trim().min(1).max(80).optional(),
      status: z.enum(['prepared', 'submitted', 'accepted', 'rejected', 'settled']).optional(),
      limit: z.coerce.number().int().positive().max(500).default(200),
    }).parse(req.query);
    const whereEntity = query.taxEntityId ? { taxEntityId: query.taxEntityId } : {};
    const whereStatus = query.status ? { status: query.status } : {};
    const [vatReturns, totReturns] = await Promise.all([
      prisma.vatReturn.findMany({
        where: { ...whereEntity, ...whereStatus },
        include: {
          taxEntity: { select: { id: true, displayLabel: true, legalForm: true } },
          events: { orderBy: { createdAt: 'asc' } },
        },
        orderBy: [{ periodStart: 'desc' }, { updatedAt: 'desc' }],
        take: query.limit,
      }),
      prisma.totReturn.findMany({
        where: { ...whereEntity, ...whereStatus },
        include: {
          taxEntity: { select: { id: true, displayLabel: true, legalForm: true } },
          events: { orderBy: { createdAt: 'asc' } },
        },
        orderBy: [{ periodStart: 'desc' }, { updatedAt: 'desc' }],
        take: query.limit,
      }),
    ]);
    return res.json({
      vat_returns: vatReturns.map((record) => ({
        id: record.id,
        tax_type: 'vat',
        tax_entity: record.taxEntity,
        period_start: record.periodStart,
        period_end: record.periodEnd,
        output_vat: Number(record.outputVat),
        eligible_input_vat: Number(record.eligibleInputVat),
        adjustments: Number(record.adjustments),
        net_payable: Number(record.netPayable),
        evidence: record.evidence,
        status: record.status,
        rejection_reason: record.rejectionReason,
        status_events: record.events,
        updated_at: record.updatedAt,
      })),
      tot_returns: totReturns.map((record) => ({
        id: record.id,
        tax_type: 'tot',
        tax_entity: record.taxEntity,
        period_start: record.periodStart,
        period_end: record.periodEnd,
        gross_sales: Number(record.grossSales),
        estimate: Number(record.estimate),
        rate_basis_points: record.rateBasisPoints,
        evidence: record.evidence,
        status: record.status,
        rejection_reason: record.rejectionReason,
        status_events: record.events,
        updated_at: record.updatedAt,
      })),
    });
  }),
);

// ---------------------------------------------------------------------------
// Tax-rule registry — reviewed by a system tax owner before app use
// ---------------------------------------------------------------------------

const taxRuleListQuerySchema = z.object({
  status: z.enum(['draft', 'needs_review', 'approved', 'active', 'retired', 'conflicted']).optional(),
  taxEntityId: z.string().trim().min(1).max(80).optional(),
  limit: z.coerce.number().int().positive().max(1000).default(200),
});

const taxRuleApprovalSchema = z.object({
  approvalNote: z.string().trim().max(1000).optional().nullable(),
}).strict();

const taxRuleView = (rule: any) => ({
  id: rule.id,
  tax_entity_id: rule.taxEntityId,
  tax_entity: rule.taxEntity
    ? { id: rule.taxEntity.id, display_label: rule.taxEntity.displayLabel, legal_form: rule.taxEntity.legalForm }
    : null,
  tax_type: rule.taxType,
  scope: rule.scope,
  jurisdiction: rule.jurisdiction,
  rate_basis_points: rule.rateBasisPoints,
  version: rule.version,
  tax_base: rule.taxBase,
  filing_frequency: rule.filingFrequency,
  filing_due_day: rule.filingDueDay,
  threshold_minor: rule.thresholdMinor == null ? null : Number(rule.thresholdMinor),
  effective_from: rule.effectiveFrom,
  effective_to: rule.effectiveTo,
  source_url: rule.sourceUrl,
  source_reference: rule.sourceReference,
  reviewed_at: rule.reviewedAt,
  approved_by: rule.approvedBy,
  approval_note: rule.approvalNote,
  status: rule.status,
  created_at: rule.createdAt,
  updated_at: rule.updatedAt,
});

router.get(
  '/tax-rules',
  asyncHandler(async (req: Request, res: Response) => {
    const { status, taxEntityId, limit } = parseBody(taxRuleListQuerySchema, req.query);
    const rules = await prisma.taxRule.findMany({
      where: { ...(status ? { status } : {}), ...(taxEntityId ? { taxEntityId } : {}) },
      include: { taxEntity: { select: { id: true, displayLabel: true, legalForm: true } } },
      orderBy: [{ effectiveFrom: 'desc' }, { createdAt: 'desc' }],
      take: limit,
    });
    return res.json({ rules: rules.map(taxRuleView) });
  }),
);

router.post(
  '/tax-rules',
  asyncHandler(async (req: Request, res: Response) => {
    const input = parseBody(taxRuleSchema, req.body);
    const effectiveFrom = new Date(input.effectiveFrom);
    const effectiveTo = input.effectiveTo ? new Date(input.effectiveTo) : null;
    if (effectiveTo && effectiveTo <= effectiveFrom) {
      return res.status(400).json({ error: 'effectiveTo must be after effectiveFrom' });
    }
    const entity = await prisma.taxEntity.findUnique({ where: { id: input.taxEntityId }, select: { id: true } });
    if (!entity) return res.status(404).json({ error: 'Tax entity not found' });
    const rule = await prisma.taxRule.create({
      data: {
        taxEntityId: input.taxEntityId,
        taxType: input.taxType,
        scope: input.scope,
        jurisdiction: input.jurisdiction,
        rateBasisPoints: input.rateBasisPoints ?? null,
        taxBase: input.taxBase,
        filingFrequency: input.filingFrequency,
        filingDueDay: input.filingDueDay ?? null,
        thresholdMinor: input.thresholdMinor ?? null,
        effectiveFrom,
        effectiveTo,
        sourceUrl: input.sourceUrl,
        sourceReference: input.sourceReference ?? null,
        approvalNote: input.approvalNote ?? null,
        status: 'needs_review',
      },
      include: { taxEntity: { select: { id: true, displayLabel: true, legalForm: true } } },
    });
    await prisma.adminAuditLog.create({
      data: {
        adminId: req.auth?.sub ?? 'unknown',
        action: 'create_tax_rule',
        targetType: 'tax_rule',
        targetId: rule.id,
        tenantId: null,
      },
    });
    return res.status(201).json({ rule: taxRuleView(rule) });
  }),
);

router.post(
  '/tax-rules/:id/approve',
  asyncHandler(async (req: Request, res: Response) => {
    const input = parseBody(taxRuleApprovalSchema, req.body ?? {});
    const ruleId = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const existing = await prisma.taxRule.findUnique({ where: { id: ruleId } });
    if (!existing) return res.status(404).json({ error: 'Tax rule not found' });
    if (existing.status === 'retired') return res.status(409).json({ error: 'Retired tax rules cannot be approved' });
    const activeRules = await prisma.taxRule.findMany({
      where: {
        taxEntityId: existing.taxEntityId,
        taxType: existing.taxType,
        scope: existing.scope,
        status: { in: ['approved', 'active'] },
        NOT: { id: existing.id },
      },
    });
    const overlaps = activeRules.some((rule) => {
      const leftEnd = existing.effectiveTo?.getTime() ?? Number.POSITIVE_INFINITY;
      const rightEnd = rule.effectiveTo?.getTime() ?? Number.POSITIVE_INFINITY;
      return existing.effectiveFrom.getTime() < rightEnd && rule.effectiveFrom.getTime() < leftEnd;
    });
    if (overlaps) return res.status(409).json({ error: 'An approved rule already covers part of this effective period' });
    const now = new Date();
    const rule = await prisma.$transaction(async (tx) => {
      const updated = await tx.taxRule.update({
        where: { id: existing.id },
        data: {
          status: existing.effectiveFrom <= now ? 'active' : 'approved',
          reviewedAt: now,
          approvedBy: req.auth?.sub ?? 'unknown',
          approvalNote: input.approvalNote ?? existing.approvalNote,
        },
        include: { taxEntity: { select: { id: true, displayLabel: true, legalForm: true } } },
      });
      await tx.adminAuditLog.create({
        data: {
          adminId: req.auth?.sub ?? 'unknown',
          action: 'approve_tax_rule',
          targetType: 'tax_rule',
          targetId: existing.id,
          tenantId: null,
        },
      });
      return updated;
    });
    return res.json({ rule: taxRuleView(rule) });
  }),
);

// ---------------------------------------------------------------------------
// GET /api/admin/support-tickets — support tickets across all tenants
// ---------------------------------------------------------------------------

const supportTicketListQuerySchema = z.object({
  status: z.enum(['open', 'in_progress', 'resolved']).optional().nullable(),
  tenantId: z.string().uuid().optional().nullable(),
  limit: z.coerce.number().int().positive().max(1000).default(100),
});

router.get(
  '/support-tickets',
  asyncHandler(async (req: Request, res: Response) => {
    const { status, tenantId, limit } = parseBody(supportTicketListQuerySchema, req.query);
    const where: Record<string, unknown> = {};
    if (status) where.status = status;
    if (tenantId) where.tenantId = tenantId;
    const tickets = await prisma.supportTicket.findMany({
      where,
      include: { tenant: { select: { id: true, shopName: true } } },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    return res.json({ tickets });
  })
);

// ---------------------------------------------------------------------------
// GET /api/admin/audit — admin audit log
// POST /api/admin/audit — record an admin action
// ---------------------------------------------------------------------------

router.get(
  '/audit',
  asyncHandler(async (req: Request, res: Response) => {
    const { limit } = parseBody(adminListQuerySchema, req.query);
    const logs = await prisma.adminAuditLog.findMany({
      orderBy: { at: 'desc' },
      take: limit,
    });
    return res.json({ logs });
  })
);

router.post(
  '/audit',
  asyncHandler(async (req: Request, res: Response) => {
    const { action, targetType, targetId, tenantId } = parseBody(adminAuditSchema, req.body);
    if (!req.auth?.sub) {
      return res.status(401).json({ error: 'Authenticated system admin required' });
    }
    const log = await prisma.adminAuditLog.create({
      data: { adminId: req.auth.sub, action, targetType, targetId, tenantId },
    });
    return res.status(201).json(log);
  })
);



// ---------------------------------------------------------------------------
// POST /api/admin/retention/run — purge aged telemetry events (data retention)
// ---------------------------------------------------------------------------

const retentionRunSchema = z.object({
  olderThanDays: z.coerce.number().int().positive().optional().nullable(),
  dryRun: z.coerce.number().int().nonnegative().optional().nullable(),
}).strict();

router.post(
  '/retention/run',
  asyncHandler(async (req: Request, res: Response) => {
    const { olderThanDays, dryRun } = parseBody(retentionRunSchema, req.body);
    if (!req.auth?.sub) {
      return res.status(401).json({ error: 'Authenticated system admin required' });
    }
    const { deletedTelemetryEvents } = await runRetention({
      olderThanDays: olderThanDays ?? undefined,
      dryRun: dryRun ?? undefined,
    });
    await prisma.adminAuditLog.create({
      data: { adminId: req.auth.sub, action: 'purge_telemetry', targetType: 'telemetry_event', tenantId: null },
    });
    log('info', 'admin.purge_telemetry', { adminId: req.auth.sub, deletedTelemetryEvents, olderThanDays, dryRun });
    return res.json({ deletedTelemetryEvents, olderThanDays, dryRun });
  })
);

export default router;
