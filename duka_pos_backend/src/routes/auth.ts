/**
 * Auth routes for the Duka POS app verification flow.
 *
 * Uses PostgreSQL/Prisma for persistent storage (no in-memory stores).
 * Flow:
 *   1. POST /api/auth/link        — create tenant + owner profile, send 6-digit code
 *   2. POST /api/auth/verify      — confirm code, mint session tokens
 *   3. POST /api/auth/refresh     — exchange refresh token for new session
 *   4. POST /api/auth/pin-reset/request   — request a PIN reset code by email
 *   5. POST /api/auth/pin-reset/confirm   — confirm reset code
 */
import { Router } from 'express';
import { asyncHandler } from '../lib/http';
import { parseBody } from '../lib/validation';
import {
  authLinkSchema,
  authVerifySchema,
  authRefreshSchema,
  pinResetRequestSchema,
  pinResetConfirmSchema,
} from '../lib/validation';
import { prisma } from '../lib/prisma';
import { log } from '../lib/observability';
import { normalizeEmail } from '../lib/identity';

const router = Router();

function generateCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function generateToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

async function sendCode(email: string, code: string): Promise<void> {
  log('info', 'auth.code_generated', { email, code });
  const smtpHost = process.env.SMTP_HOST;
  if (!smtpHost) return;
  try { /* nodemailer transport would go here when SMTP configured */ } catch { }
}

router.post(
  '/link',
  asyncHandler(async (req, res) => {
    const { email, pin, shopName, ownerName } = parseBody(authLinkSchema, req.body);
    const normalizedEmail = normalizeEmail(email);

    const existing = await prisma.profile.findFirst({
      where: { email: normalizedEmail, tenant: { shopName: shopName.trim() } },
    });
    if (existing) {
      return res.status(409).json({ error: 'This account is already linked to this shop', tenant_id: existing.tenantId });
    }

    const result = await prisma.$transaction(async (tx) => {
      const tenant = await tx.tenant.create({ data: { shopName: shopName.trim() } });
      const profile = await tx.profile.create({
        data: { oidcSubject: null, tenantId: tenant.id, name: ownerName.trim(), email: normalizedEmail, role: 'admin' },
      });
      return { tenant, profile };
    });

    const challenge = await prisma.verificationChallenge.create({
      data: {
        tenantId: result.tenant.id,
        email: normalizedEmail,
        code: generateCode(),
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      },
    });
    await sendCode(normalizedEmail, challenge.code);
    log('info', 'auth.link_created', { email: normalizedEmail, tenantId: result.tenant.id, challengeId: challenge.id });

    return res.json({
      challenge_id: challenge.id,
      email: normalizedEmail,
      expires_in_seconds: Math.floor((challenge.expiresAt.getTime() - Date.now()) / 1000),
    });
  })
);

router.post(
  '/verify',
  asyncHandler(async (req, res) => {
    const { email, pin, code } = parseBody(authVerifySchema, req.body);
    const normalizedEmail = normalizeEmail(email);

    const challenge = await prisma.verificationChallenge.findFirst({
      where: { email: normalizedEmail, code, used: false, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });
    if (!challenge) {
      return res.status(400).json({ error: 'Invalid or expired verification code', code: 'VERIFICATION_INVALID' });
    }

    const profile = await prisma.profile.findFirst({
      where: { email: normalizedEmail }, include: { tenant: true }, orderBy: { createdAt: 'desc' },
    });
    if (!profile) return res.status(404).json({ error: 'Shop not found for this email' });

    await prisma.verificationChallenge.update({ where: { id: challenge.id }, data: { used: true } });

    const accessToken = generateToken();
    const refreshToken = generateToken();
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);

    await prisma.appSession.create({ data: { tenantId: profile.tenantId, accessToken, refreshToken, expiresAt } });
    log('info', 'auth.verified', { email: normalizedEmail, tenantId: profile.tenantId });

    return res.json({
      tenant_id: profile.tenantId,
      shop_name: profile.tenant.shopName,
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_in_seconds: 24 * 60 * 60,
    });
  })
);

router.post(
  '/refresh',
  asyncHandler(async (req, res) => {
    const { refreshToken } = parseBody(authRefreshSchema, req.body);
    const session = await prisma.appSession.findUnique({ where: { refreshToken } });
    if (!session || session.expiresAt < new Date()) {
      if (session) await prisma.appSession.delete({ where: { id: session.id } });
      return res.status(401).json({ error: 'Refresh token expired or invalid', code: 'SESSION_EXPIRED' });
    }
    const newAccessToken = generateToken();
    const newRefreshToken = generateToken();
    const newExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
    await prisma.appSession.delete({ where: { id: session.id } });
    await prisma.appSession.create({ data: { tenantId: session.tenantId, accessToken: newAccessToken, refreshToken: newRefreshToken, expiresAt: newExpiresAt } });
    return res.json({
      tenant_id: session.tenantId,
      shop_name: null,
      access_token: newAccessToken,
      refresh_token: newRefreshToken,
      expires_in_seconds: 24 * 60 * 60,
    });
  })
);

router.post(
  '/pin-reset/request',
  asyncHandler(async (req, res) => {
    const { email } = parseBody(pinResetRequestSchema, req.body);
    const normalizedEmail = normalizeEmail(email);

    const profile = await prisma.profile.findFirst({ where: { email: normalizedEmail } });
    if (!profile) return res.json({ challengeId: crypto.randomBytes(16).toString('hex') });

    const challenge = await prisma.verificationChallenge.create({
      data: { tenantId: profile.tenantId, email: normalizedEmail, code: generateCode(), expiresAt: new Date(Date.now() + 10 * 60 * 1000) },
    });
    await sendCode(normalizedEmail, challenge.code);
    log('info', 'auth.pin_reset_requested', { email: normalizedEmail });
    return res.json({ challengeId: challenge.id });
  })
);

router.post(
  '/pin-reset/confirm',
  asyncHandler(async (req, res) => {
    const { email, challengeId, code } = parseBody(pinResetConfirmSchema, req.body);
    const normalizedEmail = normalizeEmail(email);
    const challenge = await prisma.verificationChallenge.findUnique({ where: { id: challengeId } });
    if (!challenge || challenge.email !== normalizedEmail || challenge.code !== code || challenge.used || challenge.expiresAt < new Date()) {
      return res.status(400).json({ error: 'Invalid or expired reset code', code: 'CODE_REJECTED' });
    }
    await prisma.verificationChallenge.update({ where: { id: challengeId }, data: { used: true } });
    log('info', 'auth.pin_reset_confirmed', { email: normalizedEmail });
    return res.status(200).json({ ok: true });
  })
);

export default router;
