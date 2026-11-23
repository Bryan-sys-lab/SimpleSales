/**
 * System administration routes.
 *
 * Mounted at /api/admin. Every route is protected by systemAdminMiddleware
 * A short-lived administrator JWT + permission middleware. The super admin
 * sees all tenants; department keys receive only their granted capabilities.
 */
import { Request, Response, Router } from 'express';
import crypto from 'node:crypto';
import { z } from 'zod';
import { asyncHandler } from '../lib/http';
import { adminAuditSchema, adminListQuerySchema, commercialLedgerQuerySchema, platformAnnouncementSchema, taxRuleSchema, parseBody, subscriptionUpdateSchema, voucherCreateSchema, billingProviderSchema } from '../lib/validation';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { prepareAdminAudit } from '../lib/admin_audit_d1';
import { requiredD1String } from '../lib/d1_results';
import { runRetention } from '../lib/retention';
import { log } from '../lib/observability';
import { authMiddleware, requireRole, systemAdminMiddleware } from '../middleware/auth';
import { broadcastAdmin } from '../services/admin_live_broker';
import { COMMERCIAL_POLICY } from '../lib/commercial_policy';
import { commercialContributionSelect, projectCommercialContribution } from '../lib/commercial_ledger';
import { aggregateCommercialRows, COMMERCIAL_DISCLOSURE_THRESHOLDS, commercialRetentionCutoff, isEligibleForCommercialOutput, prepareCommercialAggregateOutput } from '../lib/commercial_controls';
import { buildCommercialQualityReport, dedupeCommercialRows } from '../lib/commercial_quality';
import { generateVoucher } from '../lib/entitlements';
import { registerPaymentChannel } from '../services/payhero';
import { createCloudflareEmailTransport } from '../lib/email_sender';

const router = Router();

function buildMailer() {
  return createCloudflareEmailTransport({
    accountId: process.env.CLOUDFLARE_ACCOUNT_ID ?? '',
    apiToken: process.env.CLOUDFLARE_API_TOKEN ?? '',
    from: process.env.CLOUDFLARE_EMAIL_FROM ?? 'security@nerva.co.ke',
    appName: process.env.APP_NAME ?? 'SimpleSales',
  });
}

// New tenant IDs are readable owner-shop-number identifiers; older tenants
// may still be UUIDs. Support and diagnostics filters treat IDs as opaque and
// must accept both forms.
const tenantIdentifier = z.string().trim().min(1).max(120).regex(
  /^[A-Za-z0-9_-]+$/,
);

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

// Device uploads use the authenticated shop profile. Scope device identity to
// that tenant and strip common secrets before storing crash replay context.
const deviceReportSchema = z.object({
  deviceId: z.string().trim().min(1).max(128), platform: z.string().trim().min(1).max(32),
  osVersion: z.string().trim().min(1).max(128), appVersion: z.string().trim().min(1).max(64),
  buildNumber: z.string().trim().min(1).max(64), locale: z.string().trim().min(1).max(32),
  manufacturer: z.string().max(128).optional().nullable(), model: z.string().max(128).optional().nullable(),
  tenantId: z.string().max(120).optional().nullable(),
  crashes: z.array(z.object({
    clientEventId: z.string().trim().min(1).max(80).optional().nullable(),
    kind: z.enum(['crash', 'error', 'warning']), message: z.string().trim().min(1).max(4096),
    stack: z.string().max(16000).optional().nullable(), route: z.string().max(512).optional().nullable(),
    actorName: z.string().max(128).optional().nullable(), action: z.string().max(256).optional().nullable(),
    breadcrumbs: z.array(z.string().max(512)).max(30).optional().nullable(), createdAt: z.string().datetime().optional(),
  }).strict()).max(200).default([]),
}).strict();
function scrubDiagnostic(value: string | null | undefined): string | null {
  if (!value) return null;
  return value.replace(/(authorization\s*[:=]\s*bearer\s+)[^\s,;]+/gi, '$1[redacted]')
    .replace(/((?:password|pin|token|secret|api[_-]?key)\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;}]+)/gi, '$1[redacted]')
    .slice(0, 16000);
}
router.post('/diagnostics', authMiddleware, requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
  const input = parseBody(deviceReportSchema, req.body);
  const tenantId = req.user!.tenantId;
  const deviceId = crypto.createHash('sha256').update(`${tenantId}\0${input.deviceId}`).digest('hex');
  const now = new Date();
  const db = getD1DatabaseBinding();
  const statements = [db.prepare(`
    INSERT INTO device_diagnostics (
      id, tenant_id, device_id, platform, os_version, app_version, build_number,
      locale, manufacturer, model, crash_count, error_count, warning_count,
      first_seen, last_seen
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, ?, ?)
    ON CONFLICT (device_id) DO UPDATE SET
      tenant_id = excluded.tenant_id,
      platform = excluded.platform,
      os_version = excluded.os_version,
      app_version = excluded.app_version,
      build_number = excluded.build_number,
      locale = excluded.locale,
      manufacturer = excluded.manufacturer,
      model = excluded.model,
      last_seen = excluded.last_seen
    RETURNING id
  `).bind(
    crypto.randomUUID(),
    tenantId,
    deviceId,
    input.platform,
    input.osVersion,
    input.appVersion,
    input.buildNumber,
    input.locale,
    input.manufacturer ?? null,
    input.model ?? null,
    now.toISOString(),
    now.toISOString(),
  )];
  const entryResultIndexes: number[] = [];
  for (const entry of input.crashes) {
    entryResultIndexes.push(statements.length);
    statements.push(db.prepare(`
      INSERT INTO device_crash_entries (
        id, diagnostic_id, kind, message, stack, route, actor_name, action,
        breadcrumbs, created_at, session_jti, client_event_id
      )
      SELECT ?, device_diagnostics.id, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
      FROM device_diagnostics
      WHERE device_diagnostics.device_id = ?
      ON CONFLICT (diagnostic_id, client_event_id) DO NOTHING
    `).bind(
      crypto.randomUUID(),
      entry.kind,
      scrubDiagnostic(entry.message) ?? 'Diagnostic event',
      scrubDiagnostic(entry.stack),
      scrubDiagnostic(entry.route),
      scrubDiagnostic(entry.actorName),
      scrubDiagnostic(entry.action),
      scrubDiagnostic((entry.breadcrumbs ?? []).join('\n')),
      entry.createdAt ? new Date(entry.createdAt).toISOString() : now.toISOString(),
      req.auth?.jti ?? null,
      entry.clientEventId
        ? crypto.createHash('sha256').update(`${deviceId}\0${entry.clientEventId}`).digest('hex')
        : null,
      deviceId,
    ));
  }
  statements.push(db.prepare(`
    UPDATE device_diagnostics
    SET crash_count = (
          SELECT COUNT(*) FROM device_crash_entries
          WHERE diagnostic_id = device_diagnostics.id AND kind = 'crash'
        ),
        error_count = (
          SELECT COUNT(*) FROM device_crash_entries
          WHERE diagnostic_id = device_diagnostics.id AND kind = 'error'
        ),
        warning_count = (
          SELECT COUNT(*) FROM device_crash_entries
          WHERE diagnostic_id = device_diagnostics.id AND kind = 'warning'
        )
    WHERE device_id = ?
  `).bind(deviceId));
  const results = await db.batch(statements);
  const diagnosticId = requiredD1String(results[0], 'id', 'device diagnostic');
  const insertedCount = entryResultIndexes.reduce(
    (count, index) => count + (results[index]?.meta.changes ?? 0),
    0,
  );
  const diagnostic = { id: diagnosticId, insertedCount };
  await broadcastAdmin({ type: 'device_diagnostic_reported', tenantId, diagnosticId: diagnostic.id, crashes: diagnostic.insertedCount, at: now.toISOString() });
  return res.status(201).json({ id: diagnostic.id, crashesReceived: diagnostic.insertedCount });
}));

// All administration/reporting reads require an administrator capability.
router.use(systemAdminMiddleware);

// Verified account directory. This is deliberately separate from tenant
// listings because a newly verified owner may not have completed shop
// provisioning yet; the admin must still see the account immediately.
router.get('/users', asyncHandler(async (_req: Request, res: Response) => {
  const users = await prisma.user.findMany({
    select: {
      id: true,
      email: true,
      emailVerifiedAt: true,
      createdAt: true,
      profiles: {
        where: { active: true, deletedAt: null },
        select: { id: true, name: true, role: true, tenant: { select: { id: true, shopName: true } } },
        orderBy: { createdAt: 'asc' },
      },
    },
    orderBy: { createdAt: 'desc' },
  });
  return res.json({ users });
}));

router.get('/billing/provider', asyncHandler(async (_req: Request, res: Response) => {
  const rows = await prisma.systemSettings.findMany({ where: { key: { in: ['billing_channel_type', 'billing_channel_id', 'billing_short_code', 'billing_account_number'] } } });
  const values = Object.fromEntries(rows.map((row) => [row.key, row.value]));
  return res.json({ provider: { channelType: values.billing_channel_type ?? null, channelId: values.billing_channel_id ? Number(values.billing_channel_id) : null, shortCode: values.billing_short_code ?? null, accountNumber: values.billing_account_number ?? null } });
}));

router.patch('/billing/provider', asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(billingProviderSchema, req.body);
  const channel = await registerPaymentChannel(input);
  const values = { billing_channel_type: input.channelType, billing_channel_id: String(channel.id), billing_short_code: input.shortCode, billing_account_number: input.accountNumber ?? '' };
  const db = getD1DatabaseBinding();
  await db.batch(Object.entries(values).map(([key, value]) => db.prepare(`
    INSERT INTO system_settings (key, value) VALUES (?, ?)
    ON CONFLICT (key) DO UPDATE SET value = excluded.value
  `).bind(key, value)));
  await prisma.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: 'update_billing_provider', targetType: 'system_settings', tenantId: null } });
  return res.json({ provider: { ...input, channelId: channel.id } });
}));

// Subscription terms are negotiated per shop. Only system administrators can
// set the amount or activate/suspend access; the app never decides entitlement.
router.get('/billing/subscriptions', asyncHandler(async (_req: Request, res: Response) => {
  const rows = await prisma.tenantSubscription.findMany({ include: { tenant: { select: { id: true, shopName: true, profiles: { where: { role: 'admin', active: true, deletedAt: null }, orderBy: { createdAt: 'asc' }, take: 1, select: { id: true, name: true, email: true, user: { select: { email: true } } } } } } }, orderBy: { updatedAt: 'desc' } });
  return res.json({ subscriptions: rows });
}));

router.get('/billing/payments', asyncHandler(async (req: Request, res: Response) => {
  const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
  const payments = await prisma.subscriptionPayment.findMany({
    take: limit,
    orderBy: { createdAt: 'desc' },
    select: { id: true, tenantId: true, reference: true, amountMinor: true, durationMonths: true, discountPercent: true, status: true, providerStatus: true, mpesaReceiptCode: true, createdAt: true, updatedAt: true, tenant: { select: { shopName: true, subscription: { select: { currency: true } } } } },
  });
  return res.json({ payments });
}));

router.patch('/billing/subscriptions/:tenantId', asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(subscriptionUpdateSchema, req.body);
  const tenantId = String(req.params.tenantId);
  const currentPeriodEnd = input.currentPeriodEnd !== undefined
    ? input.currentPeriodEnd ? new Date(input.currentPeriodEnd) : null
    : (input.status ?? 'active') === 'active'
      ? new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
      : null;
  const subscription = await prisma.tenantSubscription.upsert({
    where: { tenantId },
    create: {
      tenantId,
      status: input.status ?? 'active',
      priceMinor: input.priceMinor ?? null,
      discountPercent: input.discountPercent ?? 0,
      currency: input.currency ?? 'KES',
      billingInterval: input.billingInterval ?? 'monthly',
      currentPeriodEnd,
      graceUntil: input.graceUntil ? new Date(input.graceUntil) : null,
      updatedBy: req.auth?.sub,
    },
    update: { ...input, currentPeriodEnd: input.currentPeriodEnd === undefined ? undefined : input.currentPeriodEnd ? new Date(input.currentPeriodEnd) : null, graceUntil: input.graceUntil === undefined ? undefined : input.graceUntil ? new Date(input.graceUntil) : null, updatedBy: req.auth?.sub },
  });
  await prisma.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: 'update_subscription', targetType: 'tenant_subscription', targetId: subscription.id, tenantId } });
  return res.json({ subscription });
}));

router.post('/billing/vouchers', asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(voucherCreateSchema, req.body);
  const mailer = buildMailer();
  if (!mailer.configured) {
    return res.status(503).json({
      error: 'Access voucher email delivery is not configured',
      code: 'EMAIL_NOT_CONFIGURED',
    });
  }
  let profile = input.profileId
    ? await prisma.profile.findUnique({
      where: { id: input.profileId },
      select: { id: true, tenantId: true, email: true, user: { select: { email: true } } },
    })
    : null;
  if (!profile && input.tenantId && !input.email) {
    profile = await prisma.profile.findFirst({
      where: { tenantId: input.tenantId, role: 'admin', active: true, deletedAt: null },
      orderBy: { createdAt: 'asc' },
      select: { id: true, tenantId: true, email: true, user: { select: { email: true } } },
    });
  }
  const profileEmail = profile?.user?.email?.trim().toLowerCase() ||
    profile?.email?.trim().toLowerCase();
  const recipientEmail = input.email ?? profileEmail;
  if (!recipientEmail) {
    return res.status(400).json({
      error: 'A recipient email is required when the selected shop has no owner email',
      code: 'VOUCHER_RECIPIENT_REQUIRED',
    });
  }
  if (profile) {
    if (profileEmail !== recipientEmail) {
      return res.status(400).json({
        error: 'Voucher email must match the selected profile',
        code: 'VOUCHER_RECIPIENT_MISMATCH',
      });
    }
    if (input.tenantId && profile.tenantId !== input.tenantId) {
      return res.status(400).json({
        error: 'Profile does not belong to the selected shop',
        code: 'VOUCHER_TENANT_MISMATCH',
      });
    }
  }
  const tenantId = input.tenantId ?? profile?.tenantId;
  const profileId = input.profileId ?? (input.tenantId && !input.email ? profile?.id : undefined);
  const generated = generateVoucher();
  const voucher = await prisma.accessVoucher.create({
    data: {
      codeHash: generated.hash,
      codePrefix: generated.prefix,
      tenantId,
      issuedToProfileId: profileId,
      issuedToEmail: recipientEmail,
      expiresAt: null,
      voucherType: input.voucherType,
      durationMonths: input.durationMonths,
      discountPercent: input.discountPercent,
      createdBy: req.auth?.sub ?? 'unknown',
      autoIssued: false,
    },
  });
  try {
    await mailer.send({
      kind: 'access_voucher',
      to: recipientEmail,
      code: generated.code,
      voucherType: input.voucherType,
      durationMonths: input.durationMonths,
      discountPercent: input.discountPercent,
    });
  } catch (error) {
    await prisma.accessVoucher.update({
      where: { id: voucher.id },
      data: { revokedAt: new Date() },
    });
    await prisma.adminAuditLog.create({
      data: {
        adminId: req.auth?.sub ?? 'unknown',
        action: 'access_voucher_email_failed',
        targetType: 'access_voucher',
        targetId: voucher.id,
        tenantId: tenantId ?? null,
      },
    });
    log('error', 'admin.voucher_email_failed', {
      voucherId: voucher.id,
      message: error instanceof Error ? error.message : 'email_provider_error',
    });
    return res.status(502).json({
      error: 'Voucher email could not be sent. The code was revoked; issue a new voucher and retry.',
      code: 'VOUCHER_EMAIL_UNAVAILABLE',
    });
  }
  await prisma.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: input.voucherType === 'discount' ? 'create_discount_voucher' : 'create_access_voucher', targetType: 'access_voucher', targetId: voucher.id, tenantId: input.tenantId ?? null } });
  // The plaintext is returned exactly once. It is never persisted or exposed
  // in list/audit responses.
  return res.status(201).json({ voucher: { id: voucher.id, code: generated.code, codePrefix: voucher.codePrefix, tenantId: voucher.tenantId, email: recipientEmail, voucherType: input.voucherType, durationMonths: input.durationMonths, discountPercent: input.discountPercent, expiresAt: null, emailSent: true } });
}));

router.get('/billing/vouchers', asyncHandler(async (_req: Request, res: Response) => {
  const vouchers = await prisma.accessVoucher.findMany({ select: { id: true, codePrefix: true, tenantId: true, issuedToProfileId: true, issuedToEmail: true, expiresAt: true, voucherType: true, durationMonths: true, discountPercent: true, redeemedAt: true, revokedAt: true, pausedAt: true, deletedAt: true, autoIssued: true, createdAt: true }, orderBy: { createdAt: 'desc' } });
  return res.json({ vouchers });
}));

router.post('/billing/vouchers/:id/:action', asyncHandler(async (req: Request, res: Response) => {
  const action = String(req.params.action);
  if (!['pause', 'resume', 'revoke', 'delete'].includes(action)) return res.status(400).json({ error: 'Unsupported voucher action' });
  const id = String(req.params.id);
  const voucher = await prisma.accessVoucher.update({ where: { id }, data: action === 'pause' ? { pausedAt: new Date() } : action === 'resume' ? { pausedAt: null } : action === 'revoke' ? { revokedAt: new Date() } : { deletedAt: new Date() } });
  await prisma.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: `${action}_access_voucher`, targetType: 'access_voucher', targetId: voucher.id, tenantId: voucher.tenantId } });
  return res.json({ status: action });
}));

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
  const db = getD1DatabaseBinding();
  const results = await db.batch([
    db.prepare(`
      UPDATE commercial_contributions
      SET status = 'withdrawn', retention_state = 'withdrawn'
      WHERE record_id = ?
    `).bind(recordId),
    prepareAdminAudit({
      adminId: req.auth?.sub ?? 'unknown',
      action: 'withdraw_commercial_contribution',
      targetType: 'commercial_contribution',
      targetId: recordId,
      onlyAfterSuccessfulWrite: true,
    }, db),
  ]);
  if ((results[0]?.meta.changes ?? 0) !== 1) throw new Error('Commercial contribution could not be withdrawn');
  const updated = await prisma.commercialContribution.findUnique({
    where: { recordId },
    select: commercialContributionSelect,
  });
  if (!updated) throw new Error('Withdrawn commercial contribution could not be reloaded');
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
  const db = getD1DatabaseBinding();
  const announcementValues = {
    platform_announcement_id: id,
    platform_announcement_title: input.title,
    platform_announcement_body: input.body,
    platform_announcement_active: String(input.active),
  };
  const updatedAt = new Date().toISOString();
  await db.batch([
    ...Object.entries(announcementValues).map(([key, value]) => db.prepare(`
      INSERT INTO system_settings (id, key, value, updated_at) VALUES (?, ?, ?, ?)
      ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
    `).bind(crypto.randomUUID(), key, value, updatedAt)),
    prepareAdminAudit({
      adminId: req.auth?.sub ?? 'unknown',
      action: 'publish_platform_announcement',
      targetType: 'platform_announcement',
      targetId: id,
    }, db),
  ]);
  platformAnnouncementNotifier?.({ id, title: input.title, body: input.body });
  await broadcastAdmin({ type: 'platform_announcement', announcement: { id, title: input.title, body: input.body } });
  return res.status(201).json({ id, title: input.title, body: input.body, active: input.active });
}));

router.delete('/announcement', asyncHandler(async (req: Request, res: Response) => {
  await prisma.systemSettings.updateMany({ where: { key: 'platform_announcement_active' }, data: { value: 'false' } });
  await prisma.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: 'clear_platform_announcement', targetType: 'platform_announcement', tenantId: null } });
  platformAnnouncementNotifier?.({ id: '', title: '', body: '' });
  await broadcastAdmin({ type: 'platform_announcement_cleared' });
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
    const where: Record<string, unknown> = { sessionJti: { not: null }, at: { gte: fromDate } };
    if (tenantId) where.tenantId = tenantId;
    const groups = await prisma.telemetryEvent.groupBy({
      by: ['sessionJti', 'tenantId'], where, _count: { _all: true }, _min: { at: true }, _max: { at: true },
      orderBy: { _max: { at: 'desc' } }, take: limit,
    });
    const sessionIds = groups.map((g) => g.sessionJti).filter((id): id is string => Boolean(id));
    const [tenantRows, deviceRows] = await Promise.all([
      prisma.tenant.findMany({ where: { id: { in: [...new Set(groups.map((g) => g.tenantId))] } }, select: { id: true, shopName: true } }),
      sessionIds.length ? prisma.telemetryEvent.findMany({ where: { sessionJti: { in: sessionIds } }, select: { sessionJti: true, deviceId: true }, distinct: ['sessionJti'], orderBy: { at: 'desc' } }) : Promise.resolve([]),
    ]);
    const tenantsById = new Map(tenantRows.map((t) => [t.id, t]));
    const devicesBySession = new Map(deviceRows.map((d) => [d.sessionJti, d.deviceId]));
    const sessions = groups.filter((g) => g.sessionJti && g._min.at && g._max.at).map((g) => ({
      id: g.sessionJti!, tenantId: g.tenantId, tenant: tenantsById.get(g.tenantId) ?? null,
      deviceId: devicesBySession.get(g.sessionJti!) ?? null,
      createdAt: g._min.at!, lastActivityAt: g._max.at!, expiresAt: new Date(g._max.at!.getTime() + 60 * 60 * 1000),
      eventCount: g._count._all,
    })).sort((a, b) => b.lastActivityAt.getTime() - a.lastActivityAt.getTime());
    return res.json({ sessions });
  })
);

router.get('/sessions/:sessionJti/replay', asyncHandler(async (req: Request, res: Response) => {
  const sessionJti = req.params.sessionJti as string;
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(sessionJti)) return res.status(400).json({ error: 'Invalid session identifier' });
  const events = await prisma.telemetryEvent.findMany({
    where: { sessionJti }, orderBy: { at: 'asc' }, take: 500,
    select: { id: true, tenantId: true, deviceId: true, name: true, at: true, route: true },
  });
  const crashes = await prisma.deviceCrashEntry.findMany({
    where: { sessionJti }, orderBy: { createdAt: 'asc' }, take: 200,
    select: { id: true, diagnosticId: true, kind: true, message: true, route: true, action: true, actorName: true, createdAt: true, diagnostic: { select: { tenantId: true, deviceId: true } } },
  });
  const tenantId = events[0]?.tenantId ?? crashes[0]?.diagnostic.tenantId;
  if (!tenantId) return res.status(404).json({ error: 'Session replay is no longer available' });
  const tenant = await prisma.tenant.findUnique({ where: { id: tenantId }, select: { id: true, shopName: true } });
  const activity = [
    ...events.map((event) => ({ id: event.id, name: event.name, route: event.route, at: event.at, deviceId: event.deviceId, message: null, kind: null, action: null, actorName: null, diagnosticId: null })),
    ...crashes.filter((crash) => crash.diagnostic.tenantId === tenantId).map((crash) => ({ id: crash.id, name: `diagnostic_${crash.kind}`, route: crash.route, at: crash.createdAt, deviceId: crash.diagnostic.deviceId, message: crash.message, kind: crash.kind, action: crash.action, actorName: crash.actorName, diagnosticId: crash.diagnosticId })),
  ].sort((a, b) => a.at.getTime() - b.at.getTime());
  await prisma.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: 'view_session_replay', targetType: 'app_session_activity', targetId: sessionJti, tenantId } });
  return res.json({ sessionId: sessionJti, tenant, deviceId: events[0]?.deviceId ?? crashes[0]?.diagnostic.deviceId ?? null, events: activity });
}));

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

// Business details are operational tenant data, not commercial contributions.
// Access is covered by tenants:read and every tenant-specific view is audited.
router.get('/tenants/:tenantId/business-context', asyncHandler(async (req: Request, res: Response) => {
  const tenantId = tenantIdentifier.parse(req.params.tenantId);
  const tenant = await prisma.tenant.findUnique({
    where: { id: tenantId },
    select: {
      id: true,
      shopName: true,
      businessProfile: true,
      businessContext: true,
    },
  });
  if (!tenant) return res.status(404).json({ error: 'Shop not found' });
  await prisma.adminAuditLog.create({
    data: {
      adminId: req.auth?.sub ?? 'unknown',
      action: 'view_business_context',
      targetType: 'business_context',
      targetId: tenant.businessContext?.id ?? tenant.id,
      tenantId,
    },
  });
  return res.json({ tenant: { ...tenant, businessContext: tenant.businessContext ? { ...tenant.businessContext, appProfile: tenant.businessProfile } : null } });
}));

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
    const db = getD1DatabaseBinding();
    const results = await db.batch([
      db.prepare(`
        UPDATE tax_rules
        SET status = ?, reviewed_at = ?, approved_by = ?, approval_note = ?
        WHERE id = ?
      `).bind(
        existing.effectiveFrom <= now ? 'active' : 'approved',
        now.toISOString(),
        req.auth?.sub ?? 'unknown',
        input.approvalNote ?? existing.approvalNote,
        existing.id,
      ),
      prepareAdminAudit({
        adminId: req.auth?.sub ?? 'unknown',
        action: 'approve_tax_rule',
        targetType: 'tax_rule',
        targetId: existing.id,
        onlyAfterSuccessfulWrite: true,
      }, db),
    ]);
    if ((results[0]?.meta.changes ?? 0) !== 1) throw new Error('Tax rule could not be approved');
    const rule = await prisma.taxRule.findUnique({
      where: { id: existing.id },
      include: { taxEntity: { select: { id: true, displayLabel: true, legalForm: true } } },
    });
    if (!rule) throw new Error('Approved tax rule could not be reloaded');
    return res.json({ rule: taxRuleView(rule) });
  }),
);

// ---------------------------------------------------------------------------
// GET /api/admin/support-tickets — support tickets across all tenants
// ---------------------------------------------------------------------------

const supportTicketListQuerySchema = z.object({
  status: z.enum(['open', 'in_progress', 'resolved']).optional().nullable(),
  tenantId: tenantIdentifier.optional().nullable(),
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

// ---------------------------------------------------------------------------
// POST /api/admin/diagnostics — receive a till phone's failure report
// GET    /api/admin/diagnostics — list device diagnostics
// GET    /api/admin/diagnostics/:id — one device with its crash entries
// ---------------------------------------------------------------------------

const diagnosticEntrySchema = z.object({
  kind: z.enum(['crash', 'error', 'warning']),
  message: z.string().trim().min(1).max(4096),
  stack: z.string().optional().nullable(),
  route: z.string().optional().nullable(),
  actorName: z.string().optional().nullable(),
  action: z.string().optional().nullable(),
  breadcrumbs: z.array(z.string()).optional().nullable(),
  createdAt: z.string().datetime().optional(),
}).strict();

const diagnosticReportSchema = z.object({
  deviceId: z.string().trim().min(1).max(128),
  platform: z.string().trim().min(1).max(32),
  osVersion: z.string().trim().min(1).max(128),
  appVersion: z.string().trim().min(1).max(64),
  buildNumber: z.string().trim().min(1).max(64),
  locale: z.string().trim().min(1).max(16),
  manufacturer: z.string().trim().max(128).optional().nullable(),
  model: z.string().trim().max(128).optional().nullable(),
  tenantId: tenantIdentifier.optional().nullable(),
  crashes: z.array(diagnosticEntrySchema).default([]),
}).strict();

router.post(
  '/diagnostics',
  asyncHandler(async (req: Request, res: Response) => {
    const input = parseBody(diagnosticReportSchema, req.body);

    // Upsert the device diagnostic row so re-reports merge into one device.
    const now = new Date();
    const diagnostic = await prisma.deviceDiagnostic.upsert({
      where: { deviceId: input.deviceId },
      update: {
        platform: input.platform,
        osVersion: input.osVersion,
        appVersion: input.appVersion,
        buildNumber: input.buildNumber,
        locale: input.locale,
        manufacturer: input.manufacturer ?? null,
        model: input.model ?? null,
        tenantId: input.tenantId ?? null,
        lastSeen: now,
        crashCount: { increment: input.crashes.filter((c) => c.kind === 'crash').length },
        errorCount: { increment: input.crashes.filter((c) => c.kind === 'error').length },
        warningCount: { increment: input.crashes.filter((c) => c.kind === 'warning').length },
      },
      create: {
        deviceId: input.deviceId,
        platform: input.platform,
        osVersion: input.osVersion,
        appVersion: input.appVersion,
        buildNumber: input.buildNumber,
        locale: input.locale,
        manufacturer: input.manufacturer ?? null,
        model: input.model ?? null,
        tenantId: input.tenantId ?? null,
        firstSeen: now,
        lastSeen: now,
        crashCount: input.crashes.filter((c) => c.kind === 'crash').length,
        errorCount: input.crashes.filter((c) => c.kind === 'error').length,
        warningCount: input.crashes.filter((c) => c.kind === 'warning').length,
      },
    });

    // Insert crash entries.
    if (input.crashes.length > 0) {
      await prisma.deviceCrashEntry.createMany({
        data: input.crashes.map((entry) => ({
          diagnosticId: diagnostic.id,
          kind: entry.kind,
          message: entry.message,
          stack: entry.stack ?? null,
          route: entry.route ?? null,
          actorName: entry.actorName ?? null,
          action: entry.action ?? null,
          breadcrumbs: (entry.breadcrumbs ?? []).join('\n') || null,
          createdAt: entry.createdAt ? new Date(entry.createdAt) : now,
        })),
      });
    }

    await prisma.adminAuditLog.create({
      data: {
        adminId: req.auth?.sub ?? 'device',
        action: 'receive_device_diagnostic',
        targetType: 'device_diagnostic',
        targetId: diagnostic.id,
        tenantId: input.tenantId ?? null,
      },
    });

    return res.status(201).json({
      id: diagnostic.id,
      deviceId: diagnostic.deviceId,
      crashesReceived: input.crashes.length,
    });
  })
);

const diagnosticListQuerySchema = z.object({
  tenantId: tenantIdentifier.optional().nullable(),
  platform: z.string().optional().nullable(),
  kind: z.enum(['crash', 'error', 'warning']).optional().nullable(),
  from: z.string().datetime().optional().nullable(),
  to: z.string().datetime().optional().nullable(),
  limit: z.coerce.number().int().positive().max(500).default(100),
}).strict();

router.get(
  '/diagnostics',
  asyncHandler(async (req: Request, res: Response) => {
    const { tenantId, platform, kind, from, to, limit } = parseBody(diagnosticListQuerySchema, req.query);

    const where: Record<string, unknown> = {};
    if (tenantId) where.tenantId = tenantId;
    if (platform) where.platform = platform;
    if (from || to) {
      where.lastSeen = {};
      if (from) (where.lastSeen as Record<string, unknown>).gte = from;
      if (to) (where.lastSeen as Record<string, unknown>).lte = to;
    }

    const diagnostics = await prisma.deviceDiagnostic.findMany({
      where,
      include: {
        _count: { select: { crashes: true } },
        crashes: kind
          ? { where: { kind }, orderBy: { createdAt: 'desc' }, take: 5 }
          : { orderBy: { createdAt: 'desc' }, take: 5 },
      },
      orderBy: { lastSeen: 'desc' },
      take: limit,
    });

    return res.json({
      diagnostics: diagnostics.map((d) => ({
        id: d.id,
        deviceId: d.deviceId,
        tenantId: d.tenantId,
        platform: d.platform,
        osVersion: d.osVersion,
        appVersion: d.appVersion,
        buildNumber: d.buildNumber,
        locale: d.locale,
        manufacturer: d.manufacturer,
        model: d.model,
        crashCount: d.crashCount,
        errorCount: d.errorCount,
        warningCount: d.warningCount,
        firstSeen: d.firstSeen,
        lastSeen: d.lastSeen,
        recentCrashes: d.crashes.map((c) => ({
          id: c.id,
          kind: c.kind,
          message: c.message,
          route: c.route,
          actorName: c.actorName,
          action: c.action,
          createdAt: c.createdAt,
        })),
      })),
    });
  })
);

router.get(
  '/diagnostics/:id',
  asyncHandler(async (req: Request, res: Response) => {
    const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const diagnostic = await prisma.deviceDiagnostic.findUnique({
      where: { id },
      include: {
        crashes: { orderBy: { createdAt: 'desc' } },
        tenant: { select: { id: true, shopName: true } },
      },
    });
    if (!diagnostic) return res.status(404).json({ error: 'Device diagnostic not found' });
    await prisma.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: 'view_device_diagnostic', targetType: 'device_diagnostic', targetId: diagnostic.id, tenantId: diagnostic.tenantId } });
    return res.json({
      id: diagnostic.id,
      deviceId: diagnostic.deviceId,
      tenantId: diagnostic.tenantId,
      tenant: diagnostic.tenant,
      platform: diagnostic.platform,
      osVersion: diagnostic.osVersion,
      appVersion: diagnostic.appVersion,
      buildNumber: diagnostic.buildNumber,
      locale: diagnostic.locale,
      manufacturer: diagnostic.manufacturer,
      model: diagnostic.model,
      crashCount: diagnostic.crashCount,
      errorCount: diagnostic.errorCount,
      warningCount: diagnostic.warningCount,
      firstSeen: diagnostic.firstSeen,
      lastSeen: diagnostic.lastSeen,
      crashes: diagnostic.crashes.map((c) => ({
        id: c.id,
        kind: c.kind,
        message: c.message,
        stack: c.stack,
        route: c.route,
        actorName: c.actorName,
        action: c.action,
        breadcrumbs: c.breadcrumbs ?? '',
        createdAt: c.createdAt,
      })),
    });
  })
);


// Cross-shop aggregated product catalog (deduplicated by name + category).
// System admin only; tenant identifiers are stripped from the response to
// avoid leaking which shop stocks what.
router.get('/products', asyncHandler(async (_req: Request, res: Response) => {
  const rows = await prisma.product.findMany({
    where: { active: true },
    select: { name: true, category: true, sellPrice: true, stockQty: true, tenantId: true, itemKind: true, gpcMappingStatus: true, unitMappingStatus: true, gtin: true },
  });
  const identityCoverage = {
    activeProducts: rows.length,
    verifiedGtinProducts: 0,
    itemKinds: { good: 0, service: 0, fee: 0, unknown: 0 },
    gpcMapping: { mapped: 0, unmapped: 0, unknown: 0, notApplicable: 0, rejected: 0 },
    unitMapping: { mapped: 0, unmapped: 0, unknown: 0, notApplicable: 0, rejected: 0 },
  };
  for (const row of rows) {
    if (row.gtin) identityCoverage.verifiedGtinProducts++;
    const kind = row.itemKind as keyof typeof identityCoverage.itemKinds;
    if (kind in identityCoverage.itemKinds) identityCoverage.itemKinds[kind]++;
    const gpc = row.gpcMappingStatus === 'not_applicable' ? 'notApplicable' : row.gpcMappingStatus;
    if (gpc in identityCoverage.gpcMapping) identityCoverage.gpcMapping[gpc as keyof typeof identityCoverage.gpcMapping]++;
    const unit = row.unitMappingStatus === 'not_applicable' ? 'notApplicable' : row.unitMappingStatus;
    if (unit in identityCoverage.unitMapping) identityCoverage.unitMapping[unit as keyof typeof identityCoverage.unitMapping]++;
  }
  const map = new Map<string, { name: string; category: string; shops: Set<string>; minPrice: number; maxPrice: number; totalStock: number }>();
  for (const r of rows) {
    const key = `${r.name}::${r.category}`;
    const entry = map.get(key) ?? { name: r.name, category: r.category, shops: new Set(), minPrice: Number(r.sellPrice), maxPrice: Number(r.sellPrice), totalStock: 0 };
    entry.shops.add(r.tenantId);
    entry.minPrice = Math.min(entry.minPrice, Number(r.sellPrice));
    entry.maxPrice = Math.max(entry.maxPrice, Number(r.sellPrice));
    entry.totalStock += Number(r.stockQty);
    map.set(key, entry);
  }
  const products = [...map.values()].map((e) => ({
    key: `${e.name}::${e.category}`,
    name: e.name,
    category: e.category,
    shops: e.shops.size,
    minPrice: Math.round(e.minPrice * 100),
    maxPrice: Math.round(e.maxPrice * 100),
    totalStock: e.totalStock,
  }));
  return res.json({ products, total: products.length, identityCoverage });
}));


// Aggregated expenses across all tenants (from synced operational records).
router.get('/expenses', asyncHandler(async (_req: Request, res: Response) => {
  const rows = await prisma.syncRecord.findMany({
    where: { kind: 'expenses', deviceId: 'admin' },
    orderBy: { createdAt: 'desc' },
    take: 500,
    select: { id: true, tenantId: true, payload: true, createdAt: true },
  });
  const items = rows.map((r) => {
    const p = (r.payload ?? {}) as Record<string, unknown>;
    return {
      id: r.id,
      tenantId: r.tenantId,
      category: (p['category'] as string) ?? 'General',
      description: (p['description'] as string) ?? (p['note'] as string) ?? 'Expense',
      amount: Number(p['amount'] ?? p['amountMinor'] ?? 0),
      date: r.createdAt.toISOString(),
    };
  });
  return res.json({ items });
}));

// Create a manual expense entry (app/infra costs) recorded by a system admin.
router.post('/expenses', asyncHandler(async (req: Request, res: Response) => {
  const input = (req.body ?? {}) as { category?: string; description?: string; amount?: number };
  const tenantId = (req as any).user?.tenantId ?? (process.env.SYSTEM_ADMIN_DEFAULT_TENANT ?? '');
  // Admin-entered expenses are stored under a synthetic tenant-less record by
  // using the first available tenant; if none, skip persistence but still audit.
  const tenant = tenantId
    ? await prisma.tenant.findUnique({ where: { id: tenantId } })
    : await prisma.tenant.findFirst();
  if (!tenant) {
    await prisma.adminAuditLog.create({ data: { adminId: (req as any).auth?.sub ?? 'unknown', action: 'add_expense', targetType: 'expense', targetId: null, tenantId: null } });
    return res.status(201).json({ ok: true });
  }
  const record = await prisma.syncRecord.create({
    data: {
      tenantId: tenant.id,
      kind: 'expenses',
      deviceId: 'admin',
      localId: Date.now(),
      createdAt: new Date(),
      payload: { category: input.category ?? 'General', description: input.description ?? 'Expense', amount: input.amount ?? 0 },
    },
  });
  await prisma.adminAuditLog.create({ data: { adminId: (req as any).auth?.sub ?? 'unknown', action: 'add_expense', targetType: 'expense', targetId: record.id, tenantId: tenant.id } });
  return res.status(201).json({ ok: true, id: record.id });
}));

export default router;
