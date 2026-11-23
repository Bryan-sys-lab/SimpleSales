import { randomUUID } from 'node:crypto';
import { Request, Response, Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../lib/http';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { prepareAdminAudit } from '../lib/admin_audit_d1';
import { parseBody } from '../lib/validation';
import { systemAdminMiddleware } from '../middleware/auth';

const router = Router();
router.use(systemAdminMiddleware);

const offerSchema = z.object({
  amountMinor: z.number().int().positive().max(2_147_483_647),
  currency: z.literal('KES').default('KES'),
  termMonths: z.number().int().min(1).max(120).nullable().default(null),
  paymentArrangement: z.string().trim().min(1).max(500),
  renewalTerms: z.string().trim().min(1).max(500),
  includedFeatures: z.array(z.string().trim().min(1).max(120)).max(50).optional(),
  additionalConditions: z.string().trim().max(2000).nullable().optional(),
  expiresAt: z.string().datetime({ offset: true }).nullable().optional(),
}).strict().superRefine((value, context) => {
  if (value.expiresAt && new Date(value.expiresAt) <= new Date()) {
    context.addIssue({ code: 'custom', path: ['expiresAt'], message: 'Offer expiry must be in the future' });
  }
});

const messageSchema = z.object({
  body: z.string().trim().min(1).max(2000),
}).strict();

router.get('/requests', asyncHandler(async (req, res) => {
  const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
  const status = typeof req.query.status === 'string' ? req.query.status : undefined;
  const allowedStatuses = new Set(['pending', 'offer_ready', 'negotiating', 'accepted', 'closed']);
  if (status && !allowedStatuses.has(status)) {
    return res.status(400).json({ error: 'Unsupported membership request status' });
  }
  const requests = await prisma.membershipRequest.findMany({
    where: status ? { status } : {},
    include: {
      tenant: { select: { id: true, shopName: true } },
      offers: { orderBy: { revision: 'desc' } },
      messages: { orderBy: { createdAt: 'asc' }, take: 100 },
      agreement: true,
    },
    orderBy: { updatedAt: 'desc' },
    take: limit,
  });
  return res.json({ requests });
}));

router.post('/requests/:id/offers', asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(offerSchema, req.body);
  const requestId = String(req.params.id);
  const request = await prisma.membershipRequest.findUnique({
    where: { id: requestId },
    select: { id: true, tenantId: true, features: true, status: true },
  });
  if (!request) return res.status(404).json({ error: 'Membership request not found' });
  if (['accepted', 'closed'].includes(request.status)) {
    return res.status(409).json({ error: 'This membership request is closed' });
  }

  const includedFeatures = input.includedFeatures ?? (
    Array.isArray(request.features)
      ? request.features.filter((item): item is string => typeof item === 'string')
      : []
  );
  const uniqueFeatures = [...new Set(includedFeatures)];
  const offerId = randomUUID();
  const createdAt = new Date().toISOString();
  const expiresAt = input.expiresAt ? new Date(input.expiresAt).toISOString() : null;
  const db = getD1DatabaseBinding();
  const results = await db.batch([
    db.prepare(`
      UPDATE membership_offers SET status = 'superseded'
      WHERE request_id = ? AND status = 'offered'
        AND EXISTS (
          SELECT 1 FROM membership_requests
          WHERE id = ? AND status NOT IN ('accepted', 'closed')
        )
    `).bind(requestId, requestId),
    db.prepare(`
      INSERT INTO membership_offers (
        id, request_id, revision, status, amount_minor, currency, term_months,
        payment_arrangement, renewal_terms, included_features,
        additional_conditions, expires_at, created_by, created_at
      )
      SELECT ?, ?, COALESCE((
        SELECT MAX(revision) FROM membership_offers WHERE request_id = ?
      ), 0) + 1, 'offered', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
      WHERE EXISTS (
          SELECT 1 FROM membership_requests
          WHERE id = ? AND status NOT IN ('accepted', 'closed')
      )
    `).bind(
      offerId, requestId, requestId, input.amountMinor, input.currency, input.termMonths,
      input.paymentArrangement, input.renewalTerms, JSON.stringify(uniqueFeatures),
      input.additionalConditions ?? null, expiresAt, req.auth?.sub ?? 'unknown',
      createdAt, requestId,
    ),
    db.prepare(`
      UPDATE membership_requests
      SET status = 'offer_ready', updated_at = ?
      WHERE id = ? AND status NOT IN ('accepted', 'closed') AND changes() = 1
    `).bind(createdAt, requestId),
    prepareAdminAudit({
      adminId: req.auth?.sub ?? 'unknown',
      action: 'membership_offer_created',
      targetType: 'membership_request',
      targetId: requestId,
      tenantId: request.tenantId,
      onlyAfterSuccessfulWrite: true,
    }, db),
  ]);
  if ((results[1]?.meta.changes ?? 0) !== 1) {
    return res.status(409).json({ error: 'Membership request was closed before the offer could be saved' });
  }
  const offer = await prisma.membershipOffer.findUnique({ where: { id: offerId } });
  if (!offer) throw new Error('Membership offer was created but could not be reloaded');
  return res.status(201).json({ offer });
}));

router.post('/requests/:id/messages', asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(messageSchema, req.body);
  const requestId = String(req.params.id);
  const request = await prisma.membershipRequest.findUnique({
    where: { id: requestId },
    select: { id: true, tenantId: true, status: true },
  });
  if (!request) return res.status(404).json({ error: 'Membership request not found' });
  if (['accepted', 'closed'].includes(request.status)) {
    return res.status(409).json({ error: 'This membership discussion is closed' });
  }
  const messageId = randomUUID();
  const createdAt = new Date().toISOString();
  const db = getD1DatabaseBinding();
  const results = await db.batch([
    db.prepare(`
      INSERT INTO membership_messages (id, request_id, sender_type, sender_id, body, created_at)
      SELECT ?, ?, 'sales', ?, ?, ?
      WHERE EXISTS (
        SELECT 1 FROM membership_requests
        WHERE id = ? AND status NOT IN ('accepted', 'closed')
      )
    `).bind(messageId, requestId, req.auth?.sub ?? 'unknown', input.body, createdAt, requestId),
    db.prepare(`
      UPDATE membership_requests
      SET status = CASE WHEN status = 'offer_ready' THEN 'negotiating' ELSE status END,
          updated_at = ?
      WHERE id = ? AND status NOT IN ('accepted', 'closed') AND changes() = 1
    `).bind(createdAt, requestId),
    prepareAdminAudit({
      adminId: req.auth?.sub ?? 'unknown',
      action: 'membership_message_sent',
      targetType: 'membership_request',
      targetId: requestId,
      tenantId: request.tenantId,
      onlyAfterSuccessfulWrite: true,
    }, db),
  ]);
  if ((results[0]?.meta.changes ?? 0) !== 1) {
    return res.status(409).json({ error: 'This membership discussion is closed' });
  }
  return res.status(201).json({
    message: { id: messageId, requestId, senderType: 'sales', senderId: req.auth?.sub ?? 'unknown', body: input.body, createdAt },
  });
}));

export default router;
