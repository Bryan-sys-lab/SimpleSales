import express from 'express';
import supertest from 'supertest';
import { describe, expect, it, vi } from 'vitest';

process.env.AUTH_JWT_SECRET = 'test-secret-at-least-32-bytes-long-xxxxxxxx';
process.env.NODE_ENV = 'test';

const mocks = vi.hoisted(() => ({
  verifyAccessToken: vi.fn(),
  profileFindMany: vi.fn(),
  tenantSubscriptionFindUnique: vi.fn(),
}));

vi.mock('../lib/jwt', () => ({
  verifyAccessToken: mocks.verifyAccessToken,
}));
vi.mock('../lib/prisma', () => ({
  prisma: {
    profile: { findMany: mocks.profileFindMany },
    tenantSubscription: { findUnique: mocks.tenantSubscriptionFindUnique },
  },
}));

describe('auth v2 lifecycle e2e', () => {
  async function buildApp() {
    const { authMiddleware } = await import('../middleware/auth');
    const app = express();
    app.use(express.json());
    app.use('/api', authMiddleware);
    app.get('/api/tenant/profile', (_req, res) => res.json({ ok: true }));
    app.get('/api/sales', (_req, res) => res.json({ ok: true }));
    app.post('/api/auth/voucher/claim', (_req, res) => res.json({ ok: true }));
    app.post('/api/backups/restore', (_req, res) => res.json({ ok: true }));
    app.use((error: any, _req: any, res: any, _next: any) => {
      res.status(error.status ?? 500).json({ error: error.message, code: error.code, entitlement: error.body?.entitlement });
    });
    return app;
  }

  function authedProfile() {
    mocks.verifyAccessToken.mockReturnValue({ sub: 'user-1', token_use: 'access', email: 'owner@example.com', email_verified: true });
    mocks.profileFindMany.mockResolvedValue([{
      id: 'profile-1', tenantId: 'tenant-1', role: 'admin', name: 'Owner', tenant: { shopName: 'Shop' },
    }]);
  }

  it('allows entitled active subscriptions', async () => {
    authedProfile();
    mocks.tenantSubscriptionFindUnique.mockResolvedValue({ status: 'active', currentPeriodEnd: new Date(Date.now() + 86400000), graceUntil: null, priceMinor: 1000, currency: 'KES', billingInterval: 'monthly' });
    const app = await buildApp();
    const res = await supertest(app).get('/api/tenant/profile').set('authorization', 'Bearer token').set('x-tenant-id', 'tenant-1');
    expect(res.status).toBe(200);
  });

  it('allows grace subscriptions', async () => {
    authedProfile();
    mocks.tenantSubscriptionFindUnique.mockResolvedValue({ status: 'active', currentPeriodEnd: new Date(Date.now() - 86400000), graceUntil: new Date(Date.now() + 86400000), priceMinor: 1000, currency: 'KES', billingInterval: 'monthly' });
    const app = await buildApp();
    const res = await supertest(app).get('/api/sales').set('authorization', 'Bearer token').set('x-tenant-id', 'tenant-1');
    expect(res.status).toBe(200);
  });

  it('blocks expired subscriptions with 402', async () => {
    authedProfile();
    mocks.tenantSubscriptionFindUnique.mockResolvedValue({ status: 'active', currentPeriodEnd: new Date(Date.now() - 86400000), graceUntil: new Date(Date.now() - 3600000), priceMinor: 1000, currency: 'KES', billingInterval: 'monthly' });
    const app = await buildApp();
    const res = await supertest(app).get('/api/tenant/profile').set('authorization', 'Bearer token').set('x-tenant-id', 'tenant-1');
    expect(res.status).toBe(402);
  });

  it('blocks pending subscriptions with 402', async () => {
    authedProfile();
    mocks.tenantSubscriptionFindUnique.mockResolvedValue(null);
    const app = await buildApp();
    const res = await supertest(app).get('/api/tenant/profile').set('authorization', 'Bearer token').set('x-tenant-id', 'tenant-1');
    expect(res.status).toBe(402);
  });

  it('allows billing recovery voucher claim while paywalled', async () => {
    authedProfile();
    mocks.tenantSubscriptionFindUnique.mockResolvedValue(null);
    const app = await buildApp();
    const res = await supertest(app).post('/api/auth/voucher/claim').set('authorization', 'Bearer token').set('x-tenant-id', 'tenant-1');
    expect(res.status).toBe(200);
  });

  it('allows voucher-entitled subscriptions', async () => {
    authedProfile();
    mocks.tenantSubscriptionFindUnique.mockResolvedValue({ status: 'voucher', currentPeriodEnd: new Date(Date.now() + 86400000), graceUntil: null, priceMinor: 1000, currency: 'KES', billingInterval: 'monthly', voucher: null });
    const app = await buildApp();
    const res = await supertest(app).get('/api/tenant/profile').set('authorization', 'Bearer token').set('x-tenant-id', 'tenant-1');
    expect(res.status).toBe(200);
  });

  it('allows device sessions on allowlisted routes when entitled', async () => {
    mocks.verifyAccessToken.mockReturnValue({ sub: 'user-1', token_use: 'device' });
    mocks.profileFindMany.mockResolvedValue([{ id: 'profile-1', tenantId: 'tenant-1', role: 'admin', name: 'Owner', tenant: { shopName: 'Shop' } }]);
    mocks.tenantSubscriptionFindUnique.mockResolvedValue({ status: 'active', currentPeriodEnd: new Date(Date.now() + 86400000), graceUntil: null, priceMinor: 1000, currency: 'KES', billingInterval: 'monthly' });
    const app = await buildApp();
    const res = await supertest(app).get('/api/sales').set('authorization', 'Bearer device-token').set('x-tenant-id', 'tenant-1');
    expect(res.status).toBe(200);
  });
});
