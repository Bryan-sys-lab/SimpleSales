import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  prisma: { profile: { findUnique: vi.fn() } },
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

describe('system user update D1 batch', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: systemRoutes } = await import('../routes/system');
    app = express();
    app.use(express.json());
    app.use((req, _res, next) => {
      req.auth = { sub: 'system-admin-1' };
      next();
    });
    app.use('/system', systemRoutes);
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
    mocks.prisma.profile.findUnique.mockResolvedValue({
      id: 'profile-1',
      tenantId: 'tenant-1',
      deletedAt: null,
    });
    mocks.d1.batch.mockResolvedValue([
      {
        meta: { changes: 1 },
        results: [{ id: 'profile-1', tenant_id: 'tenant-1', name: 'Cashier', role: 'cashier', active: 0 }],
      },
      { meta: { changes: 1 } },
    ]);
  });

  it('updates profile access and writes its audit record atomically', async () => {
    const response = await supertest(app)
      .patch('/system/users/profile-1')
      .send({ active: false });

    expect(response.status).toBe(200);
    expect(response.body.user).toEqual({
      id: 'profile-1',
      tenantId: 'tenant-1',
      name: 'Cashier',
      role: 'cashier',
      active: false,
    });
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements).toHaveLength(2);
    expect(mocks.d1.statements[0].sql).toContain('RETURNING id, tenant_id, name, role, active');
    expect(mocks.d1.statements[0].sql).toContain('refresh_token_previous_hash');
    expect(mocks.d1.statements[1].sql).toContain('WHERE changes() = 1');
    expect(mocks.d1.statements[1].values).toContain('system-admin-1');
  });

  it('does not write an audit record if the profile was removed before update', async () => {
    mocks.d1.batch.mockResolvedValue([
      { meta: { changes: 0 }, results: [] },
      { meta: { changes: 0 } },
    ]);

    const response = await supertest(app)
      .patch('/system/users/profile-1')
      .send({ role: 'manager' });

    expect(response.status).toBe(404);
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements[1].sql).toContain('WHERE changes() = 1');
  });
});
