import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {
    commercialConsentGrant: {
      findFirst: vi.fn(),
      findMany: vi.fn(),
      create: vi.fn(),
      updateMany: vi.fn(),
    },
    adminAuditLog: { create: vi.fn() },
  },
}));

vi.mock('../lib/prisma', () => ({ prisma: mocks.prisma }));

describe('commercial consent HTTP lifecycle', () => {
  let app: express.Express;
  let role = 'admin';

  beforeAll(async () => {
    const { default: routes } = await import('../routes/commercial_consent');
    app = express();
    app.use(express.json());
    app.use((req, _res, next) => {
      req.user = { id: 'owner-1', tenantId: 'tenant-server-owned', role, name: 'Owner' };
      next();
    });
    app.use('/tenant/commercial-consent', routes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    role = 'admin';
    mocks.prisma.commercialConsentGrant.findFirst.mockResolvedValue(null);
    mocks.prisma.commercialConsentGrant.findMany.mockResolvedValue([]);
    mocks.prisma.commercialConsentGrant.create.mockImplementation(async ({ data }) => ({ id: 'grant-1', ...data }));
    mocks.prisma.commercialConsentGrant.updateMany.mockResolvedValue({ count: 1 });
    mocks.prisma.adminAuditLog.create.mockResolvedValue({ id: 'audit-1' });
  });

  const validGrant = {
    scopes: ['business_activity', 'product_demand'],
    noticeVersion: 'commercial-notice-v1-draft',
    noticeDigest: `sha256:${'0'.repeat(64)}`,
    termsVersion: null,
    schemaVersion: 'commercial-contribution-v1',
    dictionaryVersion: 'duka-pos-data-dictionary-v2',
    appVersion: '100+100',
    captureMethod: 'in_app_affirmative',
    authorityEvidence: 'owner',
  };

  it('creates a scoped default-off evidence grant under the authenticated tenant', async () => {
    const response = await supertest(app).put('/tenant/commercial-consent').send(validGrant);
    expect(response.status).toBe(201);
    expect(response.body.collectionEnabled).toBe(false);
    expect(response.body.grant.tenantId).toBe('tenant-server-owned');
    expect(response.body.grant.scopes).toEqual(['business_activity', 'product_demand']);
  });

  it('rejects unauthorized roles and prohibited extra fields', async () => {
    role = 'cashier';
    expect((await supertest(app).put('/tenant/commercial-consent').send(validGrant)).status).toBe(403);
    role = 'admin';
    expect((await supertest(app).put('/tenant/commercial-consent').send({
      ...validGrant,
      customerName: 'not allowed',
    })).status).toBe(400);
  });

  it('withdraws active grants and records the lifecycle', async () => {
    mocks.prisma.commercialConsentGrant.findMany.mockResolvedValue([{ id: 'grant-1' }]);
    const response = await supertest(app).post('/tenant/commercial-consent/withdraw');
    expect(response.status).toBe(200);
    expect(response.body.withdrawn).toBe(1);
    expect(response.body.collectionEnabled).toBe(false);
    expect(mocks.prisma.commercialConsentGrant.updateMany).toHaveBeenCalledWith({
      where: { tenantId: 'tenant-server-owned', status: 'active' },
      data: expect.objectContaining({
        status: 'withdrawn',
        processingState: 'purge_queued_unsubmitted',
      }),
    });
  });

  it('rejects unknown scopes, empty scopes and invalid notice evidence', async () => {
    expect((await supertest(app).put('/tenant/commercial-consent').send({
      ...validGrant,
      scopes: [],
    })).status).toBe(400);
    expect((await supertest(app).put('/tenant/commercial-consent').send({
      ...validGrant,
      scopes: ['unknown_scope'],
    })).status).toBe(400);
    expect((await supertest(app).put('/tenant/commercial-consent').send({
      ...validGrant,
      noticeDigest: 'plain-text',
    })).status).toBe(400);
  });
});
