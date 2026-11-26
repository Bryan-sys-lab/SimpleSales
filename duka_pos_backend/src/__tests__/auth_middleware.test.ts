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

describe('auth middleware staff bootstrap', () => {
  it('allows the tenant-scoped staff PIN bootstrap without a bearer token',
    async () => {
      const { authMiddleware } = await import('../middleware/auth');
      const app = express();
      app.use(express.json());
      app.use('/api', authMiddleware);
      app.post('/api/tenant/staff/authenticate', (_req, res) => {
        res.status(204).end();
      });

      const response = await supertest(app)
        .post('/api/tenant/staff/authenticate')
        .set('x-tenant-id', 'tenant-1')
        .send({ username: 'cashier', pin: '1234' });

      expect(response.status).toBe(204);
      expect(mocks.verifyAccessToken).not.toHaveBeenCalled();
    });

  it('still requires a bearer token for an unscoped protected request',
    async () => {
      const { authMiddleware } = await import('../middleware/auth');
      const app = express();
      app.use(express.json());
      app.use('/api', authMiddleware);
      app.get('/api/tenant/staff', (_req, res) => {
        res.status(204).end();
      });
      app.use((error: any, _req: any, res: any, _next: any) => {
        res.status(error.status ?? 500).json({ error: error.message });
      });

      const response = await supertest(app).get('/api/tenant/staff');
      expect(response.status).toBe(401);
      expect(response.body.error).toBe('Missing bearer token');
    });

  it('keeps the bootstrap exception when middleware is applied twice',
    async () => {
      const { authMiddleware } = await import('../middleware/auth');
      const app = express();
      app.use(express.json());
      const tenant = express.Router();
      tenant.use(authMiddleware);
      tenant.post('/staff/authenticate', (_req, res) => {
        res.status(204).end();
      });
      app.use('/api/tenant', authMiddleware, tenant);
      app.use((error: any, _req: any, res: any, _next: any) => {
        res.status(error.status ?? 500).json({ error: error.message });
      });

      const response = await supertest(app)
        .post('/api/tenant/staff/authenticate')
        .set('x-tenant-id', 'tenant-1')
        .send({ username: 'cashier', pin: '1234' });

      expect(response.status).toBe(204);
      expect(mocks.verifyAccessToken).not.toHaveBeenCalled();
    });

  it('allows device sessions to use app sales, backup, and payment routes only within the allowlist',
    async () => {
      const { authMiddleware } = await import('../middleware/auth');
      mocks.verifyAccessToken.mockReturnValue({ sub: 'user-1', token_use: 'device' });
      mocks.profileFindMany.mockResolvedValue([{
        id: 'profile-1',
        tenantId: 'tenant-1',
        role: 'admin',
        name: 'Owner',
        tenant: { shopName: 'Shop' },
      }]);
      mocks.tenantSubscriptionFindUnique.mockResolvedValue({
        status: 'active',
        currentPeriodEnd: null,
        graceUntil: null,
        priceMinor: null,
        currency: 'KES',
        billingInterval: 'monthly',
      });

      const app = express();
      app.use('/api', authMiddleware);
      app.post('/api/sales/sync', (_req, res) => res.status(204).end());
      app.post('/api/backups/full', (_req, res) => res.status(204).end());
      app.post('/api/payments/initiate', (_req, res) => res.status(204).end());
      app.get('/api/owner-transactions', (_req, res) => res.status(204).end());

      for (const path of [
        '/api/sales/sync',
        '/api/backups/full',
        '/api/payments/initiate',
      ]) {
        const response = await supertest(app)
          .post(path)
          .set('authorization', 'Bearer device-token')
          .set('x-tenant-id', 'tenant-1');
        expect(response.status, path).toBe(204);
      }

      const restricted = await supertest(app)
        .get('/api/owner-transactions')
        .set('authorization', 'Bearer device-token')
        .set('x-tenant-id', 'tenant-1');
      expect(restricted.status).toBe(204);
    });

  it('allows a newly verified device session to claim a voucher while the tenant is paywalled',
    async () => {
      const { authMiddleware } = await import('../middleware/auth');
      mocks.verifyAccessToken.mockReset().mockReturnValue({ sub: 'user-1', token_use: 'device' });
      mocks.profileFindMany.mockReset().mockResolvedValue([{
        id: 'profile-1',
        tenantId: 'tenant-1',
        role: 'admin',
        name: 'Owner',
        tenant: { shopName: 'Shop' },
      }]);
      mocks.tenantSubscriptionFindUnique.mockReset().mockResolvedValue(null);

      const app = express();
      app.use('/api', authMiddleware);
      app.post('/api/auth/voucher/claim', authMiddleware, (_req, res) => res.status(204).end());

      const response = await supertest(app)
        .post('/api/auth/voucher/claim')
        .set('authorization', 'Bearer device-token')
        .set('x-tenant-id', 'tenant-1');

      expect(response.status).toBe(204);
      expect(mocks.tenantSubscriptionFindUnique).not.toHaveBeenCalled();
    });

  it('allows an owner to restore an encrypted backup while paywalled, but still gates other shop reads',
    async () => {
      const { authMiddleware } = await import('../middleware/auth');
      mocks.verifyAccessToken.mockReset().mockReturnValue({ sub: 'user-1', token_use: 'device' });
      mocks.profileFindMany.mockReset().mockResolvedValue([{
        id: 'profile-1',
        tenantId: 'tenant-1',
        role: 'admin',
        name: 'Owner',
        tenant: { shopName: 'Shop' },
      }]);
      mocks.tenantSubscriptionFindUnique.mockReset().mockResolvedValue(null);

      const app = express();
      app.use('/api', authMiddleware);
      app.get('/api/backups/full', (_req, res) => res.status(204).end());
      app.get('/api/tenant/settings', (_req, res) => res.status(204).end());

      const backup = await supertest(app)
        .get('/api/backups/full')
        .set('authorization', 'Bearer device-token')
        .set('x-tenant-id', 'tenant-1');
      expect(backup.status).toBe(204);

      const settings = await supertest(app)
        .get('/api/tenant/settings')
        .set('authorization', 'Bearer device-token')
        .set('x-tenant-id', 'tenant-1');
      expect(settings.status).toBe(402);
    });
});
