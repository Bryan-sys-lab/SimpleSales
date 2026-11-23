import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {},
  d1: {
    statements: [] as Array<{ sql: string; values: unknown[] }>,
    prepare: vi.fn(),
    batch: vi.fn(),
  },
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: () => mocks.d1,
}));

vi.mock('../middleware/auth', () => ({
  systemAdminMiddleware: (req: express.Request, _res: express.Response, next: () => void) => {
    req.auth = { sub: 'super-admin', email: 'root@example.com' };
    (req as express.Request & { adminAccess: unknown }).adminAccess = {
      isSuperAdmin: true,
      packages: ['finance', 'hr', 'marketing', 'operations', 'sales', 'support', 'engineering', 'custom'],
      permissions: ['system:read', 'keys:read', 'keys:manage', 'membership:read', 'membership:manage'],
      canRecruit: true,
      canMintKeys: true,
      canAssignTasks: true,
    };
    next();
  },
}));

describe('admin account package assignment', () => {
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
    mocks.d1.statements.length = 0;
    mocks.d1.prepare.mockImplementation((sql: string) => ({
      bind: (...values: unknown[]) => {
        const statement = { sql, values };
        mocks.d1.statements.push(statement);
        return statement;
      },
    }));
    mocks.d1.batch.mockResolvedValue([
      { meta: { changes: 1 } },
      { meta: { changes: 1 } },
    ]);
  });

  it('persists combined package scopes and extra permissions on a new account', async () => {
    const response = await supertest(app)
      .post('/admin/auth/keys/mint')
      .send({
        email: 'sales@example.com',
        phone: '+254700000000',
        department: 'Sales',
        role: 'manager',
        packages: ['sales', 'finance'],
        permissions: ['keys:read'],
        expiresInDays: 90,
      });

    expect(response.status).toBe(201);
    expect(response.body.packages).toEqual(['sales', 'finance']);
    expect(response.body.permissions).toEqual([
      'analytics:read',
      'commercial:read',
      'configuration:read',
      'membership:read',
      'membership:manage',
      'tenants:read',
      'keys:read',
    ]);
    expect(mocks.d1.statements[0].values[9]).toBe(
      JSON.stringify(['sales', 'finance']),
    );
    expect(mocks.d1.statements[0].values[10]).toBe(
      JSON.stringify(response.body.permissions),
    );
  });

  it('rejects scopes that are not in the access catalog', async () => {
    const response = await supertest(app)
      .post('/admin/auth/keys/mint')
      .send({
        email: 'sales@example.com',
        phone: '+254700000000',
        department: 'Sales',
        packages: ['sales'],
        permissions: ['system:root'],
      });

    expect(response.status).toBe(400);
    expect(mocks.d1.batch).not.toHaveBeenCalled();
  });
});
