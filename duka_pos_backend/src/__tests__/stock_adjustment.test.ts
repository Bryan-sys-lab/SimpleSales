import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  prisma: {
    $transaction: vi.fn(),
    product: { findFirst: vi.fn(), findMany: vi.fn() },
  },
  tx: {
    product: { updateMany: vi.fn(), findFirst: vi.fn() },
    stockAdjustment: { create: vi.fn() },
  },
}));

vi.mock('../lib/prisma', () => ({ prisma: mocks.prisma }));
describe('atomic stock adjustments', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: productRoutes } = await import('../routes/product');
    app = express();
    app.use(express.json());
    app.use((req, _res, next) => {
      req.user = { id: 'staff-1', tenantId: 'tenant-1', role: 'manager', name: 'Manager' };
      next();
    });
    app.use('/products', productRoutes);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.prisma.$transaction.mockImplementation(async (work: (tx: typeof mocks.tx) => Promise<unknown>) => work(mocks.tx));
    mocks.tx.product.updateMany.mockResolvedValue({ count: 1 });
    mocks.tx.stockAdjustment.create.mockResolvedValue({ id: 'adjustment-1' });
    mocks.prisma.product.findFirst.mockResolvedValue({ stockQty: 8 });
  });

  it('uses an atomic increment for a concurrent restock', async () => {
    const response = await supertest(app).post('/products/stock-adjust').send({
      product_id: '11111111-1111-4111-8111-111111111111',
      delta: 5,
      reason: 'Manual restock',
    });

    expect(response.status).toBe(200);
    expect(mocks.tx.product.updateMany).toHaveBeenCalledWith({
      where: {
        id: '11111111-1111-4111-8111-111111111111',
        tenantId: 'tenant-1',
      },
      data: { stockQty: { increment: 5 } },
    });
  });

  it('conditionally decrements stock so the last unit cannot be oversold', async () => {
    mocks.tx.product.updateMany.mockResolvedValue({ count: 0 });
    mocks.tx.product.findFirst.mockResolvedValue({ id: 'product-1' });

    const response = await supertest(app).post('/products/stock-adjust').send({
      product_id: '11111111-1111-4111-8111-111111111111',
      delta: -1,
    });

    expect(response.status).toBe(409);
    expect(mocks.tx.product.updateMany).toHaveBeenCalledWith({
      where: {
        id: '11111111-1111-4111-8111-111111111111',
        tenantId: 'tenant-1',
        stockQty: { gte: 1 },
      },
      data: { stockQty: { increment: -1 } },
    });
    expect(mocks.tx.stockAdjustment.create).not.toHaveBeenCalled();
  });

  it('accepts a fractional measured-goods adjustment', async () => {
    const response = await supertest(app).post('/products/stock-adjust').send({
      product_id: '11111111-1111-4111-8111-111111111111',
      delta: -0.5,
      reason: 'Tank spillage',
    });

    expect(response.status).toBe(200);
    expect(mocks.tx.product.updateMany).toHaveBeenCalledWith({
      where: {
        id: '11111111-1111-4111-8111-111111111111',
        tenantId: 'tenant-1',
        stockQty: { gte: 0.5 },
      },
      data: { stockQty: { increment: -0.5 } },
    });
  });

  it('returns bounded, resumable catalogue pages', async () => {
    mocks.prisma.product.findMany.mockResolvedValue([
      { id: 'p-2', name: 'B' },
      { id: 'p-3', name: 'C' },
    ]);

    const response = await supertest(app)
      .get('/products?limit=2&offset=2');

    expect(response.status).toBe(200);
    expect(response.body.products).toHaveLength(2);
    expect(response.body.nextOffset).toBe(4);
    expect(mocks.prisma.product.findMany).toHaveBeenCalledWith({
      where: { tenantId: 'tenant-1' },
      orderBy: [{ name: 'asc' }, { id: 'asc' }],
      skip: 2,
      take: 2,
    });
  });
});
