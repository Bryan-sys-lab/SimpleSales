import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {
  },
  d1: { prepare: vi.fn(), batch: vi.fn() },
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: () => mocks.d1,
}));
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
    mocks.d1.prepare.mockImplementation((sql: string) => ({
      sql,
      bind: (...bindings: unknown[]) => ({ sql, bindings }),
    }));
    mocks.d1.batch.mockImplementation(async (statements: unknown[]) =>
      statements.map(() => ({ results: [{ id: 'evidence-1' }], meta: { changes: 1 } })));
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
    const [statement] = mocks.d1.batch.mock.calls[0][0];
    expect(statement.sql).toContain('ON CONFLICT (tenant_id, kind, device_id, local_id)');
    expect(statement.sql).toContain('RETURNING id');
    const payload = JSON.parse(statement.bindings[5] as string);
    expect(payload.clientIntegrityHash).toBe('a'.repeat(64));
    expect(payload.serverIntegrityHash).toBe(response.body.synced[0].serverIntegrityHash);
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
    expect(mocks.d1.batch).not.toHaveBeenCalled();
  });
});
