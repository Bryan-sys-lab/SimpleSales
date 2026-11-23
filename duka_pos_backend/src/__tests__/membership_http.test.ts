import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  role: 'admin',
  prisma: {
    membershipRequest: { findMany: vi.fn(), findFirst: vi.fn(), create: vi.fn() },
    membershipOffer: { findFirst: vi.fn() },
    tenantSubscription: { findUnique: vi.fn() },
    membershipAgreement: { findMany: vi.fn() },
    subscriptionPayment: { findMany: vi.fn() },
    accessVoucher: { findMany: vi.fn() },
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
  authMiddleware: (req: express.Request, _res: express.Response, next: () => void) => {
    req.user = { id: 'profile-1', tenantId: 'tenant-1', role: mocks.role, name: 'Owner' };
    next();
  },
}));

describe('customer membership quote routes', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: membershipRoutes } = await import('../routes/membership');
    app = express();
    app.use(express.json());
    app.use('/tenant/membership', (req, _res, next) => {
      req.user = {
        id: 'profile-1',
        tenantId: 'tenant-1',
        role: mocks.role,
        name: 'Owner',
      };
      next();
    }, membershipRoutes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.role = 'admin';
    mocks.d1.statements.length = 0;
    mocks.d1.prepare.mockImplementation((sql: string) => ({
      bind: (...values: unknown[]) => {
        const statement = { sql, values };
        mocks.d1.statements.push(statement);
        return statement;
      },
    }));
    mocks.d1.batch.mockResolvedValue([
      { meta: { changes: 1 } },
      { meta: { changes: 1 } },
      { meta: { changes: 1 } },
      { meta: { changes: 1 } },
    ]);
  });

  it('requires a shop owner to create a membership request', async () => {
    mocks.role = 'cashier';

    const response = await supertest(app)
      .post('/tenant/membership/requests')
      .send({ features: ['Inventory'] });

    expect(response.status).toBe(403);
    expect(mocks.prisma.membershipRequest.create).not.toHaveBeenCalled();
  });

  it('creates a dedicated request in the authenticated tenant', async () => {
    mocks.prisma.membershipRequest.create.mockResolvedValue({
      id: 'request-1',
      tenantId: 'tenant-1',
      requestedBy: 'profile-1',
      features: ['Inventory'],
      requirements: 'Train two staff',
      status: 'pending',
    });

    const response = await supertest(app)
      .post('/tenant/membership/requests')
      .send({ features: ['Inventory', 'Inventory'], requirements: 'Train two staff' });

    expect(response.status).toBe(201);
    expect(mocks.prisma.membershipRequest.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        tenantId: 'tenant-1',
        requestedBy: 'profile-1',
        features: ['Inventory'],
        requirements: 'Train two staff',
        status: 'pending',
      }),
    });
  });

  it('rejects empty requests and messages for another tenant', async () => {
    const emptyRequest = await supertest(app)
      .post('/tenant/membership/requests')
      .send({ features: [], requirements: '  ' });
    expect(emptyRequest.status).toBe(400);

    mocks.prisma.membershipRequest.findFirst.mockResolvedValue(null);
    const message = await supertest(app)
      .post('/tenant/membership/requests/foreign-request/messages')
      .send({ body: 'Please update this offer.' });

    expect(message.status).toBe(404);
    expect(mocks.prisma.membershipRequest.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'foreign-request', tenantId: 'tenant-1' },
      }),
    );
    expect(mocks.d1.batch).not.toHaveBeenCalled();
  });

  it('previews the actual offer discount before acceptance', async () => {
    mocks.prisma.membershipRequest.findFirst.mockResolvedValue({ id: 'request-1' });
    mocks.prisma.membershipOffer.findFirst.mockResolvedValue({
      id: 'offer-1',
      requestId: 'request-1',
      revision: 1,
      status: 'offered',
      amountMinor: 10_000,
      currency: 'KES',
      termMonths: 3,
      paymentArrangement: 'Pay by M-Pesa',
      renewalTerms: 'Renewal by agreement',
      includedFeatures: ['Inventory'],
      expiresAt: null,
    });
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      voucher: {
        id: 'voucher-1',
        voucherType: 'discount',
        discountPercent: 25,
        durationMonths: 3,
        expiresAt: null,
        revokedAt: null,
        pausedAt: null,
        deletedAt: null,
      },
    });

    const response = await supertest(app)
      .get('/tenant/membership/requests/request-1/offers/offer-1/preview');

    expect(response.status).toBe(200);
    expect(response.body.pricing).toMatchObject({
      baseAmountMinor: 10_000,
      discountPercent: 25,
      discountAmountMinor: 2_500,
      amountMinor: 7_500,
      voucherApplied: true,
      voucherNotApplicable: false,
    });
  });

  it('saves an accepted agreement with conditional D1 writes', async () => {
    mocks.prisma.membershipRequest.findFirst.mockResolvedValue({
      id: 'request-1',
      tenantId: 'tenant-1',
      status: 'offer_ready',
      agreement: null,
    });
    mocks.prisma.membershipOffer.findFirst.mockResolvedValue({
      id: 'offer-1',
      requestId: 'request-1',
      revision: 1,
      status: 'offered',
      amountMinor: 10_000,
      currency: 'KES',
      termMonths: null,
      paymentArrangement: 'Pay by M-Pesa',
      renewalTerms: 'Renewal by agreement',
      includedFeatures: ['Inventory'],
      additionalConditions: null,
      expiresAt: null,
    });
    mocks.prisma.tenantSubscription.findUnique
      .mockResolvedValueOnce({ voucher: null })
      .mockResolvedValueOnce({ voucherId: null });

    const response = await supertest(app)
      .post('/tenant/membership/requests/request-1/offers/offer-1/accept')
      .send({
        expectedAmountMinor: 10_000,
        expectedDiscountPercent: 0,
        expectedVoucherApplied: false,
      });

    expect(response.status).toBe(201);
    expect(response.body.agreement.snapshot).toMatchObject({
      requestId: 'request-1',
      offerId: 'offer-1',
      amountMinor: 10_000,
      termMonths: null,
      voucherId: null,
    });
    expect(mocks.d1.batch).toHaveBeenCalledTimes(1);
    expect(mocks.d1.statements[0].sql).toContain('INSERT OR IGNORE');
    expect(mocks.d1.statements[1].sql).toContain('changes() = 1');
    expect(mocks.d1.statements[3].sql).toContain('ON CONFLICT (tenant_id)');
  });

  it('returns a conflict when another action already accepted the offer', async () => {
    mocks.prisma.membershipRequest.findFirst.mockResolvedValue({
      id: 'request-1',
      tenantId: 'tenant-1',
      status: 'offer_ready',
      agreement: null,
    });
    mocks.prisma.membershipOffer.findFirst.mockResolvedValue({
      id: 'offer-1',
      requestId: 'request-1',
      revision: 1,
      status: 'offered',
      amountMinor: 10_000,
      currency: 'KES',
      termMonths: 1,
      paymentArrangement: 'Pay by M-Pesa',
      renewalTerms: 'Renewal by agreement',
      includedFeatures: [],
      additionalConditions: null,
      expiresAt: null,
    });
    mocks.prisma.tenantSubscription.findUnique
      .mockResolvedValueOnce({ voucher: null })
      .mockResolvedValueOnce(null);
    mocks.d1.batch.mockResolvedValueOnce([
      { meta: { changes: 0 } },
      { meta: { changes: 0 } },
      { meta: { changes: 0 } },
      { meta: { changes: 0 } },
    ]);

    const response = await supertest(app)
      .post('/tenant/membership/requests/request-1/offers/offer-1/accept')
      .send({
        expectedAmountMinor: 10_000,
        expectedDiscountPercent: 0,
        expectedVoucherApplied: false,
      });

    expect(response.status).toBe(409);
    expect(response.body.error).toContain('Offer was accepted');
  });

  it('requires review again when voucher pricing changes before acceptance', async () => {
    mocks.prisma.membershipRequest.findFirst.mockResolvedValue({
      id: 'request-1',
      tenantId: 'tenant-1',
      status: 'offer_ready',
      agreement: null,
    });
    mocks.prisma.membershipOffer.findFirst.mockResolvedValue({
      id: 'offer-1',
      requestId: 'request-1',
      revision: 1,
      status: 'offered',
      amountMinor: 10_000,
      currency: 'KES',
      termMonths: 3,
      paymentArrangement: 'Pay by M-Pesa',
      renewalTerms: 'Renewal by agreement',
      includedFeatures: [],
      additionalConditions: null,
      expiresAt: null,
    });
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      voucher: {
        id: 'voucher-1',
        voucherType: 'discount',
        discountPercent: 25,
        durationMonths: 3,
        expiresAt: null,
        revokedAt: null,
        pausedAt: null,
        deletedAt: null,
      },
    });

    const response = await supertest(app)
      .post('/tenant/membership/requests/request-1/offers/offer-1/accept')
      .send({
        expectedAmountMinor: 10_000,
        expectedDiscountPercent: 0,
        expectedVoucherApplied: false,
      });

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('OFFER_PREVIEW_CHANGED');
    expect(mocks.d1.batch).not.toHaveBeenCalled();
  });
});
