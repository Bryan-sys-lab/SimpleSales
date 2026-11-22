import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  prisma: {
    subscriptionPayment: { findUnique: vi.fn(), updateMany: vi.fn() },
    payment: { findUnique: vi.fn(), updateMany: vi.fn() },
    product: { findMany: vi.fn() },
  },
  d1: {
    statements: [] as Array<{ sql: string; values: unknown[] }>,
    prepare: vi.fn(),
    batch: vi.fn(),
  },
  queryTransactionStatus: vi.fn(),
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: () => mocks.d1,
}));
vi.mock('../services/payhero', () => ({
  queryTransactionStatus: mocks.queryTransactionStatus,
}));
vi.mock('../lib/observability', () => ({ log: vi.fn() }));

const salePayment = {
  id: 'payment-1',
  tenantId: 'tenant-1',
  initiatedBy: 'staff-1',
  staffName: 'Amina',
  reference: 'DUKA-00000000-0000-0000-0000-000000000001',
  status: 'PENDING',
  saleId: null,
  cartSnapshot: [{
    product_id: 'product-1',
    product_name: 'Water',
    qty: 1,
    unit_price: 10,
    unit_cost: 8,
  }],
};

describe('PayHero D1 settlement batches', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { handlePayheroCallback } = await import('../routes/payhero-callback');
    app = express();
    app.use(express.json());
    app.post('/callback', handlePayheroCallback);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.d1.statements.length = 0;
    mocks.d1.prepare.mockImplementation((sql: string) => ({
      bind: (...values: unknown[]) => {
        const statement = { sql, values };
        mocks.d1.statements.push(statement);
        return statement;
      },
    }));
    mocks.d1.batch.mockResolvedValue([{ meta: { changes: 1 } }, { meta: { changes: 1 } }]);
  });

  it('updates payment entitlement exactly once in one D1 batch', async () => {
    mocks.prisma.subscriptionPayment.findUnique.mockResolvedValue({
      id: 'subscription-payment-1',
      tenantId: 'tenant-1',
      durationMonths: 1,
      status: 'PENDING',
    });
    mocks.queryTransactionStatus.mockResolvedValue({
      status: 'SUCCESS',
      MpesaReceiptNumber: 'abc123',
    });

    const response = await supertest(app).post('/callback').send({
      ExternalReference: 'SUBS-00000000-0000-0000-0000-000000000001',
    });

    expect(response.status).toBe(200);
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements[0].sql).toContain("status <> 'SUCCESS'");
    expect(mocks.d1.statements[1].sql).toContain('WHERE changes() = 1');
    expect(mocks.d1.statements[1].sql).toContain('ON CONFLICT (tenant_id)');
    expect(mocks.d1.statements[0].values).toEqual(['ABC123', 'subscription-payment-1']);
  });

  it('finalizes sale, stock, items and payment in one D1 batch', async () => {
    const { finalizeSale } = await import('../routes/payhero-callback');
    mocks.prisma.payment.findUnique.mockResolvedValue(salePayment);
    mocks.prisma.product.findMany.mockResolvedValue([{ id: 'product-1' }]);

    const saleId = await finalizeSale(salePayment.id);

    expect(saleId).toEqual(expect.any(String));
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements).toHaveLength(5);
    expect(mocks.d1.statements[0].sql).toContain("SET status = 'PROCESSING'");
    expect(mocks.d1.statements[1].sql).toContain('json_each(?)');
    expect(mocks.d1.statements[2].sql).toContain('CASE WHEN changes() = ?');
    expect(mocks.d1.statements[4].sql).toContain("SET status = 'SUCCESS'");
  });

  it('returns the committed sale when a concurrent callback wins the claim', async () => {
    const { finalizeSale } = await import('../routes/payhero-callback');
    mocks.prisma.payment.findUnique
      .mockResolvedValueOnce(salePayment)
      .mockResolvedValueOnce({ saleId: 'sale-committed' });
    mocks.prisma.product.findMany.mockResolvedValue([{ id: 'product-1' }]);
    mocks.d1.batch.mockRejectedValue(new Error('constraint failed'));

    await expect(finalizeSale(salePayment.id)).resolves.toBe('sale-committed');
  });
});
