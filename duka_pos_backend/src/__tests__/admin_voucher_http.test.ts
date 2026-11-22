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
    },
  },
  sendEmail: vi.fn(),
  generateVoucher: vi.fn(),
}));

vi.mock('../lib/prisma', () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: vi.fn(),
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
      durationMonths: 6,
    });
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
