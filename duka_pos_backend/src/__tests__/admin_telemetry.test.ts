import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {
    telemetryEvent: { findMany: vi.fn() },
  },
  database: {
    prepare: vi.fn(),
    batch: vi.fn(),
  },
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

describe('admin telemetry event listing', () => {
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
  });

  it('returns a filtered, cursor-paginated event page without telemetry details', async () => {
    const first = {
      id: 'event-2',
      tenantId: 'shop-1',
      deviceId: 'hashed-device',
      sessionJti: 'session-id',
      name: 'app_open',
      at: new Date('2026-11-23T12:00:00.000Z'),
      route: '/home',
      createdAt: new Date('2026-11-23T12:00:01.000Z'),
      tenant: { id: 'shop-1', shopName: 'Main shop' },
    };
    const next = { ...first, id: 'event-1' };
    mocks.prisma.telemetryEvent.findMany.mockResolvedValue([first, next]);

    const response = await supertest(app)
      .get('/admin/telemetry/events')
      .query({
        tenantId: 'shop-1',
        name: 'app_open',
        from: '2026-11-23T00:00:00.000Z',
        to: '2026-11-23T23:59:59.999Z',
        limit: '1',
      });

    expect(response.status).toBe(200);
    expect(response.body.events).toHaveLength(1);
    expect(response.body.events[0]).toMatchObject({
      id: 'event-2',
      name: 'app_open',
      tenant: { shopName: 'Main shop' },
    });
    expect(response.body.events[0]).not.toHaveProperty('detail');
    expect(response.body.nextCursor).toBe('event-2');
    expect(mocks.prisma.telemetryEvent.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: {
        tenantId: 'shop-1',
        name: 'app_open',
        at: {
          gte: new Date('2026-11-23T00:00:00.000Z'),
          lte: new Date('2026-11-23T23:59:59.999Z'),
        },
      },
      take: 2,
    }));
  });

  it('rejects a reversed date range', async () => {
    const response = await supertest(app)
      .get('/admin/telemetry/events')
      .query({
        from: '2026-11-24T00:00:00.000Z',
        to: '2026-11-23T00:00:00.000Z',
      });

    expect(response.status).toBe(400);
    expect(mocks.prisma.telemetryEvent.findMany).not.toHaveBeenCalled();
  });
});
