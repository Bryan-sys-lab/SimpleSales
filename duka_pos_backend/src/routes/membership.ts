import { randomUUID } from 'node:crypto';
import { Request, Response, Router } from 'express';
import { z } from 'zod';
import { asyncHandler, requireUser } from '../lib/http';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { parseBody } from '../lib/validation';

const router = Router();

const requestSchema = z.object({
  features: z.array(z.string().trim().min(1).max(120)).max(50).default([]),
  requirements: z.string().trim().max(2000).default(''),
}).strict().refine((value) => value.features.length > 0 || value.requirements.length > 0, {
  message: 'Select at least one feature or describe a requirement',
});

const messageSchema = z.object({
  body: z.string().trim().min(1).max(2000),
}).strict();

const acceptOfferSchema = z.object({
  expectedAmountMinor: z.number().int().positive(),
  expectedDiscountPercent: z.number().int().min(0).max(100),
  expectedVoucherApplied: z.boolean(),
}).strict();

function isActiveDiscountVoucher(voucher: {
  voucherType: string;
  discountPercent: number;
  durationMonths: number;
  expiresAt: Date | null;
  revokedAt: Date | null;
  pausedAt: Date | null;
  deletedAt: Date | null;
} | null, termMonths: number | null): boolean {
  return Boolean(
    voucher &&
    voucher.voucherType === 'discount' &&
    voucher.discountPercent > 0 &&
    termMonths !== null &&
    voucher.durationMonths === termMonths &&
    (!voucher.expiresAt || voucher.expiresAt > new Date()) &&
    !voucher.revokedAt &&
    !voucher.pausedAt &&
    !voucher.deletedAt,
  );
}

async function getOfferPreview(tenantId: string, requestId: string, offerId: string) {
  const offer = await prisma.membershipOffer.findFirst({
    where: { id: offerId, requestId },
  });
  if (!offer || offer.status !== 'offered' || (offer.expiresAt && offer.expiresAt <= new Date())) {
    return null;
  }
  const subscription = await prisma.tenantSubscription.findUnique({
    where: { tenantId },
    include: {
      voucher: {
        select: {
          id: true,
          voucherType: true,
          discountPercent: true,
          durationMonths: true,
          expiresAt: true,
          revokedAt: true,
          pausedAt: true,
          deletedAt: true,
        },
      },
    },
  });
  const voucher = subscription?.voucher ?? null;
  const voucherApplicable = isActiveDiscountVoucher(voucher, offer.termMonths);
  const discountPercent = voucherApplicable && voucher ? voucher.discountPercent : 0;
  const amountMinor = Math.round(offer.amountMinor * (100 - discountPercent) / 100);
  if (!Number.isSafeInteger(amountMinor) || amountMinor < 1) {
    throw new RangeError('Discounted membership offer must be at least one minor currency unit');
  }
  return {
    offer,
    voucherId: voucherApplicable ? voucher?.id ?? null : null,
    voucherApplicable,
    voucherNotApplicable: Boolean(voucher?.voucherType === 'discount' && !voucherApplicable),
    discountPercent,
    baseAmountMinor: offer.amountMinor,
    discountAmountMinor: offer.amountMinor - amountMinor,
    amountMinor,
  };
}

function requireShopOwner(req: Request, res: Response) {
  const user = requireUser(req);
  if (user.role !== 'admin') {
    res.status(403).json({ error: 'Shop owner access required' });
    return null;
  }
  return user;
}

router.get('/requests', asyncHandler(async (req, res) => {
  const user = requireShopOwner(req, res);
  if (!user) return;
  const requests = await prisma.membershipRequest.findMany({
    where: { tenantId: user.tenantId },
    include: {
      offers: { orderBy: { revision: 'desc' } },
      messages: { orderBy: { createdAt: 'asc' }, take: 100 },
      agreement: true,
    },
    orderBy: { createdAt: 'desc' },
    take: 20,
  });
  return res.json({ requests });
}));

router.post('/requests', asyncHandler(async (req, res) => {
  const user = requireShopOwner(req, res);
  if (!user) return;
  const input = parseBody(requestSchema, req.body);
  const features = [...new Set(input.features)];
  const request = await prisma.membershipRequest.create({
    data: {
      tenantId: user.tenantId,
      requestedBy: user.id,
      features,
      requirements: input.requirements,
      status: 'pending',
    },
  });
  return res.status(201).json({ request });
}));

router.get('/requests/:id', asyncHandler(async (req, res) => {
  const user = requireShopOwner(req, res);
  if (!user) return;
  const request = await prisma.membershipRequest.findFirst({
    where: { id: String(req.params.id), tenantId: user.tenantId },
    include: {
      offers: { orderBy: { revision: 'desc' } },
      messages: { orderBy: { createdAt: 'asc' }, take: 100 },
      agreement: true,
    },
  });
  if (!request) return res.status(404).json({ error: 'Membership request not found' });
  return res.json({ request });
}));

router.post('/requests/:id/messages', asyncHandler(async (req, res) => {
  const user = requireShopOwner(req, res);
  if (!user) return;
  const input = parseBody(messageSchema, req.body);
  const requestId = String(req.params.id);
  const request = await prisma.membershipRequest.findFirst({
    where: { id: requestId, tenantId: user.tenantId },
    select: { id: true, status: true },
  });
  if (!request) return res.status(404).json({ error: 'Membership request not found' });
  if (['accepted', 'closed'].includes(request.status)) {
    return res.status(409).json({ error: 'This membership discussion is closed' });
  }
  const db = getD1DatabaseBinding();
  const messageId = randomUUID();
  const createdAt = new Date().toISOString();
  const results = await db.batch([
    db.prepare(`
      INSERT INTO membership_messages (id, request_id, sender_type, sender_id, body, created_at)
      SELECT ?, ?, 'customer', ?, ?, ?
      WHERE EXISTS (
        SELECT 1 FROM membership_requests
        WHERE id = ? AND tenant_id = ? AND status NOT IN ('accepted', 'closed')
      )
    `).bind(messageId, requestId, user.id, input.body, createdAt, requestId, user.tenantId),
    db.prepare(`
      UPDATE membership_requests
      SET status = CASE WHEN status = 'offer_ready' THEN 'negotiating' ELSE status END,
          updated_at = ?
      WHERE id = ? AND tenant_id = ? AND status NOT IN ('accepted', 'closed') AND changes() = 1
    `).bind(createdAt, requestId, user.tenantId),
  ]);
  if ((results[0]?.meta.changes ?? 0) !== 1) {
    return res.status(409).json({ error: 'This membership discussion is closed' });
  }
  return res.status(201).json({
    message: { id: messageId, requestId, senderType: 'customer', senderId: user.id, body: input.body, createdAt },
  });
}));

router.get('/requests/:id/offers/:offerId/preview', asyncHandler(async (req, res) => {
  const user = requireShopOwner(req, res);
  if (!user) return;
  const request = await prisma.membershipRequest.findFirst({
    where: { id: String(req.params.id), tenantId: user.tenantId },
    select: { id: true },
  });
  if (!request) return res.status(404).json({ error: 'Membership request not found' });
  const preview = await getOfferPreview(user.tenantId, request.id, String(req.params.offerId));
  if (!preview) return res.status(404).json({ error: 'Offer is no longer available' });
  return res.json({
    offer: preview.offer,
    pricing: {
      currency: preview.offer.currency,
      baseAmountMinor: preview.baseAmountMinor,
      discountPercent: preview.discountPercent,
      discountAmountMinor: preview.discountAmountMinor,
      amountMinor: preview.amountMinor,
      voucherApplied: preview.voucherApplicable,
      voucherNotApplicable: preview.voucherNotApplicable,
    },
  });
}));

router.post('/requests/:id/offers/:offerId/accept', asyncHandler(async (req, res) => {
  const user = requireShopOwner(req, res);
  if (!user) return;
  const expected = parseBody(acceptOfferSchema, req.body);
  const requestId = String(req.params.id);
  const offerId = String(req.params.offerId);
  const request = await prisma.membershipRequest.findFirst({
    where: { id: requestId, tenantId: user.tenantId },
    include: { agreement: true },
  });
  if (!request) return res.status(404).json({ error: 'Membership request not found' });
  if (request.agreement || request.status === 'accepted') {
    return res.status(409).json({ error: 'This offer has already been accepted' });
  }
  const preview = await getOfferPreview(user.tenantId, requestId, offerId);
  if (!preview) return res.status(409).json({ error: 'Offer is no longer available' });
  if (
    expected.expectedAmountMinor !== preview.amountMinor ||
    expected.expectedDiscountPercent !== preview.discountPercent ||
    expected.expectedVoucherApplied !== preview.voucherApplicable
  ) {
    return res.status(409).json({
      error: 'Offer pricing changed. Review the current amount before accepting.',
      code: 'OFFER_PREVIEW_CHANGED',
    });
  }

  const acceptedAt = new Date().toISOString();
  const agreementId = randomUUID();
  const reference = `AGR-${randomUUID()}`;
  const snapshot = {
    requestId,
    offerId,
    revision: preview.offer.revision,
    amountMinor: preview.amountMinor,
    baseAmountMinor: preview.baseAmountMinor,
    discountPercent: preview.discountPercent,
    discountAmountMinor: preview.discountAmountMinor,
    currency: preview.offer.currency,
    termMonths: preview.offer.termMonths,
    paymentArrangement: preview.offer.paymentArrangement,
    renewalTerms: preview.offer.renewalTerms,
    includedFeatures: preview.offer.includedFeatures,
    additionalConditions: preview.offer.additionalConditions,
    voucherId: preview.voucherId,
    acceptedAt,
  };
  const subscription = await prisma.tenantSubscription.findUnique({
    where: { tenantId: user.tenantId },
    select: { voucherId: true },
  });
  const db = getD1DatabaseBinding();
  const results = await db.batch([
    db.prepare(`
      INSERT OR IGNORE INTO membership_agreements (
        id, tenant_id, request_id, offer_id, reference, snapshot, accepted_at
      )
      SELECT ?, ?, ?, ?, ?, ?, ?
      WHERE EXISTS (
        SELECT 1 FROM membership_offers
        WHERE id = ? AND request_id = ? AND status = 'offered'
          AND (expires_at IS NULL OR expires_at > ?)
      )
    `).bind(
      agreementId, user.tenantId, requestId, offerId, reference,
      JSON.stringify(snapshot), acceptedAt, offerId, requestId, acceptedAt,
    ),
    db.prepare(`
      UPDATE membership_offers
      SET status = 'accepted'
      WHERE id = ? AND request_id = ? AND status = 'offered' AND changes() = 1
    `).bind(offerId, requestId),
    db.prepare(`
      UPDATE membership_requests
      SET status = 'accepted', updated_at = ?
      WHERE id = ? AND tenant_id = ? AND changes() = 1
    `).bind(acceptedAt, requestId, user.tenantId),
    db.prepare(`
      INSERT INTO tenant_subscriptions (
        id, tenant_id, status, price_minor, discount_percent, currency,
        billing_interval, current_period_end, grace_until, voucher_id,
        agreement_id, updated_by, created_at, updated_at
      )
      SELECT ?, ?, 'awaiting_payment', ?, ?, ?, 'as_agreed', NULL, NULL, ?, ?, ?, ?, ?
      WHERE changes() = 1
      ON CONFLICT (tenant_id) DO UPDATE SET
        status = 'awaiting_payment',
        price_minor = excluded.price_minor,
        discount_percent = excluded.discount_percent,
        currency = excluded.currency,
        billing_interval = 'as_agreed',
        current_period_end = NULL,
        grace_until = NULL,
        voucher_id = excluded.voucher_id,
        agreement_id = excluded.agreement_id,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
    `).bind(
      randomUUID(), user.tenantId, preview.baseAmountMinor, preview.discountPercent,
      preview.offer.currency, subscription?.voucherId ?? null, agreementId, user.id,
      acceptedAt, acceptedAt,
    ),
  ]);
  if ((results[0]?.meta.changes ?? 0) !== 1) {
    return res.status(409).json({ error: 'Offer was accepted by another action or is no longer available' });
  }
  return res.status(201).json({
    agreement: { id: agreementId, reference, acceptedAt, snapshot },
  });
}));

router.get('/agreements', asyncHandler(async (req, res) => {
  const user = requireShopOwner(req, res);
  if (!user) return;
  const agreements = await prisma.membershipAgreement.findMany({
    where: { tenantId: user.tenantId },
    orderBy: { acceptedAt: 'desc' },
    take: 50,
  });
  return res.json({ agreements });
}));

router.get('/payments', asyncHandler(async (req, res) => {
  const user = requireShopOwner(req, res);
  if (!user) return;
  const payments = await prisma.subscriptionPayment.findMany({
    where: { tenantId: user.tenantId },
    select: {
      id: true,
      reference: true,
      amountMinor: true,
      durationMonths: true,
      discountPercent: true,
      status: true,
      providerStatus: true,
      mpesaReceiptCode: true,
      agreementId: true,
      createdAt: true,
      updatedAt: true,
    },
    orderBy: { createdAt: 'desc' },
    take: 50,
  });
  return res.json({ payments });
}));

router.get('/vouchers', asyncHandler(async (req, res) => {
  const user = requireShopOwner(req, res);
  if (!user) return;
  const vouchers = await prisma.accessVoucher.findMany({
    where: {
      tenantId: user.tenantId,
      OR: [{ redeemedAt: { not: null } }, { issuedToEmail: { not: null } }],
    },
    select: {
      id: true,
      codePrefix: true,
      voucherType: true,
      durationMonths: true,
      discountPercent: true,
      expiresAt: true,
      redeemedAt: true,
      revokedAt: true,
      pausedAt: true,
      createdAt: true,
    },
    orderBy: { createdAt: 'desc' },
    take: 100,
  });
  return res.json({ vouchers });
}));

export default router;
