import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, requireUser } from '../lib/http';
import { parseBody } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { COMMERCIAL_POLICY } from '../lib/commercial_policy';
import { COMMERCIAL_CONSENT_SCOPES } from '../lib/commercial_consent';

const router = Router();

const scopeSchema = z.enum(COMMERCIAL_CONSENT_SCOPES);
const grantSchema = z.object({
  scopes: z.array(scopeSchema).min(1).max(COMMERCIAL_CONSENT_SCOPES.length),
  noticeVersion: z.string().trim().min(1).max(80),
  noticeDigest: z.string().regex(/^sha256:[a-f0-9]{64}$/),
  termsVersion: z.string().trim().min(1).max(80).optional().nullable(),
  schemaVersion: z.string().trim().min(1).max(80),
  dictionaryVersion: z.string().trim().min(1).max(80),
  appVersion: z.string().trim().min(1).max(80),
  captureMethod: z.enum(['in_app_affirmative']),
  authorityEvidence: z.enum(['owner', 'authorized_representative']).optional().default('owner'),
}).strict();

router.get('/', asyncHandler(async (req, res) => {
  const user = requireUser(req);
  if (user.role !== 'admin') return res.status(403).json({ error: 'Shop owner or authorized representative required' });
  const grant = await prisma.commercialConsentGrant.findFirst({
    where: { tenantId: user.tenantId },
    orderBy: { effectiveAt: 'desc' },
  });
  return res.json({ collectionEnabled: COMMERCIAL_POLICY.collectionEnabled, grant });
}));

router.put('/', asyncHandler(async (req, res) => {
  const user = requireUser(req);
  if (user.role !== 'admin') return res.status(403).json({ error: 'Shop owner or authorized representative required' });
  const input = parseBody(grantSchema, req.body);
  const scopes = [...new Set(input.scopes)].sort();
  const grant = await prisma.commercialConsentGrant.create({
    data: {
      tenantId: user.tenantId,
      actorId: user.id,
      actorRole: user.role,
      status: 'active',
      scopes,
      noticeVersion: input.noticeVersion,
      noticeDigest: input.noticeDigest,
      termsVersion: input.termsVersion ?? null,
      schemaVersion: input.schemaVersion,
      dictionaryVersion: input.dictionaryVersion,
      appVersion: input.appVersion,
      captureMethod: input.captureMethod,
      authorityEvidence: input.authorityEvidence,
      effectiveAt: new Date(),
    },
  });
  return res.status(201).json({ collectionEnabled: COMMERCIAL_POLICY.collectionEnabled, grant });
}));

router.post('/withdraw', asyncHandler(async (req, res) => {
  const user = requireUser(req);
  if (user.role !== 'admin') return res.status(403).json({ error: 'Shop owner or authorized representative required' });
  const active = await prisma.commercialConsentGrant.findMany({
    where: { tenantId: user.tenantId, status: 'active' },
  });
  if (active.length === 0) return res.json({ collectionEnabled: COMMERCIAL_POLICY.collectionEnabled, withdrawn: 0 });
  const now = new Date();
  await prisma.commercialConsentGrant.updateMany({
    where: { tenantId: user.tenantId, status: 'active' },
    data: { status: 'withdrawn', withdrawnAt: now, processingState: 'purge_queued_unsubmitted' },
  });
  await prisma.adminAuditLog.create({
    data: {
      adminId: 'merchant-withdrawal',
      action: 'withdraw_commercial_consent',
      targetType: 'commercial_consent_grant',
      targetId: active.map((grant) => grant.id).join(','),
      tenantId: user.tenantId,
    },
  }).catch(() => undefined);
  return res.json({ collectionEnabled: COMMERCIAL_POLICY.collectionEnabled, withdrawn: active.length });
}));

export default router;
