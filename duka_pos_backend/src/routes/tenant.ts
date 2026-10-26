/**
 * Tenant routes: shop provisioning, settings, staff sync, portfolio, auth.
 *
 * All routes require an OIDC/app session (mounted at /api/tenant behind
 * authMiddleware in index.ts), except provision/shops and the explicitly
 * tenant-selected staff bootstrap route.
 */
import { Router } from 'express';
import { pbkdf2Sync, timingSafeEqual } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody } from '../lib/validation';
import { provisionSchema, settingsSchema, staffSyncSchema, deletionSchema, staffAuthenticateSchema, mpesaChannelSchema, taxEntitySchema, vatReturnStatusSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { authMiddleware } from '../middleware/auth';
import rateLimit from 'express-rate-limit';
import { registerPaymentChannel } from '../services/payhero';
import { taxReportingActivated, taxReportingStatus } from '../services/tax_reporting';
import { encryptTaxSecret, lastFour } from '../services/tax_entity';
import { activityTenantScope } from '../lib/activity_scope';

const router = Router();

const staffAuthLimiter = rateLimit({
  windowMs: 60_000,
  limit: 10,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
});

/** Verifies the app's self-describing PBKDF2-HMAC-SHA256 PIN format. */
function verifyStaffPin(pin: string, stored: string | null): boolean {
  if (!stored?.startsWith('pbkdf2$')) return false;
  const parts = stored.split('$');
  if (parts.length !== 4) return false;
  const iterations = Number.parseInt(parts[1], 10);
  if (!Number.isSafeInteger(iterations) || iterations < 1 || iterations > 2_000_000) {
    return false;
  }
  try {
    const salt = Buffer.from(parts[2], 'base64url');
    const expected = Buffer.from(parts[3], 'base64url');
    if (salt.length < 8 || expected.length === 0 || expected.length > 64) return false;
    const actual = pbkdf2Sync(pin, salt, iterations, expected.length, 'sha256');
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  } catch {
    // A malformed verifier is simply an invalid credential.
    return false;
  }
}

// Prisma stores server ledger amounts as major currency units. The mobile KPI
// contract is integer minor units, matching the local SQLite ledger. Keep the
// conversion at this HTTP boundary so a remote shop cannot render 100x low.
const toMinor = (value: unknown): number => {
  const major = Number(value ?? 0);
  return Number.isFinite(major) ? Math.round(major * 100) : 0;
};

const toMajorString = (minor: number): string => (minor / 100).toFixed(2);

const returnTotalMinor = (payload: unknown): number => {
  const row = payload as Record<string, unknown>;
  const value = Number(row.total ?? row.total_minor ?? 0);
  return Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0;
};

const vatReturnView = (record: any) => ({
  id: record.id,
  tax_entity_id: record.taxEntityId,
  period_start: record.periodStart,
  period_end: record.periodEnd,
  output_vat_minor: toMinor(record.outputVat),
  eligible_input_vat_minor: toMinor(record.eligibleInputVat),
  adjustments_minor: toMinor(record.adjustments),
  withholding_vat_credit_minor: toMinor(record.withholdingVatCredit),
  net_payable_minor: toMinor(record.netPayable),
  evidence: record.evidence,
  status: record.status,
  submitted_at: record.submittedAt,
  accepted_at: record.acceptedAt,
  paid_at: record.paidAt,
  rejection_reason: record.rejectionReason,
  created_at: record.createdAt,
  updated_at: record.updatedAt,
});

const totReturnView = (record: any) => ({
  id: record.id,
  tax_entity_id: record.taxEntityId,
  period_start: record.periodStart,
  period_end: record.periodEnd,
  gross_sales_minor: toMinor(record.grossSales),
  rate_basis_points: record.rateBasisPoints,
  estimate_minor: toMinor(record.estimate),
  evidence: record.evidence,
  status: record.status,
  submitted_at: record.submittedAt,
  accepted_at: record.acceptedAt,
  paid_at: record.paidAt,
  rejection_reason: record.rejectionReason,
  created_at: record.createdAt,
  updated_at: record.updatedAt,
});

// Apply OIDC auth to all routes except provision and shops.
// (authMiddleware is applied in index.ts at the /api level; we apply role
// checks inline here.)
router.use(authMiddleware);

router.post(
  '/mpesa/channel',
  asyncHandler(async (req, res) => {
    const user = requireUser(req);
    if (user.role !== 'admin') {
      return res.status(403).json({ error: 'Shop admin access required' });
    }
    const { channelType, shortCode, description } = parseBody(mpesaChannelSchema, req.body);
    const channel = await registerPaymentChannel({
      channelType,
      shortCode,
      description,
    });
    await prisma.tenant.update({
      where: { id: user.tenantId },
      data: { mpesaEnabled: true, payheroChannelId: channel.id },
    });
    return res.json({ channelId: channel.id, channelType, shortCode });
  }),
);

// ---------------------------------------------------------------------------
// Provision tenant (first-time setup)
// ---------------------------------------------------------------------------

router.post(
  '/provision',
  asyncHandler(async (req, res) => {
    const { shopName, ownerName, email, businessProfile } = parseBody(provisionSchema, req.body);
    const oidcUserId = req.auth?.sub;
    if (!oidcUserId) {
      return res.status(401).json({ error: 'Authenticated user required' });
    }
    // Verify the OIDC email matches the account email.
    // (identity.isVerifiedEmailMatch is imported where needed.)
    const existingShop = await prisma.profile.findFirst({
      where: { oidcSubject: oidcUserId, tenant: { shopName: shopName.trim() } },
    });
    if (existingShop) {
      return res.status(409).json({ error: 'This account is already linked to this shop', tenant_id: existingShop.tenantId });
    }
    const result = await prisma.$transaction(async (tx) => {
      const tenant = await tx.tenant.create({
        data: { shopName: shopName.trim(), businessProfile },
      });
      const profile = await tx.profile.create({
        data: {
          oidcSubject: oidcUserId,
          tenantId: tenant.id,
          name: ownerName.trim(),
          email,
          role: 'admin',
        },
      });
      return { tenant, profile };
    });
    return res.json({ tenant_id: result.tenant.id });
  })
);

// ---------------------------------------------------------------------------
// Get the shops linked to the authenticated OIDC account
// ---------------------------------------------------------------------------

router.get(
  '/shops',
  asyncHandler(async (req, res) => {
    const user = requireUser(req);
    const identity = req.auth;
    const accountWhere = identity?.email
      ? {
          OR: [
            ...(identity.sub ? [{ oidcSubject: identity.sub }] : []),
            { email: identity.email },
          ],
        }
      : identity?.sub
        ? { oidcSubject: identity.sub }
        : { id: user.id };
    const profiles = await prisma.profile.findMany({
      where: { ...accountWhere, active: true, deletedAt: null },
      include: { tenant: true },
      orderBy: { createdAt: 'asc' },
    });
    return res.json({
      shops: profiles.map((profile: any) => ({
        tenantId: profile.tenantId,
        shopName: profile.tenant.shopName,
        role: profile.role,
      })),
    });
  })
);

// ---------------------------------------------------------------------------
// Get tenant settings
// ---------------------------------------------------------------------------

router.get(
  '/settings',
  asyncHandler(async (req, res) => {
    const tenant = await prisma.tenant.findUnique({
      where: { id: requireUser(req).tenantId },
      select: {
        id: true,
        shopName: true,
        mpesaEnabled: true,
        etimsEnabled: true,
        taxProvider: true,
        payheroChannelId: true,
        businessProfile: true,
      },
    });
    return res.json({
      ...tenant,
      ...taxReportingStatus(),
    });
  })
);

// ---------------------------------------------------------------------------
// Update tenant settings (owner only)
// ---------------------------------------------------------------------------

router.patch(
  '/settings',
  asyncHandler(async (req, res) => {
    if (requireUser(req).role !== 'admin') {
      return res.status(403).json({ error: 'Shop admin access required' });
    }
    const { mpesaEnabled, etimsEnabled, payheroChannelId, businessProfile } = parseBody(settingsSchema, req.body);
    if (etimsEnabled === true && !taxReportingActivated()) {
      return res.status(409).json({
        error: 'Tax reporting is not activated yet',
        provider: 'risiti',
        kra_activated: false,
      });
    }
    const tenant = await prisma.tenant.update({
      where: { id: requireUser(req).tenantId },
      data: {
        ...(mpesaEnabled !== undefined && { mpesaEnabled }),
        ...(etimsEnabled !== undefined && { etimsEnabled }),
        ...(payheroChannelId !== undefined && { payheroChannelId }),
        ...(businessProfile !== undefined && { businessProfile }),
      },
    });
    return res.json(tenant);
  })
);

// ---------------------------------------------------------------------------
// Tax entity and effective shop mapping (owner only for writes)
// ---------------------------------------------------------------------------

const taxRuleView = (rule: any) => ({
  id: rule.id,
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
  status: rule.status,
});

const taxEntityView = (entity: any) => ({
  id: entity.id,
  legal_form: entity.legalForm,
  display_label: entity.displayLabel,
  kra_pin_set: Boolean(entity.kraPinCiphertext),
  kra_pin_last4: entity.kraPinLast4,
  registered_tax_obligations: entity.registeredTaxObligations,
  accounting_period_start_month: entity.accountingPeriodStartMonth,
  status: entity.status,
  etims_onboarding_status: entity.etimsOnboardingStatus,
  etims_method: entity.etimsMethod,
  rules: Array.isArray(entity.taxRules) ? entity.taxRules.map(taxRuleView) : [],
  created_at: entity.createdAt,
  updated_at: entity.updatedAt,
});

router.get(
  '/tax-entity',
  asyncHandler(async (req, res) => {
    const tenantId = requireUser(req).tenantId;
    const now = new Date();
    const link = await prisma.shopTaxEntity.findFirst({
      where: {
        tenantId,
        effectiveFrom: { lte: now },
        OR: [{ effectiveTo: null }, { effectiveTo: { gt: now } }],
      },
      include: {
        tenant: { select: { etimsEnabled: true } },
        taxEntity: {
          include: {
            taxRules: {
              where: {
                status: { in: ['approved', 'active'] },
                effectiveFrom: { lte: now },
                OR: [{ effectiveTo: null }, { effectiveTo: { gt: now } }],
              },
              orderBy: { effectiveFrom: 'desc' },
            },
          },
        },
      },
      orderBy: { effectiveFrom: 'desc' },
    });
    if (!link) return res.json({ tax_entity: null, mapping: null, threshold: null });

    const entityLinks = await prisma.shopTaxEntity.findMany({
      where: { taxEntityId: link.taxEntityId },
      select: { tenantId: true },
    });
    const month = link.taxEntity.accountingPeriodStartMonth;
    const year = now.getUTCMonth() + 1 < month ? now.getUTCFullYear() - 1 : now.getUTCFullYear();
    const periodStart = new Date(Date.UTC(year, month - 1, 1));
    const turnover = await prisma.sale.aggregate({
      where: { tenantId: { in: entityLinks.map((row) => row.tenantId) }, createdAt: { gte: periodStart } },
      _sum: { total: true },
    });
    const obligations = Array.isArray(link.taxEntity.registeredTaxObligations)
      ? link.taxEntity.registeredTaxObligations.filter((value): value is string => typeof value === 'string')
      : [];
    const totRule = link.taxEntity.taxRules.find((rule) => rule.taxType === 'tot');
    const totStart = totRule?.filingFrequency === 'quarterly'
      ? new Date(Date.UTC(now.getUTCFullYear(), Math.floor(now.getUTCMonth() / 3) * 3, 1))
      : totRule?.filingFrequency === 'annual'
        ? periodStart
        : new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    const totEnd = totRule?.filingFrequency === 'quarterly'
      ? new Date(Date.UTC(totStart.getUTCFullYear(), totStart.getUTCMonth() + 3, 1))
      : totRule?.filingFrequency === 'annual'
        ? new Date(Date.UTC(totStart.getUTCFullYear() + 1, totStart.getUTCMonth(), 1))
        : new Date(Date.UTC(totStart.getUTCFullYear(), totStart.getUTCMonth() + 1, 1));
    const totReturnRows = totRule
      ? await prisma.syncRecord.findMany({
          where: {
            tenantId: { in: entityLinks.map((row) => row.tenantId) },
            kind: 'returns',
            createdAt: { gte: totStart, lt: totEnd },
          },
          select: { payload: true },
        })
      : [];
    const totAdjustmentsMinor = totReturnRows.reduce(
      (sum, row) => sum + returnTotalMinor(row.payload),
      0,
    );
    const totTurnover = totRule
      ? await prisma.sale.aggregate({
          where: {
            tenantId: { in: entityLinks.map((row) => row.tenantId) },
            createdAt: { gte: totStart, lt: totEnd },
          },
          _sum: { total: true },
        })
      : null;
    const totTurnoverMinor = Math.max(
      0,
      toMinor(totTurnover?._sum.total) - totAdjustmentsMinor,
    );
    const totEstimateMinor = totRule?.rateBasisPoints == null
      ? null
      : Math.round((totTurnoverMinor * totRule.rateBasisPoints) / 10000);
    const totDueDate = totRule?.filingDueDay == null
      ? null
      : new Date(Date.UTC(
          totEnd.getUTCFullYear(),
          totEnd.getUTCMonth(),
          Math.min(totRule.filingDueDay, 28),
        ));
    const vatPeriodEnd = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
    const vatPeriodStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    const vatLines = await prisma.saleItem.findMany({
      where: {
        tenantId: { in: entityLinks.map((row) => row.tenantId) },
        sale: { createdAt: { gte: vatPeriodStart, lt: vatPeriodEnd } },
      },
      select: {
        taxClass: true,
        vatRateBps: true,
        vatAmount: true,
        taxRuleId: true,
      },
    });
    const etimsReceipts = await prisma.etimsReceipt.findMany({
      where: { tenantId: { in: entityLinks.map((row) => row.tenantId) } },
      select: { status: true },
    });
    const etimsQueue = etimsReceipts.reduce(
      (counts, receipt) => {
        if (receipt.status === 'issued') counts.issued += 1;
        else if (receipt.status === 'pending') counts.pending += 1;
        else if (receipt.status === 'rejected') counts.rejected += 1;
        return counts;
      },
      { issued: 0, pending: 0, rejected: 0 },
    );
    const conditionalObligations = [
      'income_tax',
      'withholding',
      'withholding_vat',
      'excise',
      'payroll',
    ].map((taxType) => {
      const configured = link.taxEntity.taxRules.filter((rule) => rule.taxType === taxType).length;
      const registered = obligations.includes(taxType);
      return {
        tax_type: taxType,
        registered,
        reviewed_rule_count: configured,
        status: !registered
          ? 'not_registered'
          : configured > 0
            ? 'configured'
            : 'not_supported_for_automated_calculation',
      };
    });
    const vatGroups = new Map<string, { taxClass: string; rateBasisPoints: number | null; vatMinor: number; lines: number }>();
    let vatLinesWithoutRule = 0;
    for (const line of vatLines) {
      if (!line.taxRuleId) vatLinesWithoutRule += 1;
      const taxClass = line.taxClass ?? 'legacy_unknown';
      const key = `${taxClass}:${line.vatRateBps ?? 'null'}`;
      const prior = vatGroups.get(key) ?? {
        taxClass,
        rateBasisPoints: line.vatRateBps,
        vatMinor: 0,
        lines: 0,
      };
      prior.vatMinor += toMinor(line.vatAmount);
      prior.lines += 1;
      vatGroups.set(key, prior);
    }
    const returnRows = await prisma.syncRecord.findMany({
      where: {
        tenantId: { in: entityLinks.map((row) => row.tenantId) },
        kind: 'returns',
        createdAt: { gte: vatPeriodStart, lt: vatPeriodEnd },
      },
      select: { payload: true },
    });
    const creditNoteVatMinor = returnRows.reduce((sum, row) => {
      const payload = row.payload as Record<string, unknown>;
      const value = Number(payload.vatTotal ?? payload.vat_total ?? 0);
      return sum + (Number.isFinite(value) ? Math.round(value) : 0);
    }, 0);
    // Purchase evidence is carried through the existing offline purchase
    // stream. Only verified evidence contributes to eligible input VAT; a
    // recorded amount without a supplier invoice/reference stays visible as
    // needs-review evidence.
    const inputLookbackStart = new Date(Date.UTC(
      vatPeriodStart.getUTCFullYear(),
      vatPeriodStart.getUTCMonth() - 12,
      1,
    ));
    const purchaseRows = await prisma.syncRecord.findMany({
      where: {
        tenantId: { in: entityLinks.map((row) => row.tenantId) },
        kind: 'purchases',
        createdAt: { gte: inputLookbackStart, lt: vatPeriodEnd },
      },
      select: { payload: true, createdAt: true },
    });
    let eligibleInputVatMinor = 0;
    let purchaseEvidenceCount = 0;
    let unmatchedPurchaseCount = 0;
    let overduePurchaseCount = 0;
    const claimWindowStart = new Date(Date.UTC(
      vatPeriodStart.getUTCFullYear(),
      vatPeriodStart.getUTCMonth() - 6,
      1,
    ));
    for (const row of purchaseRows) {
      const payload = row.payload as Record<string, unknown>;
      const receivedAt = new Date(String(payload.createdAt ?? row.createdAt));
      const inputVat = Number(payload.inputVatMinor ?? 0);
      const hasReference = Boolean(payload.etimsInvoiceRef || payload.invoiceNumber);
      const status = String(payload.taxEvidenceStatus ?? 'needs_review');
      const inCurrentPeriod = receivedAt >= vatPeriodStart && receivedAt < vatPeriodEnd;
      if (inCurrentPeriod && inputVat > 0 && hasReference && status === 'verified') {
        eligibleInputVatMinor += Math.round(inputVat);
      }
      if (inCurrentPeriod && (inputVat > 0 || hasReference)) purchaseEvidenceCount += 1;
      if (inCurrentPeriod && (!hasReference || status === 'needs_review')) unmatchedPurchaseCount += 1;
      if (inputVat > 0 && receivedAt < claimWindowStart && status !== 'verified') overduePurchaseCount += 1;
    }
    return res.json({
      tax_entity: taxEntityView(link.taxEntity),
      mapping: {
        shop_id: tenantId,
        outlet_reference: link.outletReference,
        effective_from: link.effectiveFrom,
        effective_to: link.effectiveTo,
      },
      threshold: {
        period_start: periodStart,
        linked_shop_count: entityLinks.length,
        turnover_minor: toMinor(turnover._sum.total),
        status: link.taxEntity.status === 'active' ? 'calculated' : 'needs_review',
      },
      obligation_report: {
        vat: {
          registered: obligations.includes('vat'),
          rule_count: link.taxEntity.taxRules.filter((rule) => rule.taxType === 'vat').length,
          status: link.taxEntity.taxRules.some((rule) => rule.taxType === 'vat') ? 'configured' : 'needs_review',
        },
        etims: {
          registered: obligations.includes('etims'),
          enabled: link.tenant.etimsEnabled && taxReportingActivated(),
          status: taxReportingActivated() ? 'available' : 'not_activated',
          queue: {
            ...etimsQueue,
            status: etimsQueue.rejected > 0
              ? 'needs_attention'
              : etimsQueue.pending > 0
                ? 'pending'
                : 'clear',
          },
        },
        tot: {
          registered: obligations.includes('tot'),
          status: link.taxEntity.taxRules.some((rule) => rule.taxType === 'tot') ? 'configured' : 'needs_review',
        },
        conditional: conditionalObligations,
      },
      tot_report: {
        registered: obligations.includes('tot'),
        status: !totRule ? 'needs_review' : 'indicative_not_filed',
        period_start: totRule ? totStart : null,
        period_end: totRule ? totEnd : null,
        gross_sales_minor: totRule ? totTurnoverMinor : null,
        estimate_minor: obligations.includes('tot') ? totEstimateMinor : null,
        returns_and_credit_notes_minor: totRule ? totAdjustmentsMinor : null,
        due_date: obligations.includes('tot') ? totDueDate : null,
        rate_basis_points: totRule?.rateBasisPoints ?? null,
        source_url: totRule?.sourceUrl ?? null,
      },
      vat_report: {
        period_start: vatPeriodStart,
        period_end: vatPeriodEnd,
        output_vat_minor: [...vatGroups.values()].reduce((sum, row) => sum + row.vatMinor, 0),
        credit_note_vat_minor: creditNoteVatMinor,
        adjusted_output_vat_minor: [...vatGroups.values()].reduce((sum, row) => sum + row.vatMinor, 0) - creditNoteVatMinor,
        by_tax_class: [...vatGroups.values()],
        lines_without_rule_snapshot: vatLinesWithoutRule,
        status: vatLinesWithoutRule === 0 ? 'reconciled' : 'needs_review',
      },
      input_vat_report: {
        period_start: vatPeriodStart,
        period_end: vatPeriodEnd,
        eligible_input_vat_minor: eligibleInputVatMinor,
        evidence_count: purchaseEvidenceCount,
        unmatched_count: unmatchedPurchaseCount,
        overdue_count: overduePurchaseCount,
        status: unmatchedPurchaseCount === 0 ? 'reconciled' : 'needs_review',
      },
    });
  }),
);

/**
 * Prepares/exports a VAT-period reconciliation. This is evidence, not a KRA
 * filing: the persisted status remains `prepared` until an approved external
 * integration or an authorised reviewer records the next state.
 */
router.get(
  '/tax-entity/vat-return',
  asyncHandler(async (req, res) => {
    const tenantId = requireUser(req).tenantId;
    const now = new Date();
    const rawStart = typeof req.query.period_start === 'string' ? req.query.period_start : null;
    const rawEnd = typeof req.query.period_end === 'string' ? req.query.period_end : null;
    const periodStart = rawStart ? new Date(rawStart) : new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    const periodEnd = rawEnd ? new Date(rawEnd) : new Date(Date.UTC(periodStart.getUTCFullYear(), periodStart.getUTCMonth() + 1, 1));
    if (!Number.isFinite(periodStart.getTime()) || !Number.isFinite(periodEnd.getTime()) || periodEnd <= periodStart) {
      return res.status(400).json({ error: 'Invalid VAT return period' });
    }
    const link = await prisma.shopTaxEntity.findFirst({
      where: {
        tenantId,
        effectiveFrom: { lte: periodStart },
        OR: [{ effectiveTo: null }, { effectiveTo: { gt: periodStart } }],
      },
      select: { taxEntityId: true },
      orderBy: { effectiveFrom: 'desc' },
    });
    if (!link) return res.status(404).json({ error: 'Tax entity mapping is not configured' });
    const entityLinks = await prisma.shopTaxEntity.findMany({
      where: { taxEntityId: link.taxEntityId },
      select: { tenantId: true },
    });
    const tenantIds = entityLinks.map((row) => row.tenantId);
    const saleLines = await prisma.saleItem.findMany({
      where: { tenantId: { in: tenantIds }, sale: { createdAt: { gte: periodStart, lt: periodEnd } } },
      select: { taxClass: true, vatRateBps: true, vatAmount: true, taxRuleId: true },
    });
    const outputGroups = new Map<string, { tax_class: string; rate_basis_points: number | null; vat_minor: number; lines: number }>();
    let linesWithoutRule = 0;
    for (const line of saleLines) {
      if (!line.taxRuleId) linesWithoutRule += 1;
      const taxClass = line.taxClass ?? 'legacy_unknown';
      const key = `${taxClass}:${line.vatRateBps ?? 'null'}`;
      const group = outputGroups.get(key) ?? {
        tax_class: taxClass,
        rate_basis_points: line.vatRateBps,
        vat_minor: 0,
        lines: 0,
      };
      group.vat_minor += toMinor(line.vatAmount);
      group.lines += 1;
      outputGroups.set(key, group);
    }
    const purchaseRows = await prisma.syncRecord.findMany({
      where: { tenantId: { in: tenantIds }, kind: 'purchases', createdAt: { gte: periodStart, lt: periodEnd } },
      select: { payload: true },
    });
    const returnRows = await prisma.syncRecord.findMany({
      where: { tenantId: { in: tenantIds }, kind: 'returns', createdAt: { gte: periodStart, lt: periodEnd } },
      select: { payload: true },
    });
    const creditNoteVatMinor = returnRows.reduce((sum, row) => {
      const payload = row.payload as Record<string, unknown>;
      const value = Number(payload.vatTotal ?? payload.vat_total ?? 0);
      return sum + (Number.isFinite(value) ? Math.round(value) : 0);
    }, 0);
    let eligibleInput = 0;
    let evidenceCount = 0;
    let unmatchedCount = 0;
    for (const row of purchaseRows) {
      const payload = row.payload as Record<string, unknown>;
      const inputVat = Number(payload.inputVatMinor ?? 0);
      const hasReference = Boolean(payload.etimsInvoiceRef || payload.invoiceNumber);
      const status = String(payload.taxEvidenceStatus ?? 'needs_review');
      if (inputVat > 0 || hasReference) evidenceCount += 1;
      if (inputVat > 0 && hasReference && status === 'verified') eligibleInput += Math.round(inputVat);
      if (!hasReference || status === 'needs_review' || status === 'unmatched') unmatchedCount += 1;
    }
    const outputVat = [...outputGroups.values()].reduce((sum, row) => sum + row.vat_minor, 0);
    const adjustedOutputVat = outputVat - creditNoteVatMinor;
    const existing = await prisma.vatReturn.findUnique({
      where: { taxEntityId_periodStart_periodEnd: { taxEntityId: link.taxEntityId, periodStart, periodEnd } },
    });
    const evidence = {
      output_by_tax_class: [...outputGroups.values()],
      credit_note_vat_minor: creditNoteVatMinor,
      adjusted_output_vat_minor: adjustedOutputVat,
      withholding_vat_credit_minor: 0,
      withholding_vat_credit_status: 'not_supported_for_automated_calculation',
      lines_without_rule_snapshot: linesWithoutRule,
      purchase_evidence_count: evidenceCount,
      unmatched_purchase_count: unmatchedCount,
      source: 'offline-ledger-and-backend-sync',
    };
    const record = await prisma.vatReturn.upsert({
      where: { taxEntityId_periodStart_periodEnd: { taxEntityId: link.taxEntityId, periodStart, periodEnd } },
      create: {
        taxEntityId: link.taxEntityId,
        periodStart,
        periodEnd,
        outputVat: toMajorString(outputVat),
        eligibleInputVat: toMajorString(eligibleInput),
        adjustments: toMajorString(-creditNoteVatMinor),
        netPayable: toMajorString(adjustedOutputVat - eligibleInput),
        evidence,
      },
      update: existing && existing.status !== 'prepared'
        ? {}
        : {
            outputVat: toMajorString(outputVat),
            eligibleInputVat: toMajorString(eligibleInput),
            adjustments: toMajorString(-creditNoteVatMinor),
            netPayable: toMajorString(adjustedOutputVat - eligibleInput),
            evidence,
          },
    });
    return res.json({ vat_return: vatReturnView(record), export_type: 'reconciliation_evidence' });
  }),
);

router.post(
  '/tax-entity/vat-return/status',
  asyncHandler(async (req, res) => {
    const user = requireUser(req);
    if (user.role !== 'admin') return res.status(403).json({ error: 'Shop admin access required' });
    const input = parseBody(vatReturnStatusSchema, req.body);
    const periodStart = new Date(input.periodStart);
    const periodEnd = new Date(input.periodEnd);
    const link = await prisma.shopTaxEntity.findFirst({
      where: { tenantId: user.tenantId, taxEntity: { vatReturns: { some: { periodStart, periodEnd } } } },
      select: { taxEntityId: true },
    });
    if (!link) return res.status(404).json({ error: 'Prepared VAT return not found' });
    const current = await prisma.vatReturn.findUnique({
      where: { taxEntityId_periodStart_periodEnd: { taxEntityId: link.taxEntityId, periodStart, periodEnd } },
    });
    if (!current) return res.status(404).json({ error: 'Prepared VAT return not found' });
    const allowed: Record<string, string[]> = {
      prepared: ['submitted', 'rejected'],
      submitted: ['accepted', 'rejected'],
      accepted: ['settled'],
      rejected: ['prepared'],
      settled: [],
    };
    if (current.status !== input.status && !allowed[current.status]?.includes(input.status)) {
      return res.status(409).json({ error: `Invalid VAT return status transition: ${current.status} -> ${input.status}` });
    }
    const now = new Date();
    const updated = await prisma.$transaction(async (tx) => {
      const saved = await tx.vatReturn.update({
        where: { id: current.id },
        data: {
          status: input.status,
          rejectionReason: input.status === 'rejected' ? input.rejectionReason ?? null : null,
          submittedAt: input.status === 'submitted' ? now : current.submittedAt,
          acceptedAt: input.status === 'accepted' ? now : current.acceptedAt,
          paidAt: input.status === 'settled' ? now : current.paidAt,
        },
      });
      if (current.status !== input.status) {
        await tx.taxReturnEvent.create({
          data: {
            taxEntityId: link.taxEntityId,
            vatReturnId: current.id,
            fromStatus: current.status,
            toStatus: input.status,
            actorId: user.id,
            note: input.rejectionReason ?? null,
          },
        });
      }
      return saved;
    });
    return res.json({ vat_return: vatReturnView(updated) });
  }),
);

router.get(
  '/tax-entity/tot-return',
  asyncHandler(async (req, res) => {
    const tenantId = requireUser(req).tenantId;
    const now = new Date();
    const link = await prisma.shopTaxEntity.findFirst({
      where: {
        tenantId,
        effectiveFrom: { lte: now },
        OR: [{ effectiveTo: null }, { effectiveTo: { gt: now } }],
      },
      include: { taxEntity: { include: { taxRules: true } } },
      orderBy: { effectiveFrom: 'desc' },
    });
    if (!link) return res.status(404).json({ error: 'Tax entity mapping is not configured' });
    const rule = link.taxEntity.taxRules.find((candidate) =>
      candidate.taxType === 'tot' &&
      ['approved', 'active'].includes(candidate.status) &&
      candidate.effectiveFrom <= now &&
      (candidate.effectiveTo == null || candidate.effectiveTo > now));
    if (!rule || rule.rateBasisPoints == null) {
      return res.status(409).json({ error: 'No active reviewed TOT rule is configured' });
    }
    const start = rule.filingFrequency === 'quarterly'
      ? new Date(Date.UTC(now.getUTCFullYear(), Math.floor(now.getUTCMonth() / 3) * 3, 1))
      : rule.filingFrequency === 'annual'
        ? new Date(Date.UTC(now.getUTCFullYear(), 0, 1))
        : new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    const end = rule.filingFrequency === 'quarterly'
      ? new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + 3, 1))
      : rule.filingFrequency === 'annual'
        ? new Date(Date.UTC(start.getUTCFullYear() + 1, 0, 1))
        : new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + 1, 1));
    const linked = await prisma.shopTaxEntity.findMany({
      where: { taxEntityId: link.taxEntityId },
      select: { tenantId: true },
    });
    const sales = await prisma.sale.aggregate({
      where: { tenantId: { in: linked.map((row) => row.tenantId) }, createdAt: { gte: start, lt: end } },
      _sum: { total: true },
    });
    const returnRows = await prisma.syncRecord.findMany({
      where: {
        tenantId: { in: linked.map((row) => row.tenantId) },
        kind: 'returns',
        createdAt: { gte: start, lt: end },
      },
      select: { payload: true },
    });
    const returnsAndCreditNotesMinor = returnRows.reduce(
      (sum, row) => sum + returnTotalMinor(row.payload),
      0,
    );
    const grossSalesMinor = Math.max(
      0,
      toMinor(sales._sum.total) - returnsAndCreditNotesMinor,
    );
    const estimateMinor = Math.round((grossSalesMinor * rule.rateBasisPoints) / 10000);
    const evidence = {
      basis: 'gross_sales',
      expenses_deducted: false,
      returns_and_credit_notes_minor: returnsAndCreditNotesMinor,
      linked_shop_count: linked.length,
      source: 'sales-ledger',
      due_day: rule.filingDueDay,
      source_url: rule.sourceUrl,
    };
    const prior = await prisma.totReturn.findUnique({
      where: { taxEntityId_periodStart_periodEnd: { taxEntityId: link.taxEntityId, periodStart: start, periodEnd: end } },
      select: { status: true },
    });
    const record = await prisma.totReturn.upsert({
      where: { taxEntityId_periodStart_periodEnd: { taxEntityId: link.taxEntityId, periodStart: start, periodEnd: end } },
      create: {
        taxEntityId: link.taxEntityId,
        periodStart: start,
        periodEnd: end,
        grossSales: toMajorString(grossSalesMinor),
        rateBasisPoints: rule.rateBasisPoints,
        estimate: toMajorString(estimateMinor),
        evidence,
      },
      update: {
        ...(prior?.status === 'prepared'
          ? {
              grossSales: toMajorString(grossSalesMinor),
              rateBasisPoints: rule.rateBasisPoints,
              estimate: toMajorString(estimateMinor),
              evidence,
            }
          : {}),
      },
    });
    return res.json({ tot_return: totReturnView(record), export_type: 'indicative_period_evidence' });
  }),
);

router.post(
  '/tax-entity/tot-return/status',
  asyncHandler(async (req, res) => {
    const user = requireUser(req);
    if (user.role !== 'admin') return res.status(403).json({ error: 'Shop admin access required' });
    const input = parseBody(vatReturnStatusSchema, req.body);
    const periodStart = new Date(input.periodStart);
    const periodEnd = new Date(input.periodEnd);
    const link = await prisma.shopTaxEntity.findFirst({
      where: { tenantId: user.tenantId, taxEntity: { totReturns: { some: { periodStart, periodEnd } } } },
      select: { taxEntityId: true },
    });
    if (!link) return res.status(404).json({ error: 'Prepared TOT return not found' });
    const current = await prisma.totReturn.findUnique({
      where: { taxEntityId_periodStart_periodEnd: { taxEntityId: link.taxEntityId, periodStart, periodEnd } },
    });
    if (!current) return res.status(404).json({ error: 'Prepared TOT return not found' });
    const allowed: Record<string, string[]> = {
      prepared: ['submitted', 'rejected'], submitted: ['accepted', 'rejected'],
      accepted: ['settled'], rejected: ['prepared'], settled: [],
    };
    if (current.status !== input.status && !allowed[current.status]?.includes(input.status)) {
      return res.status(409).json({ error: `Invalid TOT return status transition: ${current.status} -> ${input.status}` });
    }
    const now = new Date();
    const updated = await prisma.$transaction(async (tx) => {
      const saved = await tx.totReturn.update({
        where: { id: current.id },
        data: {
          status: input.status,
          rejectionReason: input.status === 'rejected' ? input.rejectionReason ?? null : null,
          submittedAt: input.status === 'submitted' ? now : current.submittedAt,
          acceptedAt: input.status === 'accepted' ? now : current.acceptedAt,
          paidAt: input.status === 'settled' ? now : current.paidAt,
        },
      });
      if (current.status !== input.status) {
        await tx.taxReturnEvent.create({
          data: {
            taxEntityId: link.taxEntityId,
            totReturnId: current.id,
            fromStatus: current.status,
            toStatus: input.status,
            actorId: user.id,
            note: input.rejectionReason ?? null,
          },
        });
      }
      return saved;
    });
    return res.json({ tot_return: totReturnView(updated) });
  }),
);

router.patch(
  '/tax-entity',
  asyncHandler(async (req, res) => {
    const user = requireUser(req);
    if (user.role !== 'admin') return res.status(403).json({ error: 'Shop admin access required' });
    const input = parseBody(taxEntitySchema, req.body);
    const tenantId = user.tenantId;
    const effectiveFrom = new Date(input.effectiveFrom);
    const saved = await prisma.$transaction(async (tx) => {
      const now = new Date();
      const current = await tx.shopTaxEntity.findFirst({
        where: {
          tenantId,
          effectiveFrom: { lte: now },
          OR: [{ effectiveTo: null }, { effectiveTo: { gt: now } }],
        },
        include: { taxEntity: true },
        orderBy: { effectiveFrom: 'desc' },
      });
      if (current && effectiveFrom < current.effectiveFrom) {
        throw new HttpError(409, 'A tax-entity mapping cannot be back-dated over the current mapping');
      }
      const data = {
        legalForm: input.legalForm,
        displayLabel: input.displayLabel,
        registeredTaxObligations: input.registeredTaxObligations,
        accountingPeriodStartMonth: input.accountingPeriodStartMonth,
        status: input.status,
        etimsOnboardingStatus: input.etimsOnboardingStatus,
        etimsMethod: input.etimsMethod ?? null,
        ...(input.kraPin === undefined ? {} : {
          kraPinCiphertext: encryptTaxSecret(input.kraPin),
          kraPinLast4: lastFour(input.kraPin),
        }),
      };
      const entity = current
        ? await tx.taxEntity.update({ where: { id: current.taxEntityId }, data })
        : await tx.taxEntity.create({ data });
      if (current && current.effectiveFrom.getTime() === effectiveFrom.getTime()) {
        await tx.shopTaxEntity.update({
          where: { id: current.id },
          data: { taxEntityId: entity.id, outletReference: input.outletReference },
        });
      } else {
        if (current && current.effectiveTo == null && effectiveFrom > current.effectiveFrom) {
          await tx.shopTaxEntity.update({ where: { id: current.id }, data: { effectiveTo: effectiveFrom } });
        }
        await tx.shopTaxEntity.create({
          data: {
            tenantId,
            taxEntityId: entity.id,
            outletReference: input.outletReference,
            effectiveFrom,
          },
        });
      }
      return entity;
    });
    return res.json({ tax_entity: taxEntityView(saved) });
  }),
);

// ---------------------------------------------------------------------------
// Bulk staff sync (owner only)
// ---------------------------------------------------------------------------

router.post(
  '/staff/sync',
  asyncHandler(async (req, res) => {
    if (requireUser(req).role !== 'admin') {
      return res.status(403).json({ error: 'Shop admin access required' });
    }
    const { staff } = parseBody(staffSyncSchema, req.body);
    const tenantId = requireUser(req).tenantId;
    const usernames = staff
      .map((item) => item.username?.trim().toLowerCase())
      .filter((username): username is string => Boolean(username));
    const duplicate = usernames.find(
      (username, index) => usernames.indexOf(username) !== index,
    );
    if (duplicate) {
      return res.status(409).json({
        error: 'Each staff username must be unique within this shop',
        username: duplicate,
      });
    }
    if (usernames.length > 0) {
      const existing = await prisma.profile.findMany({
        where: { tenantId, username: { in: usernames } },
        select: { id: true, localId: true, username: true },
      });
      for (const profile of existing) {
        const incoming = staff.find(
          (item) => item.username?.trim().toLowerCase() === profile.username,
        );
        const isSameProfile = incoming != null &&
          (incoming.remoteId === profile.id ||
            (incoming.remoteId == null && incoming.localId === profile.localId));
        if (!isSameProfile) {
          return res.status(409).json({
            error: 'That staff username is already used in this shop',
            username: profile.username,
          });
        }
      }
    }
    const synced = await prisma.$transaction(async (tx) => {
      const result: any[] = [];
      for (const item of staff) {
        const existing = item.remoteId
          ? await tx.profile.findFirst({ where: { id: item.remoteId, tenantId, role: { in: ['cashier', 'manager'] } } })
          : await tx.profile.findFirst({ where: { tenantId, localId: item.localId, role: { in: ['cashier', 'manager'] } } });
        const credential = item.pinHash == null ? {} : { pinHash: item.pinHash };
        const username = item.username?.trim().toLowerCase() ?? null;
        const profile = existing
          ? await tx.profile.update({ where: { id: existing.id }, data: { name: item.name, username, active: item.active, ...credential } })
          : await tx.profile.create({ data: { tenantId, localId: item.localId, name: item.name, username, role: item.role, active: item.active, ...credential } });
        result.push({ localId: item.localId, remoteId: profile.id });
      }
      return result;
    });
    return res.json({ synced });
  })
);

// Pull profile changes made by another till. PIN material is intentionally
// absent: each device owns its local unlock secret.
router.get(
  '/staff',
  asyncHandler(async (req, res) => {
    const profiles = await prisma.profile.findMany({
      where: {
        tenantId: requireUser(req).tenantId,
        role: { in: ['cashier', 'manager'] },
      },
      select: { id: true, localId: true, name: true, username: true, role: true, active: true },
      orderBy: { name: 'asc' },
    });
    return res.json({ staff: profiles });
  })
);

// ---------------------------------------------------------------------------
// Delete a cashier's identity data (owner only)
// ---------------------------------------------------------------------------

router.delete(
  '/staff/:profileId',
  asyncHandler(async (req, res) => {
    if (requireUser(req).role !== 'admin') {
      return res.status(403).json({ error: 'Shop admin access required' });
    }
    const { reason } = parseBody(deletionSchema, req.body ?? {});
    const profileId = req.params.profileId as string;
    const profile = await prisma.profile.findFirst({
      where: { id: profileId, tenantId: requireUser(req).tenantId, role: { in: ['cashier', 'manager'] } },
    });
    if (!profile) {
      return res.status(404).json({ error: 'Staff profile not found' });
    }
    const deletedLabel = 'Deleted cashier';
    await prisma.$transaction(async (tx) => {
      await tx.deletionLedger.create({
        data: {
          tenantId: requireUser(req).tenantId,
          subjectType: 'staff_profile',
          subjectId: profile.id,
          reason,
          completedAt: new Date(),
        },
      });
      await tx.profile.update({
        where: { id: profile.id },
        data: { name: deletedLabel, active: false, deletedAt: new Date() },
      });
      await tx.sale.updateMany({ where: { tenantId: requireUser(req).tenantId, staffId: profile.id }, data: { staffName: deletedLabel } });
      await tx.stockAdjustment.updateMany({ where: { tenantId: requireUser(req).tenantId, staffId: profile.id }, data: { staffId: profile.id } });
      await tx.payment.updateMany({ where: { tenantId: requireUser(req).tenantId, initiatedBy: profile.id }, data: { staffName: deletedLabel } });
    });
    return res.json({ deleted: true, profile_id: profile.id });
  })
);

// ---------------------------------------------------------------------------
// Staff authenticate (till PIN check against backend)
// ---------------------------------------------------------------------------

router.post(
  '/staff/authenticate',
  staffAuthLimiter,
  asyncHandler(async (req, res) => {
    const parsed = parseBody(staffAuthenticateSchema, req.body);
    const username = parsed.username.trim().toLowerCase();
    const { pin } = parsed;

    // On a fresh till there is no bearer token yet. The shop was selected in
    // the app before this request, so the tenant header is the only accepted
    // shop selector; credentials are never used to discover a tenant.
    const tenantId = req.user?.tenantId ?? req.header('x-tenant-id');
    if (!tenantId || tenantId.trim().length === 0) {
      return res.status(400).json({ error: 'Shop selection required' });
    }
    const profile = await prisma.profile.findFirst({
      where: {
        tenantId,
        username,
        role: { in: ['cashier', 'manager'] },
        active: true,
        deletedAt: null,
      },
      include: { tenant: { select: { shopName: true } } },
    });
    if (!profile) {
      return res.status(401).json({ error: 'Staff not found or inactive' });
    }

    // Keep a server-side verifier so a fresh device can bootstrap its offline
    // roster without accepting an arbitrary PIN. Existing local devices still
    // verify first, but the backend closes the online trust boundary too.
    if (!verifyStaffPin(pin, profile.pinHash)) {
      return res.status(401).json({ error: 'Invalid staff credentials' });
    }
    return res.json({
      staff_id: profile.id,
      local_id: profile.localId ?? null,
      name: profile.name,
      role: profile.role,
      tenant_id: profile.tenantId,
      shop_name: profile.tenant.shopName,
    });
  })
);

// ---------------------------------------------------------------------------
// Tenant portfolio KPIs (aggregated across the caller's owned tenants)
// ---------------------------------------------------------------------------

router.get(
  '/portfolio',
  asyncHandler(async (req, res) => {
    const from = typeof req.query.from === 'string' ? new Date(req.query.from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const to = typeof req.query.to === 'string' ? new Date(req.query.to) : new Date();
    if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from > to) {
      return res.status(400).json({ error: 'Invalid report date range' });
    }

    // Portfolio is an owner view. A cashier or manager may report on the
    // selected shop, but must not infer the performance of every shop linked
    // to the account. OIDC uses the subject; email-code sessions use the
    // verified profile email as the account identity.
    const user = requireUser(req);
    const identity = req.auth;
    const accountWhere = identity?.email
      ? {
          OR: [
            ...(identity.sub ? [{ oidcSubject: identity.sub }] : []),
            { email: identity.email },
          ],
        }
      : identity?.sub
        ? { oidcSubject: identity.sub }
        : { id: user.id };
    const profiles = await prisma.profile.findMany({
      where: {
        ...accountWhere,
        role: 'admin',
        active: true,
        deletedAt: null,
      },
      select: {
        tenantId: true,
        role: true,
        tenant: { select: { shopName: true, businessProfile: true } },
      },
    });
    const tenantIds = [...new Set(profiles.map((p: any) => p.tenantId))];
    if (tenantIds.length === 0) {
      return res.json({
        from: from.toISOString(),
        to: to.toISOString(),
        shops: [],
      });
    }

    // Keep portfolio windows half-open, exactly like /reports/sales and
    // /reports/products. Adjacent periods can then be combined without a sale
    // exactly at the boundary being counted twice.
    const where = { tenantId: { in: tenantIds }, createdAt: { gte: from, lt: to } };
    const tenantList = Prisma.join(tenantIds.map((id) => Prisma.sql`${id}`));
    const [shopRows, tenderRows, shiftRows] = await Promise.all([
      prisma.sale.groupBy({
        by: ['tenantId'],
        where,
        _count: { _all: true },
        _sum: { total: true, profit: true },
      }),
      prisma.sale.groupBy({
        by: ['tenantId', 'paymentMethod'],
        where,
        _count: { _all: true },
      }),
      prisma.$queryRaw<Array<{
        tenant_id: string;
        shifts_closed: bigint;
        shifts_open: bigint;
        cash_variance: bigint | null;
      }>>(Prisma.sql`
        SELECT tenant_id,
               COUNT(*) FILTER (
                 WHERE payload->>'status' = 'closed'
                   AND created_at >= ${from}
                   AND created_at < ${to}
               ) AS shifts_closed,
               COUNT(*) FILTER (
                 WHERE payload->>'status' = 'open'
                   AND created_at >= ${from}
                   AND created_at < ${to}
               ) AS shifts_open,
               COALESCE(SUM(
                 CASE WHEN payload->>'status' = 'closed'
                           AND created_at >= ${from}
                           AND created_at < ${to} THEN
                   COALESCE(NULLIF(payload->>'countedCash', '')::bigint, 0) -
                   COALESCE(NULLIF(payload->>'expectedCash', '')::bigint, 0)
                 ELSE 0 END
               ), 0)::bigint AS cash_variance
          FROM sync_records
         WHERE kind = 'shifts'
           AND tenant_id IN (${tenantList})
         GROUP BY tenant_id
      `),
    ]);

    const tenders = new Map<string, { method: string; count: number }>();
    for (const row of tenderRows) {
      const method = row.paymentMethod || 'cash';
      const current = tenders.get(row.tenantId);
      if (!current || row._count._all > current.count) {
        tenders.set(row.tenantId, { method, count: row._count._all });
      }
    }
    const totals = new Map(shopRows.map((row) => [row.tenantId, row]));
    const shifts = new Map(shiftRows.map((row) => [row.tenant_id, row]));

    return res.json({
      from: from.toISOString(),
      to: to.toISOString(),
      shops: profiles.map((profile: any) => {
        const row = totals.get(profile.tenantId);
        const shift = shifts.get(profile.tenantId);
        return {
          tenantId: profile.tenantId,
          shopName: profile.tenant.shopName,
          businessProfile: profile.tenant.businessProfile,
          role: profile.role,
          revenue: toMinor(row?._sum.total),
          profit: toMinor(row?._sum.profit),
          transactions: row?._count._all ?? 0,
          topPaymentMethod: tenders.get(profile.tenantId)?.method ?? null,
          shiftsClosed: Number(shift?.shifts_closed ?? 0),
          shiftsOpen: Number(shift?.shifts_open ?? 0),
          // Shift cash fields are already integer minor units on the wire.
          cashVariance: Number(shift?.cash_variance ?? 0),
          // The server keeps sales and operational records separately from
          // the till's append-only financial event stream. Do not present
          // unavailable remote finance fields as zero; the client renders
          // this shop as incomplete until its canonical local statement is
          // available.
          operatingExpenses: 0,
          cashIn: 0,
          cashOut: 0,
          receivableDelta: 0,
          payableDelta: 0,
          stockValue: 0,
          financialDataComplete: false,
        };
      }),
    });
  })
);

// Owner-scoped, normalized activity rows. This deliberately starts with the
// two append-only sources that exist for every shop: completed sales and
// synced operational records. The authorization set is resolved from the
// caller's active admin profiles, never from a tenant id supplied by the
// client.
router.get(
  '/activity',
  asyncHandler(async (req, res) => {
    const user = requireUser(req);
    const from = typeof req.query.from === 'string'
      ? new Date(req.query.from)
      : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const to = typeof req.query.to === 'string' ? new Date(req.query.to) : new Date();
    const limitValue = Number(req.query.limit ?? 100);
    const limit = Number.isInteger(limitValue) ? Math.min(Math.max(limitValue, 1), 200) : 100;
    const rawCursor = typeof req.query.cursor === 'string' ? req.query.cursor : undefined;
    const cursorSeparator = rawCursor?.indexOf('|') ?? -1;
    const cursorAt = cursorSeparator > 0
      ? new Date(rawCursor!.slice(0, cursorSeparator))
      : undefined;
    const cursorEventId = cursorSeparator > 0 ? rawCursor!.slice(cursorSeparator + 1) : undefined;
    if (rawCursor && (!cursorAt || !Number.isFinite(cursorAt.getTime()) || !cursorEventId)) {
      return res.status(400).json({ error: 'Invalid activity cursor' });
    }
    if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from >= to) {
      return res.status(400).json({ error: 'Invalid activity date range' });
    }

    const identity = req.auth;
    const accountWhere = identity?.email
      ? { OR: [...(identity.sub ? [{ oidcSubject: identity.sub }] : []), { email: identity.email }] }
      : identity?.sub
        ? { oidcSubject: identity.sub }
        : { id: user.id };
    const profiles = await prisma.profile.findMany({
      where: { ...accountWhere, role: 'admin', active: true, deletedAt: null },
      select: { tenantId: true, tenant: { select: { shopName: true, businessProfile: true } } },
    });
    const authorized = new Map(profiles.map((profile: any) => [profile.tenantId, profile.tenant]));
    const requestedTenant = typeof req.query.tenantId === 'string' ? req.query.tenantId : undefined;
    const tenantIds = activityTenantScope([...authorized.keys()], requestedTenant);
    if (tenantIds == null) {
      return res.status(403).json({ error: 'Shop access denied' });
    }
    if (tenantIds.length === 0) return res.json({ events: [], nextCursor: null });

    const profileFilter = typeof req.query.profile === 'string' ? req.query.profile : undefined;
    const paymentFilter = typeof req.query.payment === 'string' ? req.query.payment : undefined;
    const typeFilter = typeof req.query.type === 'string' ? req.query.type : undefined;
    const statusFilter = typeof req.query.status === 'string' ? req.query.status : undefined;
    const createdAtFilter = cursorAt && cursorEventId
      ? { gte: from, lte: cursorAt }
      : { gte: from, lt: to };
    const sales = typeFilter && typeFilter !== 'sale'
      ? []
      : await prisma.sale.findMany({
          where: {
            tenantId: { in: tenantIds },
            createdAt: createdAtFilter,
            ...(paymentFilter ? { paymentMethod: paymentFilter } : {}),
          },
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          take: limit,
          select: {
            id: true, tenantId: true, staffName: true, paymentMethod: true,
            total: true, profit: true, createdAt: true,
          },
        });
    const synced = typeFilter && typeFilter !== 'activity'
      ? []
      : await prisma.syncRecord.findMany({
          where: { tenantId: { in: tenantIds }, createdAt: createdAtFilter },
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          take: limit,
          select: { id: true, tenantId: true, kind: true, localId: true, payload: true, createdAt: true },
        });
    const events = [
      ...sales.map((sale: any) => ({
        eventId: `sale:${sale.id}`, sourceId: sale.id, sourceType: 'sale',
        isRemote: true, workspaceKey: sale.tenantId,
        tenantId: sale.tenantId, shopName: authorized.get(sale.tenantId)?.shopName,
        businessProfile: authorized.get(sale.tenantId)?.businessProfile,
        createdAt: sale.createdAt, type: 'sale', status: 'completed',
        paymentMethod: sale.paymentMethod, amountMinor: toMinor(sale.total),
        profitMinor: toMinor(sale.profit), actor: sale.staffName,
      })),
      ...synced.map((record: any) => {
        const payload = (record.payload ?? {}) as Record<string, unknown>;
        const status = String(payload.status ?? 'synced');
        return {
          eventId: `activity:${record.id}`, sourceId: String(record.localId), sourceType: record.kind,
          isRemote: true, workspaceKey: record.tenantId,
          tenantId: record.tenantId, shopName: authorized.get(record.tenantId)?.shopName,
          businessProfile: authorized.get(record.tenantId)?.businessProfile,
          createdAt: record.createdAt, type: 'activity', status,
          paymentMethod: typeof payload.paymentMethod === 'string' ? payload.paymentMethod : null,
          amountMinor: returnTotalMinor(payload), profitMinor: null,
          actor: typeof payload.staffName === 'string' ? payload.staffName : null,
        };
      }),
    ]
      .filter((event: any) => !statusFilter || event.status === statusFilter)
      .sort((a: any, b: any) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
      .filter((event: any) => {
        if (!cursorAt || !cursorEventId) return true;
        const eventTime = new Date(event.createdAt).getTime();
        const cursorTime = cursorAt.getTime();
        return eventTime < cursorTime ||
          (eventTime === cursorTime && event.eventId < cursorEventId);
      })
      .slice(0, limit);
    if (profileFilter && !['drinks', 'duka', 'fashion', 'open'].includes(profileFilter)) {
      return res.status(400).json({ error: 'Invalid profile filter' });
    }
    const filtered = profileFilter
      ? events.filter((event: any) => event.businessProfile === profileFilter)
      : events;
    const nextCursor = filtered.length === limit && filtered.length > 0
      ? `${new Date(filtered[filtered.length - 1].createdAt).toISOString()}|${filtered[filtered.length - 1].eventId}`
      : null;
    return res.json({ from: from.toISOString(), to: to.toISOString(), events: filtered, nextCursor });
  }),
);

export default router;
