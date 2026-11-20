import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';
import { KESIC_REFERENCE_VERSION, KESIC_VERIFIED_CODES } from '../data/kesic_codes';

const mocks = vi.hoisted(() => ({
  prisma: {
    businessContext: { findUnique: vi.fn(), upsert: vi.fn() },
    tenant: { findUnique: vi.fn() },
  },
}));
vi.mock('../lib/prisma', () => ({ prisma: mocks.prisma }));

describe('tenant business context API', () => {
  let app: express.Express;
  let role = 'admin';

  beforeAll(async () => {
    const { default: routes } = await import('../routes/business_context');
    app = express();
    app.use(express.json());
    app.use((req, _res, next) => {
      req.user = { id: 'owner-1', tenantId: 'tenant-owned-by-token', role, name: 'Owner' };
      next();
    });
    app.use('/tenant/business-context', routes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    role = 'admin';
    mocks.prisma.tenant.findUnique.mockResolvedValue({ businessProfile: 'fashion' });
    mocks.prisma.businessContext.findUnique.mockResolvedValue(null);
    mocks.prisma.businessContext.upsert.mockImplementation(async ({ create }) => ({ id: 'ctx-1', ...create }));
  });

  it('reads only the tenant selected by authenticated profile context', async () => {
    const response = await supertest(app).get('/tenant/business-context');
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ context: null, appProfile: 'fashion' });
    expect(mocks.prisma.businessContext.findUnique).toHaveBeenCalledWith({ where: { tenantId: 'tenant-owned-by-token' } });
  });

  it('writes the owner-confirmed context under the authenticated tenant', async () => {
    const response = await supertest(app).put('/tenant/business-context').send({
      primaryActivityCode: '477110', primaryActivityStatus: 'selected', activityScheme: 'KESIC',
      activityVersion: 'KeSIC-2020-First-Edition-2021', secondaryActivityCodes: [],
      operatorRoles: ['retailer'], salesChannels: ['physical_shop'], countyCode: '047',
      settlementContext: 'urban', fieldProvenance: {
        primary_activity_code: 'owner_confirmed', primary_activity_status: 'owner_confirmed',
        operator_roles: 'owner_confirmed', sales_channels: 'owner_confirmed',
        county_code: 'owner_confirmed', settlement_context: 'owner_confirmed',
      },
      confirmedAt: '2026-11-19T00:00:00.000Z', schemaVersion: 1,
    });
    expect(response.status).toBe(200);
    expect(response.body.context.tenantId).toBe('tenant-owned-by-token');
    expect(response.body.context.appProfile).toBe('fashion');
    expect(mocks.prisma.businessContext.upsert.mock.calls[0][0].where).toEqual({ tenantId: 'tenant-owned-by-token' });
  });

  it('preserves an unlisted code as pending and uses the shared versioned reference', async () => {
    const response = await supertest(app).put('/tenant/business-context').send({
      primaryActivityCode: '016190', primaryActivityStatus: 'pending', activityScheme: 'KESIC',
      activityVersion: KESIC_REFERENCE_VERSION, secondaryActivityCodes: [], operatorRoles: [],
      salesChannels: [], countyCode: null, settlementContext: 'unknown', fieldProvenance: { primary_activity_code: 'owner_confirmed', primary_activity_status: 'owner_confirmed' },
      confirmedAt: null, schemaVersion: 1,
    });
    expect(response.status).toBe(200);
    expect(KESIC_VERIFIED_CODES.size).toBe(1169);
    expect(KESIC_VERIFIED_CODES.has('016190')).toBe(false);
    expect(response.body.context.primaryActivityCode).toBe('016190');
    expect(response.body.context.primaryActivityStatus).toBe('pending');
  });

  it('rejects non-owners and malformed or duplicate activity codes', async () => {
    role = 'manager';
    expect((await supertest(app).get('/tenant/business-context')).status).toBe(403);
    expect((await supertest(app).put('/tenant/business-context').send({})).status).toBe(403);
    role = 'admin';
    const response = await supertest(app).put('/tenant/business-context').send({
      primaryActivityCode: '477110', primaryActivityStatus: 'selected', activityScheme: 'KESIC', activityVersion: 'v1',
      secondaryActivityCodes: ['477110', '477110'], operatorRoles: [], salesChannels: [], countyCode: null,
      settlementContext: 'unknown', fieldProvenance: { primary_activity_code: 'owner_confirmed', primary_activity_status: 'owner_confirmed', secondary_activity_codes: 'owner_confirmed' }, confirmedAt: null, schemaVersion: 1,
    });
    expect(response.status).toBe(400);
    expect(mocks.prisma.businessContext.upsert).not.toHaveBeenCalled();
  });

  it('rejects unverified selected codes and fields outside the allowlist', async () => {
    const payload = {
      primaryActivityCode: '999999', primaryActivityStatus: 'selected', activityScheme: 'KESIC',
      activityVersion: KESIC_REFERENCE_VERSION, secondaryActivityCodes: [], operatorRoles: [],
      salesChannels: [], countyCode: null, settlementContext: 'unknown', fieldProvenance: { primary_activity_status: 'owner_confirmed' },
      confirmedAt: null, schemaVersion: 1,
    };
    expect((await supertest(app).put('/tenant/business-context').send(payload)).status).toBe(400);
    expect((await supertest(app).put('/tenant/business-context').send({ ...payload, primaryActivityCode: null, primaryActivityStatus: 'pending', activityScheme: null, activityVersion: null, kraPin: 'sensitive' })).status).toBe(400);
    expect(mocks.prisma.businessContext.upsert).not.toHaveBeenCalled();
  });
});
