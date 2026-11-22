import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  prisma: {
    product: { findMany: vi.fn() },
  },
  d1: { prepare: vi.fn(), batch: vi.fn() },
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: () => mocks.d1,
}));

describe('product sync CUID contract', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: productRoutes } = await import('../routes/product');
    app = express();
    app.use(express.json());
    app.use((req, _res, next) => {
      req.user = {
        id: 'owner-1',
        tenantId: 'owner-shop-1234',
        role: 'admin',
        name: 'Owner',
      };
      next();
    });
    app.use('/products', productRoutes);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.prisma.product.findMany.mockResolvedValue([
      { id: 'clw7productcuid123' },
    ]);
    mocks.d1.prepare.mockImplementation((sql: string) => ({
      sql,
      bind: (...bindings: unknown[]) => ({ sql, bindings }),
    }));
    mocks.d1.batch.mockImplementation(async (statements: Array<{ sql: string }>) =>
      statements.map((statement) => statement.sql.includes('RETURNING id')
        ? { results: [{ id: 'clw7productcuid123' }], meta: { changes: 1 } }
        : { meta: { changes: 0 } }));
  });

  it('returns and accepts the CUID on the next catalogue sync', async () => {
    const first = await supertest(app).post('/products/sync').send({
      products: [{
        id: 7,
        syncKey: 'device-1:product-7',
        name: 'Mineral water',
        costPrice: 50,
        sellPrice: 80,
        stockQty: 10,
        reorderLevel: 2,
      }],
    });

    expect(first.status).toBe(200);
    expect(first.body.synced).toEqual([
      { localId: 7, remoteId: 'clw7productcuid123' },
    ]);

    const second = await supertest(app).post('/products/sync').send({
      products: [{
        id: 7,
        remoteId: 'clw7productcuid123',
        name: 'Mineral water updated',
        costPrice: 55,
        sellPrice: 85,
        stockQty: 10,
        reorderLevel: 2,
      }],
    });

    expect(second.status).toBe(200);
    expect(second.body.synced).toEqual([
      { localId: 7, remoteId: 'clw7productcuid123' },
    ]);
    const [update] = mocks.d1.batch.mock.calls[1][0];
    expect(update.sql).toContain('WHERE id = ? AND tenant_id = ?');
    expect(update.sql).not.toContain('stock_qty');
  });
});
