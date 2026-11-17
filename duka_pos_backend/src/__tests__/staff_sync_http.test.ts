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
}));

vi.mock('../lib/prisma', () => ({ prisma: mocks.prisma }));
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
      req.user = {
        id: 'owner-1',
        tenantId: 'tenant-1',
        role: 'admin',
        name: 'Owner',
      };
      next();
    });
    app.use('/tenant', tenantRoutes);
  });

  beforeEach(() => {
    vi.clearAllMocks();
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
        { localId: 7, remoteId: 'remote-staff-1' },
      ]);
      expect(mocks.tx.profile.create).toHaveBeenCalledWith({
        data: {
          tenantId: 'tenant-1',
          localId: 7,
          name: 'Amina',
          username: 'amina',
          role: 'cashier',
          active: true,
        },
      });
    });

  it('pulls the tenant staff roster without returning PIN material', async () => {
    mocks.prisma.profile.findMany.mockResolvedValue([{
      id: 'remote-staff-1',
      localId: 7,
      name: 'Amina',
      username: 'amina',
      role: 'cashier',
      active: true,
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

  it('accepts a returned CUID when the same staff row syncs again', async () => {
    mocks.tx.profile.findFirst.mockResolvedValue({
      id: 'clw7staffcuid123',
      tenantId: 'tenant-1',
      role: 'cashier',
    });
    mocks.tx.profile.update.mockResolvedValue({
      id: 'clw7staffcuid123',
      localId: 7,
    });

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
    expect(mocks.tx.profile.update).toHaveBeenCalledWith(expect.objectContaining({
      where: { id: 'clw7staffcuid123' },
      data: expect.objectContaining({ role: 'manager' }),
    }));
    expect(mocks.tx.profile.update.mock.calls[0][0].data).not.toHaveProperty('pinHash');
  });

  it('authenticates a fresh till using the selected tenant and PIN verifier',
    async () => {
      const salt = randomBytes(16);
      const digest = pbkdf2Sync('123456', salt, 120000, 32, 'sha256');
      mocks.prisma.profile.findFirst.mockResolvedValue({
        id: 'remote-staff-1',
        localId: 7,
        name: 'Amina',
        username: 'amina',
        role: 'cashier',
        active: true,
        deletedAt: null,
        tenantId: 'tenant-1',
        pinHash: [
          'pbkdf2',
          '120000',
          salt.toString('base64url'),
          digest.toString('base64url'),
        ].join('$'),
        tenant: { shopName: 'Main shop' },
      });

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
      expect(mocks.prisma.profile.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            tenantId: 'tenant-1',
            username: 'amina',
          }),
        }),
      );
      expect(response.body.session_token).toEqual(expect.any(String));
    });

  it('lets a staff session change only that staff member PIN', async () => {
    const salt = randomBytes(16);
    const digest = pbkdf2Sync('1234', salt, 120000, 32, 'sha256');
    mocks.prisma.profile.findFirst.mockResolvedValue({
      id: 'remote-staff-1', tenantId: 'tenant-1', role: 'cashier', active: true,
      deletedAt: null,
      pinHash: ['pbkdf2', '120000', salt.toString('base64url'), digest.toString('base64url')].join('$'),
    });
    const { issueStaffSessionToken } = await import('../lib/jwt');
    const token = issueStaffSessionToken({ profileId: 'remote-staff-1', tenantId: 'tenant-1', userId: 'staff:remote-staff-1' }).token;
    const response = await supertest(app)
      .post('/tenant/staff/self-pin')
      .set('authorization', `Bearer ${token}`)
      .set('x-tenant-id', 'tenant-1')
      .send({ currentPin: '1234', newPin: '5678' });

    expect(response.status).toBe(200);
    expect(mocks.prisma.profile.update).toHaveBeenCalledWith({
      where: { id: 'remote-staff-1' },
      data: { pinHash: expect.stringMatching(/^pbkdf2\$/) },
    });
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
    mocks.tx.profile.update.mockResolvedValue({ id: 'remote-staff-1' });
    const completed = await supertest(app)
      .post('/tenant/staff/pin-reset-requests/request-1/reset')
      .send({ temporaryPin: '5678' });
    expect(completed.status).toBe(200);
    expect(mocks.tx.profile.update.mock.calls[0][0].data.pinHash).toMatch(/^pbkdf2\$/);
    expect(mocks.tx.profile.update.mock.calls[0][0].data.pinHash).not.toContain('5678');
    expect(mocks.tx.syncRecord.update).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ payload: expect.objectContaining({ status: 'completed' }) }),
    }));
  });
});
