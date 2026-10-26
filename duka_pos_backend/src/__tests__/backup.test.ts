import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {
    cloudBackup: {
      create: vi.fn(),
      findMany: vi.fn(),
      deleteMany: vi.fn(),
      findFirst: vi.fn(),
    },
  },
  putOpaqueBackup: vi.fn(),
  getOpaqueBackup: vi.fn(),
  deleteOpaqueBackup: vi.fn(),
}));

vi.mock('../lib/prisma', () => ({ prisma: mocks.prisma }));
vi.mock('../lib/r2', () => ({
  putOpaqueBackup: mocks.putOpaqueBackup,
  getOpaqueBackup: mocks.getOpaqueBackup,
  deleteOpaqueBackup: mocks.deleteOpaqueBackup,
}));
vi.mock('../middleware/auth', () => ({
  requireRole: () => (req: any, _res: any, next: () => void) => {
    req.user = { id: 'profile-1', tenantId: 'tenant-1', role: 'admin', name: 'Owner' };
    next();
  },
}));

describe('cloud backup storage', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: backupRoutes } = await import('../routes/backup');
    app = express();
    app.use(express.json());
    app.use('/backups/full', backupRoutes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.prisma.cloudBackup.findMany.mockResolvedValue([]);
    mocks.prisma.cloudBackup.deleteMany.mockResolvedValue({ count: 0 });
    mocks.prisma.cloudBackup.create.mockResolvedValue({
      id: 'backup-1',
      workspaceKey: 'shop one',
      kind: 'device_bound',
      createdAt: new Date('2026-10-24T00:00:00.000Z'),
    });
  });

  it('stores new ciphertext in R2 and only an empty legacy field in Postgres', async () => {
    const response = await supertest(app).post('/backups/full').send({
      workspaceKey: 'shop one',
      payload: 'opaque-ciphertext',
    });

    expect(response.status).toBe(201);
    expect(mocks.putOpaqueBackup).toHaveBeenCalledWith(
      expect.stringMatching(/^backups\/tenant-1\/shop%20one\/.+\.duka$/),
      'opaque-ciphertext',
    );
    expect(mocks.prisma.cloudBackup.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({
        tenantId: 'tenant-1',
        workspaceKey: 'shop one',
        kind: 'device_bound',
        payload: '',
        storageKey: expect.stringMatching(/^backups\/tenant-1\//),
      }),
    }));
  });

  it('returns the existing row when the same snapshot is retried', async () => {
    const snapshotHash = 'a'.repeat(64);
    mocks.prisma.cloudBackup.findFirst.mockResolvedValueOnce({
      id: 'existing',
      workspaceKey: 'shop one',
      kind: 'device_bound',
      createdAt: new Date('2026-10-24T00:00:00.000Z'),
    });

    const response = await supertest(app).post('/backups/full').send({
      workspaceKey: 'shop one',
      payload: 'same-opaque-ciphertext',
      snapshotHash,
    });

    expect(response.status).toBe(200);
    expect(response.body.id).toBe('existing');
    expect(mocks.putOpaqueBackup).not.toHaveBeenCalled();
    expect(mocks.prisma.cloudBackup.create).not.toHaveBeenCalled();
  });

  it('rejects a malformed snapshot hash before storing ciphertext', async () => {
    const response = await supertest(app).post('/backups/full').send({
      workspaceKey: 'shop one',
      payload: 'opaque-ciphertext',
      snapshotHash: 'not-a-sha256',
    });

    expect(response.status).toBe(400);
    expect(mocks.putOpaqueBackup).not.toHaveBeenCalled();
  });

  it('reads new R2-backed snapshots and legacy database snapshots', async () => {
    mocks.prisma.cloudBackup.findFirst
      .mockResolvedValueOnce({
        id: 'new',
        workspaceKey: 'shop one',
        kind: 'device_bound',
        payload: '',
        storageKey: 'backups/tenant-1/shop%20one/new.duka',
        createdAt: new Date('2026-10-24T00:00:00.000Z'),
      })
      .mockResolvedValueOnce({
        id: 'old',
        workspaceKey: 'shop one',
        kind: 'device_bound',
        payload: 'legacy-ciphertext',
        storageKey: null,
        createdAt: new Date('2026-10-23T00:00:00.000Z'),
      });
    mocks.getOpaqueBackup.mockResolvedValue('r2-ciphertext');

    const r2Response = await supertest(app).get('/backups/full').query({ workspaceKey: 'shop one' });
    const legacyResponse = await supertest(app).get('/backups/full').query({ workspaceKey: 'shop one' });

    expect(r2Response.body.payload).toBe('r2-ciphertext');
    expect(legacyResponse.body.payload).toBe('legacy-ciphertext');
    expect(mocks.getOpaqueBackup).toHaveBeenCalledWith('backups/tenant-1/shop%20one/new.duka');
  });

  it('removes retained R2 objects when metadata rows rotate out', async () => {
    mocks.prisma.cloudBackup.findMany.mockResolvedValue([
      { id: 'old-1', storageKey: 'backups/old-1.duka' },
      { id: 'old-2', storageKey: null },
    ]);

    await supertest(app).post('/backups/full').send({
      workspaceKey: 'shop one',
      payload: 'opaque-ciphertext',
    });

    expect(mocks.prisma.cloudBackup.deleteMany).toHaveBeenCalledWith({
      where: { id: { in: ['old-1', 'old-2'] } },
    });
    expect(mocks.deleteOpaqueBackup).toHaveBeenCalledWith('backups/old-1.duka');
  });

  it('selects a portable backup separately from device-bound automatic copies', async () => {
    mocks.prisma.cloudBackup.findFirst.mockResolvedValue({
      id: 'portable',
      workspaceKey: 'shop one',
      kind: 'portable',
      payload: '',
      storageKey: 'backups/portable.duka',
      createdAt: new Date('2026-10-24T00:00:00.000Z'),
    });
    mocks.getOpaqueBackup.mockResolvedValue('portable-ciphertext');

    const response = await supertest(app)
      .get('/backups/full')
      .query({ workspaceKey: 'shop one', kind: 'portable' });

    expect(response.status).toBe(200);
    expect(response.body.kind).toBe('portable');
    expect(response.body.payload).toBe('portable-ciphertext');
    expect(mocks.prisma.cloudBackup.findFirst).toHaveBeenCalledWith(expect.objectContaining({
      where: { tenantId: 'tenant-1', workspaceKey: 'shop one', kind: 'portable' },
    }));
  });
});
