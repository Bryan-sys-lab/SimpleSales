import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';
import { issueAccessToken, verifyAccessToken } from '../lib/jwt';

const mocks = vi.hoisted(() => ({
  adminKeyFindUnique: vi.fn(),
}));

vi.mock('../lib/prisma', () => ({
  prisma: {
    adminKey: {
      findUnique: mocks.adminKeyFindUnique,
    },
  },
  getD1DatabaseBinding: vi.fn(),
}));

process.env.AUTH_JWT_SECRET = 'test-secret-at-least-32-bytes-long-xxxxxxxx';
process.env.NODE_ENV = 'test';

describe('admin session refresh', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: adminAuthRoutes } = await import('../routes/admin_auth');
    app = express();
    app.use(express.json());
    app.use('/admin/auth', adminAuthRoutes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.adminKeyFindUnique.mockResolvedValue({
      id: 'key-1',
      email: 'analyst@example.com',
      department: 'Analytics',
      permissions: [],
      canRecruit: false,
      canMintKeys: false,
      canAssignTasks: false,
      revokedAt: null,
      expiresAt: new Date(Date.now() + 60_000),
    });
  });

  it('renews an active department session without exposing extra permissions', async () => {
    const original = issueAccessToken({
      userId: 'admin:key-1',
      email: 'analyst@example.com',
      emailVerified: true,
      tier: 'admin',
    });

    const response = await supertest(app)
      .post('/admin/auth/refresh')
      .set('authorization', `Bearer ${original.token}`)
      .send({});

    expect(response.status).toBe(200);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.body).toMatchObject({
      token_type: 'Bearer',
      expires_in: 3600,
    });
    expect(response.body.access_token).not.toBe(original.token);
    expect(verifyAccessToken(response.body.access_token)).toMatchObject({
      sub: 'admin:key-1',
      email: 'analyst@example.com',
      token_use: 'admin',
    });
  });

  it('does not refresh an invalid or expired session', async () => {
    const response = await supertest(app)
      .post('/admin/auth/refresh')
      .set('authorization', 'Bearer invalid-token')
      .send({});

    expect(response.status).toBe(401);
    expect(response.body.error).toContain('Invalid or expired administrator token');
  });

  it('does not renew an administrator key after it has been revoked', async () => {
    mocks.adminKeyFindUnique.mockResolvedValue({
      id: 'key-1',
      email: 'analyst@example.com',
      department: 'Analytics',
      permissions: [],
      canRecruit: false,
      canMintKeys: false,
      canAssignTasks: false,
      revokedAt: new Date(),
      expiresAt: new Date(Date.now() + 60_000),
    });
    const original = issueAccessToken({
      userId: 'admin:key-1',
      email: 'analyst@example.com',
      emailVerified: true,
      tier: 'admin',
    });

    const response = await supertest(app)
      .post('/admin/auth/refresh')
      .set('authorization', `Bearer ${original.token}`)
      .send({});

    expect(response.status).toBe(403);
    expect(response.body.error).toBe('System administrator access required');
  });
});
