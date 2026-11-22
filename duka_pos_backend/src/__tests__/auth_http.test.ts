import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';
import { hashCodeSecret, newSalt } from '../lib/verification';
// import { authMiddleware } from '../middleware/auth';

const mocks = vi.hoisted(() => ({
  prisma: {
    user: {
      findUnique: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
    },
    profile: {
      findMany: vi.fn(),
      findFirst: vi.fn(),
      findUnique: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      updateMany: vi.fn(),
    },
    tenant: {
      create: vi.fn(),
    },
    verificationChallenge: {
      count: vi.fn(),
      findFirst: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      updateMany: vi.fn(),
    },
    accessVoucher: {
      updateMany: vi.fn(),
      create: vi.fn(),
      findFirst: vi.fn(),
      findUnique: vi.fn(),
    },
  },
  sendEmail: vi.fn(),
  emailConfigured: true,
}));

vi.mock('../lib/prisma', () => ({ prisma: mocks.prisma }));
vi.mock('../lib/email_sender', () => ({
  createCloudflareEmailTransport: () => ({ configured: mocks.emailConfigured, send: mocks.sendEmail }),
}));
vi.mock('../middleware/auth', () => ({
  authMiddleware: (req: any, _res: any, next: () => void) => {
    req.auth = { sub: 'user-1', email: 'owner@example.com', email_verified: true, token_use: 'access' };
    req.user = { id: 'profile-1', tenantId: 'tenant-1', role: 'admin', name: 'Owner' };
    next();
  },
  systemAdminMiddleware: (_req: any, _res: any, next: () => void) => next(),
  requireOwner: (_req: any, _res: any, next: () => void) => next(),
  requireRole: () => (_req: any, _res: any, next: () => void) => next(),
}));

// ensure env
process.env.AUTH_JWT_SECRET = 'test-secret-at-least-32-bytes-long-xxxxxxxx';
process.env.EMAIL_VERIFICATION_SECRET = 'verify-secret';
process.env.NODE_ENV = 'test';

describe('auth http', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: authRoutes } = await import('../routes/auth');
    app = express();
    app.set('trust proxy', 1);
    app.use(express.json());
    app.use('/auth', authRoutes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.emailConfigured = true;
    mocks.sendEmail.mockResolvedValue(undefined);
    process.env.AUTH_TEST_CODE = '123456';
    delete process.env.VERIFICATION_DEBUG_CODES;
    mocks.prisma.verificationChallenge.count.mockResolvedValue(0);
    mocks.prisma.verificationChallenge.updateMany.mockResolvedValue({ count: 0 });
    mocks.prisma.accessVoucher.updateMany.mockResolvedValue({ count: 0 });
  });

  it('sends the first-registration voucher with the verification code', async () => {
    mocks.prisma.user.findUnique.mockResolvedValue(null);
    mocks.prisma.user.create.mockResolvedValue({ id: 'user-1', email: 'owner@example.com', emailVerifiedAt: null });
    mocks.prisma.verificationChallenge.create.mockResolvedValue({ id: 'ch-1', expiresAt: new Date(Date.now() + 600000) });
    mocks.prisma.verificationChallenge.update.mockResolvedValue({});

    const res = await supertest(app).post('/auth/link').send({
      email: 'owner@example.com', password: '123456', shopName: 'Shop', ownerName: 'Owner',
    }).set('x-forwarded-for', '198.51.100.10');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('code_sent');
    expect(mocks.prisma.accessVoucher.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        issuedToEmail: 'owner@example.com',
        autoIssued: true,
        createdBy: 'system:first-registration',
      }),
    });
    expect(mocks.sendEmail).toHaveBeenCalledWith(expect.objectContaining({
      to: 'owner@example.com',
      code: '123456',
      firstVoucherCode: expect.stringMatching(/^SS-/),
    }));
  });

  it('rejects account setup when no email transport is configured', async () => {
    mocks.emailConfigured = false;

    const res = await supertest(app).post('/auth/link').send({
      email: 'owner@example.com', password: '123456', shopName: 'Shop', ownerName: 'Owner',
    });

    expect(res.status).toBe(503);
    expect(res.body.code).toBe('EMAIL_NOT_CONFIGURED');
    expect(mocks.prisma.user.findUnique).not.toHaveBeenCalled();
    expect(mocks.prisma.verificationChallenge.create).not.toHaveBeenCalled();
    expect(mocks.prisma.accessVoucher.create).not.toHaveBeenCalled();
  });

  it('allows deterministic email-free verification only in non-production debug mode', async () => {
    mocks.emailConfigured = false;
    process.env.VERIFICATION_DEBUG_CODES = 'true';
    mocks.prisma.user.findUnique.mockResolvedValue(null);
    mocks.prisma.user.create.mockResolvedValue({ id: 'user-1', email: 'owner@example.com', emailVerifiedAt: null });
    mocks.prisma.verificationChallenge.create.mockResolvedValue({ id: 'ch-1', expiresAt: new Date(Date.now() + 600000) });
    mocks.prisma.verificationChallenge.update.mockResolvedValue({});

    const res = await supertest(app).post('/auth/link').send({
      email: 'owner@example.com', password: '123456', shopName: 'Shop', ownerName: 'Owner',
    });

    expect(res.status).toBe(200);
    expect(res.body.debug_code).toBe('123456');
    expect(res.body.debug_first_voucher_code).toMatch(/^SS-/);
    expect(mocks.sendEmail).not.toHaveBeenCalled();
  });

  it('requires the staging test secret before returning debug codes', async () => {
    const previousEnv = {
      nodeEnv: process.env.NODE_ENV,
      publicApiUrl: process.env.PUBLIC_API_URL,
      verificationDebugCodes: process.env.VERIFICATION_DEBUG_CODES,
      stagingAuthTestSecret: process.env.STAGING_AUTH_TEST_SECRET,
    };
    process.env.NODE_ENV = 'production';
    process.env.PUBLIC_API_URL = 'https://duka-pos-backend-staging.example.workers.dev';
    process.env.VERIFICATION_DEBUG_CODES = 'true';
    process.env.STAGING_AUTH_TEST_SECRET = 'staging-ci-test-secret';
    mocks.prisma.user.findUnique.mockResolvedValue(null);
    mocks.prisma.user.create.mockResolvedValue({ id: 'user-1', email: 'owner@example.com', emailVerifiedAt: null });
    mocks.prisma.verificationChallenge.create.mockResolvedValue({ id: 'ch-1', expiresAt: new Date(Date.now() + 600000) });
    mocks.prisma.verificationChallenge.update.mockResolvedValue({});

    const postLink = (ip: string, secret?: string) => {
      const request = supertest(app).post('/auth/link').send({
        email: 'owner@example.com', password: '123456', shopName: 'Shop', ownerName: 'Owner',
      }).set('x-forwarded-for', ip);
      if (secret) request.set('x-staging-auth-test-secret', secret);
      return request;
    };

    try {
      const unauthenticated = await postLink('198.51.100.11');
      expect(unauthenticated.status).toBe(200);
      expect(unauthenticated.body).not.toHaveProperty('debug_code');
      expect(unauthenticated.body).not.toHaveProperty('debug_first_voucher_code');

      const rejected = await postLink('198.51.100.12', 'invalid-ci-test-secret');
      expect(rejected.status).toBe(200);
      expect(rejected.body).not.toHaveProperty('debug_code');
      expect(rejected.body).not.toHaveProperty('debug_first_voucher_code');

      const authorized = await postLink('198.51.100.13', 'staging-ci-test-secret');
      expect(authorized.status).toBe(200);
      expect(authorized.body.debug_code).toMatch(/^\d{6}$/);
      expect(authorized.body.debug_first_voucher_code).toMatch(/^SS-/);
    } finally {
      if (previousEnv.nodeEnv === undefined) delete process.env.NODE_ENV;
      else process.env.NODE_ENV = previousEnv.nodeEnv;
      if (previousEnv.publicApiUrl === undefined) delete process.env.PUBLIC_API_URL;
      else process.env.PUBLIC_API_URL = previousEnv.publicApiUrl;
      if (previousEnv.verificationDebugCodes === undefined) delete process.env.VERIFICATION_DEBUG_CODES;
      else process.env.VERIFICATION_DEBUG_CODES = previousEnv.verificationDebugCodes;
      if (previousEnv.stagingAuthTestSecret === undefined) delete process.env.STAGING_AUTH_TEST_SECRET;
      else process.env.STAGING_AUTH_TEST_SECRET = previousEnv.stagingAuthTestSecret;
    }
  });

  it('does not expose test verification codes outside NODE_ENV=test', async () => {
    const previousNodeEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'production';
    process.env.VERIFICATION_DEBUG_CODES = 'true';
    mocks.prisma.user.findUnique.mockResolvedValue(null);
    mocks.prisma.user.create.mockResolvedValue({ id: 'user-1', email: 'owner@example.com', emailVerifiedAt: null });
    mocks.prisma.verificationChallenge.create.mockResolvedValue({ id: 'ch-1', expiresAt: new Date(Date.now() + 600000) });
    mocks.prisma.verificationChallenge.update.mockResolvedValue({});

    try {
      const res = await supertest(app).post('/auth/link').send({
        email: 'owner@example.com', password: '123456', shopName: 'Shop', ownerName: 'Owner',
      });

      expect(res.status).toBe(200);
      expect(res.body).not.toHaveProperty('debug_code');
      expect(res.body).not.toHaveProperty('debug_first_voucher_code');
      expect(mocks.sendEmail).toHaveBeenCalledWith(expect.objectContaining({
        to: 'owner@example.com',
        code: expect.not.stringMatching(/^123456$/),
      }));
    } finally {
      if (previousNodeEnv === undefined) delete process.env.NODE_ENV;
      else process.env.NODE_ENV = previousNodeEnv;
    }
  });

  it('login rejects unknown user', async () => {
    mocks.prisma.user.findUnique.mockResolvedValue(null);
    const res = await supertest(app).post('/auth/login').send({ email: 'x@example.com', password: '123456' });
    expect(res.status).toBe(401);
  });

  it('requires a voucher code during email verification', async () => {
    const res = await supertest(app).post('/auth/verify').send({
      email: 'owner@example.com',
      password: '123456',
      code: '123456',
      shopName: 'Shop',
      ownerName: 'Owner',
    });

    expect(res.status).toBe(400);
    expect(mocks.prisma.verificationChallenge.findFirst).not.toHaveBeenCalled();
    expect(mocks.prisma.user.update).not.toHaveBeenCalled();
  });

  it('accepts a valid code without consuming the challenge or creating an account', async () => {
    const salt = newSalt();
    const secret = process.env.EMAIL_VERIFICATION_SECRET!;
    mocks.prisma.verificationChallenge.findFirst.mockResolvedValue({
      id: 'ch-1',
      expiresAt: new Date(Date.now() + 60_000),
      code: [
        salt,
        hashCodeSecret('123456', salt, secret),
        hashCodeSecret('123456', salt, secret),
      ].join(':'),
    });

    const res = await supertest(app).post('/auth/verify-code').send({
      email: 'owner@example.com',
      password: '123456',
      code: '123456',
    });

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('code_verified');
    expect(mocks.prisma.verificationChallenge.update).not.toHaveBeenCalled();
    expect(mocks.prisma.verificationChallenge.updateMany).not.toHaveBeenCalled();
    expect(mocks.prisma.accessVoucher.findUnique).not.toHaveBeenCalled();
    expect(mocks.prisma.user.create).not.toHaveBeenCalled();
    expect(mocks.prisma.user.update).not.toHaveBeenCalled();
    expect(mocks.prisma.tenant.create).not.toHaveBeenCalled();
    expect(mocks.prisma.profile.create).not.toHaveBeenCalled();
  });

  it('rejects an incorrect code without consuming the challenge', async () => {
    const salt = newSalt();
    const secret = process.env.EMAIL_VERIFICATION_SECRET!;
    mocks.prisma.verificationChallenge.findFirst.mockResolvedValue({
      id: 'ch-1',
      expiresAt: new Date(Date.now() + 60_000),
      code: [
        salt,
        hashCodeSecret('123456', salt, secret),
        hashCodeSecret('123456', salt, secret),
      ].join(':'),
    });

    const res = await supertest(app).post('/auth/verify-code').send({
      email: 'owner@example.com',
      password: '123456',
      code: '654321',
    });

    expect(res.status).toBe(400);
    expect(res.body.code).toBe('VERIFICATION_INVALID');
    expect(mocks.prisma.verificationChallenge.update).not.toHaveBeenCalled();
    expect(mocks.prisma.verificationChallenge.updateMany).not.toHaveBeenCalled();
    expect(mocks.prisma.user.create).not.toHaveBeenCalled();
  });

  it('me returns user', async () => {
    mocks.prisma.user.findUnique.mockResolvedValue({ id: 'user-1', email: 'owner@example.com', emailVerifiedAt: new Date() });
    mocks.prisma.profile.findMany.mockResolvedValue([{ tenantId: 'tenant-1', role: 'admin', tenant: { shopName: 'Shop' } }]);
    const res = await supertest(app).get('/auth/me');
    expect(res.status).toBe(200);
    expect(res.body.email).toBe('owner@example.com');
  });

  it('change-password requires current', async () => {
    mocks.prisma.user.findUnique.mockResolvedValue({ id: 'user-1', email: 'owner@example.com', passwordHash: '$2a$12$' + 'a'.repeat(53), emailVerifiedAt: new Date() });
    const res = await supertest(app).post('/auth/change-password').send({ currentPassword: '000000', newPassword: '123456' });
    expect(res.status).toBe(401);
  });

  it('logout clears', async () => {
    mocks.prisma.profile.updateMany.mockResolvedValue({ count: 1 });
    const res = await supertest(app).post('/auth/logout').send({});
    expect(res.status).toBe(200);
  });
});
