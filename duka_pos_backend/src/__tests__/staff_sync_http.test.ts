import express from 'express';
import supertest from 'supertest';
import { pbkdf2Sync, randomBytes } from 'node:crypto';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

process.env.AUTH_JWT_SECRET = 'test-secret-at-least-32-bytes-long-xxxxxxxx';

const mocks = vi.hoisted(() => ({
  prisma: {
    profile: {
      findMany: vi.fn(),
      findFirst: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
    },
    tenantSubscription: {
      findUnique: vi.fn(),
    },
    tenant: {
      findUnique: vi.fn(),
    },
    syncRecord: {
      create: vi.fn(),
      findMany: vi.fn(),
      findFirst: vi.fn(),
      update: vi.fn(),
    },
    $transaction: vi.fn(),
  },
  tx: {
    profile: {
      findFirst: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
    },
    syncRecord: {
      update: vi.fn(),
    },
  },
  d1: {
    statements: [] as Array<{ sql: string; values: unknown[] }>,
    prepare: vi.fn(),
    batch: vi.fn(),
    firstResult: null as Record<string, unknown> | null,
  },
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: () => mocks.d1,
}));
vi.mock('../middleware/auth', () => ({
  authMiddleware: (_req: unknown, _res: unknown, next: () => void) => next(),
}));

describe('staff registration, pull and bootstrap contracts', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: tenantRoutes } = await import('../routes/tenant');
    app = express();
    app.use(express.json());
    app.use((req, _res, next) => {
      req.auth = {
        sub: 'owner-1',
        email: 'owner@example.com',
        email_verified: true,
        token_use: 'access',
      };
      if (req.path !== '/shops') {
        req.user = {
          id: 'owner-1',
          tenantId: 'tenant-1',
          role: req.header('x-test-role') ?? 'admin',
          name: 'Owner',
        };
      }
      next();
    });
    app.use('/tenant', tenantRoutes);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.d1.statements.length = 0;
    mocks.d1.prepare.mockImplementation((sql: string) => ({
      bind: (...values: unknown[]) => {
        const statement = { sql, values };
        mocks.d1.statements.push(statement);
        return {
          ...statement,
          first: async () => mocks.d1.firstResult,
        };
      },
    }));
    mocks.d1.firstResult = null;
    mocks.d1.batch.mockImplementation(async (statements: unknown[]) =>
      statements.map(() => ({ meta: { changes: 1 } })));
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      status: 'active',
      currentPeriodEnd: new Date(Date.now() + 60_000),
      graceUntil: null,
      priceMinor: null,
      currency: 'KES',
      billingInterval: 'monthly',
    });
    mocks.prisma.$transaction.mockImplementation(
      async (work: (tx: typeof mocks.tx) => Promise<unknown>) =>
        work(mocks.tx),
    );
    mocks.prisma.profile.findMany.mockResolvedValue([]);
    mocks.tx.profile.findFirst.mockResolvedValue(null);
    mocks.tx.profile.create.mockResolvedValue({
      id: 'remote-staff-1',
      localId: 7,
      name: 'Amina',
      username: 'amina',
      role: 'cashier',
      active: true,
    });
    mocks.prisma.syncRecord.create.mockResolvedValue({ id: 'request-1' });
  });

  it('lists account shops from the verified identity without a selected tenant profile', async () => {
    mocks.prisma.profile.findMany.mockResolvedValue([{
      tenantId: 'tenant-1',
      role: 'admin',
      tenant: { shopName: 'Main shop' },
    }]);

    const response = await supertest(app).get('/tenant/shops');

    expect(response.status).toBe(200);
    expect(response.body.shops).toEqual([{
      tenantId: 'tenant-1',
      shopName: 'Main shop',
      role: 'admin',
    }]);
    expect(mocks.prisma.profile.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({
        OR: expect.arrayContaining([
          { userId: 'owner-1' },
          { email: 'owner@example.com' },
        ]),
      }),
    }));
  });

  it('refuses provisioning when the requested owner email differs from OIDC', async () => {
    const response = await supertest(app).post('/tenant/provision').send({
      shopName: 'Shop',
      ownerName: 'Owner',
      email: 'other@example.com',
    });

    expect(response.status).toBe(403);
    expect(response.body.code).toBe('EMAIL_IDENTITY_MISMATCH');
    expect(mocks.prisma.$transaction).not.toHaveBeenCalled();
  });

  it('creates tenant, pending subscription, and owner profile in one D1 batch', async () => {
    mocks.prisma.profile.findFirst.mockResolvedValue(null);

    const response = await supertest(app).post('/tenant/provision').send({
      shopName: 'Fresh Shop',
      ownerName: 'Owner',
      email: 'owner@example.com',
      businessProfile: 'duka',
    });

    expect(response.status).toBe(200);
    expect(response.body.tenant_id).toBeTruthy();
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements.map((statement) => statement.sql)).toEqual([
      expect.stringContaining('INSERT INTO tenants'),
      expect.stringContaining('INSERT INTO tenant_subscriptions'),
      expect.stringContaining('INSERT INTO profiles'),
    ]);
    expect(mocks.d1.statements[1].sql).toContain('WHERE changes() = 1');
    expect(mocks.d1.statements[2].sql).toContain("SELECT ?, ?, ?, ?, ?, 'admin', ?");
  });

  it('updates tenant settings and business context in one D1 batch', async () => {
    mocks.prisma.tenant.findUnique.mockResolvedValue({
      id: 'tenant-1',
      shopName: 'Main shop',
      businessProfile: 'fashion',
      mpesaEnabled: false,
      etimsEnabled: false,
    });

    const response = await supertest(app).patch('/tenant/settings').send({
      businessProfile: 'fashion',
      mpesaEnabled: false,
    });

    expect(response.status).toBe(200);
    expect(response.body.businessProfile).toBe('fashion');
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements).toHaveLength(2);
    expect(mocks.d1.statements[0].sql).toContain('UPDATE tenants');
    expect(mocks.d1.statements[1].sql).toContain('UPDATE business_context');
  });

  for (const role of ['manager', 'cashier']) {
    it(`refuses staff roster changes from a ${role} session`, async () => {
      const response = await supertest(app)
        .post('/tenant/staff/sync')
        .set('x-test-role', role)
        .send({ staff: [] });

      expect(response.status).toBe(403);
      expect(response.body.error).toBe('Shop admin access required');
      expect(mocks.prisma.$transaction).not.toHaveBeenCalled();
    });
  }

  it('upserts a newly registered staff profile and returns its remote id',
    async () => {
      const response = await supertest(app).post('/tenant/staff/sync').send({
        staff: [{
          localId: 7,
          name: 'Amina',
          username: 'Amina',
          role: 'cashier',
          active: true,
          pinHash: null,
        }],
      });

      expect(response.status).toBe(200);
      expect(response.body.synced).toEqual([
        { localId: 7, remoteId: expect.any(String) },
      ]);
      expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
      expect(mocks.d1.statements[0].sql).toContain('INSERT INTO profiles');
      expect(mocks.d1.statements[0].values).toContain('amina');
      expect(mocks.d1.statements[0].values).toContain(null);
    });

  it('syncs Admin staff without matching an account owner profile', async () => {
    const response = await supertest(app).post('/tenant/staff/sync').send({
      staff: [{
        localId: 12,
        name: 'Operations Admin',
        username: 'ops-admin',
        role: 'admin',
        active: true,
        pinHash: null,
      }],
    });

    expect(response.status).toBe(200);
    expect(response.body.synced).toEqual([
      { localId: 12, remoteId: expect.any(String) },
    ]);
    expect(mocks.d1.statements[0].sql).toContain('INSERT INTO profiles');
    expect(mocks.d1.statements[0].values).toContain('admin');
    const roleFilter = mocks.prisma.profile.findMany.mock.calls[1][0].where.AND[0].OR;
    expect(roleFilter).toContainEqual({
      role: 'admin',
      userId: null,
      localId: { not: null },
    });
  });

  it('updates the remote PIN verifier when an existing local staff PIN changes', async () => {
    mocks.prisma.profile.findMany
      .mockResolvedValueOnce([{
        id: 'remote-staff-1',
        localId: 7,
        username: 'amina',
      }])
      .mockResolvedValueOnce([{
        id: 'remote-staff-1',
        localId: 7,
        role: 'cashier',
      }]);

    const response = await supertest(app).post('/tenant/staff/sync').send({
      staff: [{
        localId: 7,
        remoteId: 'remote-staff-1',
        name: 'Amina',
        username: 'amina',
        role: 'cashier',
        active: true,
        pinHash: 'pbkdf2$120000$c2FsdA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      }],
    });

    expect(response.status).toBe(200);
    expect(mocks.d1.statements[0].sql).toContain('pin_hash = COALESCE(?, pin_hash)');
    expect(mocks.d1.statements[0].values).toContain('pbkdf2$120000$c2FsdA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
  });

  it('pulls the tenant staff roster without returning PIN material', async () => {
    mocks.prisma.profile.findMany.mockResolvedValue([{
      id: 'remote-staff-1',
      localId: 7,
      name: 'Amina',
      username: 'amina',
      role: 'cashier',
      active: true,
      deletedAt: null,
    }]);

    const response = await supertest(app).get('/tenant/staff');

    expect(response.status).toBe(200);
    expect(response.body.staff).toEqual([{
      id: 'remote-staff-1',
      localId: 7,
      name: 'Amina',
      username: 'amina',
      role: 'cashier',
      active: true,
    }]);
    expect(response.body.staff[0]).not.toHaveProperty('pinHash');
  });

  it('reports soft-deleted profiles as inactive', async () => {
    mocks.prisma.profile.findMany.mockResolvedValue([{
      id: 'remote-staff-1',
      localId: 7,
      name: 'Deleted cashier',
      username: 'amina',
      role: 'cashier',
      active: true,
      deletedAt: new Date(),
    }]);

    const response = await supertest(app).get('/tenant/staff');

    expect(response.status).toBe(200);
    expect(response.body.staff).toEqual([{
      id: 'remote-staff-1',
      localId: 7,
      name: 'Deleted cashier',
      username: 'amina',
      role: 'cashier',
      active: false,
    }]);
  });

  it('accepts a returned CUID when the same staff row syncs again', async () => {
    mocks.prisma.profile.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([{
      id: 'clw7staffcuid123',
      localId: 7,
      role: 'cashier',
    }]);

    const response = await supertest(app).post('/tenant/staff/sync').send({
      staff: [{
        localId: 7,
        remoteId: 'clw7staffcuid123',
        name: 'Amina Updated',
        username: 'amina',
        role: 'manager',
        active: true,
        pinHash: null,
      }],
    });

    expect(response.status).toBe(200);
    expect(response.body.synced).toEqual([
      { localId: 7, remoteId: 'clw7staffcuid123' },
    ]);
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements[0].sql).toContain('UPDATE profiles');
    expect(mocks.d1.statements[0].values).toContain('manager');
    expect(mocks.d1.statements[0].values).not.toContain('5678');
  });

  it('authenticates a fresh till using the selected tenant and PIN verifier',
    async () => {
      const salt = randomBytes(16);
      const digest = pbkdf2Sync('123456', salt, 100000, 32, 'sha256');
      mocks.d1.firstResult = {
        id: 'remote-staff-1',
        local_id: 7,
        name: 'Amina',
        username: 'amina',
        role: 'cashier',
        active: true,
        pin_hash: [
          'pbkdf2',
          '100000',
          salt.toString('base64url'),
          digest.toString('base64url'),
        ].join('$'),
        shop_name: 'Main shop',
      };

      const response = await supertest(app)
        .post('/tenant/staff/authenticate')
        .set('x-tenant-id', 'tenant-1')
        .send({ username: 'Amina', pin: '123456' });

      expect(response.status).toBe(200);
      expect(response.body).toMatchObject({
        staff_id: 'remote-staff-1',
        local_id: 7,
        name: 'Amina',
        role: 'cashier',
        tenant_id: 'tenant-1',
        shop_name: 'Main shop',
      });
      expect(mocks.d1.statements[0].sql).toContain('p.pin_hash');
      expect(mocks.d1.statements[0].values).toEqual(['tenant-1', 'amina']);
      expect(response.body.session_token).toEqual(expect.any(String));
    });

  it('authenticates owner-created Admin staff with the app PIN hash work factor',
    async () => {
      const salt = randomBytes(16);
      const digest = pbkdf2Sync('123456', salt, 120000, 32, 'sha256');
      mocks.d1.firstResult = {
        id: 'remote-admin-staff',
        local_id: 12,
        name: 'Operations Admin',
        username: 'ops-admin',
        role: 'admin',
        active: true,
        pin_hash: `pbkdf2$120000$${salt.toString('base64url')}$${digest.toString('base64url')}`,
        shop_name: 'Main shop',
      };

      const response = await supertest(app)
        .post('/tenant/staff/authenticate')
        .set('x-tenant-id', 'tenant-1')
        .send({ username: 'ops-admin', pin: '123456' });

      expect(response.status).toBe(200);
      expect(response.body).toMatchObject({
        staff_id: 'remote-admin-staff',
        role: 'admin',
      });
      expect(mocks.d1.statements[0].sql).toContain("p.role = 'admin'");
    });

  it('rejects a wrong remote staff PIN without issuing a session', async () => {
    const salt = randomBytes(16);
    const digest = pbkdf2Sync('123456', salt, 100000, 32, 'sha256');
    mocks.d1.firstResult = {
      id: 'remote-staff-1',
      local_id: 7,
      name: 'Amina',
      username: 'amina',
      role: 'cashier',
      active: true,
      pin_hash: `pbkdf2$100000$${salt.toString('base64url')}$${digest.toString('base64url')}`,
      shop_name: 'Main shop',
    };

    const response = await supertest(app)
      .post('/tenant/staff/authenticate')
      .set('x-tenant-id', 'tenant-1')
      .send({ username: 'Amina', pin: '654321' });

    expect(response.status).toBe(401);
    expect(response.body.error).toBe('Invalid staff credentials');
  });

  it('lets a staff session change only that staff member PIN', async () => {
    const salt = randomBytes(16);
    const digest = pbkdf2Sync('1234', salt, 100000, 32, 'sha256');
    mocks.prisma.profile.findFirst.mockResolvedValue({
      id: 'remote-staff-1', tenantId: 'tenant-1', role: 'cashier', active: true,
      deletedAt: null,
      pinHash: ['pbkdf2', '100000', salt.toString('base64url'), digest.toString('base64url')].join('$'),
    });
    const { issueStaffSessionToken } = await import('../lib/jwt');
    const token = issueStaffSessionToken({ profileId: 'remote-staff-1', tenantId: 'tenant-1', userId: 'staff:remote-staff-1' }).token;
    const response = await supertest(app)
      .post('/tenant/staff/self-pin')
      .set('authorization', `Bearer ${token}`)
      .set('x-tenant-id', 'tenant-1')
      .send({ currentPin: '1234', newPin: '567890' });

    expect(response.status).toBe(200);
    expect(mocks.prisma.profile.update).toHaveBeenCalledWith({
      where: { id: 'remote-staff-1' },
      data: expect.objectContaining({
        pinHash: expect.stringMatching(/^pbkdf2\$v2\$sha256\$600000\$/),
        pinFormat: 'v2',
        pinFailedAttempts: 0,
        pinLockedUntil: null,
        pinCredentialVersion: { increment: 1 },
      }),
    });
  });

  it('redacts staff identity and ledger references in one D1 batch', async () => {
    mocks.prisma.profile.findFirst.mockResolvedValue({
      id: 'remote-staff-1',
      tenantId: 'tenant-1',
      role: 'cashier',
      deletedAt: null,
    });

    const response = await supertest(app)
      .delete('/tenant/staff/remote-staff-1')
      .send({ reason: 'Staff left the shop' });

    expect(response.status).toBe(200);
    expect(response.body).toEqual({ deleted: true, profile_id: 'remote-staff-1' });
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements).toHaveLength(4);
    expect(mocks.d1.statements[0].sql).toContain('UPDATE profiles');
    expect(mocks.d1.statements[1].sql).toContain('INSERT INTO deletion_ledgers');
    expect(mocks.d1.statements[2].sql).toContain('UPDATE sales');
    expect(mocks.d1.statements[3].sql).toContain('UPDATE payments');
  });

  it('creates a private forgotten-PIN request and lets the owner complete it', async () => {
    mocks.prisma.profile.findFirst.mockResolvedValue({
      id: 'remote-staff-1', localId: 7, name: 'Amina', role: 'cashier', active: true, deletedAt: null,
    });
    const requested = await supertest(app)
      .post('/tenant/staff/pin-reset-request')
      .set('x-tenant-id', 'tenant-1')
      .send({ username: 'Amina' });
    expect(requested.status).toBe(202);
    expect(requested.body).toEqual({ status: 'request_received' });
    expect(mocks.prisma.syncRecord.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({
        kind: 'staff_pin_reset_request',
        payload: expect.objectContaining({ status: 'pending', staffProfileId: 'remote-staff-1' }),
      }),
    }));
    const record = {
      id: 'request-1', tenantId: 'tenant-1', kind: 'staff_pin_reset_request',
      payload: { status: 'pending', staffProfileId: 'remote-staff-1', staffName: 'Amina' },
      createdAt: new Date(), updatedAt: new Date(),
    };
    mocks.prisma.syncRecord.findFirst.mockResolvedValue(record);
    const completed = await supertest(app)
      .post('/tenant/staff/pin-reset-requests/request-1/reset')
      .send({ temporaryPin: '567890' });
    expect(completed.status).toBe(200);
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements[0].sql).toContain('UPDATE profiles');
    expect(mocks.d1.statements[0].values[0]).toMatch(/^pbkdf2\$v2\$sha256\$600000\$/);
    expect(mocks.d1.statements[0].values[0]).not.toContain('567890');
    expect(JSON.parse(String(mocks.d1.statements[1].values[0]))).toMatchObject({
      status: 'completed',
    });
  });
});
