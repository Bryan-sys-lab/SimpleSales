import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  prisma: {
    $transaction: vi.fn(),
    sale: { findUnique: vi.fn() },
    saleSyncConflict: { upsert: vi.fn(), findUnique: vi.fn(), update: vi.fn() },
  },
  tx: {
    sale: { findUnique: vi.fn(), create: vi.fn() },
    product: { findMany: vi.fn(), updateMany: vi.fn() },
    saleSyncConflict: { update: vi.fn() },
  },
}));

vi.mock('../lib/prisma', () => ({ prisma: mocks.prisma }));
vi.mock('../middleware/auth', () => ({
  requireRole: () => (req: any, _res: any, next: () => void) => {
    req.user = { id: 'manager-1', tenantId: 'tenant-1', role: 'manager', name: 'Manager' };
    next();
  },
}));

const sale = {
  localId: 17,
  deviceId: 'till-2',
  staffName: 'Cashier',
  paymentMethod: 'cash',
  total: 1000,
  profit: 200,
  amountTendered: 1000,
  changeGiven: 0,
  createdAt: '2026-10-24T10:00:00.000Z',
  items: [{
    productId: 'product-1',
    productName: 'Water',
    qty: 1,
    unitPrice: 1000,
    unitCost: 800,
    portion: 'full',
    portionMl: 0,
  }],
};

describe('offline sale conflict boundary', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: salesRoutes } = await import('../routes/sales');
    app = express();
    app.use(express.json());
    app.use((req, _res, next) => {
      req.user = { id: 'cashier-1', tenantId: 'tenant-1', role: 'cashier', name: 'Cashier' };
      next();
    });
    app.use('/sales', salesRoutes);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.prisma.$transaction.mockImplementation(async (work: (tx: typeof mocks.tx) => Promise<unknown>) => work(mocks.tx));
    mocks.tx.sale.findUnique.mockResolvedValue(null);
    mocks.tx.product.findMany.mockResolvedValue([{ id: 'product-1', bottleMl: 750 }]);
    mocks.tx.product.updateMany.mockResolvedValue({ count: 0 });
    mocks.prisma.saleSyncConflict.upsert.mockResolvedValue({ id: 'conflict-1' });
  });

  it('retains a stock-race loser in the tenant conflict ledger', async () => {
    const response = await supertest(app).post('/sales/sync').send({ sales: [sale] });

    expect(response.status).toBe(200);
    expect(response.body.synced).toEqual([]);
    expect(response.body.conflicts).toEqual([{
      localId: 17,
      reason: 'Insufficient stock; another till recorded the sale first',
    }]);
    expect(mocks.prisma.saleSyncConflict.upsert).toHaveBeenCalledWith(expect.objectContaining({
      where: { tenantId_deviceId_localId: { tenantId: 'tenant-1', deviceId: 'till-2', localId: 17 } },
      create: expect.objectContaining({ tenantId: 'tenant-1', deviceId: 'till-2', localId: 17 }),
    }));
  });

  it('updates products in the same order for a multi-product sale', async () => {
    mocks.tx.product.findMany.mockResolvedValue([
      { id: 'product-a', bottleMl: 750 },
      { id: 'product-z', bottleMl: 750 },
    ]);
    mocks.tx.product.updateMany.mockResolvedValue({ count: 1 });
    mocks.tx.sale.create.mockResolvedValue({ id: 'remote-sale-1' });
    const multi = {
      ...sale,
      items: [
        { ...sale.items[0], productId: 'product-z' },
        { ...sale.items[0], productId: 'product-a' },
      ],
    };

    const response = await supertest(app).post('/sales/sync').send({ sales: [multi] });

    expect(response.status).toBe(200);
    expect(mocks.tx.product.updateMany.mock.calls.map(([args]) => args.where.id))
      .toEqual(['product-a', 'product-z']);
  });
});
