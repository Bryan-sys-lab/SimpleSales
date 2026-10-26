import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {
    syncRecord: { upsert: vi.fn() },
    $transaction: vi.fn(),
  },
}));

vi.mock('../lib/prisma', () => ({ prisma: mocks.prisma }));
vi.mock('../middleware/auth', () => ({
  requireRole: () => (req: any, _res: any, next: () => void) => {
    req.user = { id: 'profile-1', tenantId: 'tenant-1', role: 'admin', name: 'Owner' };
    next();
  },
}));

describe('financial evidence sync', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: evidenceRoutes } = await import('../routes/evidence');
    app = express();
    app.use(express.json());
    app.use('/evidence', evidenceRoutes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.prisma.$transaction.mockImplementation(async (callback: any) =>
      callback({
        syncRecord: {
          upsert: vi.fn().mockResolvedValue({ id: 'evidence-1' }),
        },
      }),
    );
  });

  it('accepts only sanitized financial facts and stores a server hash', async () => {
    const response = await supertest(app).post('/evidence/sync').send({
      deviceId: 'device-a',
      events: [{
        localId: 1,
        uuid: 'event-1',
        eventType: 'sale',
        sourceType: 'sale',
        sourceId: 7,
        occurredAtUtc: '2026-10-26T00:00:00.000Z',
        revenueMinor: 200,
        cashInMinor: 200,
        cashOutMinor: 0,
        cogsMinor: 100,
        operatingExpenseMinor: 0,
        taxCollectedMinor: 0,
        receivableDeltaMinor: 0,
        payableDeltaMinor: 0,
        customerDepositDeltaMinor: 0,
        inventoryDeltaMilliunits: -1000,
        previousHash: null,
        integrityHash: 'a'.repeat(64),
      }],
    });

    expect(response.status).toBe(200);
    expect(response.body.synced[0].serverIntegrityHash).toMatch(/^[a-f0-9]{64}$/);
    const upsert = mocks.prisma.$transaction.mock.calls[0][0];
    expect(upsert).toBeTypeOf('function');
  });

  it('rejects customer fields instead of allowing them into evidence', async () => {
    const response = await supertest(app).post('/evidence/sync').send({
      deviceId: 'device-a',
      events: [{
        localId: 1,
        uuid: 'event-1',
        eventType: 'sale',
        sourceType: 'sale',
        occurredAtUtc: '2026-10-26T00:00:00.000Z',
        revenueMinor: 200,
        cashInMinor: 200,
        cashOutMinor: 0,
        cogsMinor: 100,
        operatingExpenseMinor: 0,
        taxCollectedMinor: 0,
        receivableDeltaMinor: 0,
        payableDeltaMinor: 0,
        customerDepositDeltaMinor: 0,
        inventoryDeltaMilliunits: -1000,
        integrityHash: 'a'.repeat(64),
        customerName: 'must-not-cross-boundary',
      }],
    });

    expect(response.status).toBe(400);
    expect(mocks.prisma.$transaction).not.toHaveBeenCalled();
  });
});
