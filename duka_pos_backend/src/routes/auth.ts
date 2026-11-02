/**
 * Custom identity/auth routes.
 */
import { Router, Request, Response } from 'express';
import rateLimit from 'express-rate-limit';
import { randomBytes } from 'node:crypto';
import { prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import {
  authLinkSchema,
  authVerifySchema,
  authLoginSchema,
  authRefreshSchema,
  authForgotPasswordSchema,
  authResetPasswordSchema,
  authChangePasswordSchema,
  parseBody,
} from '../lib/validation';
import { log } from '../lib/observability';
import {
  CODE_REQUEST_WINDOW_MINUTES,
  MAX_CODES_PER_WINDOW,
  VERIFICATION_TTL_MINUTES,
  codeRequestWindowStart,
  generateVerificationCode,
  hashCodeSecret,
  hashesMatch,
  isVerificationExpired,
  maskEmail,
  newSalt,
} from '../lib/verification';
import { hashPassword, verifyPassword } from '../lib/password';
import { issueAccessToken } from '../lib/jwt';
import { authMiddleware } from '../middleware/auth';
import { createCloudflareEmailTransport } from '../lib/email_sender';

const router = Router();

const REFRESH_TOKEN_TTL_MS = 180 * 24 * 60 * 60 * 1000;
const GRACE_WINDOW_MS = 10 * 1000;

function verificationSecret(): string {
  return process.env.EMAIL_VERIFICATION_SECRET ?? '';
}

function isConfigured(): boolean {
  return Boolean(verificationSecret() && process.env.AUTH_JWT_SECRET);
}

function mailerConfigured(): boolean {
  return Boolean(process.env.CLOUDFLARE_ACCOUNT_ID && process.env.CLOUDFLARE_API_TOKEN);
}

function notConfigured(res: Response, requestId?: string) {
  return res.status(503).json({ error: 'Online account verification is not configured on this server', code: 'VERIFICATION_NOT_CONFIGURED', requestId });
}

function addressKey(req: Request): string {
  const body = req.body as { email?: unknown };
  const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
  return `${req.ip ?? 'unknown'}:${email}`;
}

const _isNode = typeof module !== 'undefined';
const _noop = (_req: any, _res: any, next: any) => next();
const linkLimiter = _isNode ? rateLimit({ windowMs: CODE_REQUEST_WINDOW_MINUTES * 60_000, limit: MAX_CODES_PER_WINDOW, standardHeaders: 'draft-7', legacyHeaders: false, keyGenerator: addressKey, validate: { keyGeneratorIpFallback: false } }) : _noop;
const verifyLimiter = _isNode ? rateLimit({ windowMs: 10 * 60_000, limit: 20, standardHeaders: 'draft-7', legacyHeaders: false, keyGenerator: addressKey, validate: { keyGeneratorIpFallback: false } }) : _noop;
const loginLimiter = _isNode ? rateLimit({ windowMs: 10 * 60_000, limit: 20, standardHeaders: 'draft-7', legacyHeaders: false, keyGenerator: addressKey, validate: { keyGeneratorIpFallback: false } }) : _noop;
const refreshLimiter = _isNode ? rateLimit({ windowMs: 10 * 60_000, limit: 20, standardHeaders: 'draft-7', legacyHeaders: false, keyGenerator: addressKey, validate: { keyGeneratorIpFallback: false } }) : _noop;

function buildMailer() {
  return createCloudflareEmailTransport({
    accountId: process.env.CLOUDFLARE_ACCOUNT_ID ?? '',
    apiToken: process.env.CLOUDFLARE_API_TOKEN ?? '',
    from: process.env.CLOUDFLARE_EMAIL_FROM ?? 'security@nerva.co.ke',
    appName: process.env.APP_NAME ?? 'SimpleSales',
  });
}

function hashRefreshToken(token: string): string {
  return hashCodeSecret(token, 'app-session-refresh', verificationSecret());
}

async function ensureOwnerProfile(input: { userId: string; email: string; shopName?: string; ownerName?: string }, options: { allowCreate: boolean }) {
  // 1. exact account + shop name
  if (input.shopName?.trim()) {
    const exact = await prisma.profile.findFirst({
      where: { userId: input.userId, tenant: { shopName: input.shopName.trim() }, active: true, deletedAt: null },
      include: { tenant: true },
    });
    if (exact) return { tenantId: exact.tenantId, shopName: exact.tenant.shopName, profileId: exact.id, created: false };
  }
  // 2. any owned shop
  const owned = await prisma.profile.findFirst({
    where: { userId: input.userId, active: true, deletedAt: null },
    include: { tenant: true },
    orderBy: { createdAt: 'asc' },
  });
  if (owned) return { tenantId: owned.tenantId, shopName: owned.tenant.shopName, profileId: owned.id, created: false };

  // 3. unclaimed profile by email
  const unclaimed = await prisma.profile.findFirst({
    where: { email: input.email, userId: null, active: true, deletedAt: null },
    include: { tenant: true },
  });
  if (unclaimed) {
    const adopted = await prisma.profile.update({ where: { id: unclaimed.id }, data: { userId: input.userId, email: input.email } });
    return { tenantId: unclaimed.tenantId, shopName: unclaimed.tenant.shopName, profileId: adopted.id, created: false };
  }

  if (!options.allowCreate || !input.shopName?.trim() || !input.ownerName?.trim()) return null;

  const created = await prisma.$transaction(async (tx) => {
    const tenant = await tx.tenant.create({ data: { shopName: input.shopName!.trim() } });
    const profile = await tx.profile.create({
      data: { userId: input.userId, tenantId: tenant.id, name: input.ownerName!.trim(), email: input.email, role: 'admin' },
    });
    return { tenant, profile };
  });
  return { tenantId: created.tenant.id, shopName: created.tenant.shopName, profileId: created.profile.id, created: true };
}

async function issueRefreshToken(profileId: string, tier: 'device' | 'access') {
  const token = randomBytes(32).toString('base64url');
  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_MS);
  await prisma.profile.update({
    where: { id: profileId },
    data: {
      refreshTokenHash: hashRefreshToken(token),
      refreshTokenPreviousHash: null,
      refreshTokenExpiresAt: expiresAt,
      refreshTokenTier: tier,
    },
  });
  return { token, expiresAt };
}

async function rotateRefreshToken(profile: any, tier: string) {
  const newToken = randomBytes(32).toString('base64url');
  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_MS);
  const currentHash = profile.refreshTokenHash;
  await prisma.profile.update({
    where: { id: profile.id },
    data: {
      refreshTokenPreviousHash: currentHash,
      refreshTokenHash: hashRefreshToken(newToken),
      refreshTokenExpiresAt: expiresAt,
      refreshTokenTier: tier,
      refreshTokenRotatedAt: new Date(),
    },
  });
  return { token: newToken, expiresAt };
}

// POST /auth/link
router.post('/link', linkLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { email, password, shopName } = parseBody(authLinkSchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const secret = verificationSecret();
  // rate limit per mailbox
  const recent = await prisma.verificationChallenge.count({
    where: { email, createdAt: { gte: codeRequestWindowStart(new Date()) } },
  });
  if (recent >= MAX_CODES_PER_WINDOW) {
    return res.status(429).json({ error: `Too many codes requested. Wait ${CODE_REQUEST_WINDOW_MINUTES} minutes.`, code: 'TOO_MANY_CODES', requestId });
  }

  // upsert user (unverified) with passwordHash
  let user: any = await prisma.user.findUnique({ where: { email } });
  if (!user || !user.emailVerifiedAt) {
    const passwordHash = await hashPassword(password);
    if (user) {
      await prisma.user.update({ where: { id: user.id }, data: { passwordHash } });
    } else {
      user = await prisma.user.create({ data: { email, passwordHash } });
    }
  }

  // invalidate outstanding codes
  await prisma.verificationChallenge.updateMany({ where: { email, used: false }, data: { used: true } });

  const code = generateVerificationCode();
  const salt = newSalt();
  const challenge = await prisma.verificationChallenge.create({
    data: {
      email,
      code: hashCodeSecret(code, salt, secret), // storing hash in code field (reuse)
      expiresAt: new Date(Date.now() + VERIFICATION_TTL_MINUTES * 60_000),
      tenantId: null,
    },
  });
  // store salt+pinHash in? VerificationChallenge lacks salt/pinHash. Store combined in code? We'll store salt in code? 
  // For simplicity store salt.pinHash via code field? Need salt for hashing. We'll store `${salt}:${codeHash}:${pinHash}`.
  await prisma.verificationChallenge.update({
    where: { id: challenge.id },
    data: { code: `${salt}:${hashCodeSecret(code, salt, secret)}:${hashCodeSecret(password, salt, secret)}` },
  });

  // email
  if (mailerConfigured()) {
    try {
      const mailer = buildMailer();
      await mailer.send({ to: email, code, shopName, ttlMinutes: VERIFICATION_TTL_MINUTES });
    } catch {
      await prisma.verificationChallenge.update({ where: { id: challenge.id }, data: { used: true } });
      return res.status(502).json({ error: 'Email could not be sent', code: 'EMAIL_UNAVAILABLE', requestId });
    }
  }

  log('info', 'auth.code_sent', { requestId, email: maskEmail(email) });
  res.json({
    status: 'code_sent',
    challenge_id: challenge.id,
    email: maskEmail(email),
    expires_in_seconds: VERIFICATION_TTL_MINUTES * 60,
    ...(process.env.NODE_ENV !== 'production' && process.env.VERIFICATION_DEBUG_CODES === 'true' ? { debug_code: code } : {}),
  });
}));

// POST /auth/verify
router.post('/verify', verifyLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { email, password, code, shopName, ownerName } = parseBody(authVerifySchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const secret = verificationSecret();
  const now = new Date();
  const challenge = await prisma.verificationChallenge.findFirst({ where: { email, used: false }, orderBy: { createdAt: 'desc' } });
  if (!challenge) return res.status(400).json({ error: 'Code expired', code: 'VERIFICATION_EXPIRED', requestId });
  if (isVerificationExpired(challenge.expiresAt, now)) {
    await prisma.verificationChallenge.update({ where: { id: challenge.id }, data: { used: true } });
    return res.status(400).json({ error: 'Code expired', code: 'VERIFICATION_EXPIRED', requestId });
  }

  const parts = (challenge.code || '').split(':');
  if (parts.length !== 3) return res.status(400).json({ error: 'Invalid challenge', code: 'VERIFICATION_INVALID', requestId });
  const [salt, codeHash, pinHash] = parts;
  const codeCorrect = hashesMatch(hashCodeSecret(code, salt, secret), codeHash);
  const pinCorrect = hashesMatch(hashCodeSecret(password, salt, secret), pinHash);
  if (!codeCorrect || !pinCorrect) {
    return res.status(400).json({ error: 'Code is not right', code: 'VERIFICATION_INVALID', requestId });
  }

  await prisma.verificationChallenge.updateMany({ where: { email, used: false }, data: { used: true } });

  // set user verified
  let user: any = await prisma.user.findUnique({ where: { email } });
  if (!user) {
    const passwordHash = await hashPassword(password);
    user = await prisma.user.create({ data: { email, passwordHash, emailVerifiedAt: now } });
  } else {
    const passwordHash = await hashPassword(password);
    await prisma.user.update({ where: { id: user.id }, data: { passwordHash, emailVerifiedAt: now } });
    user = await prisma.user.findUnique({ where: { email } })!;
  }

  const shop = await ensureOwnerProfile({ userId: user.id, email, shopName, ownerName }, { allowCreate: true });
  if (!shop) {
    return res.status(400).json({ error: 'Shop setup required', code: 'SHOP_SETUP_REQUIRED', requestId });
  }

  const tier = 'device';
  const access = issueAccessToken({ userId: user.id, email, emailVerified: true, tier });
  const refresh = await issueRefreshToken(shop.profileId, tier);

  res.json({
    status: 'verified',
    tenant_id: shop.tenantId,
    shop_name: shop.shopName,
    role: 'admin',
    access_token: access.token,
    refresh_token: refresh.token,
    expires_in_seconds: access.expiresIn,
    refresh_expires_in_seconds: REFRESH_TOKEN_TTL_MS / 1000,
  });
}));

// POST /auth/login
router.post('/login', loginLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { email, password } = parseBody(authLoginSchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const user = await prisma.user.findUnique({ where: { email } });
  const dummyHash = '$2a$12$' + 'a'.repeat(53);
  const hashToCheck = user?.passwordHash ?? dummyHash;
  const ok = await verifyPassword(password, hashToCheck);

  if (!user || !user.emailVerifiedAt) {
    // unknown or unverified
    if (user) {
      await prisma.user.update({ where: { id: user.id }, data: { failedLoginAttempts: { increment: 1 } } });
    }
    return res.status(401).json({ error: 'Invalid credentials', code: 'INVALID_CREDENTIALS', requestId });
  }

  // lockout check
  if (user.lockedUntil && user.lockedUntil > new Date()) {
    return res.status(429).json({ error: 'Account locked', code: 'ACCOUNT_LOCKED', requestId });
  }

  if (!ok) {
    const attempts = user.failedLoginAttempts + 1;
    let lockedUntil: Date | null = null;
    if (attempts >= 5) {
      const lockMs = Math.min(30 * 60 * 1000, 30 * 1000 * Math.pow(2, attempts - 5));
      lockedUntil = new Date(Date.now() + lockMs);
    }
    await prisma.user.update({ where: { id: user.id }, data: { failedLoginAttempts: attempts, lockedUntil } });
    return res.status(401).json({ error: 'Invalid credentials', code: 'INVALID_CREDENTIALS', requestId });
  }

  // success: reset counters
  await prisma.user.update({ where: { id: user.id }, data: { failedLoginAttempts: 0, lockedUntil: null } });

  const profiles = await prisma.profile.findMany({ where: { userId: user.id, active: true, deletedAt: null }, include: { tenant: true } });
  if (profiles.length === 0) {
    return res.status(403).json({ error: 'No shop linked', code: 'NO_SHOP_LINKED', requestId });
  }

  const tier = 'access';
  // issue token per first profile? We issue one full token; tenant selection via x-tenant-id.
  const access = issueAccessToken({ userId: user.id, email, emailVerified: true, tier });
  // store refresh on first admin/manager profile? Plan: one refresh per profile. For login, use first profile.
  const primaryProfile = profiles[0];
  const refresh = await issueRefreshToken(primaryProfile.id, tier);

  res.json({
    status: 'logged_in',
    access_token: access.token,
    refresh_token: refresh.token,
    expires_in_seconds: access.expiresIn,
    refresh_expires_in_seconds: REFRESH_TOKEN_TTL_MS / 1000,
    tenants: profiles.map((p) => ({ id: p.tenantId, shopName: p.tenant.shopName, role: p.role })),
  });
}));

// POST /auth/refresh
router.post('/refresh', refreshLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { refreshToken } = parseBody(authRefreshSchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const now = new Date();
  const hash = hashRefreshToken(refreshToken);
  // find manually
  const allProfiles = await prisma.profile.findMany({ where: { active: true, deletedAt: null } });
  const matched = allProfiles.find((p) => p.refreshTokenHash === hash || p.refreshTokenPreviousHash === hash);
  if (!matched) {
    return res.status(401).json({ error: 'Invalid refresh token', code: 'INVALID_REFRESH_TOKEN', requestId });
  }
  const p = matched;
  if (!p.refreshTokenExpiresAt || p.refreshTokenExpiresAt <= now) {
    return res.status(401).json({ error: 'Session expired', code: 'SESSION_EXPIRED', requestId });
  }

  const tier = (p.refreshTokenTier === 'device' ? 'device' : 'access') as 'device' | 'access';

  // grace window for previous hash
  if (p.refreshTokenPreviousHash === hash && p.refreshTokenHash !== hash) {
    const rotatedAt = p.refreshTokenRotatedAt ?? p.refreshTokenExpiresAt;
    const age = now.getTime() - new Date(rotatedAt).getTime();
    if (age <= GRACE_WINDOW_MS) {
      // return current token? We need to re-issue access token but keep refresh. Issue new access token only.
      const user = await prisma.user.findUnique({ where: { id: p.userId! } });
      const access = issueAccessToken({ userId: p.userId!, email: user?.email ?? '', emailVerified: !!user?.emailVerifiedAt, tier });
      return res.json({
        status: 'refreshed',
        access_token: access.token,
        refresh_token: refreshToken,
        expires_in_seconds: access.expiresIn,
        refresh_expires_in_seconds: REFRESH_TOKEN_TTL_MS / 1000,
      });
    }
    // reuse detected
    await prisma.profile.update({ where: { id: p.id }, data: { refreshTokenHash: null, refreshTokenPreviousHash: null } });
    return res.status(401).json({ error: 'Refresh reuse detected', code: 'REFRESH_REUSE_DETECTED', requestId });
  }

  // matches current: rotate
  const refresh = await rotateRefreshToken(p, tier);
  const user = await prisma.user.findUnique({ where: { id: p.userId! } });
  const access = issueAccessToken({ userId: p.userId!, email: user?.email ?? '', emailVerified: !!user?.emailVerifiedAt, tier });
  res.json({
    status: 'refreshed',
    access_token: access.token,
    refresh_token: refresh.token,
    expires_in_seconds: access.expiresIn,
    refresh_expires_in_seconds: REFRESH_TOKEN_TTL_MS / 1000,
  });
}));

// POST /auth/forgot-password
router.post('/forgot-password', loginLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { email } = parseBody(authForgotPasswordSchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const user = await prisma.user.findUnique({ where: { email } });
  if (user) {
    // generate code, store EmailVerification? use VerificationChallenge
    const code = generateVerificationCode();
    const salt = newSalt();
    const secret = verificationSecret();
    await prisma.verificationChallenge.updateMany({ where: { email, used: false }, data: { used: true } });
    await prisma.verificationChallenge.create({
      data: {
        email,
        code: `${salt}:${hashCodeSecret(code, salt, secret)}:${hashCodeSecret('reset', salt, secret)}`,
        expiresAt: new Date(Date.now() + VERIFICATION_TTL_MINUTES * 60_000),
      },
    });
    if (mailerConfigured()) {
      try {
        const mailer = buildMailer();
        await mailer.send({ to: email, code, ttlMinutes: VERIFICATION_TTL_MINUTES });
      } catch {
        // ignore
      }
    }
  }
  res.json({ status: 'code_sent' });
}));

// POST /auth/reset-password
router.post('/reset-password', loginLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { email, code, newPassword } = parseBody(authResetPasswordSchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const secret = verificationSecret();
  const challenge = await prisma.verificationChallenge.findFirst({ where: { email, used: false }, orderBy: { createdAt: 'desc' } });
  if (!challenge) return res.status(400).json({ error: 'Invalid code', code: 'VERIFICATION_INVALID', requestId });
  const parts = (challenge.code || '').split(':');
  if (parts.length !== 3) return res.status(400).json({ error: 'Invalid code', code: 'VERIFICATION_INVALID', requestId });
  const [salt, codeHash] = parts;
  const now = new Date();
  if (isVerificationExpired(challenge.expiresAt, now)) {
    await prisma.verificationChallenge.update({ where: { id: challenge.id }, data: { used: true } });
    return res.status(400).json({ error: 'Code expired', code: 'VERIFICATION_EXPIRED', requestId });
  }
  if (!hashesMatch(hashCodeSecret(code, salt, secret), codeHash)) {
    return res.status(400).json({ error: 'Invalid code', code: 'VERIFICATION_INVALID', requestId });
  }
  await prisma.verificationChallenge.updateMany({ where: { email, used: false }, data: { used: true } });

  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) return res.status(400).json({ error: 'Invalid', code: 'VERIFICATION_INVALID', requestId });

  const passwordHash = await hashPassword(newPassword);
  await prisma.user.update({ where: { id: user.id }, data: { passwordHash, emailVerifiedAt: user.emailVerifiedAt ?? now } });

  // clear refresh hashes on all profiles
  await prisma.profile.updateMany({ where: { userId: user.id }, data: { refreshTokenHash: null, refreshTokenPreviousHash: null } });

  res.json({ status: 'password_reset' });
}));

// POST /auth/change-password (authenticated)
router.post('/change-password', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { currentPassword, newPassword } = parseBody(authChangePasswordSchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const userId = req.auth?.sub;
  if (!userId) return res.status(401).json({ error: 'Unauthorized', requestId });

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) return res.status(401).json({ error: 'Unauthorized', requestId });

  const ok = await verifyPassword(currentPassword, user.passwordHash);
  if (!ok) return res.status(401).json({ error: 'Invalid current password', code: 'INVALID_CREDENTIALS', requestId });

  const passwordHash = await hashPassword(newPassword);
  await prisma.user.update({ where: { id: userId }, data: { passwordHash } });
  await prisma.profile.updateMany({ where: { userId }, data: { refreshTokenHash: null, refreshTokenPreviousHash: null } });

  res.json({ status: 'password_changed' });
}));

// POST /auth/logout
router.post('/logout', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const userId = req.auth?.sub;
  const { refreshToken, all } = req.body ?? {};
  if (!userId) return res.status(401).json({ error: 'Unauthorized', requestId });

  if (all) {
    await prisma.profile.updateMany({ where: { userId }, data: { refreshTokenHash: null, refreshTokenPreviousHash: null } });
  } else if (refreshToken) {
    const hash = hashRefreshToken(refreshToken);
    await prisma.profile.updateMany({ where: { userId, refreshTokenHash: hash }, data: { refreshTokenHash: null, refreshTokenPreviousHash: null } });
  } else {
    await prisma.profile.updateMany({ where: { userId }, data: { refreshTokenHash: null, refreshTokenPreviousHash: null } });
  }
  res.json({ status: 'logged_out' });
}));

// GET /auth/me
router.get('/me', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const userId = req.auth?.sub;
  if (!userId) return res.status(401).json({ error: 'Unauthorized', requestId });
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) return res.status(401).json({ error: 'Unauthorized', requestId });
  const profiles = await prisma.profile.findMany({ where: { userId, active: true, deletedAt: null }, include: { tenant: true } });
  res.json({
    userId: user.id,
    email: user.email,
    emailVerified: !!user.emailVerifiedAt,
    tenants: profiles.map((p) => ({ id: p.tenantId, shopName: p.tenant.shopName, role: p.role })),
  });
}));

export default router;
