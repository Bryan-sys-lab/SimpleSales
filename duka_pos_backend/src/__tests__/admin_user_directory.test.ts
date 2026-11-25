import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {
    user: { findMany: vi.fn() },
    profile: { findMany: vi.fn() },
  },
  database: {
    prepare: vi.fn(),
    batch: vi.fn(),
  },
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: () => mocks.database,
}));
vi.mock('../middleware/auth', () => ({
  authMiddleware: (_req: unknown, _res: unknown, next: () => void) => next(),
  requireRole: () => (_req: unknown, _res: unknown, next: () => void) => next(),
  systemAdminMiddleware: (req: express.Request, _res: unknown, next: () => void) => {
    req.auth = { sub: 'admin-1' };
    next();
  },
}));
vi.mock('../services/payhero', () => ({
  registerPaymentChannel: vi.fn(),
}));
vi.mock('../lib/email_sender', () => ({
  createCloudflareEmailTransport: () => ({ configured: false, send: vi.fn() }),
}));
vi.mock('../lib/entitlements', () => ({
  generateVoucher: vi.fn(),
}));

describe('admin user directories', () => {
  let app: express.Express;

  beforeAll(async () => {
    const [{ default: adminRoutes }, { default: systemRoutes }] = await Promise.all([
      import('../routes/admin'),
      import('../routes/system'),
    ]);
    app = express();
    app.use(express.json());
    app.use('/admin', adminRoutes);
    app.use('/system', systemRoutes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns all admin users using bounded relation-query pages', async () => {
    const user = (index: number) => ({
      id: `user-${index}`,
      email: `user-${index}@example.com`,
      emailVerifiedAt: null,
      createdAt: new Date(`2026-11-25T00:${String(index).padStart(2, '0')}:00.000Z`),
      profiles: [{
        id: `profile-${index}`,
        name: `Owner ${index}`,
        role: 'admin',
        tenant: { id: `tenant-${index}`, shopName: `Shop ${index}` },
      }],
    });
    mocks.prisma.user.findMany.mockImplementation(({ cursor }: { cursor?: { id: string } }) =>
      Promise.resolve(cursor
        ? [user(1)]
        : Array.from({ length: 25 }, (_, index) => user(26 - index))),
    );

    const response = await supertest(app).get('/admin/users');

    expect(response.status).toBe(200);
    expect(response.body.users).toHaveLength(26);
    expect(response.body.users[0].id).toBe('user-26');
    expect(response.body.users[25].id).toBe('user-1');
    expect(response.body.users[0].profiles[0].tenant.shopName).toBe('Shop 26');
    expect(mocks.prisma.user.findMany).toHaveBeenCalledTimes(2);
    expect(mocks.prisma.user.findMany).toHaveBeenNthCalledWith(1, expect.objectContaining({
      take: 25,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    }));
    expect(mocks.prisma.user.findMany).toHaveBeenNthCalledWith(2, expect.objectContaining({
      cursor: { id: 'user-2' },
      skip: 1,
      take: 25,
    }));
  });

  it('returns all shop profiles using bounded relation-query pages', async () => {
    const profile = (index: number) => ({
      id: `profile-${index}`,
      name: `Staff ${index}`,
      role: 'cashier',
      active: true,
      createdAt: new Date(`2026-11-25T00:${String(index).padStart(2, '0')}:00.000Z`),
      user: { email: `user-${index}@example.com` },
      tenant: { id: `tenant-${index}`, shopName: `Shop ${index}` },
    });
    mocks.prisma.profile.findMany.mockImplementation(({ cursor }: { cursor?: { id: string } }) =>
      Promise.resolve(cursor
        ? [profile(1)]
        : Array.from({ length: 25 }, (_, index) => profile(26 - index))),
    );

    const response = await supertest(app).get('/system/users');

    expect(response.status).toBe(200);
    expect(response.body.users).toHaveLength(26);
    expect(response.body.users[0].id).toBe('profile-26');
    expect(response.body.users[25].id).toBe('profile-1');
    expect(response.body.users[0].tenant.shopName).toBe('Shop 26');
    expect(mocks.prisma.profile.findMany).toHaveBeenCalledTimes(2);
    expect(mocks.prisma.profile.findMany).toHaveBeenNthCalledWith(1, expect.objectContaining({
      take: 25,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    }));
    expect(mocks.prisma.profile.findMany).toHaveBeenNthCalledWith(2, expect.objectContaining({
      cursor: { id: 'profile-2' },
      skip: 1,
      take: 25,
    }));
  });
});
