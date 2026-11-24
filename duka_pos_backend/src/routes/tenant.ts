/**
 * Tenant routes: shop provisioning, settings, staff sync, portfolio, auth.
 *
 * All routes require an OIDC/app session (mounted at /api/tenant behind
 * authMiddleware in index.ts), except provision/shops and the explicitly
 * tenant-selected staff bootstrap route.
 */
import { Router } from 'express';
import { randomUUID } from 'node:crypto';
import { Prisma } from '../generated/prisma/client';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { parseBody } from '../lib/validation';
import { provisionSchema, settingsSchema, staffSyncSchema, deletionSchema, staffAuthenticateSchema, staffSelfPinSchema, staffPinResetRequestSchema, staffPinResetApproveSchema, mpesaChannelSchema, taxEntitySchema, vatReturnStatusSchema, subscriptionPaymentSchema } from '../lib/validation';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { authMiddleware } from '../middleware/auth';
import rateLimit from 'express-rate-limit';
import { registerPaymentChannel, initiateStkPush, queryTransactionStatus } from '../services/payhero';
import { taxReportingActivated, taxReportingStatus } from '../services/tax_reporting';
import { encryptTaxSecret, lastFour } from '../services/tax_entity';
import { activityTenantScope } from '../lib/activity_scope';
import { readableTenantId } from '../lib/tenant_id';
import { issueStaffSessionToken, verifyStaffSessionToken } from '../lib/jwt';
import { broadcastTenantChange } from '../services/live_broker';
import { tenantEntitlement } from '../lib/entitlements';
import { calculateSubscriptionQuote, effectiveSubscriptionDiscountPercent } from '../lib/subscription_pricing';
import { isVerifiedEmailMatch } from '../lib/identity';
import { activateSubscriptionPaymentAtomically } from '../lib/subscription_settlement';

const router = Router();

function managedStaffProfileFilter() {
  return {
    OR: [
      { role: { in: ['cashier', 'manager'] } },
      { role: 'admin', userId: null, localId: { not: null } },
    ],
  };
}

const _isNode = typeof module !== 'undefined';
const staffAuthLimiter = _isNode ? rateLimit({
  windowMs: 60_000,
  limit: 10,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
}) : ((_req: any, _res: any, next: any) => next());
const STAFF_PIN_HASH_ITERATIONS = 120_000;

async function deriveStaffPin(pin: string, salt: Uint8Array, iterations: number, length: number): Promise<Uint8Array> {
  const key = await globalThis.crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(pin),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await globalThis.crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt: new Uint8Array(salt), iterations },
    key,
    length * 8,
  );
  return new Uint8Array(bits);
}

function decodeBase64Url(value: string): Uint8Array {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/');
  const decoded = atob(base64 + '='.repeat((4 - base64.length % 4) % 4));
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function encodeBase64Url(value: Uint8Array): string {
  let binary = '';
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

/** Verifies the app's self-describing PBKDF2-HMAC-SHA256 PIN format. */
async function verifyStaffPin(pin: string, stored: string | null): Promise<boolean> {
  if (!stored?.startsWith('pbkdf2$')) return false;
  const parts = stored.split('$');
  if (parts.length !== 4) return false;
  const iterations = Number.parseInt(parts[1], 10);
  if (!Number.isSafeInteger(iterations) || iterations < 1 || iterations > 2_000_000) {
    return false;
  }
  try {
    const salt = decodeBase64Url(parts[2]);
    const expected = decodeBase64Url(parts[3]);
    if (salt.length < 8 || expected.length === 0 || expected.length > 64) return false;
    const actual = await deriveStaffPin(pin, salt, iterations, expected.length);
    if (actual.length !== expected.length) return false;
    let difference = 0;
    for (let index = 0; index < actual.length; index += 1) {
      difference |= actual[index] ^ expected[index];
    }
    return difference === 0;
  } catch {
    // A malformed verifier is simply an invalid credential.
    return false;
  }
}

async function hashStaffPin(pin: string): Promise<string> {
  const salt = globalThis.crypto.getRandomValues(new Uint8Array(16));
  const iterations = STAFF_PIN_HASH_ITERATIONS;
  const hash = await deriveStaffPin(pin, salt, iterations, 32);
  return `pbkdf2$${iterations}$${encodeBase64Url(salt)}$${encodeBase64Url(hash)}`;
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

async function saveTaxReturnStatus(params: {
  kind: 'vat' | 'tot';
  returnId: string;
  taxEntityId: string;
  currentStatus: string;
  nextStatus: string;
  rejectionReason?: string | null;
  actorId: string;
  now: Date;
}): Promise<void> {
  const table = params.kind === 'vat' ? 'vat_returns' : 'tot_returns';
  const eventColumn = params.kind === 'vat' ? 'vat_return_id' : 'tot_return_id';
  const db = getD1DatabaseBinding();
  const statements = [
    db.prepare(`
      UPDATE ${table}
      SET status = ?,
          rejection_reason = CASE WHEN ? = 'rejected' THEN ? ELSE NULL END,
          submitted_at = CASE WHEN ? = 'submitted' THEN ? ELSE submitted_at END,
          accepted_at = CASE WHEN ? = 'accepted' THEN ? ELSE accepted_at END,
          paid_at = CASE WHEN ? = 'settled' THEN ? ELSE paid_at END,
          updated_at = ?
      WHERE id = ? AND status = ?
    `).bind(
      params.nextStatus,
      params.nextStatus,
      params.rejectionReason ?? null,
      params.nextStatus,
      params.now.toISOString(),
      params.nextStatus,
      params.now.toISOString(),
      params.nextStatus,
      params.now.toISOString(),
      params.now.toISOString(),
      params.returnId,
      params.currentStatus,
    ),
  ];
  if (params.currentStatus !== params.nextStatus) {
    statements.push(db.prepare(`
      INSERT INTO tax_return_events (
        id, tax_entity_id, ${eventColumn}, from_status, to_status, actor_id, note, created_at
      )
      SELECT ?, ?, ?, ?, ?, ?, ?, ? WHERE changes() = 1
    `).bind(
      randomUUID(),
      params.taxEntityId,
      params.returnId,
      params.currentStatus,
      params.nextStatus,
      params.actorId,
      params.rejectionReason ?? null,
      params.now.toISOString(),
    ));
  }
  const results = await db.batch(statements);
  if ((results[0]?.meta.changes ?? 0) !== 1) {
    throw new HttpError(409, 'Tax return status changed; reload before retrying');
  }
}

// Apply OIDC auth to all routes except provision and shops.
// (authMiddleware is applied in index.ts at the /api level; we apply role
// checks inline here.)
router.use(authMiddleware);

router.get('/subscription', asyncHandler(async (req, res) => {
  if (!req.user) return res.status(401).json({ error: 'Tenant selection required' });
  const digits = (process.env.WHATSAPP_CONTACT_NUMBER ?? '').replace(/\D/g, '');
  const whatsappUrl = digits.length >= 8 && digits.length <= 15
    ? `https://wa.me/${digits}?text=${encodeURIComponent(`Hello, I would like a subscription quote for ${req.user.tenantId}.`)}`
    : null;
  const availableVoucher = req.auth?.email
    ? await prisma.accessVoucher.findFirst({
        where: {
          issuedToEmail: req.auth.email.toLowerCase(),
          redeemedAt: null,
          revokedAt: null,
          pausedAt: null,
          deletedAt: null,
          AND: [
            { OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] },
            { OR: [{ tenantId: null }, { tenantId: req.user.tenantId }] },
            { OR: [{ issuedToProfileId: null }, { issuedToProfileId: req.user.id }] },
          ],
        },
        select: { voucherType: true, durationMonths: true, discountPercent: true },
        orderBy: { createdAt: 'desc' },
      })
    : null;
  return res.json({
    entitlement: await tenantEntitlement(req.user.tenantId),
    support: {
      whatsappUrl,
      availableVoucher: availableVoucher
        ? {
            voucherType: availableVoucher.voucherType,
            durationMonths: availableVoucher.durationMonths,
            discountPercent: availableVoucher.discountPercent,
          }
        : null,
    },
  });
}));

router.post('/subscription/payment', asyncHandler(async (req, res) => {
  if (!req.user || req.user.role !== 'admin') return res.status(403).json({ error: 'Shop owner access required' });
  const input = parseBody(subscriptionPaymentSchema, req.body);
  const subscription = await prisma.tenantSubscription.findUnique({
    where: { tenantId: req.user.tenantId },
    include: { voucher: { select: { voucherType: true, durationMonths: true, discountPercent: true } } },
  });
  if (subscription?.agreementId && !input.agreementId) {
    return res.status(409).json({
      error: 'Payment must follow the accepted membership agreement',
      code: 'AGREEMENT_PAYMENT_REQUIRED',
    });
  }
  let amountMinor: number;
  let baseAmountMinor: number;
  let discountAmountMinor: number;
  let discountPercent: number;
  let durationMonths: number;
  let agreementId: string | null = null;
  let voucherApplied: boolean;

  if (input.agreementId) {
    const agreement = await prisma.membershipAgreement.findFirst({
      where: { id: input.agreementId, tenantId: req.user.tenantId },
    });
    if (!agreement) return res.status(404).json({ error: 'Accepted agreement not found' });
    if (!subscription || subscription.agreementId !== agreement.id || subscription.status !== 'awaiting_payment') {
      return res.status(409).json({ error: 'This agreement is not awaiting payment' });
    }
    const snapshot = agreement.snapshot;
    if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot)) {
      return res.status(409).json({ error: 'Accepted agreement terms are invalid' });
    }
    const terms = snapshot as Prisma.JsonObject;
    const amount = terms.amountMinor;
    const baseAmount = terms.baseAmountMinor;
    const discount = terms.discountPercent;
    const term = terms.termMonths;
    const voucherId = terms.voucherId;
    if (
      typeof amount !== 'number' || !Number.isSafeInteger(amount) || amount < 1 ||
      amount > 2_147_483_647 ||
      typeof baseAmount !== 'number' || !Number.isSafeInteger(baseAmount) ||
      baseAmount < amount || baseAmount > 2_147_483_647 ||
      typeof discount !== 'number' || !Number.isInteger(discount) || discount < 0 || discount > 100 ||
      (term !== null && (typeof term !== 'number' || !Number.isInteger(term) || term < 1 || term > 120)) ||
      terms.currency !== 'KES' || subscription.currency !== 'KES'
    ) {
      return res.status(409).json({ error: 'Accepted agreement terms are incomplete' });
    }
    amountMinor = amount;
    baseAmountMinor = baseAmount;
    discountAmountMinor = baseAmount - amount;
    discountPercent = discount;
    durationMonths = typeof term === 'number' ? term : 0;
    agreementId = agreement.id;
    voucherApplied = typeof voucherId === 'string' && voucherId.length > 0;
  } else {
    if (!subscription?.priceMinor) return res.status(409).json({ error: 'Subscription price has not been set by the system administrator' });
    const discountVoucher = subscription.voucher?.voucherType === 'discount'
      ? subscription.voucher
      : null;
    if (discountVoucher && input.durationMonths !== discountVoucher.durationMonths) {
      return res.status(409).json({
        error: `This discount voucher applies to a ${discountVoucher.durationMonths}-month plan`,
        code: 'VOUCHER_DURATION_MISMATCH',
      });
    }
    discountPercent = effectiveSubscriptionDiscountPercent(
      subscription.discountPercent,
      discountVoucher ? 'discount' : null,
      discountVoucher?.discountPercent,
    );
    const quote = calculateSubscriptionQuote(
      subscription.priceMinor,
      input.durationMonths,
      discountPercent,
    );
    amountMinor = quote.amountMinor;
    baseAmountMinor = quote.baseAmountMinor;
    discountAmountMinor = quote.discountAmountMinor;
    durationMonths = input.durationMonths;
    voucherApplied = Boolean(discountVoucher);
  }

  if (agreementId) {
    const existingPayment = await prisma.subscriptionPayment.findFirst({
      where: { agreementId, status: 'PENDING' },
      orderBy: { createdAt: 'desc' },
    });
    if (existingPayment) {
      return res.json({
        reference: existingPayment.reference,
        amountMinor: existingPayment.amountMinor,
        baseAmountMinor,
        discountAmountMinor,
        discountPercent: existingPayment.discountPercent,
        durationMonths: existingPayment.durationMonths,
        agreementId,
        status: existingPayment.status,
      });
    }
  }

  const provider = await prisma.systemSettings.findMany({ where: { key: { in: ['billing_channel_id'] } } });
  const channelId = Number(provider.find((row) => row.key === 'billing_channel_id')?.value);
  if (!Number.isSafeInteger(channelId) || channelId <= 0) return res.status(503).json({ error: 'Subscription payment destination is not configured' });
  const reference = `SUBS-${randomUUID()}`;
  let payment;
  try {
    payment = await prisma.subscriptionPayment.create({
      data: {
        tenantId: req.user.tenantId,
        reference,
        phoneNumber: input.phoneNumber,
        amountMinor,
        durationMonths,
        discountPercent,
        agreementId,
        voucherApplied,
      },
    });
  } catch (error) {
    if (agreementId) {
      const existingPayment = await prisma.subscriptionPayment.findFirst({
        where: { agreementId, status: 'PENDING' },
        orderBy: { createdAt: 'desc' },
      });
      if (existingPayment) {
        return res.json({
          reference: existingPayment.reference,
          amountMinor: existingPayment.amountMinor,
          baseAmountMinor,
          discountAmountMinor,
          discountPercent: existingPayment.discountPercent,
          durationMonths: existingPayment.durationMonths,
          agreementId,
          status: existingPayment.status,
        });
      }
    }
    throw error;
  }
  try {
    const push = await initiateStkPush({ amount: amountMinor / 100, phoneNumber: input.phoneNumber, channelId, externalReference: reference, customerName: req.user.name, callbackUrl: `${process.env.PUBLIC_API_URL}/webhooks/payhero-callback` });
    await prisma.subscriptionPayment.update({ where: { id: payment.id }, data: { checkoutRequestId: push.checkoutRequestId } });
    return res.status(201).json({
      reference,
      amountMinor,
      baseAmountMinor,
      discountAmountMinor,
      discountPercent,
      durationMonths,
      agreementId,
      status: 'PENDING',
    });
  } catch (error) {
    await prisma.subscriptionPayment.update({ where: { id: payment.id }, data: { status: 'FAILED', providerStatus: error instanceof Error ? error.message : 'provider_error' } });
    throw error;
  }
}));

router.get('/subscription/payment/:reference', asyncHandler(async (req, res) => {
  if (!req.user || req.user.role !== 'admin') return res.status(403).json({ error: 'Shop owner access required' });
  const reference = String(req.params.reference);
  const payment = await prisma.subscriptionPayment.findFirst({ where: { reference, tenantId: req.user.tenantId } });
  if (!payment) return res.status(404).json({ error: 'Subscription payment not found' });
  if (payment.status === 'PENDING') {
    const provider = await queryTransactionStatus(reference);
    if (provider.status === 'SUCCESS') await activateSubscriptionPayment(payment.id);
    else if (provider.status === 'FAILED') await prisma.subscriptionPayment.update({ where: { id: payment.id }, data: { status: 'FAILED', providerStatus: String(provider.status) } });
  }
  return res.json({ reference, status: (await prisma.subscriptionPayment.findUnique({ where: { id: payment.id } }))?.status ?? payment.status });
}));

router.post('/subscription/payment/:reference/confirm-code', asyncHandler(async (req, res) => {
  if (!req.user || req.user.role !== 'admin') return res.status(403).json({ error: 'Shop owner access required' });
  const reference = String(req.params.reference);
  const code = typeof req.body?.mpesaCode === 'string' ? req.body.mpesaCode.trim().toUpperCase() : '';
  if (!/^[A-Z0-9]{6,20}$/.test(code)) return res.status(400).json({ error: 'Enter the M-Pesa receipt code shown in the confirmation message' });
  const payment = await prisma.subscriptionPayment.findFirst({ where: { reference, tenantId: req.user.tenantId } });
  if (!payment) return res.status(404).json({ error: 'Subscription payment not found' });
  const provider = await queryTransactionStatus(reference);
  const providerReceipt = String(provider.MpesaReceiptNumber ?? provider.mpesa_receipt_number ?? provider.receipt ?? '').trim().toUpperCase();
  if (provider.status !== 'SUCCESS' || providerReceipt !== code) {
    return res.status(409).json({ error: 'The receipt code does not match a successful PayHero transaction yet', code: 'PAYMENT_NOT_VERIFIED' });
  }
  await prisma.subscriptionPayment.update({ where: { id: payment.id }, data: { mpesaReceiptCode: code } });
  await activateSubscriptionPayment(payment.id);
  return res.json({ status: 'SUCCESS', reference });
}));

async function activateSubscriptionPayment(paymentId: string) {
  const payment = await prisma.subscriptionPayment.findUnique({ where: { id: paymentId } });
  if (!payment || payment.status === 'SUCCESS') return;
  await activateSubscriptionPaymentAtomically({
    paymentId: payment.id,
    tenantId: payment.tenantId,
    durationMonths: payment.durationMonths,
    receiptCode: payment.mpesaReceiptCode,
    voucherApplied: payment.voucherApplied,
  });
}

router.post(
  '/mpesa/channel',
  asyncHandler(async (req, res) => {
    const user = requireUser(req);
    if (user.role !== 'admin') {
      return res.status(403).json({ error: 'Shop admin access required' });
    }
    const { channelType, shortCode, accountNumber, qrTransactionCode, qrCreditPartyIdentifier, description } = parseBody(mpesaChannelSchema, req.body);
    const channel = await registerPaymentChannel({
      channelType,
      shortCode,
      accountNumber,
      description,
    });
    await prisma.tenant.update({
      where: { id: user.tenantId },
      data: {
        mpesaEnabled: true,
        payheroChannelId: channel.id,
        // Safaricom Dynamic QR uses the merchant till/paybill directly. A
        // PayHero bank destination remains valid for STK but cannot be used
        // as a Dynamic QR CPI.
        mpesaQrCpi: channelType === 'bank' ? null : (qrCreditPartyIdentifier ?? shortCode),
        mpesaQrTrxCode: channelType === 'bank' ? null : (qrTransactionCode ?? (channelType === 'till' ? 'BG' : 'PB')),
      },
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
    const userId = req.auth?.sub;
    if (!userId) {
      return res.status(401).json({ error: 'Authenticated user required' });
    }
    if (!isVerifiedEmailMatch(req.auth, email)) {
      return res.status(403).json({
        error: 'A verified account email matching the shop owner email is required',
        code: 'EMAIL_IDENTITY_MISMATCH',
      });
    }
    const existingShop = await prisma.profile.findFirst({
      where: { userId: userId, tenant: { shopName: shopName.trim() } },
    });
    if (existingShop) {
      return res.status(409).json({ error: 'This account is already linked to this shop', tenant_id: existingShop.tenantId });
    }
    const tenantId = readableTenantId(ownerName, shopName);
    const profileId = globalThis.crypto.randomUUID();
    const subscriptionId = globalThis.crypto.randomUUID();
    const now = new Date().toISOString();
    const db = getD1DatabaseBinding();
    const results = await db.batch([
      db.prepare(`
        INSERT INTO tenants (id, shop_name, business_profile, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
      `).bind(tenantId, shopName.trim(), businessProfile, now, now),
      db.prepare(`
        INSERT INTO tenant_subscriptions (id, tenant_id, status, created_at, updated_at)
        SELECT ?, ?, 'pending', ?, ? WHERE changes() = 1
      `).bind(subscriptionId, tenantId, now, now),
      db.prepare(`
        INSERT INTO profiles (id, user_id, tenant_id, name, email, role, created_at)
        SELECT ?, ?, ?, ?, ?, 'admin', ? WHERE changes() = 1
      `).bind(profileId, userId, tenantId, ownerName.trim(), email, now),
    ]);
    if (results.some((result) => (result.meta.changes ?? 0) !== 1)) {
      throw new Error('Tenant provisioning did not create all required records');
    }
    return res.json({ tenant_id: tenantId });
  })
);

// ---------------------------------------------------------------------------
// Get the shops linked to the authenticated OIDC account
// ---------------------------------------------------------------------------

router.get(
  '/shops',
  asyncHandler(async (req, res) => {
    const identity = req.auth;
    if (!identity?.sub && !identity?.email) {
      return res.status(401).json({ error: 'Authentication required' });
    }
    const accountWhere = {
      OR: [
        ...(identity.sub ? [{ userId: identity.sub }] : []),
        ...(identity.email ? [{ email: identity.email }] : []),
      ],
    };
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
    const { mpesaEnabled, etimsEnabled, payheroChannelId, businessProfile, risitiMerchantId } = parseBody(settingsSchema, req.body);
    if (etimsEnabled === true && !taxReportingActivated()) {
      return res.status(409).json({
        error: 'Tax reporting is not activated yet',
        provider: 'risiti',
        kra_activated: false,
      });
    }
    const tenantId = requireUser(req).tenantId;
    const now = new Date().toISOString();
    const db = getD1DatabaseBinding();
    const statements = [
      db.prepare(`
        UPDATE tenants
        SET mpesa_enabled = CASE WHEN ? = 1 THEN ? ELSE mpesa_enabled END,
            etims_enabled = CASE WHEN ? = 1 THEN ? ELSE etims_enabled END,
            payhero_channel_id = CASE WHEN ? = 1 THEN ? ELSE payhero_channel_id END,
            business_profile = CASE WHEN ? = 1 THEN ? ELSE business_profile END,
            risiti_merchant_id = CASE WHEN ? = 1 THEN ? ELSE risiti_merchant_id END,
            updated_at = ?
        WHERE id = ?
      `).bind(
        mpesaEnabled !== undefined ? 1 : 0,
        mpesaEnabled ?? null,
        etimsEnabled !== undefined ? 1 : 0,
        etimsEnabled ?? null,
        payheroChannelId !== undefined ? 1 : 0,
        payheroChannelId ?? null,
        businessProfile !== undefined ? 1 : 0,
        businessProfile ?? null,
        risitiMerchantId !== undefined ? 1 : 0,
        risitiMerchantId ?? null,
        now,
        tenantId,
      ),
    ];
    if (businessProfile !== undefined) {
      statements.push(db.prepare(`
        UPDATE business_context SET app_profile = ? WHERE tenant_id = ?
      `).bind(businessProfile, tenantId));
    }
    const results = await db.batch(statements);
    if ((results[0]?.meta.changes ?? 0) !== 1) {
      return res.status(404).json({ error: 'Shop not found' });
    }
    const tenant = await prisma.tenant.findUnique({ where: { id: tenantId } });
    if (!tenant) return res.status(404).json({ error: 'Shop not found' });
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
    await saveTaxReturnStatus({
      kind: 'vat',
      returnId: current.id,
      taxEntityId: link.taxEntityId,
      currentStatus: current.status,
      nextStatus: input.status,
      rejectionReason: input.rejectionReason,
      actorId: user.id,
      now,
    });
    const updated = await prisma.vatReturn.findUnique({ where: { id: current.id } });
    if (!updated) throw new Error('Updated VAT return could not be reloaded');
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
    await saveTaxReturnStatus({
      kind: 'tot',
      returnId: current.id,
      taxEntityId: link.taxEntityId,
      currentStatus: current.status,
      nextStatus: input.status,
      rejectionReason: input.rejectionReason,
      actorId: user.id,
      now,
    });
    const updated = await prisma.totReturn.findUnique({ where: { id: current.id } });
    if (!updated) throw new Error('Updated TOT return could not be reloaded');
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
    const now = new Date();
    const current = await prisma.shopTaxEntity.findFirst({
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

    const taxEntityId = current?.taxEntityId ?? randomUUID();
    const nowIso = now.toISOString();
    const kraPinCiphertext = input.kraPin === undefined ? null : encryptTaxSecret(input.kraPin);
    const kraPinLast4 = input.kraPin === undefined ? null : lastFour(input.kraPin);
    const db = getD1DatabaseBinding();
    const statements = current
      ? [db.prepare(`
          UPDATE tax_entities
          SET legal_form = ?, display_label = ?,
              kra_pin_ciphertext = COALESCE(?, kra_pin_ciphertext),
              kra_pin_last4 = COALESCE(?, kra_pin_last4),
              registered_tax_obligations = ?, accounting_period_start_month = ?,
              status = ?, etims_onboarding_status = ?, etims_method = ?, updated_at = ?
          WHERE id = ?
        `).bind(
          input.legalForm,
          input.displayLabel,
          kraPinCiphertext,
          kraPinLast4,
          JSON.stringify(input.registeredTaxObligations),
          input.accountingPeriodStartMonth,
          input.status,
          input.etimsOnboardingStatus,
          input.etimsMethod ?? null,
          nowIso,
          taxEntityId,
        )]
      : [db.prepare(`
          INSERT INTO tax_entities (
            id, legal_form, display_label, kra_pin_ciphertext, kra_pin_last4,
            registered_tax_obligations, accounting_period_start_month, status,
            etims_onboarding_status, etims_method, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).bind(
          taxEntityId,
          input.legalForm,
          input.displayLabel,
          kraPinCiphertext,
          kraPinLast4,
          JSON.stringify(input.registeredTaxObligations),
          input.accountingPeriodStartMonth,
          input.status,
          input.etimsOnboardingStatus,
          input.etimsMethod ?? null,
          nowIso,
          nowIso,
        )];

    if (current && current.effectiveFrom.getTime() === effectiveFrom.getTime()) {
      statements.push(db.prepare(`
        UPDATE shop_tax_entities
        SET tax_entity_id = ?, outlet_reference = ?
        WHERE id = ?
      `).bind(taxEntityId, input.outletReference, current.id));
      statements.push(db.prepare(`
        INSERT INTO shop_tax_entities (id, tenant_id, tax_entity_id, effective_from)
        SELECT NULL, NULL, NULL, NULL WHERE changes() <> 1
      `));
    } else {
      if (current && current.effectiveTo == null && effectiveFrom > current.effectiveFrom) {
        statements.push(db.prepare(`
          UPDATE shop_tax_entities SET effective_to = ? WHERE id = ?
        `).bind(effectiveFrom.toISOString(), current.id));
        statements.push(db.prepare(`
          INSERT INTO shop_tax_entities (id, tenant_id, tax_entity_id, effective_from)
          SELECT NULL, NULL, NULL, NULL WHERE changes() <> 1
        `));
      }
      statements.push(db.prepare(`
        INSERT INTO shop_tax_entities (
          id, tenant_id, tax_entity_id, outlet_reference, effective_from, created_at
        ) VALUES (?, ?, ?, ?, ?, ?)
      `).bind(
        randomUUID(),
        tenantId,
        taxEntityId,
        input.outletReference,
        effectiveFrom.toISOString(),
        nowIso,
      ));
    }
    await db.batch(statements);
    const saved = await prisma.taxEntity.findUnique({ where: { id: taxEntityId } });
    if (!saved) throw new Error('Tax entity could not be reloaded after update');
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
    const remoteIds = staff.map((item) => item.remoteId).filter((id): id is string => Boolean(id));
    const localIds = staff.map((item) => item.localId);
    const profiles = staff.length === 0
      ? []
      : await prisma.profile.findMany({
          where: {
            tenantId,
            AND: [
              managedStaffProfileFilter(),
              {
                OR: [
                  ...(remoteIds.length > 0 ? [{ id: { in: remoteIds } }] : []),
                  { localId: { in: localIds } },
                ],
              },
            ],
          },
          select: { id: true, localId: true, role: true },
        });
    const plannedProfiles = profiles.map((profile) => ({
      id: profile.id,
      localId: profile.localId,
      role: profile.role,
    }));
    const db = getD1DatabaseBinding();
    const statements = [];
    const synced: Array<{ localId: number; remoteId: string }> = [];
    for (const item of staff) {
      const existing = item.remoteId
        ? plannedProfiles.find((profile) => profile.id === item.remoteId)
        : plannedProfiles.find((profile) => profile.localId === item.localId);
      const username = item.username?.trim().toLowerCase() ?? null;
      if (existing) {
        statements.push(db.prepare(`
          UPDATE profiles
          SET name = ?, username = ?, role = ?, active = ?, pin_hash = COALESCE(?, pin_hash)
          WHERE id = ? AND tenant_id = ?
            AND (
              role IN ('cashier', 'manager')
              OR (role = 'admin' AND user_id IS NULL AND local_id IS NOT NULL)
            )
        `).bind(item.name, username, item.role, item.active, item.pinHash ?? null, existing.id, tenantId));
        synced.push({ localId: item.localId, remoteId: existing.id });
      } else {
        const remoteId = randomUUID();
        statements.push(db.prepare(`
          INSERT INTO profiles (id, tenant_id, local_id, name, username, pin_hash, role, active)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `).bind(
          remoteId,
          tenantId,
          item.localId,
          item.name,
          username,
          item.pinHash ?? null,
          item.role,
          item.active,
        ));
        plannedProfiles.push({ id: remoteId, localId: item.localId, role: item.role });
        synced.push({ localId: item.localId, remoteId });
      }
    }
    if (statements.length > 0) {
      const results = await db.batch(statements);
      if (results.some((result) => (result.meta.changes ?? 0) !== 1)) {
        throw new HttpError(409, 'One or more staff profiles changed during sync; retry the roster');
      }
    }
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
        AND: [managedStaffProfileFilter()],
      },
      select: { id: true, localId: true, name: true, username: true, role: true, active: true, deletedAt: true },
      orderBy: { name: 'asc' },
    });
    return res.json({
      staff: profiles.map(({ deletedAt, ...profile }) => ({
        ...profile,
        active: profile.active &&
          (deletedAt === null || deletedAt === undefined),
      })),
    });
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
      where: {
        id: profileId,
        tenantId: requireUser(req).tenantId,
        AND: [managedStaffProfileFilter()],
      },
    });
    if (!profile) {
      return res.status(404).json({ error: 'Staff profile not found' });
    }
    const deletedLabel = 'Deleted cashier';
    const tenantId = requireUser(req).tenantId;
    const now = new Date().toISOString();
    const ledgerId = randomUUID();
    const db = getD1DatabaseBinding();
    const results = await db.batch([
      db.prepare(`
        UPDATE profiles
        SET name = ?, active = 0, deleted_at = ?
        WHERE id = ? AND tenant_id = ?
          AND (
            role IN ('cashier', 'manager')
            OR (role = 'admin' AND user_id IS NULL AND local_id IS NOT NULL)
          )
          AND deleted_at IS NULL
      `).bind(deletedLabel, now, profile.id, tenantId),
      db.prepare(`
        INSERT INTO deletion_ledgers (id, tenant_id, subject_type, subject_id, reason, completed_at)
        SELECT ?, ?, 'staff_profile', ?, ?, ?
        WHERE changes() = 1
      `).bind(ledgerId, tenantId, profile.id, reason ?? null, now),
      db.prepare(`
        UPDATE sales SET staff_name = ?
        WHERE tenant_id = ? AND staff_id = ?
          AND EXISTS (SELECT 1 FROM deletion_ledgers WHERE id = ?)
      `).bind(deletedLabel, tenantId, profile.id, ledgerId),
      db.prepare(`
        UPDATE payments SET staff_name = ?
        WHERE tenant_id = ? AND initiated_by = ?
          AND EXISTS (SELECT 1 FROM deletion_ledgers WHERE id = ?)
      `).bind(deletedLabel, tenantId, profile.id, ledgerId),
    ]);
    if ((results[0]?.meta.changes ?? 0) !== 1 || (results[1]?.meta.changes ?? 0) !== 1) {
      return res.status(409).json({ error: 'Staff profile changed during deletion; reload before retrying' });
    }
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
    const requestId = (req as any).requestId ?? req.header('x-request-id') ?? null;
    const headerTenantId = req.header('x-tenant-id')?.trim() || null;
    const authTenantId = req.user?.tenantId ?? null;
    console.info('[staff-auth] request received', {
      requestId,
      path: req.originalUrl,
      method: req.method,
      hasAuthUser: Boolean(req.user),
      authTenantId,
      headerTenantId,
      ip: req.ip,
    });

    try {
      const parsed = parseBody(staffAuthenticateSchema, req.body);
      const rawUsername = typeof parsed.username === 'string' ? parsed.username : '';
      const username = rawUsername.trim().toLowerCase();
      const pin = typeof parsed.pin === 'string' ? parsed.pin : '';
      console.info('[staff-auth] parsed request', {
        requestId,
        headerTenantId,
        authTenantId,
        rawUsernameLength: rawUsername.length,
        normalizedUsername: username,
        pinLength: pin.length,
      });

      // On a fresh till there is no bearer token yet. The shop was selected in
      // the app before this request, so the tenant header is the only accepted
      // shop selector; credentials are never used to discover a tenant.
      const tenantId = authTenantId ?? headerTenantId;
      if (!tenantId || tenantId.trim().length === 0) {
        console.warn('[staff-auth] rejected: missing tenant/shop selection', {
          requestId,
          headerTenantId,
          authTenantId,
          normalizedUsername: username,
          status: 400,
          code: 'SHOP_SELECTION_REQUIRED',
        });
        return res.status(400).json({ error: 'Shop selection required' });
      }

      const entitlement = await tenantEntitlement(tenantId);
      if (!entitlement.allowed) {
        console.warn('[staff-auth] rejected: entitlement/subscription required', {
          requestId,
          tenantId,
          normalizedUsername: username,
          status: 402,
          code: 'SUBSCRIPTION_REQUIRED',
          entitlementState: (entitlement as any)?.state ?? null,
          entitlementReason: (entitlement as any)?.reason ?? null,
        });
        return res.status(402).json({
          error: 'An active subscription or voucher is required',
          code: 'SUBSCRIPTION_REQUIRED',
          entitlement,
        });
      }

      const profile = await getD1DatabaseBinding().prepare(`
        SELECT p.id, p.local_id, p.name, p.username, p.role, p.active,
               p.pin_hash, t.shop_name
        FROM profiles p
        JOIN tenants t ON t.id = p.tenant_id
        WHERE p.tenant_id = ?
          AND p.username = ?
          AND (
            p.role IN ('cashier', 'manager')
            OR (p.role = 'admin' AND p.user_id IS NULL AND p.local_id IS NOT NULL)
          )
          AND p.active = 1
          AND p.deleted_at IS NULL
        LIMIT 1
      `).bind(tenantId, username).first<{
        id: string;
        local_id: number | null;
        name: string;
        username: string;
        role: 'cashier' | 'manager' | 'admin';
        active: number;
        pin_hash: string | null;
        shop_name: string;
      }>();

      console.info('[staff-auth] profile lookup result', {
        requestId,
        tenantId,
        normalizedUsername: username,
        found: Boolean(profile),
        profileId: profile?.id ?? null,
        localId: profile?.local_id ?? null,
        role: profile?.role ?? null,
        active: profile?.active ?? null,
        hasPinHash: profile ? Boolean(profile.pin_hash) : null,
      });

      if (!profile) {
        console.warn('[staff-auth] rejected: staff not found or inactive', {
          requestId,
          tenantId,
          normalizedUsername: username,
          status: 401,
          code: 'STAFF_NOT_FOUND_OR_INACTIVE',
        });
        return res.status(401).json({ error: 'Staff not found or inactive' });
      }

      // Keep a server-side verifier so a fresh device can bootstrap its offline
      // roster without accepting an arbitrary PIN. Existing local devices still
      // verify first, but the backend closes the online trust boundary too.
      const pinValid = await verifyStaffPin(pin, profile.pin_hash);
      console.info('[staff-auth] pin verification result', {
        requestId,
        tenantId,
        normalizedUsername: username,
        profileId: profile.id,
        role: profile.role,
        pinValid,
      });
      if (!pinValid) {
        console.warn('[staff-auth] rejected: invalid staff credentials', {
          requestId,
          tenantId,
          normalizedUsername: username,
          profileId: profile.id,
          role: profile.role,
          status: 401,
          code: 'INVALID_STAFF_CREDENTIALS',
        });
        return res.status(401).json({ error: 'Invalid staff credentials' });
      }

      const response = {
        staff_id: profile.id,
        local_id: profile.local_id ?? null,
        name: profile.name,
        role: profile.role,
        tenant_id: tenantId,
        shop_name: profile.shop_name,
        session_token: issueStaffSessionToken({
          profileId: profile.id,
          tenantId,
          userId: `staff:${profile.id}`,
        }).token,
      };
      console.info('[staff-auth] authentication succeeded', {
        requestId,
        tenantId,
        normalizedUsername: username,
        profileId: profile.id,
        localId: profile.local_id ?? null,
        role: profile.role,
        shopName: profile.shop_name,
        status: 200,
      });
      return res.json(response);
    } catch (error) {
      const err = error as any;
      console.error('[staff-auth] unhandled error', {
        requestId,
        headerTenantId,
        authTenantId,
        path: req.originalUrl,
        name: err?.name ?? null,
        message: err?.message ?? String(error),
        status: err?.status ?? err?.statusCode ?? null,
        code: err?.code ?? null,
        stack: err?.stack ?? null,
      });
      throw error;
    }
  })
);

router.post(
  '/staff/self-pin',
  staffAuthLimiter,
  asyncHandler(async (req, res) => {
    const authorization = req.header('authorization') ?? '';
    const token = authorization.match(/^Bearer\s+(.+)$/i)?.[1]?.trim() ?? '';
    const claims = verifyStaffSessionToken(token);
    const tenantId = req.header('x-tenant-id');
    if (!claims || !tenantId || claims.tenantId !== tenantId) {
      return res.status(401).json({ error: 'Staff session required' });
    }
    const { currentPin, newPin } = parseBody(staffSelfPinSchema, req.body);
    if (currentPin === newPin) return res.status(400).json({ error: 'New PIN must be different' });
    const profile = await prisma.profile.findFirst({
      where: {
        id: claims.profileId,
        tenantId,
        active: true,
        deletedAt: null,
        AND: [managedStaffProfileFilter()],
      },
    });
    if (!profile || !await verifyStaffPin(currentPin, profile.pinHash)) {
      return res.status(401).json({ error: 'Current PIN is incorrect' });
    }
    await prisma.profile.update({ where: { id: profile.id }, data: { pinHash: await hashStaffPin(newPin) } });
    return res.json({ status: 'pin_changed', staff_id: profile.id });
  }),
);

// A forgotten PIN cannot authenticate, so this deliberately narrow bootstrap
// route accepts only the selected tenant and username. It never confirms
// whether a username exists; the same response prevents staff enumeration.
router.post(
  '/staff/pin-reset-request',
  staffAuthLimiter,
  asyncHandler(async (req, res) => {
    const { username: rawUsername } = parseBody(staffPinResetRequestSchema, req.body);
    const tenantId = req.header('x-tenant-id')?.trim();
    if (!tenantId) return res.status(400).json({ error: 'Shop selection required' });
    const username = rawUsername.toLowerCase();
    const profile = await prisma.profile.findFirst({
      where: {
        tenantId,
        username,
        active: true,
        deletedAt: null,
        AND: [managedStaffProfileFilter()],
      },
      select: { id: true, localId: true, name: true },
    });
    if (profile) {
      await prisma.syncRecord.create({
        data: {
          tenantId,
          kind: 'staff_pin_reset_request',
          deviceId: `staff:${profile.id}`,
          localId: Date.now(),
          payload: { status: 'pending', staffProfileId: profile.id, staffLocalId: profile.localId, staffName: profile.name },
          createdAt: new Date(),
        },
      });
      broadcastTenantChange(tenantId, ['staff_pin_reset_requested']);
    }
    return res.status(202).json({ status: 'request_received' });
  }),
);

router.get(
  '/staff/pin-reset-requests',
  asyncHandler(async (req, res) => {
    const user = requireUser(req);
    if (user.role !== 'admin') return res.status(403).json({ error: 'Shop admin access required' });
    const records = await prisma.syncRecord.findMany({
      where: { tenantId: user.tenantId, kind: 'staff_pin_reset_request' },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    return res.json({ requests: records.map((record: any) => {
      const payload = record.payload as Record<string, unknown>;
      return {
        id: record.id,
        status: payload.status ?? 'pending',
        staff_profile_id: payload.staffProfileId,
        staff_local_id: payload.staffLocalId,
        staff_name: payload.staffName,
        created_at: record.createdAt,
        updated_at: record.updatedAt,
      };
    }).filter((request: any) => request.status === 'pending') });
  }),
);

router.post(
  '/staff/pin-reset-requests/:requestId/reset',
  asyncHandler(async (req, res) => {
    const user = requireUser(req);
    if (user.role !== 'admin') return res.status(403).json({ error: 'Shop admin access required' });
    const { temporaryPin } = parseBody(staffPinResetApproveSchema, req.body);
    const requestId = typeof req.params.requestId === 'string' ? req.params.requestId : '';
    const record = await prisma.syncRecord.findFirst({
      where: { id: requestId, tenantId: user.tenantId, kind: 'staff_pin_reset_request' },
    });
    if (!record) return res.status(404).json({ error: 'PIN reset request not found' });
    const payload = record.payload as Record<string, unknown>;
    if (payload.status !== 'pending' || typeof payload.staffProfileId !== 'string') {
      return res.status(409).json({ error: 'PIN reset request is no longer pending' });
    }
    const profile = await prisma.profile.findFirst({
      where: {
        id: payload.staffProfileId,
        tenantId: user.tenantId,
        active: true,
        deletedAt: null,
        AND: [managedStaffProfileFilter()],
      },
    });
    if (!profile) return res.status(404).json({ error: 'Staff profile is no longer active' });
    const now = new Date().toISOString();
    const db = getD1DatabaseBinding();
    const newPinHash = await hashStaffPin(temporaryPin);
    const results = await db.batch([
      db.prepare(`
        UPDATE profiles
        SET pin_hash = ?
        WHERE id = ? AND tenant_id = ?
          AND (
            role IN ('cashier', 'manager')
            OR (role = 'admin' AND user_id IS NULL AND local_id IS NOT NULL)
          )
          AND active = 1 AND deleted_at IS NULL
          AND EXISTS (
            SELECT 1 FROM sync_records
            WHERE id = ? AND tenant_id = ? AND kind = 'staff_pin_reset_request'
              AND json_extract(payload, '$.status') = 'pending'
              AND json_extract(payload, '$.staffProfileId') = ?
          )
      `).bind(
        newPinHash,
        profile.id,
        user.tenantId,
        record.id,
        user.tenantId,
        profile.id,
      ),
      db.prepare(`
        UPDATE sync_records
        SET payload = ?
        WHERE id = ? AND tenant_id = ? AND kind = 'staff_pin_reset_request'
          AND json_extract(payload, '$.status') = 'pending'
          AND json_extract(payload, '$.staffProfileId') = ?
          AND changes() = 1
      `).bind(
        JSON.stringify({ ...payload, status: 'completed', completedAt: now }),
        record.id,
        user.tenantId,
        profile.id,
      ),
    ]);
    if ((results[0]?.meta.changes ?? 0) !== 1 || (results[1]?.meta.changes ?? 0) !== 1) {
      return res.status(409).json({ error: 'PIN reset request changed; reload before retrying' });
    }
    // Never include the temporary PIN in the response, live signal, or audit
    // payload. The owner communicates it directly to the named staff member.
    broadcastTenantChange(user.tenantId, ['staff_pin_reset_completed']);
    return res.json({ status: 'reset_completed', staff_profile_id: profile.id });
  }),
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
            ...(identity.sub ? [{ userId: identity.sub }] : []),
            { email: identity.email },
          ],
        }
      : identity?.sub
        ? { userId: identity.sub }
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
        shifts_closed: number;
        shifts_open: number;
        cash_variance: number | null;
      }>>(Prisma.sql`
        SELECT tenant_id,
               SUM(CASE
                 WHEN json_extract(payload, '$.status') = 'closed'
                   AND created_at >= ${from}
                   AND created_at < ${to}
                 THEN 1 ELSE 0
               END) AS shifts_closed,
               SUM(CASE
                 WHEN json_extract(payload, '$.status') = 'open'
                   AND created_at >= ${from}
                   AND created_at < ${to}
                 THEN 1 ELSE 0
               END) AS shifts_open,
               COALESCE(SUM(
                 CASE WHEN json_extract(payload, '$.status') = 'closed'
                           AND created_at >= ${from}
                           AND created_at < ${to} THEN
                   COALESCE(CAST(NULLIF(json_extract(payload, '$.countedCash'), '') AS INTEGER), 0) -
                   COALESCE(CAST(NULLIF(json_extract(payload, '$.expectedCash'), '') AS INTEGER), 0)
                 ELSE 0 END
               ), 0) AS cash_variance
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
      ? { OR: [...(identity.sub ? [{ userId: identity.sub }] : []), { email: identity.email }] }
      : identity?.sub
        ? { userId: identity.sub }
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
