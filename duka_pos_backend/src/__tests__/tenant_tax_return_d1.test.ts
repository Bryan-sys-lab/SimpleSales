import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  prisma: {
    shopTaxEntity: { findFirst: vi.fn() },
    vatReturn: { findUnique: vi.fn() },
    totReturn: { findUnique: vi.fn() },
  },
  d1: {
    statements: [] as Array<{ sql: string; values: unknown[] }>,
    prepare: vi.fn(),
    batch: vi.fn(),
  },
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: () => mocks.d1,
}));
vi.mock('../middleware/auth', () => ({
  authMiddleware: (req: any, _res: any, next: () => void) => {
    req.user = { id: 'owner-1', tenantId: 'tenant-1', role: 'admin', name: 'Owner' };
    next();
  },
}));

const current = {
  id: 'return-1',
  taxEntityId: 'tax-1',
  status: 'prepared',
  outputVat: 100,
  eligibleInputVat: 20,
  adjustments: 0,
  withholdingVatCredit: 0,
  netPayable: 80,
  evidence: {},
  submittedAt: null,
  acceptedAt: null,
  paidAt: null,
  rejectionReason: null,
  createdAt: new Date('2026-01-01T00:00:00.000Z'),
  updatedAt: new Date('2026-01-01T00:00:00.000Z'),
};

describe('tax return status D1 batches', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: tenantRoutes } = await import('../routes/tenant');
    app = express();
    app.use(express.json());
    app.use('/tenant', tenantRoutes);
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
    mocks.prisma.shopTaxEntity.findFirst.mockResolvedValue({ taxEntityId: 'tax-1' });
  });

  it('updates VAT return status and audit event atomically', async () => {
    mocks.prisma.vatReturn.findUnique
      .mockResolvedValueOnce(current)
      .mockResolvedValueOnce({ ...current, status: 'submitted' });

    const response = await supertest(app).post('/tenant/tax-entity/vat-return/status').send({
      periodStart: '2026-01-01T00:00:00.000Z',
      periodEnd: '2026-02-01T00:00:00.000Z',
      status: 'submitted',
    });

    expect(response.status).toBe(200);
    expect(response.body.vat_return.status).toBe('submitted');
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements[0].sql).toContain('UPDATE vat_returns');
    expect(mocks.d1.statements[1].sql).toContain('vat_return_id');
    expect(mocks.d1.statements[1].sql).toContain('WHERE changes() = 1');
  });

  it('updates TOT return status and writes the matching event relation', async () => {
    mocks.prisma.totReturn.findUnique
      .mockResolvedValueOnce(current)
      .mockResolvedValueOnce({ ...current, status: 'submitted' });

    const response = await supertest(app).post('/tenant/tax-entity/tot-return/status').send({
      periodStart: '2026-01-01T00:00:00.000Z',
      periodEnd: '2026-02-01T00:00:00.000Z',
      status: 'submitted',
    });

    expect(response.status).toBe(200);
    expect(response.body.tot_return.status).toBe('submitted');
    expect(mocks.d1.statements[0].sql).toContain('UPDATE tot_returns');
    expect(mocks.d1.statements[1].sql).toContain('tot_return_id');
  });
});
