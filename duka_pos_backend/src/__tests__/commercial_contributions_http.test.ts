import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { errorHandler } from '../lib/http';

const mocks = vi.hoisted(() => ({
  prisma: {
    commercialConsentGrant: { findFirst: vi.fn() },
    commercialContribution: { findFirst: vi.fn(), create: vi.fn() },
  },
}));

vi.mock('../lib/prisma', () => ({ prisma: mocks.prisma }));

describe('commercial contribution batch ingest', () => {
  let app: express.Express;
  let role = 'admin';

  beforeAll(async () => {
    const { default: routes } = await import('../routes/commercial_contributions');
    app = express();
    app.use(express.json());
    app.use((req, _res, next) => {
      req.user = { id: 'owner-1', tenantId: 'tenant-server-owned', role, name: 'Owner' };
      next();
    });
    app.use('/tenant/commercial-contributions', routes);
    app.use(errorHandler);
  });

  beforeEach(() => {
    vi.clearAllMocks();
    role = 'admin';
    mocks.prisma.commercialConsentGrant.findFirst.mockResolvedValue({
      tenantId: 'tenant-server-owned',
      status: 'active',
      scopes: ['product_demand', 'digitisation_metrics'],
    });
    mocks.prisma.commercialContribution.findFirst.mockResolvedValue(null);
    mocks.prisma.commercialContribution.create.mockImplementation(async ({ data }) => ({ id: 'contribution-1', ...data }));
  });

  const batch = () => ({
    batch_id: '7d2a7b6a-6d74-4d4b-a5d5-0c5b5b5b5b5b',
    schema_version: 'ci-contribution-v1',
    dictionary_version: '2.0.0',
    period: {
      from_utc: '2026-10-01T00:00:00Z',
      to_utc: '2026-11-01T00:00:00Z',
      grain: 'month',
      reporting_timezone: 'Africa/Nairobi',
    },
    app_profile: 'duka',
    scope_codes: ['product_demand', 'digitisation_metrics'],
    dimensions: { currency: 'KES', unit_scheme: 'UNECE-REC20', unit_code: 'PCE' },
    metrics: {
      transaction_count: 120,
      gross_sales_minor: 48500000,
      discount_minor: 1500000,
      refund_minor: 500000,
      net_sales_ex_tax_minor: 46500000,
    },
    quality: { sale_line_coverage: 0.98, category_mapping_coverage: 0.91 },
  });

  it('accepts an active scoped batch for the authenticated tenant', async () => {
    const response = await supertest(app).post('/tenant/commercial-contributions/batches').send(batch());
    expect(response.status).toBe(201);
    expect(response.body).toEqual({
      batch_id: '7d2a7b6a-6d74-4d4b-a5d5-0c5b5b5b5b5b',
      status: 'accepted',
      idempotent: false,
      received: true,
    });
    expect(mocks.prisma.commercialContribution.create.mock.calls[0][0].data.tenantId).toBe('tenant-server-owned');
  });

  it('is idempotent for the same tenant and batch hash', async () => {
    const payload = batch();
    const crypto = await import('node:crypto');
    const canonical = (value: unknown): string => {
      if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
      if (value !== null && typeof value === 'object') {
        const record = value as Record<string, unknown>;
        return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${canonical(record[key])}`).join(',')}}`;
      }
      return JSON.stringify(value);
    };
    const hash = crypto.createHash('sha256').update(canonical(payload)).digest('hex');
    mocks.prisma.commercialContribution.findFirst.mockResolvedValue({ payloadChecksum: hash });
    const response = await supertest(app).post('/tenant/commercial-contributions/batches').send(payload);
    expect(response.status).toBe(200);
    expect(response.body.idempotent).toBe(true);
  });

  it('rejects repeated batch IDs with changed payloads', async () => {
    mocks.prisma.commercialContribution.findFirst.mockResolvedValue({ payloadChecksum: 'different' });
    const response = await supertest(app).post('/tenant/commercial-contributions/batches').send(batch());
    expect(response.status).toBe(409);
  });

  it('rejects withdrawn or out-of-scope grants and unknown nested fields', async () => {
    mocks.prisma.commercialConsentGrant.findFirst.mockResolvedValue(null);
    expect((await supertest(app).post('/tenant/commercial-contributions/batches').send(batch())).status).toBe(403);
    mocks.prisma.commercialConsentGrant.findFirst.mockResolvedValue({
      status: 'active',
      scopes: ['digitisation_metrics'],
    });
    expect((await supertest(app).post('/tenant/commercial-contributions/batches').send(batch())).status).toBe(403);
    mocks.prisma.commercialConsentGrant.findFirst.mockResolvedValue({
      status: 'active',
      scopes: ['product_demand', 'digitisation_metrics'],
    });
    expect((await supertest(app).post('/tenant/commercial-contributions/batches').send({
      ...batch(),
      tenant_id: 'spoofed',
    })).status).toBe(400);
  });

  it('denies non-owner roles', async () => {
    role = 'cashier';
    const response = await supertest(app).post('/tenant/commercial-contributions/batches').send(batch());
    expect(response.status).toBe(403);
  });
});
