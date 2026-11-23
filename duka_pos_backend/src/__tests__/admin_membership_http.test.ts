import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  prisma: {
    membershipRequest: { findMany: vi.fn(), findUnique: vi.fn() },
    membershipOffer: { findUnique: vi.fn() },
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
  systemAdminMiddleware: (req: express.Request, _res: express.Response, next: () => void) => {
    req.auth = { sub: 'sales-admin-1' };
    next();
  },
}));

describe('admin membership offer routes', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: adminMembershipRoutes } = await import('../routes/admin_membership');
    app = express();
    app.use(express.json());
    app.use('/admin/membership', adminMembershipRoutes);
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
    mocks.d1.batch.mockResolvedValue([
      { meta: { changes: 0 } },
      { meta: { changes: 1 } },
      { meta: { changes: 1 } },
      { meta: { changes: 1 } },
    ]);
  });

  it('creates a revisioned offer with request features and records the audit event', async () => {
    mocks.prisma.membershipRequest.findUnique.mockResolvedValue({
      id: 'request-1',
      tenantId: 'tenant-1',
      features: ['Inventory', 'Reports'],
      status: 'pending',
    });
    mocks.prisma.membershipOffer.findUnique.mockResolvedValue({
      id: 'offer-1',
      requestId: 'request-1',
      revision: 1,
      status: 'offered',
      amountMinor: 15_000,
      currency: 'KES',
      termMonths: null,
      includedFeatures: ['Inventory', 'Reports'],
    });

    const response = await supertest(app)
      .post('/admin/membership/requests/request-1/offers')
      .send({
        amountMinor: 15_000,
        paymentArrangement: 'Pay by M-Pesa',
        renewalTerms: 'Renewal as agreed',
      });

    expect(response.status).toBe(201);
    expect(response.body.offer).toMatchObject({
      id: 'offer-1',
      revision: 1,
      amountMinor: 15_000,
    });
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements[1].sql).toContain('MAX(revision)');
    expect(mocks.d1.statements[1].values).toContain(
      JSON.stringify(['Inventory', 'Reports']),
    );
    expect(mocks.d1.statements[3].sql).toContain('admin_audit_logs');
  });

  it('rejects attempts to replace an already accepted agreement', async () => {
    mocks.prisma.membershipRequest.findUnique.mockResolvedValue({
      id: 'request-1',
      tenantId: 'tenant-1',
      features: [],
      status: 'accepted',
    });

    const response = await supertest(app)
      .post('/admin/membership/requests/request-1/offers')
      .send({
        amountMinor: 15_000,
        paymentArrangement: 'Pay by M-Pesa',
        renewalTerms: 'Renewal as agreed',
      });

    expect(response.status).toBe(409);
    expect(mocks.d1.batch).not.toHaveBeenCalled();
  });
});
