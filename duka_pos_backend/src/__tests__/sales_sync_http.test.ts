import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  prisma: {
    sale: { findUnique: vi.fn() },
    product: { findMany: vi.fn() },
    shopTaxEntity: { findFirst: vi.fn() },
    taxRule: { findMany: vi.fn() },
    saleSyncConflict: { upsert: vi.fn(), findUnique: vi.fn(), update: vi.fn() },
  },
  d1: {
    statements: [] as Array<{ sql: string; values: unknown[] }>,
    saleChanges: 0,
    stockChanges: 0,
    prepare: vi.fn(),
    batch: vi.fn(),
  },
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: () => mocks.d1,
}));
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
    mocks.d1.statements.length = 0;
    mocks.d1.saleChanges = 0;
    mocks.d1.stockChanges = 0;
    mocks.d1.prepare.mockImplementation((sql: string) => ({
      bind: (...values: unknown[]) => {
        const statement = { sql, values };
        mocks.d1.statements.push(statement);
        return statement;
      },
    }));
    mocks.d1.batch.mockImplementation(async (statements: Array<{ sql: string }>) => {
      const hasConflictClaim = statements[0].sql.includes("SET status = 'resolving'");
      const hasStockUpdate = statements.some((statement) => statement.sql.includes('UPDATE products'));
      const isStandaloneConflictUpdate = !hasConflictClaim
        && statements.length === 1
        && statements[0].sql.includes('UPDATE sale_sync_conflicts');
      const stockIndex = hasConflictClaim ? 1 : 0;
      const saleIndex = hasConflictClaim ? 2 : hasStockUpdate ? 1 : 0;
      return statements.map((_, index) => ({
        meta: {
          changes: isStandaloneConflictUpdate && index === 0
            ? 1
            : hasConflictClaim && index === 0
            ? 1
            : hasStockUpdate && index === stockIndex
              ? mocks.d1.stockChanges
              : index === saleIndex
                ? mocks.d1.saleChanges
                : 1,
        },
      }));
    });
    mocks.prisma.sale.findUnique.mockResolvedValue(null);
    mocks.prisma.product.findMany.mockResolvedValue([{ id: 'product-1', bottleMl: 750 }]);
    mocks.prisma.shopTaxEntity.findFirst.mockResolvedValue(null);
    mocks.prisma.taxRule.findMany.mockResolvedValue([]);
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
    mocks.d1.saleChanges = 1;
    mocks.d1.stockChanges = 2;
    mocks.prisma.product.findMany.mockResolvedValue([
      { id: 'product-a', bottleMl: 750 },
      { id: 'product-z', bottleMl: 750 },
    ]);
    const multi = {
      ...sale,
      items: [
        { ...sale.items[0], productId: 'product-z' },
        { ...sale.items[0], productId: 'product-a' },
      ],
    };

    const response = await supertest(app).post('/sales/sync').send({ sales: [multi] });

    expect(response.status).toBe(200);
    const stockPayload = JSON.parse(String(mocks.d1.statements[0].values[0]));
    expect(stockPayload.map((entry: { id: string }) => entry.id))
      .toEqual(['product-a', 'product-z']);
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements[1].sql).toContain('changes() = 2');
  });

  it('accepts a sale conflict and resolves it in the same D1 batch', async () => {
    mocks.d1.saleChanges = 1;
    mocks.d1.stockChanges = 1;
    mocks.prisma.saleSyncConflict.findUnique.mockResolvedValue({
      status: 'open',
      payload: sale,
    });

    const response = await supertest(app)
      .post('/sales/sync/conflicts/resolve')
      .send({ device_id: 'till-2', local_id: 17, resolution: 'accept_negative_stock' });

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ resolved: true, resolution: 'accept_negative_stock' });
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements[0].sql).toContain("SET status = 'resolving'");
    expect(mocks.d1.statements[mocks.d1.statements.length - 2].sql).toContain("SET status = 'resolved'");
  });

  it('voids a sale conflict with a conditional D1 update', async () => {
    mocks.prisma.saleSyncConflict.findUnique.mockResolvedValue({ status: 'open', payload: sale });

    const response = await supertest(app)
      .post('/sales/sync/conflicts/resolve')
      .send({ device_id: 'till-2', local_id: 17, resolution: 'void' });

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ resolved: true, resolution: 'void', remoteId: null });
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements[0].sql).toContain("SET status = 'resolved'");
    expect(mocks.d1.statements[0].sql).toContain("resolution = ?");
  });
});
