import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {
    tenantSubscription: { findUnique: vi.fn() },
    accessVoucher: { findFirst: vi.fn() },
    membershipAgreement: { findFirst: vi.fn() },
    systemSettings: { findMany: vi.fn() },
    subscriptionPayment: { create: vi.fn(), findFirst: vi.fn(), update: vi.fn() },
  },
  initiateStkPush: vi.fn(),
  payHeroSettlementContractConfirmed: vi.fn(),
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: vi.fn(),
}));
vi.mock('../services/payhero', () => ({
  registerPaymentChannel: vi.fn(),
  initiateStkPush: mocks.initiateStkPush,
  queryTransactionStatus: vi.fn(),
  payHeroCallbackUrl: () => 'https://api.example.test/payhero/callback',
  payHeroSettlementContractConfirmed: mocks.payHeroSettlementContractConfirmed,
}));
vi.mock('../middleware/auth', () => ({
  authMiddleware: (req: any, _res: any, next: () => void) => {
    req.user = { id: 'owner-1', tenantId: 'tenant-1', role: 'admin', name: 'Owner' };
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
    mocks.payHeroSettlementContractConfirmed.mockReturnValue(true);
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      tenantId: 'tenant-1',
      status: 'pending',
      priceMinor: 10_000,
      discountPercent: 10,
      currency: 'KES',
      billingInterval: 'quarterly',
      agreementId: null,
      agreement: null,
      voucher: {
        voucherType: 'discount',
        durationMonths: 3,
        discountPercent: 25,
      },
    });
    mocks.prisma.systemSettings.findMany.mockResolvedValue([
      { key: 'billing_channel_id', value: '12345' },
      { key: 'billing_channel_type', value: 'paybill' },
      { key: 'billing_short_code', value: '123456' },
    ]);
    mocks.prisma.accessVoucher.findFirst.mockResolvedValue(null);
    mocks.prisma.subscriptionPayment.create.mockResolvedValue({
      id: 'payment-1',
    });
    mocks.prisma.subscriptionPayment.findFirst.mockResolvedValue(null);
    mocks.prisma.subscriptionPayment.update.mockResolvedValue({});
    mocks.initiateStkPush.mockResolvedValue({
      checkoutRequestId: 'checkout-1',
    });
  });

  it('does not initiate subscription payments before settlement requirements are confirmed', async () => {
    mocks.payHeroSettlementContractConfirmed.mockReturnValue(false);

    const response = await supertest(app)
      .post('/tenant/subscription/payment')
      .send({ phoneNumber: '254700000000' });

    expect(response.status).toBe(503);
    expect(mocks.prisma.subscriptionPayment.create).not.toHaveBeenCalled();
    expect(mocks.initiateStkPush).not.toHaveBeenCalled();
  });

  it('uses the administrator-set period and applies a matching voucher discount', async () => {
    const response = await supertest(app)
      .post('/tenant/subscription/payment')
      .send({ phoneNumber: '254700000000', durationMonths: 1 });

    expect(response.status).toBe(201);
    expect(response.body).toMatchObject({
      baseAmountMinor: 30_000,
      discountAmountMinor: 7_500,
      amountMinor: 22_500,
      discountPercent: 25,
      durationMonths: 3,
      paymentMethod: {
        method: 'mpesa_stk',
        channelType: 'paybill',
        shortCode: '123456',
      },
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

  it('uses the same whole-shilling amount in the quote, stored payment, and STK request', async () => {
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      tenantId: 'tenant-1',
      status: 'pending',
      priceMinor: 10_050,
      discountPercent: 0,
      currency: 'KES',
      billingInterval: 'monthly',
      agreementId: null,
      agreement: null,
      voucher: null,
    });

    const response = await supertest(app)
      .post('/tenant/subscription/payment')
      .send({ phoneNumber: '254700000000' });

    expect(response.status).toBe(201);
    expect(response.body.amountMinor).toBe(10_100);
    expect(mocks.prisma.subscriptionPayment.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ amountMinor: 10_100 }),
    });
    expect(mocks.initiateStkPush).toHaveBeenCalledWith(
      expect.objectContaining({ amount: 101 }),
    );
  });

  it('returns the configured amount, billing period, and public payment destination', async () => {
    const response = await supertest(app).get('/tenant/subscription');

    expect(response.status).toBe(200);
    expect(response.body.support.checkout).toMatchObject({
      amountMinor: 22_500,
      baseAmountMinor: 30_000,
      discountPercent: 25,
      durationMonths: 3,
    });
    expect(response.body.support.paymentMethod).toEqual({
      method: 'mpesa_stk',
      channelType: 'paybill',
      shortCode: '123456',
      accountNumber: null,
    });
    expect(response.body.support.paymentMethod).not.toHaveProperty('channelId');
  });

  it('keeps a term-mismatched discount voucher unused and charges the admin discount', async () => {
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      tenantId: 'tenant-1',
      status: 'pending',
      priceMinor: 10_000,
      discountPercent: 10,
      currency: 'KES',
      billingInterval: 'monthly',
      voucher: {
        voucherType: 'discount',
        durationMonths: 3,
        discountPercent: 25,
      },
    });
    const response = await supertest(app)
      .post('/tenant/subscription/payment')
      .send({ phoneNumber: '254700000000' });

    expect(response.status).toBe(201);
    expect(response.body).toMatchObject({
      amountMinor: 9_000,
      discountPercent: 10,
      durationMonths: 1,
    });
    expect(mocks.prisma.subscriptionPayment.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        amountMinor: 9_000,
        durationMonths: 1,
        voucherApplied: false,
      }),
    });
  });

  it('charges only the immutable accepted offer amount and records voucher use', async () => {
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      tenantId: 'tenant-1',
      status: 'active',
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
      .send({ phoneNumber: '254700000000' });

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

  it('does not allow checkout to override an accepted agreement', async () => {
    mocks.prisma.tenantSubscription.findUnique.mockResolvedValue({
      tenantId: 'tenant-1',
      status: 'awaiting_payment',
      currency: 'KES',
      agreementId: 'agreement-1',
    });

    const response = await supertest(app)
      .post('/tenant/subscription/payment')
      .send({ phoneNumber: '254700000000', agreementId: 'different-agreement' });

    expect(response.status).toBe(409);
    expect(response.body.error).toContain('accepted membership agreement');
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
