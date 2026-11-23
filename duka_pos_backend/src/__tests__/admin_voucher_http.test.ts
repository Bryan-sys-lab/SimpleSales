import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {
    accessVoucher: {
      create: vi.fn(),
      update: vi.fn(),
      findMany: vi.fn(),
    },
    adminAuditLog: {
      create: vi.fn(),
    },
    profile: {
      findUnique: vi.fn(),
      findFirst: vi.fn(),
    },
  },
  sendEmail: vi.fn(),
  generateVoucher: vi.fn(),
  registerPaymentChannel: vi.fn(),
  database: {
    prepare: vi.fn(),
    batch: vi.fn(),
  },
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: () => mocks.database,
}));
vi.mock('../services/payhero', () => ({
  registerPaymentChannel: mocks.registerPaymentChannel,
}));
vi.mock('../lib/email_sender', () => ({
  createCloudflareEmailTransport: () => ({
    configured: true,
    send: mocks.sendEmail,
  }),
}));
vi.mock('../lib/entitlements', () => ({
  generateVoucher: mocks.generateVoucher,
}));
vi.mock('../middleware/auth', () => ({
  authMiddleware: (req: any, _res: any, next: () => void) => {
    req.auth = { sub: 'admin-1' };
    next();
  },
  requireRole: () => (_req: any, _res: any, next: () => void) => next(),
  systemAdminMiddleware: (req: any, _res: any, next: () => void) => {
    req.auth = { sub: 'admin-1' };
    next();
  },
}));

describe('admin access voucher issuance', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { default: adminRoutes } = await import('../routes/admin');
    app = express();
    app.use(express.json());
    app.use('/admin', adminRoutes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.database.prepare.mockImplementation((sql: string) => ({
      bind: (...values: unknown[]) => ({ sql, values }),
    }));
    mocks.database.batch.mockResolvedValue([]);
    mocks.generateVoucher.mockReturnValue({
      code: 'SS-TEST-CLAIM-CODE',
      hash: 'voucher-hash',
      prefix: 'SS-TEST-',
    });
    mocks.prisma.accessVoucher.create.mockResolvedValue({
      id: 'voucher-1',
      codePrefix: 'SS-TEST-',
      tenantId: 'tenant-1',
      expiresAt: null,
    });
    mocks.prisma.accessVoucher.update.mockResolvedValue({});
    mocks.prisma.adminAuditLog.create.mockResolvedValue({});
    mocks.sendEmail.mockResolvedValue(undefined);
    mocks.registerPaymentChannel.mockResolvedValue({ id: 12345 });
  });

  it('creates a no-expiry voucher and emails its claim details', async () => {
    const response = await supertest(app).post('/admin/billing/vouchers').send({
      tenantId: 'tenant-1',
      email: 'owner@example.com',
      durationMonths: 6,
    });

    expect(response.status).toBe(201);
    expect(response.body.voucher).toMatchObject({
      code: 'SS-TEST-CLAIM-CODE',
      email: 'owner@example.com',
      durationMonths: 6,
      expiresAt: null,
      emailSent: true,
    });
    expect(mocks.prisma.accessVoucher.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        tenantId: 'tenant-1',
        issuedToEmail: 'owner@example.com',
        durationMonths: 6,
        expiresAt: null,
        autoIssued: false,
      }),
    });
    expect(mocks.sendEmail).toHaveBeenCalledWith({
      kind: 'access_voucher',
      to: 'owner@example.com',
      code: 'SS-TEST-CLAIM-CODE',
      voucherType: 'access',
      durationMonths: 6,
      discountPercent: 0,
    });
  });

  it('uses the selected shop owner email when the admin leaves it blank', async () => {
    mocks.prisma.profile.findFirst.mockResolvedValue({
      id: 'profile-1',
      tenantId: 'tenant-1',
      email: null,
      user: { email: 'owner@example.com' },
    });

    const response = await supertest(app).post('/admin/billing/vouchers').send({
      tenantId: 'tenant-1',
      durationMonths: 3,
    });

    expect(response.status).toBe(201);
    expect(response.body.voucher).toMatchObject({
      email: 'owner@example.com',
      durationMonths: 3,
      tenantId: 'tenant-1',
    });
    expect(mocks.prisma.accessVoucher.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        tenantId: 'tenant-1',
        issuedToProfileId: 'profile-1',
        issuedToEmail: 'owner@example.com',
      }),
    });
    expect(mocks.sendEmail).toHaveBeenCalledWith(
      expect.objectContaining({
        kind: 'access_voucher',
        to: 'owner@example.com',
      }),
    );
  });

  it('issues a no-expiry discount voucher through the existing voucher endpoint', async () => {
    const response = await supertest(app).post('/admin/billing/vouchers').send({
      email: 'owner@example.com',
      voucherType: 'discount',
      durationMonths: 3,
      discountPercent: 25,
    });

    expect(response.status).toBe(201);
    expect(response.body.voucher).toMatchObject({
      voucherType: 'discount',
      durationMonths: 3,
      discountPercent: 25,
      expiresAt: null,
    });
    expect(mocks.prisma.accessVoucher.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        voucherType: 'discount',
        durationMonths: 3,
        discountPercent: 25,
        expiresAt: null,
      }),
    });
    expect(mocks.sendEmail).toHaveBeenCalledWith(expect.objectContaining({
      kind: 'access_voucher',
      voucherType: 'discount',
      durationMonths: 3,
      discountPercent: 25,
    }));
  });

  it('rejects a discount voucher with no discount percentage', async () => {
    const response = await supertest(app).post('/admin/billing/vouchers').send({
      email: 'owner@example.com',
      voucherType: 'discount',
      durationMonths: 3,
      discountPercent: 0,
    });

    expect(response.status).toBe(400);
    expect(mocks.generateVoucher).not.toHaveBeenCalled();
    expect(mocks.prisma.accessVoucher.create).not.toHaveBeenCalled();
  });

  it('registers a billing destination and persists the returned provider channel', async () => {
    const response = await supertest(app).patch('/admin/billing/provider').send({
      channelType: 'till',
      shortCode: '12345',
    });

    expect(response.status).toBe(200);
    expect(response.body.provider).toMatchObject({
      channelType: 'till',
      shortCode: '12345',
      channelId: 12345,
    });
    expect(mocks.registerPaymentChannel).toHaveBeenCalledWith({
      channelType: 'till',
      shortCode: '12345',
    });
    expect(mocks.database.batch).toHaveBeenCalledTimes(1);
    expect(mocks.database.batch.mock.calls[0][0]).toHaveLength(4);
    expect(mocks.prisma.adminAuditLog.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ action: 'update_billing_provider' }),
    });
  });

  it('requires an email when no shop owner recipient can be resolved', async () => {
    const response = await supertest(app).post('/admin/billing/vouchers').send({
      durationMonths: 1,
    });

    expect(response.status).toBe(400);
    expect(response.body.code).toBe('VOUCHER_RECIPIENT_REQUIRED');
    expect(mocks.generateVoucher).not.toHaveBeenCalled();
    expect(mocks.prisma.accessVoucher.create).not.toHaveBeenCalled();
  });

  it('rejects unsupported durations before generating a code', async () => {
    const response = await supertest(app).post('/admin/billing/vouchers').send({
      email: 'owner@example.com',
      durationMonths: 2,
    });

    expect(response.status).toBe(400);
    expect(mocks.generateVoucher).not.toHaveBeenCalled();
    expect(mocks.prisma.accessVoucher.create).not.toHaveBeenCalled();
  });

  it('revokes an issued code when its voucher email cannot be sent', async () => {
    mocks.sendEmail.mockRejectedValue(new Error('provider unavailable'));

    const response = await supertest(app).post('/admin/billing/vouchers').send({
      email: 'owner@example.com',
      durationMonths: 1,
    });

    expect(response.status).toBe(502);
    expect(response.body.code).toBe('VOUCHER_EMAIL_UNAVAILABLE');
    expect(mocks.prisma.accessVoucher.update).toHaveBeenCalledWith({
      where: { id: 'voucher-1' },
      data: { revokedAt: expect.any(Date) },
    });
    expect(response.body).not.toHaveProperty('voucher.code');
  });
});
