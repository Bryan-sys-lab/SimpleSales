import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {
    tenantSubscription: { findUnique: vi.fn() },
    membershipAgreement: { findFirst: vi.fn() },
    systemSettings: { findMany: vi.fn() },
    subscriptionPayment: { create: vi.fn(), findFirst: vi.fn(), update: vi.fn() },
  },
  initiateStkPush: vi.fn(),
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: vi.fn(),
}));
vi.mock('../services/payhero', () => ({
  registerPaymentChannel: vi.fn(),
  initiateStkPush: mocks.initiateStkPush,
  queryTransactionStatus: vi.fn(),
}));
vi.mock('../middleware/auth', () => ({
  authMiddleware: (req: any, _res: any, next: () => void) => {
    req.user = { tenantId: 'tenant-1', role: 'admin', name: 'Owner' };
    req.auth = { sub: 'profile-1', email: 'owner@example.com' };
    next();
  },
}));

describe('subscription payment discount vouchers', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: tenantRoutes } = await import('../routes/tenant');
    app = express();
    app.use(express.json());
    app.use('/tenant', tenantRoutes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      tenantId: 'tenant-1',
      priceMinor: 10_000,
      discountPercent: 10,
      currency: 'KES',
      voucher: {
        voucherType: 'discount',
        durationMonths: 3,
        discountPercent: 25,
      },
    });
    mocks.prisma.systemSettings.findMany.mockResolvedValue([
      { key: 'billing_channel_id', value: '12345' },
    ]);
    mocks.prisma.subscriptionPayment.create.mockResolvedValue({
      id: 'payment-1',
    });
    mocks.prisma.subscriptionPayment.findFirst.mockResolvedValue(null);
    mocks.prisma.subscriptionPayment.update.mockResolvedValue({});
    mocks.initiateStkPush.mockResolvedValue({
      checkoutRequestId: 'checkout-1',
    });
  });

  it('applies the larger discount once to the matching plan checkout', async () => {
    const response = await supertest(app)
      .post('/tenant/subscription/payment')
      .send({ phoneNumber: '254700000000', durationMonths: 3 });

    expect(response.status).toBe(201);
    expect(response.body).toMatchObject({
      baseAmountMinor: 30_000,
      discountAmountMinor: 7_500,
      amountMinor: 22_500,
      discountPercent: 25,
      durationMonths: 3,
    });
    expect(mocks.prisma.subscriptionPayment.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        amountMinor: 22_500,
        discountPercent: 25,
        durationMonths: 3,
      }),
    });
    expect(mocks.initiateStkPush).toHaveBeenCalledWith(
      expect.objectContaining({ amount: 225 }),
    );
  });

  it('rejects a checkout term that does not match the claimed discount voucher', async () => {
    const response = await supertest(app)
      .post('/tenant/subscription/payment')
      .send({ phoneNumber: '254700000000', durationMonths: 1 });

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('VOUCHER_DURATION_MISMATCH');
    expect(mocks.prisma.subscriptionPayment.create).not.toHaveBeenCalled();
    expect(mocks.initiateStkPush).not.toHaveBeenCalled();
  });

  it('charges only the immutable accepted offer amount and records voucher use', async () => {
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      tenantId: 'tenant-1',
      status: 'awaiting_payment',
      currency: 'KES',
      agreementId: 'agreement-1',
    });
    mocks.prisma.membershipAgreement.findFirst.mockResolvedValue({
      id: 'agreement-1',
      snapshot: {
        amountMinor: 22_500,
        baseAmountMinor: 30_000,
        discountPercent: 25,
        termMonths: 3,
        currency: 'KES',
        voucherId: 'voucher-1',
      },
    });

    const response = await supertest(app)
      .post('/tenant/subscription/payment')
      .send({ phoneNumber: '254700000000', agreementId: 'agreement-1' });

    expect(response.status).toBe(201);
    expect(response.body).toMatchObject({
      amountMinor: 22_500,
      baseAmountMinor: 30_000,
      discountAmountMinor: 7_500,
      discountPercent: 25,
      durationMonths: 3,
      agreementId: 'agreement-1',
    });
    expect(mocks.prisma.subscriptionPayment.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        amountMinor: 22_500,
        durationMonths: 3,
        agreementId: 'agreement-1',
        voucherApplied: true,
      }),
    });
    expect(mocks.initiateStkPush).toHaveBeenCalledWith(
      expect.objectContaining({ amount: 225 }),
    );
  });

  it('does not allow a fixed-price checkout to bypass an accepted agreement', async () => {
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      tenantId: 'tenant-1',
      status: 'awaiting_payment',
      currency: 'KES',
      agreementId: 'agreement-1',
    });

    const response = await supertest(app)
      .post('/tenant/subscription/payment')
      .send({ phoneNumber: '254700000000', durationMonths: 3 });

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('AGREEMENT_PAYMENT_REQUIRED');
    expect(mocks.prisma.subscriptionPayment.create).not.toHaveBeenCalled();
    expect(mocks.initiateStkPush).not.toHaveBeenCalled();
  });

  it('reuses an existing pending agreement payment instead of starting another charge', async () => {
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      tenantId: 'tenant-1',
      status: 'awaiting_payment',
      currency: 'KES',
      agreementId: 'agreement-1',
    });
    mocks.prisma.membershipAgreement.findFirst.mockResolvedValue({
      id: 'agreement-1',
      snapshot: {
        amountMinor: 10_000,
        baseAmountMinor: 10_000,
        discountPercent: 0,
        termMonths: null,
        currency: 'KES',
        voucherId: null,
      },
    });
    mocks.prisma.subscriptionPayment.findFirst.mockResolvedValue({
      reference: 'SUBS-existing',
      amountMinor: 10_000,
      discountPercent: 0,
      durationMonths: 0,
      status: 'PENDING',
    });

    const response = await supertest(app)
      .post('/tenant/subscription/payment')
      .send({ phoneNumber: '254700000000', agreementId: 'agreement-1' });

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({
      reference: 'SUBS-existing',
      amountMinor: 10_000,
      durationMonths: 0,
      status: 'PENDING',
    });
    expect(mocks.prisma.subscriptionPayment.create).not.toHaveBeenCalled();
    expect(mocks.initiateStkPush).not.toHaveBeenCalled();
  });
});
