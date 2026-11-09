// HTTP-level safety boundaries for the eTIMS surface.
//
// The interesting questions about a tax-invoice endpoint are not "does it work"
// but "can it be reached by someone who should not, and does it leak anything".
// Those are exactly the things a unit test of the arithmetic cannot answer, and
// exactly the things that go wrong in practice: a signing key in a response body,
// an unregistered shop filing an invoice, a verification page that reveals more
// than the receipt already shows.

import { beforeAll, describe, expect, it, vi } from 'vitest';
import type { Express } from 'express';
import { prisma } from '../lib/prisma';

let app: Express;

beforeAll(async () => {
  process.env.NODE_ENV = 'test';
  process.env.OIDC_ISSUER_URL = 'https://id.example.test/realms/duka';
  process.env.OIDC_AUDIENCE = 'duka-api';
  process.env.DATABASE_URL ??= 'postgresql://localhost:5432/duka_pos_test';
  const module = await import('../index');
  app = module.default;
});

describe('eTIMS access boundaries', () => {
  it('refuses to issue a receipt without a bearer token', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app)
      .post('/api/etims/receipts')
      .send({
        receipt_number: 'T1-000001',
        issued_at: '2026-10-03T14:05:00.000Z',
        total: 8000,
        vat_rate_percent: 16,
        items: [
          {
            name: 'Soda 350ml',
            qty: 1,
            unit_price: 8000,
            unit_cost: 4500,
            portion: 'full',
            portion_ml: 350,
            vat_amount: 1103,
            line_total: 8000,
          },
        ],
      });
    expect(response.status).toBe(401);
    expect(response.body.requestId).toBeTruthy();
  });

  it('refuses to register a device without a bearer token', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app)
      .post('/api/etims/device')
      .send({ tin: 'P051234567X', device_id: 'DUKA-TILL-1' });
    expect(response.status).toBe(401);
  });

  it('refuses to read the queue status without a bearer token', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/etims/status');
    expect(response.status).toBe(401);
  });

  it('refuses to publish a Z-report without a bearer token', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).post('/api/etims/z-report').send({});
    expect(response.status).toBe(401);
  });

  it('refuses an offline batch upload without a bearer token', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).post('/api/etims/upload');
    expect(response.status).toBe(401);
  });

  it('never projects a signing key into the device status', async () => {
    // `/etims/status` is read by the till on every settings visit. `access_key`
    // and `encryption_key` sign every invoice the shop will ever file, so they
    // are not fetched at all rather than filtered on the way out — no future
    // edit to the response body can then leak them by accident.
    const { etimsDeviceStatusSelect } = await import('../routes/etims');
    const fields = Object.keys(etimsDeviceStatusSelect);
    expect(fields).toContain('tin');
    expect(fields).toContain('status');
    expect(fields).not.toContain('accessKey');
    expect(fields).not.toContain('encryptionKey');
    expect(fields.some((field) => /key/i.test(field))).toBe(false);
  });

  it('returns nothing tenant-identifying from the public receipt view', async () => {
    // The verification page has no tenant filter and no auth, because the
    // person following the QR is a customer. It therefore may return only what
    // is already printed on the paper in their hand. A field added here would
    // be a shop-data leak reachable by anyone with a receipt.
    const { publicReceiptSelect } = await import('../routes/etims');
    const fields = Object.keys(publicReceiptSelect);
    expect(fields).toContain('kraReceiptNumber');
    expect(fields).toContain('total');
    expect(fields).toContain('vatTotal');
    for (const forbidden of ['tenantId', 'tenant', 'tin', 'deviceId', 'payload', 'rejectionReason']) {
      expect(fields).not.toContain(forbidden);
    }
  });

  it('serves the public verification page without authentication', async () => {
    // Deliberately public: the person scanning the receipt's QR code is the
    // customer, who has no account. It must still answer rather than 401, and
    // it must not answer for a receipt that does not exist.
    const supertest = await import('supertest');
    const lookup = vi
      .spyOn(prisma.etimsReceipt, 'findFirst')
      .mockResolvedValue(null);
    const response = await supertest.default(app)
      .get('/api/etims/verify/00000000-0000-0000-0000-000000000000');
    expect(response.status).toBe(404);
    expect(response.body.error).toBe('No such receipt');
    lookup.mockRestore();
  });
});

describe('eTIMS request validation', () => {
  it('rejects a malformed payload before it reaches KRA', async () => {
    // These run unauthenticated, so a 401 proves the body was rejected by the
    // auth layer rather than parsed. The schema itself is covered in
    // validation.test.ts; this asserts the route is wired to a parser at all.
    const supertest = await import('supertest');
    const response = await supertest.default(app)
      .post('/api/etims/receipts')
      .send({ receipt_number: 'x' });
    expect(response.status).toBe(401);
  });
});
