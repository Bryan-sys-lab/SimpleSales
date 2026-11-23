import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {
    telemetryEvent: { count: vi.fn(), groupBy: vi.fn(), findMany: vi.fn() },
    deviceDiagnostic: { count: vi.fn() },
    deviceCrashEntry: { groupBy: vi.fn() },
    tenant: { findMany: vi.fn() },
    sale: { groupBy: vi.fn() },
  },
  database: { prepare: vi.fn(), batch: vi.fn() },
  statement: { bind: vi.fn(), all: vi.fn() },
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: () => mocks.database,
}));
vi.mock('../middleware/auth', () => ({
  authMiddleware: (_req: unknown, _res: unknown, next: () => void) => next(),
  requireRole: () => (_req: unknown, _res: unknown, next: () => void) => next(),
  systemAdminMiddleware: (req: express.Request, _res: unknown, next: () => void) => {
    req.auth = { sub: 'admin-1' };
    next();
  },
}));
vi.mock('../services/payhero', () => ({
  registerPaymentChannel: vi.fn(),
}));
vi.mock('../lib/email_sender', () => ({
  createCloudflareEmailTransport: () => ({ configured: false, send: vi.fn() }),
}));
vi.mock('../lib/entitlements', () => ({
  generateVoucher: vi.fn(),
}));

describe('admin observability summaries', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: adminRoutes } = await import('../routes/admin');
    app = express();
    app.use(express.json());
    app.use('/admin', adminRoutes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.database.prepare.mockReturnValue(mocks.statement);
    mocks.statement.bind.mockReturnValue(mocks.statement);
    mocks.statement.all.mockResolvedValue({
      results: [{ hour: '2026-11-23T12:00:00Z', count: 7 }],
    });
  });

  it('returns an aggregate telemetry trend and top event types', async () => {
    mocks.prisma.telemetryEvent.count.mockResolvedValue(7);
    mocks.prisma.telemetryEvent.groupBy.mockResolvedValue([
      { name: 'app_open', _count: { _all: 5 } },
      { name: 'screen_view', _count: { _all: 2 } },
    ]);

    const response = await supertest(app).get('/admin/observability/telemetry?range=24h');

    expect(response.status).toBe(200);
    expect(response.body.eventCount).toBe(7);
    expect(response.body.eventTypes).toEqual([
      { name: 'app_open', count: 5 },
      { name: 'screen_view', count: 2 },
    ]);
    expect(response.body.trend).toEqual([{ hour: '2026-11-23T12:00:00Z', count: 7 }]);
    expect(mocks.database.prepare).toHaveBeenCalledOnce();
  });

  it('returns device totals and failure counts by kind', async () => {
    mocks.prisma.deviceDiagnostic.count.mockResolvedValue(3);
    mocks.prisma.deviceCrashEntry.groupBy.mockResolvedValue([
      { kind: 'crash', _count: { _all: 2 } },
      { kind: 'error', _count: { _all: 4 } },
    ]);

    const response = await supertest(app).get('/admin/observability/diagnostics?range=7d');

    expect(response.status).toBe(200);
    expect(response.body.deviceCount).toBe(3);
    expect(response.body.entries).toEqual([
      { kind: 'crash', count: 2 },
      { kind: 'error', count: 4 },
    ]);
  });

  it('limits tenant results and reports 30-day sale activity separately from all-time counts', async () => {
    mocks.prisma.tenant.findMany.mockResolvedValue([{
      id: 'tenant-1',
      shopName: 'Shop One',
      _count: { profiles: 3, sales: 42 },
    }]);
    mocks.prisma.sale.groupBy.mockResolvedValue([{
      tenantId: 'tenant-1',
      _count: { _all: 5 },
      _max: { createdAt: new Date('2026-11-25T10:00:00.000Z') },
    }]);

    const response = await supertest(app).get('/admin/tenants?limit=1&activity=30d');

    expect(response.status).toBe(200);
    expect(response.body.tenants).toEqual([{
      id: 'tenant-1',
      shopName: 'Shop One',
      _count: { profiles: 3, sales: 42 },
      activity30d: { salesCount: 5, lastSaleAt: '2026-11-25T10:00:00.000Z' },
    }]);
    expect(mocks.prisma.tenant.findMany).toHaveBeenCalledWith(expect.objectContaining({ take: 1 }));
    expect(mocks.prisma.sale.groupBy).toHaveBeenCalledWith(expect.objectContaining({
      by: ['tenantId'],
      _count: { _all: true },
      _max: { createdAt: true },
      where: {
        tenantId: { in: ['tenant-1'] },
        createdAt: { gte: expect.any(Date) },
      },
    }));
  });

  it('rejects malformed tenant limits without querying the directory', async () => {
    const response = await supertest(app).get('/admin/tenants?limit=0');

    expect(response.status).toBe(400);
    expect(mocks.prisma.tenant.findMany).not.toHaveBeenCalled();
  });
});
