import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';
import { authMiddleware } from '../middleware/auth';

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
  },
  sendEmail: vi.fn(),
}));

vi.mock('../lib/prisma', () => ({ prisma: mocks.prisma }));
vi.mock('../lib/email_sender', () => ({
  createCloudflareEmailTransport: () => ({ configured: true, send: mocks.sendEmail }),
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
    app.use(express.json());
    app.use('/auth', authRoutes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.sendEmail.mockResolvedValue(undefined);
    mocks.prisma.verificationChallenge.count.mockResolvedValue(0);
    mocks.prisma.verificationChallenge.updateMany.mockResolvedValue({ count: 0 });
  });

  it('link sends code', async () => {
    mocks.prisma.user.findUnique.mockResolvedValue(null);
    mocks.prisma.user.create.mockResolvedValue({ id: 'user-1', email: 'owner@example.com', emailVerifiedAt: null });
    mocks.prisma.verificationChallenge.create.mockResolvedValue({ id: 'ch-1', expiresAt: new Date(Date.now() + 600000) });
    mocks.prisma.verificationChallenge.update.mockResolvedValue({});

    const res = await supertest(app).post('/auth/link').send({
      email: 'owner@example.com', password: '123456', shopName: 'Shop', ownerName: 'Owner',
    });
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('code_sent');
  });

  it('login rejects unknown user', async () => {
    mocks.prisma.user.findUnique.mockResolvedValue(null);
    const res = await supertest(app).post('/auth/login').send({ email: 'x@example.com', password: '123456' });
    expect(res.status).toBe(401);
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
