import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  prisma: {
    $transaction: vi.fn(),
  },
  tx: {
    product: {
      findFirst: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      upsert: vi.fn(),
    },
  },
}));

vi.mock('../lib/prisma', () => ({ prisma: mocks.prisma }));

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
    mocks.prisma.$transaction.mockImplementation(
      async (work: (tx: typeof mocks.tx) => Promise<unknown>) => work(mocks.tx),
    );
    mocks.tx.product.create.mockResolvedValue({ id: 'clw7productcuid123' });
    mocks.tx.product.upsert.mockResolvedValue({ id: 'clw7productcuid123' });
    mocks.tx.product.findFirst.mockResolvedValue({
      id: 'clw7productcuid123',
      tenantId: 'owner-shop-1234',
    });
    mocks.tx.product.update.mockResolvedValue({ id: 'clw7productcuid123' });
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
    expect(mocks.tx.product.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'clw7productcuid123' } }),
    );
  });
});
