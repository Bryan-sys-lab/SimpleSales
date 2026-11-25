/**
 * Custom identity/auth routes.
 */
import { Router, Request, Response } from 'express';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { simpleRateLimit } from '../lib/simple_rate_limit';
import { prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import {
  authLinkSchema,
  authVerifyCodeSchema,
  authVerifySchema,
  authLoginSchema,
  authRefreshSchema,
  authForgotPasswordSchema,
  authResetPasswordSchema,
  authChangePasswordSchema,
  pinResetRequestSchema,
  pinResetConfirmSchema,
  voucherRedeemSchema,
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
import { readableTenantId } from '../lib/tenant_id';
import { hashVoucher, tenantEntitlement } from '../lib/entitlements';
import { redeemVoucherAtomically } from '../lib/voucher_redemption';

const router = Router();

const REFRESH_TOKEN_TTL_MS = 180 * 24 * 60 * 60 * 1000;
const GRACE_WINDOW_MS = 10 * 1000;

function verificationSecret(): string {
  return process.env.EMAIL_VERIFICATION_SECRET ?? '';
}

function isConfigured(): boolean {
  return Boolean(verificationSecret() && process.env.AUTH_JWT_SECRET);
}

function notConfigured(res: Response, requestId?: string) {
  return res.status(503).json({ error: 'Online account verification is not configured on this server', code: 'VERIFICATION_NOT_CONFIGURED', requestId });
}

function addressKey(req: Request): string {
  const body = req.body as { email?: unknown };
  const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
  return `${req.ip ?? 'unknown'}:${email}`;
}

const linkLimiter = simpleRateLimit('auth:link', { windowMs: CODE_REQUEST_WINDOW_MINUTES * 60_000, limit: MAX_CODES_PER_WINDOW, standardHeaders: 'draft-7', legacyHeaders: false, keyGenerator: addressKey });
const verifyLimiter = simpleRateLimit('auth:verify', { windowMs: 10 * 60_000, limit: 20, standardHeaders: 'draft-7', legacyHeaders: false, keyGenerator: addressKey });
const loginLimiter = simpleRateLimit('auth:login', { windowMs: 10 * 60_000, limit: 20, standardHeaders: 'draft-7', legacyHeaders: false, keyGenerator: addressKey });
const refreshLimiter = simpleRateLimit('auth:refresh', { windowMs: 10 * 60_000, limit: 20, standardHeaders: 'draft-7', legacyHeaders: false, keyGenerator: addressKey });
const pinResetLimiter = simpleRateLimit('auth:pin-reset', { windowMs: CODE_REQUEST_WINDOW_MINUTES * 60_000, limit: MAX_CODES_PER_WINDOW, standardHeaders: 'draft-7', legacyHeaders: false, keyGenerator: addressKey });

function buildMailer() {
  return createCloudflareEmailTransport({
    accountId: process.env.CLOUDFLARE_ACCOUNT_ID ?? '',
    apiToken: process.env.CLOUDFLARE_API_TOKEN ?? '',
    from: process.env.CLOUDFLARE_EMAIL_FROM ?? 'security@nerva.co.ke',
    appName: process.env.APP_NAME ?? 'SimpleSales',
  });
}

function debugCodesEnabled(req: Request): boolean {
  if (process.env.VERIFICATION_DEBUG_CODES !== 'true') return false;
  if (process.env.NODE_ENV === 'test') return true;
  const publicUrl = process.env.PUBLIC_API_URL ?? '';
  if (!/^https:\/\/[^/]*staging[^/]*/i.test(publicUrl)) return false;
  const expectedSecret = process.env.STAGING_AUTH_TEST_SECRET;
  const suppliedSecret = req.get('x-staging-auth-test-secret') ?? '';
  if (!expectedSecret || !suppliedSecret) return false;
  const expected = Buffer.from(expectedSecret, 'utf8');
  const supplied = Buffer.from(suppliedSecret, 'utf8');
  return expected.length === supplied.length && timingSafeEqual(expected, supplied);
}

function createVerificationCode(): string {
  const testCode = process.env.AUTH_TEST_CODE;
  if (process.env.NODE_ENV === 'test' && testCode && /^\d{6}$/.test(testCode)) {
    return testCode;
  }
  return generateVerificationCode();
}

function mailerConfigured(): boolean {
  return buildMailer().configured;
}

function hashRefreshToken(token: string): string {
  return hashCodeSecret(token, 'app-session-refresh', verificationSecret());
}

type VerificationCodeCheck =
  | { valid: true }
  | { valid: false; error: string; code: string };

async function checkVerificationCode(input: {
  email: string;
  password: string;
  code: string;
  now: Date;
}): Promise<VerificationCodeCheck> {
  const challenge = await prisma.verificationChallenge.findFirst({
    where: { email: input.email, used: false },
    orderBy: { createdAt: 'desc' },
  });
  if (!challenge) return { valid: false, error: 'Code expired', code: 'VERIFICATION_EXPIRED' };
  if (isVerificationExpired(challenge.expiresAt, input.now)) {
    await prisma.verificationChallenge.update({
      where: { id: challenge.id },
      data: { used: true },
    });
    return { valid: false, error: 'Code expired', code: 'VERIFICATION_EXPIRED' };
  }

  const parts = (challenge.code || '').split(':');
  // V2: salt:codeHash (password verified against User.passwordHash, not stored in challenge)
  // Legacy: salt:codeHash:passwordHmac
  if (parts.length < 2 || parts.length > 3) {
    return { valid: false, error: 'Invalid challenge', code: 'VERIFICATION_INVALID' };
  }
  const [salt, codeHash] = parts;
  const codeCorrect = hashesMatch(
    hashCodeSecret(input.code, salt, verificationSecret()),
    codeHash,
  );
  if (!codeCorrect) {
    return { valid: false, error: 'Code is not right', code: 'VERIFICATION_INVALID' };
  }

  const user = await prisma.user.findUnique({ where: { email: input.email } });
  const passwordHash = user?.passwordHash;
  const pinCorrect = typeof passwordHash === 'string' && passwordHash.length > 0
    ? await verifyPassword(input.password, passwordHash)
    : false;
  if (!pinCorrect) {
    return { valid: false, error: 'Code is not right', code: 'VERIFICATION_INVALID' };
  }
  return { valid: true };
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

  const tenant = await prisma.tenant.create({
    data: {
      id: readableTenantId(input.ownerName!, input.shopName!),
      shopName: input.shopName!.trim(),
    },
  });
  try {
    await prisma.tenantSubscription.create({
      data: { tenantId: tenant.id, status: 'pending' },
    });
  } catch (error) {
    console.error('tenant_subscription_create_failed', error);
  }
  const profile = await prisma.profile.create({
    data: { userId: input.userId, tenantId: tenant.id, name: input.ownerName!.trim(), email: input.email, role: 'admin' },
  });
  const created = { tenant, profile };
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
  const mailer = buildMailer();
  const debugWithoutEmail = debugCodesEnabled(req);
  if (!mailer.configured && !debugCodesEnabled(req)) {
    return res.status(503).json({ error: 'Email verification is not configured on this server', code: 'EMAIL_NOT_CONFIGURED', requestId });
  }

  const secret = verificationSecret();
  // rate limit per mailbox
  const recent = await prisma.verificationChallenge.count({
    where: { email, createdAt: { gte: codeRequestWindowStart(new Date()) } },
  });
  if (recent >= MAX_CODES_PER_WINDOW) {
    return res.status(429).json({ error: `Too many codes requested. Wait ${CODE_REQUEST_WINDOW_MINUTES} minutes.`, code: 'TOO_MANY_CODES', requestId });
  }

  // upsert user (unverified) with passwordHash
  const user: any = await prisma.user.findUnique({ where: { email } });
  if (!user || !user.emailVerifiedAt) {
    const passwordHash = await hashPassword(password);
    if (user) {
      await prisma.user.update({ where: { id: user.id }, data: { passwordHash } });
    } else {
      await prisma.user.create({ data: { email, passwordHash } });
    }
  }

  // invalidate outstanding codes
  await prisma.verificationChallenge.updateMany({ where: { email, used: false }, data: { used: true } });

  const code = createVerificationCode();
  const salt = newSalt();
  const challenge = await prisma.verificationChallenge.create({
    data: {
      email,
      // V2: store only salt:codeHash. Password is verified against User.passwordHash.
      code: `${salt}:${hashCodeSecret(code, salt, secret)}`,
      expiresAt: new Date(Date.now() + VERIFICATION_TTL_MINUTES * 60_000),
      tenantId: null,
    },
  });

  // email
  if (!debugWithoutEmail) {
    try {
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
    ...(debugCodesEnabled(req) ? {
      debug_code: code,
    } : {}),
  });
}));

// POST /auth/verify-code
// Confirms the email code before showing the voucher paywall. It deliberately
// leaves the challenge unused; /verify rechecks it when the voucher is submitted.
router.post('/verify-code', verifyLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { email, password, code } = parseBody(authVerifyCodeSchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const check = await checkVerificationCode({ email, password, code, now: new Date() });
  if (!check.valid) {
    return res.status(400).json({ error: check.error, code: check.code, requestId });
  }
  return res.json({ status: 'code_verified' });
}));

// POST /auth/verify
router.post('/verify', verifyLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { email, password, code, voucherCode, claimVoucher, shopName, ownerName } = parseBody(authVerifySchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const now = new Date();
  const check = await checkVerificationCode({ email, password, code, now });
  if (!check.valid) {
    return res.status(400).json({ error: check.error, code: check.code, requestId });
  }

  const accessVoucherModel = (prisma as typeof prisma & { accessVoucher?: typeof prisma.accessVoucher }).accessVoucher;
  let voucher: Awaited<ReturnType<typeof prisma.accessVoucher.findUnique>> = null;
  if (voucherCode && accessVoucherModel) {
    voucher = await accessVoucherModel.findUnique({
      where: { codeHash: hashVoucher(voucherCode) },
    });
  } else if (claimVoucher && accessVoucherModel) {
    voucher = await accessVoucherModel.findFirst({
      where: {
        issuedToEmail: email,
        redeemedAt: null,
        revokedAt: null,
        pausedAt: null,
        deletedAt: null,
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
      orderBy: { createdAt: 'desc' },
    });
  }
  if ((voucherCode || claimVoucher) &&
      (!voucher || voucher.revokedAt || voucher.pausedAt || voucher.deletedAt ||
        voucher.redeemedAt || (voucher.expiresAt && voucher.expiresAt <= now) ||
        (voucher.issuedToEmail && voucher.issuedToEmail !== email))) {
    return res.status(400).json({
      error: claimVoucher
        ? 'No active access voucher is assigned to this account yet'
        : 'Voucher code is invalid or does not belong to this account',
      code: claimVoucher ? 'VOUCHER_UNAVAILABLE' : 'VOUCHER_INVALID',
      requestId,
    });
  }

  await prisma.verificationChallenge.updateMany({ where: { email, used: false }, data: { used: true } });

  // set user verified
  let user: any = await prisma.user.findUnique({ where: { email }, include: { profiles: true } });
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

  if (voucher) {
    if ((voucher.tenantId && voucher.tenantId !== shop.tenantId) ||
        (voucher.issuedToProfileId && voucher.issuedToProfileId !== shop.profileId)) {
      return res.status(403).json({
        error: 'Voucher is assigned to another shop or profile',
        code: 'VOUCHER_PROFILE_MISMATCH',
        requestId,
      });
    }
    const redeemed = await redeemVoucherAtomically({
      voucherId: voucher.id,
      tenantId: shop.tenantId,
      profileId: shop.profileId,
      email,
      now,
      durationMonths: voucher.durationMonths,
      voucherType: voucher.voucherType === 'discount' ? 'discount' : 'access',
    });
    if (!redeemed) {
      return res.status(409).json({
        error: 'Voucher could not be redeemed',
        code: 'VOUCHER_REDEEM_FAILED',
        requestId,
      });
    }
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
    voucher_redeemed: Boolean(voucher && voucher.voucherType !== 'discount'),
    voucher_claimed: Boolean(voucher),
    voucher_type: voucher ? (voucher.voucherType === 'discount' ? 'discount' : 'access') : null,
    voucher_discount_percent: voucher?.discountPercent ?? null,
    voucher_duration_months: voucher?.durationMonths ?? null,
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
    tenants: await Promise.all(profiles.map(async (p) => ({ id: p.tenantId, shopName: p.tenant.shopName, role: p.role, entitlement: await tenantEntitlement(p.tenantId) }))),
  });
}));

// Redeeming is intentionally separate from login: the caller must first
// authenticate, while this endpoint remains available when the shop is behind
// the paywall. The voucher is stored only as a hash and can be used once.
router.post('/voucher/redeem', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const { code } = parseBody(voucherRedeemSchema, req.body);
  const profile = req.user;
  if (!profile) return res.status(401).json({ error: 'Tenant selection required' });
  const voucher = await prisma.accessVoucher.findUnique({ where: { codeHash: hashVoucher(code) } });
  const now = new Date();
  if (!voucher || voucher.revokedAt || voucher.pausedAt || voucher.deletedAt || voucher.redeemedAt || (voucher.expiresAt && voucher.expiresAt <= now)) {
    return res.status(400).json({ error: 'Voucher is invalid, expired, or already used', code: 'VOUCHER_INVALID' });
  }
  if (voucher.tenantId && voucher.tenantId !== profile.tenantId) return res.status(403).json({ error: 'Voucher is issued for another shop', code: 'VOUCHER_TENANT_MISMATCH' });
  if (voucher.issuedToProfileId && voucher.issuedToProfileId !== profile.id) return res.status(403).json({ error: 'Voucher is issued to another user', code: 'VOUCHER_PROFILE_MISMATCH' });
  if (voucher.issuedToEmail && voucher.issuedToEmail !== (req.auth?.email ?? '').toLowerCase()) return res.status(403).json({ error: 'Voucher is issued to another email', code: 'VOUCHER_EMAIL_MISMATCH' });
  const claimed = await redeemVoucherAtomically({
    voucherId: voucher.id,
    tenantId: profile.tenantId,
    profileId: profile.id,
    email: (req.auth?.email ?? '').toLowerCase(),
    now,
    durationMonths: voucher.durationMonths,
    voucherType: voucher.voucherType === 'discount' ? 'discount' : 'access',
  });
  if (!claimed) {
    return res.status(400).json({ error: 'Voucher is invalid, expired, or already used', code: 'VOUCHER_INVALID' });
  }
  const voucherType = voucher.voucherType === 'discount' ? 'discount' : 'access';
  return res.json({
    status: voucherType === 'discount' ? 'discount_voucher_applied' : 'voucher_redeemed',
    voucher: { voucherType, durationMonths: voucher.durationMonths, discountPercent: voucher.discountPercent ?? 0 },
    entitlement: await tenantEntitlement(profile.tenantId),
  });
}));

router.post('/voucher/claim', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const profile = req.user;
  const email = (req.auth?.email ?? '').toLowerCase();
  if (!profile || !email) return res.status(401).json({ error: 'Tenant selection required' });
  if (profile.role !== 'admin') return res.status(403).json({ error: 'Shop owner access required' });

  const now = new Date();
  const voucher = await prisma.accessVoucher.findFirst({
    where: {
      issuedToEmail: email,
      redeemedAt: null,
      revokedAt: null,
      pausedAt: null,
      deletedAt: null,
      AND: [
        { OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
        { OR: [{ tenantId: null }, { tenantId: profile.tenantId }] },
        { OR: [{ issuedToProfileId: null }, { issuedToProfileId: profile.id }] },
      ],
    },
    orderBy: { createdAt: 'desc' },
  });
  if (!voucher) {
    return res.status(404).json({
      error: 'No active voucher is assigned to this account yet',
      code: 'VOUCHER_UNAVAILABLE',
    });
  }

  const claimed = await redeemVoucherAtomically({
    voucherId: voucher.id,
    tenantId: profile.tenantId,
    profileId: profile.id,
    email,
    now,
    durationMonths: voucher.durationMonths,
    voucherType: voucher.voucherType === 'discount' ? 'discount' : 'access',
  });
  if (!claimed) {
    return res.status(409).json({
      error: 'Voucher could not be claimed. Refresh and try again.',
      code: 'VOUCHER_REDEEM_FAILED',
    });
  }
  return res.json({
    status: voucher.voucherType === 'discount' ? 'discount_voucher_applied' : 'voucher_redeemed',
    voucher: {
      voucherType: voucher.voucherType === 'discount' ? 'discount' : 'access',
      durationMonths: voucher.durationMonths,
      discountPercent: voucher.discountPercent ?? 0,
    },
    entitlement: await tenantEntitlement(profile.tenantId),
  });
}));

// POST /auth/refresh
router.post('/refresh', refreshLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { refreshToken } = parseBody(authRefreshSchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const now = new Date();
  const hash = hashRefreshToken(refreshToken);
  const p = await prisma.profile.findFirst({
    where: {
      active: true,
      deletedAt: null,
      OR: [
        { refreshTokenHash: hash },
        { refreshTokenPreviousHash: hash },
      ],
    },
  });
  if (!p) {
    return res.status(401).json({ error: 'Invalid refresh token', code: 'INVALID_REFRESH_TOKEN', requestId });
  }
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
  let debugCode: string | undefined;
  if (user) {
    // generate code, store EmailVerification? use VerificationChallenge
    const code = createVerificationCode();
    debugCode = debugCodesEnabled(req) ? code : undefined;
    const salt = newSalt();
    const secret = verificationSecret();
    await prisma.verificationChallenge.updateMany({ where: { email, used: false }, data: { used: true } });
    await prisma.verificationChallenge.create({
      data: {
        email,
        code: `${salt}:${hashCodeSecret(code, salt, secret)}`,
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
  res.json({
    status: 'code_sent',
    ...(debugCode ? { debug_code: debugCode } : {}),
  });
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
  if (parts.length < 2 || parts.length > 3) return res.status(400).json({ error: 'Invalid code', code: 'VERIFICATION_INVALID', requestId });
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


// POST /auth/pin-reset/request
router.post('/pin-reset/request', pinResetLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { email } = parseBody(pinResetRequestSchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const secret = verificationSecret();
  const recent = await prisma.verificationChallenge.count({
    where: { email, createdAt: { gte: codeRequestWindowStart(new Date()) } },
  });
  if (recent >= MAX_CODES_PER_WINDOW) {
    return res.status(429).json({ error: `Too many codes requested. Wait ${CODE_REQUEST_WINDOW_MINUTES} minutes.`, code: 'TOO_MANY_CODES', requestId });
  }

  const user = await prisma.user.findUnique({ where: { email } });

  await prisma.verificationChallenge.updateMany({ where: { email, used: false }, data: { used: true } });

  const code = createVerificationCode();
  const salt = newSalt();
  const challenge = await prisma.verificationChallenge.create({
    data: {
      email,
      code: `${salt}:${hashCodeSecret(code, salt, secret)}`,
      expiresAt: new Date(Date.now() + VERIFICATION_TTL_MINUTES * 60_000),
      tenantId: null,
    },
  });

  if (user && mailerConfigured()) {
    try {
      const mailer = buildMailer();
      const profile = await prisma.profile.findFirst({ where: { userId: user.id, active: true, deletedAt: null }, include: { tenant: true }, orderBy: { createdAt: 'asc' } });
      await mailer.send({ to: email, code, shopName: profile?.tenant?.shopName ?? process.env.APP_NAME ?? 'SimpleSales', ttlMinutes: VERIFICATION_TTL_MINUTES });
    } catch {
      await prisma.verificationChallenge.update({ where: { id: challenge.id }, data: { used: true } });
      return res.status(502).json({ error: 'Email could not be sent', code: 'EMAIL_UNAVAILABLE', requestId });
    }
  }

  log('info', 'auth.pin_reset_code_sent', { requestId, email: maskEmail(email) });
  res.json({
    status: 'code_sent',
    challengeId: challenge.id,
    challenge_id: challenge.id,
    email: maskEmail(email),
    expires_in_seconds: VERIFICATION_TTL_MINUTES * 60,
    ...(debugCodesEnabled(req) && user ? { debug_code: code } : {}),
  });
}));

// POST /auth/pin-reset/confirm
router.post('/pin-reset/confirm', loginLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { email, challengeId, code, newPin } = parseBody(pinResetConfirmSchema, req.body);
  if (!isConfigured()) return notConfigured(res, requestId);

  const secret = verificationSecret();
  const now = new Date();
  const challenge = await prisma.verificationChallenge.findUnique({ where: { id: challengeId } });
  if (!challenge || challenge.email !== email) {
    return res.status(400).json({ error: 'Invalid or expired reset code', code: 'CODE_REJECTED', requestId });
  }
  if (challenge.used) {
    return res.status(400).json({ error: 'Invalid or expired reset code', code: 'CODE_REJECTED', requestId });
  }
  if (isVerificationExpired(challenge.expiresAt, now)) {
    await prisma.verificationChallenge.update({ where: { id: challenge.id }, data: { used: true } });
    return res.status(400).json({ error: 'Invalid or expired reset code', code: 'CODE_REJECTED', requestId });
  }

  const parts = (challenge.code || '').split(':');
  if (parts.length !== 2) {
    return res.status(400).json({ error: 'Invalid or expired reset code', code: 'CODE_REJECTED', requestId });
  }
  const [salt, codeHash] = parts;
  if (!hashesMatch(hashCodeSecret(code, salt, secret), codeHash)) {
    return res.status(400).json({ error: 'Invalid or expired reset code', code: 'CODE_REJECTED', requestId });
  }

  await prisma.verificationChallenge.updateMany({ where: { email, used: false }, data: { used: true } });

  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) {
    return res.status(400).json({ error: 'Invalid or expired reset code', code: 'CODE_REJECTED', requestId });
  }

  const passwordHash = await hashPassword(newPin);
  await prisma.user.update({ where: { id: user.id }, data: { passwordHash, emailVerifiedAt: user.emailVerifiedAt ?? now } });
  await prisma.profile.updateMany({ where: { userId: user.id }, data: { refreshTokenHash: null, refreshTokenPreviousHash: null } });

  log('info', 'auth.pin_reset', { requestId, email: maskEmail(email) });
  res.json({ status: 'password_reset' });
}));

export default router;
