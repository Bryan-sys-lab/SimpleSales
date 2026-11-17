import express from 'express';
import supertest from 'supertest';
import { describe, expect, it, vi } from 'vitest';

process.env.AUTH_JWT_SECRET = 'test-secret-at-least-32-bytes-long-xxxxxxxx';
process.env.NODE_ENV = 'test';

const mocks = vi.hoisted(() => ({
  verifyAccessToken: vi.fn(),
  profileFindMany: vi.fn(),
}));

vi.mock('../lib/jwt', () => ({
  verifyAccessToken: mocks.verifyAccessToken,
}));
vi.mock('../lib/prisma', () => ({
  prisma: { profile: { findMany: mocks.profileFindMany } },
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
});
