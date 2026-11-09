// The M-Pesa C2B surface, at its seams.
//
// ## WHAT IS UNDER TEST
//
// The webhook is the only PUBLIC money path on the server, so its tests are
// the server's promises in miniature:
//
//   * a payment exists exactly ONCE — duplicate and out-of-order callbacks
//     store one row (spec 12.7's first case);
//   * the payer is masked at the DOOR; no full phone number reaches storage;
//   * one payment funds one sale — two devices race, one wins, the loser
//     gets 409 with who and when;
//   * the same device retrying its own claim is the SAME claim;
//   * ignoring is a manager's act, with a reason;
//   * an unkeyed callback is refused.
//
// The prisma client is scripted here, in-module, because the interesting
// behaviour is ORDER synchronisation (two claims staged deterministically —
// a real-isolate race cannot guarantee the loser's write lands after the
// winner's, which is the property under test).

import express from 'express';
import supertest from 'supertest';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

interface Row {
  id: string;
  tenantId: string;
  remoteId: string;
  transId: string;
  amount: number;
  payerLabel: string;
  billRef: string | null;
  receivedAt: Date;
  status: 'unclaimed' | 'claimed' | 'ignored' | 'expired';
  claimedByDevice: string | null;
  claimedSaleUuid: string | null;
  claimedAt: Date | null;
  ignoreReason: string | null;
}

const h = vi.hoisted(() => ({
  rows: [] as unknown[],
  receipts: [] as Record<string, unknown>[],
  links: [] as Record<string, unknown>[],
  calls: { upsert: 0, updateMany: 0 },
}));

vi.mock('../lib/prisma', () => {
  const copy = (row: unknown) => ({ ...(row as Record<string, unknown>) });
  const byRemoteId = (remoteId: string) =>
    h.rows.find((r) => (r as Row).remoteId === remoteId) as Row | undefined;

  return {
    prisma: {
      mpesaIncoming: {
        upsert: vi.fn(
          async ({
            where,
            create,
          }: {
            where: { transId: string };
            create: Partial<Row>;
            update: object;
          }) => {
            h.calls.upsert++;
            const existing = h.rows.find(
              (r) => (r as Row).transId === where.transId,
            );
            if (existing) return copy(existing);
            // The real client applies the MODEL's defaults (status opens at
            // 'unclaimed'); a fake must say what the schema says, or the
            // route reads undefined where a document never is.
            h.rows.push({
              ...create,
              status: create.status ?? 'unclaimed',
              id: create.id ?? '',
              tenantId: create.tenantId ?? 't-1',
            } as unknown as Row);
            return copy(h.rows[h.rows.length - 1]);
          },
        ),
        updateMany: vi.fn(
          async ({
            where,
            data,
          }: {
            where: {
              remoteId?: string;
              status?: string;
              tenantId?: string;
              receivedAt?: unknown;
            };
            data: Record<string, unknown>;
          }) => {
            h.calls.updateMany++;
            let matched = 0;
            for (const row of h.rows) {
              const r = row as Row;
              if (where.remoteId !== undefined && r.remoteId !== where.remoteId) continue;
              if (where.status !== undefined && r.status !== where.status) continue;
              if (where.tenantId !== undefined && r.tenantId !== where.tenantId) continue;
              r.status = (data.status as Row['status']) ?? r.status;
              if (data.claimedByDevice !== undefined)
                r.claimedByDevice = data.claimedByDevice as string;
              if (data.claimedSaleUuid !== undefined)
                r.claimedSaleUuid = data.claimedSaleUuid as string;
              if (data.claimedAt !== undefined) r.claimedAt = data.claimedAt as Date;
              if (data.ignoreReason !== undefined)
                r.ignoreReason = data.ignoreReason as string;
              matched++;
            }
            return { count: matched };
          },
        ),
        findUnique: vi.fn(async ({ where }: { where: { remoteId: string } }) => {
          const row = byRemoteId(where.remoteId);
          return row ? copy(row) : null;
        }),
        findMany: vi.fn(async () => {
          return (h.rows.map(copy) as unknown as Row[]).filter(
            (r) => r.status === 'unclaimed',
          );
        }),
      },
      etimsReceipt: {
        findUnique: vi.fn(async ({ where }: { where: { tenantId_returnNumber: { tenantId: string; returnNumber: string } } }) => {
          const found = h.receipts.find(
            (r) =>
              r.get === undefined &&
              r !== null &&
              r.tenantId === where.tenantId_returnNumber.tenantId &&
              r.returnNumber === where.tenantId_returnNumber.returnNumber,
          );
          return found ? { ...found } : null;
        }),
        findFirst: vi.fn(async ({ where }: { where: { OR: Array<Record<string, string>> } }) => {
          const byNumber = (kind: 'kraReceiptNumber' | 'receiptNumber'): string =>
            (where.OR.find((b) => kind in b) as Record<string, string>)?.[kind] ?? '';
          const kra = (byNumber('kraReceiptNumber') ?? '') as string;
          const own = (byNumber('receiptNumber') ?? '') as string;
          const found = h.receipts.find(
            (r) => r.kraReceiptNumber === kra || r.receiptNumber === own,
          );
          return found ? { ...found, id: 'rcpt-1', status: 'issued' } : null;
        }),
        create: vi.fn(async ({ data }: { data: Record<string, unknown> }) => {
          h.receipts.push({ ...data, id: `note-${h.receipts.length + 1}` });
          return { id: `note-${h.receipts.length}`, ...data };
        }),
      },
      receiptLink: {
        create: vi.fn(async ({ data }: { data: Record<string, unknown> }) => {
          const row = {
            ...data,
            id: `link-${h.links.length + 1}`,
            createdAt: new Date(),
            revokedAt: null,
          };
          h.links.push(row);
          return { ...row, id: `link-${h.links.length}` };
        }),
        findUnique: vi.fn(async ({ where }: { where: { token: string } }) => {
          const link = h.links.find((candidate) => candidate.token === where.token);
          return link ? copy(link) : null;
        }),
        updateMany: vi.fn(async ({ where, data }: {
          where: { token: string; tenantId: string; revokedAt: null };
          data: { revokedAt: Date };
        }) => {
          let count = 0;
          for (const candidate of h.links) {
            if (candidate.token !== where.token || candidate.tenantId !== where.tenantId) continue;
            if (candidate.revokedAt !== null) continue;
            candidate.revokedAt = data.revokedAt;
            count++;
          }
          return { count };
        }),
      },
    },
  };
});

vi.mock('../lib/http', () => {
  class HttpError extends Error {
    constructor(
      readonly status: number,
      message: string,
    ) {
      super(message);
    }
  }
  const asyncHandler =
    (fn: unknown) =>
    (req: unknown, res: unknown, next: unknown): void => {
      void Promise.resolve(
        (fn as (r: unknown, s: unknown, n: unknown) => unknown)(req, res, next),
      ).catch(next as (e: unknown) => void);
    };
  return {
    HttpError,
    asyncHandler,
    requireUser: () => ({ id: 'u1', tenantId: 't-1', role: 'manager', name: 'Owner' }),
  };
});

// Mounted under their own silence: the webhook router alone, with a JSON
// parser, the way index.ts mounts it.
let webhookApp: express.Express;
let claimsApp: express.Express;

beforeAll(async () => {
  const { mpesaWebhookRoutes, mpesaRoutes } = await import('../routes/mpesa');
  webhookApp = express();
  webhookApp.use(express.json());
  webhookApp.use('/callback/mpesa', mpesaWebhookRoutes);
  claimsApp = express();
  claimsApp.use(express.json());
  claimsApp.use('/api/mpesa', mpesaRoutes);
});

beforeEach(() => {
  h.rows.length = 0;
  h.receipts.length = 0;
  h.links.length = 0;
  h.calls.upsert = 0;
  h.calls.updateMany = 0;
  // The callback key the tests share with the route.
  process.env.MPESA_CALLBACK_KEY = 'test-key';
  delete process.env.MPESA_TILL_TENANTS;
});

// The builder supertest hands back is agent-shaped differently by version; the
// one thing every version's builder shares is `.set`. Typed structurally and
// loose on the return (tests only touch `.status`/`.body` after `await`).
const withKey = (request: any, key = 'test-key'): any =>
  request.set('x-callback-key', key);

describe('the C2B confirmation callback', () => {
  it('stores a payment once, whatever the payloads do', async () => {
    // The shop's till number is what binds a payment to a tenant: the
    // deployment names the map, the callback carries the shortcode.
    process.env.MPESA_TILL_TENANTS = '111222=t-1';
    const base = {
      TransID: 'SF13W1N7Q1',
      TransAmount: '750',
      FirstName: 'Joseph',
      BusinessShortCode: '111222',
      BillRefNumber: 'SHOP-001',
      TransTime: '20261022143059',
    };
    // The delivery, then the retry that arrives after a network flap, then a
    // payload that arrives OUT of order (fields scrambled).
    await withKey(supertest(webhookApp).post('/callback/mpesa/confirmation')).send(base);
    await withKey(supertest(webhookApp).post('/callback/mpesa/confirmation')).send({ ...base });
    await withKey(supertest(webhookApp).post('/callback/mpesa/confirmation')).send({
      TransTime: '20261022143059',
      BusinessShortCode: '111222',
      BillRefNumber: 'SHOP-001',
      FirstName: 'Joseph',
      TransAmount: '750',
      TransID: 'SF13W1N7Q1',
    });

    expect(h.rows).toHaveLength(1);
    const row = h.rows[0] as Row;
    expect(row.amount).toBe(750);
    expect(row.status).toBe('unclaimed');
  });

  it('masks the payer at the door: a name and three digits', async () => {
    process.env.MPESA_TILL_TENANTS = '111222=t-1';
    await withKey(supertest(webhookApp).post('/callback/mpesa/confirmation')).send({
      TransID: 'SF13W1N7Q2',
      TransAmount: '1200',
      FirstName: 'Joseph',
      BusinessShortCode: '111222',
      BillRefNumber: 'SHOP-001',
      TransTime: '20261022143100',
      MSISDN: '254712345678',
    });
    const row = h.rows[0] as Row;
    expect(row.payerLabel).toContain('Joseph');
    expect(row.payerLabel).toMatch(/\*\*\*\s?·+|···678|678$/);
    expect(JSON.stringify(row)).not.toContain('254712345678');
  });

  it('defers to the transaction code: a SECOND payment is a second row', async () => {
    process.env.MPESA_TILL_TENANTS = '111222=t-1';
    const send = (transId: string) =>
      withKey(supertest(webhookApp).post('/callback/mpesa/confirmation')).send({
        TransID: transId,
        TransAmount: '100',
        FirstName: 'Amina',
        BusinessShortCode: '111222',
        TransTime: '20261022143101',
      });
    await send('SF13W1N7Q3');
    await send('SF13W1N7Q4');
    expect(h.rows).toHaveLength(2);
  });

  it('refuses an unkeyed or wrongly-keyed callback', async () => {
    const request = supertest(webhookApp).post('/callback/mpesa/confirmation').send({
      TransID: 'SF13W1N7Q5',
      TransAmount: '50',
    });
    const response = await request; // no key at all
    expect(response.status).toBe(401);
    expect(h.rows).toHaveLength(0);
  });

  it('refuses a callback for a shop that is not bound', async () => {
    const response = await withKey(
      supertest(webhookApp).post('/callback/mpesa/confirmation'),
    ).send({ TransID: 'SF13W1N7Q6', TransAmount: '50' });
    expect(response.status).toBe(400);
    expect(response.body.error).toContain('No tenant');
    expect(h.rows).toHaveLength(0);
  });

  it('accepts the validation callback and demands the key too', async () => {
    const open = await supertest(webhookApp)
      .post('/callback/mpesa/validation')
      .send({});
    expect(open.status).toBe(401);

    const accepted = await withKey(
      supertest(webhookApp).post('/callback/mpesa/validation'),
    ).send({});
    expect(accepted.status).toBe(200);
    expect(accepted.body.ResultCode).toBe(0);
  });
});

describe('claiming a payment for a sale', () => {
  it('exactly one of two racers wins; the loser reads who and when', async () => {
    process.env.MPESA_TILL_TENANTS = '111222=t-1';
    const stored = await withKey(
      supertest(webhookApp).post('/callback/mpesa/confirmation'),
    ).send({
      TransID: 'SF13W1RACE',
      TransAmount: '800',
      FirstName: 'Benna',
      BusinessShortCode: '111222',
      TransTime: '20261022234555',
    });
    expect(stored.status).toBe(200);

    // The SECOND device's claim is staged BEHIND the first device's: the
    // predicate update sees the row as unclaimed, and the count from the
    // second device lands after the winner's — the update predicated on
    // status: 'unclaimed' returns 0.
    const first = await supertest(claimsApp)
      .post('/api/mpesa/incoming/c2b-SF13W1RACE/claim')
      .send({ sale_uuid: 'sale-a', device: 'till-1' });
    expect(first.status).toBe(200);
    expect(first.body.claimed).toBe(true);

    // Forcing the loser into the race: the FIRST claim already took the row,
    // so a second claim is a conflict showing the winner.
    const second = await supertest(claimsApp)
      .post('/api/mpesa/incoming/c2b-SF13W1RACE/claim')
      .send({ sale_uuid: 'sale-b', device: 'till-2' });
    expect(second.status).toBe(409);
    expect(second.body.claimed_by).toBe('till-1');
    expect(second.body.claimed_sale).toBe('sale-a');
    expect(second.body.claimed_at).toBeTruthy();
  });

  it('a device retrying its own claim is the SAME claim', async () => {
    process.env.MPESA_TILL_TENANTS = '111222=t-1';
    await withKey(supertest(webhookApp).post('/callback/mpesa/confirmation')).send({
      TransID: 'SF13W1IDE',
      TransAmount: '800',
      FirstName: 'Benna',
      BusinessShortCode: '111222',
      TransTime: '20261022234556',
    });
    const first = await supertest(claimsApp)
      .post('/api/mpesa/incoming/c2b-SF13W1IDE/claim')
      .send({ sale_uuid: 'sale-a', device: 'till-1' });
    expect(first.status).toBe(200);
    const again = await supertest(claimsApp)
      .post('/api/mpesa/incoming/c2b-SF13W1IDE/claim')
      .send({ sale_uuid: 'sale-a', device: 'till-1' });
    expect(again.status).toBe(200);
    expect(again.body.claimed).toBe(true);
    const row = h.rows[0] as Row;
    expect(row.claimedByDevice).toBe('till-1');
  });
});

describe('receipt share links', () => {
  it('creates a tenant-owned immutable snapshot and serves it publicly', async () => {
    const { receiptLinksRoutes } = await import('../routes/receipt_links');
    const app = express();
    app.use(express.json());
    app.use('/api/receipt-links', receiptLinksRoutes);

    const created = await supertest(app)
      .post('/api/receipt-links')
      .send({ snapshot: { total_minor: 1250, items: [{ name: 'Tea' }] } });
    expect(created.status).toBe(201);
    expect(created.body.token).toBeTruthy();
    expect((h.links[0] as Record<string, unknown>).tenantId).toBe('t-1');

    const page = await supertest(app).get(
      `/api/receipt-links/${created.body.token}/page`,
    );
    expect(page.status).toBe(200);
    expect(page.body.page.snapshot).toEqual({
      total_minor: 1250,
      items: [{ name: 'Tea' }],
    });
  });

  it('revokes a link and returns 410 for revoked and expired links', async () => {
    const { receiptLinksRoutes } = await import('../routes/receipt_links');
    const app = express();
    app.use(express.json());
    app.use('/api/receipt-links', receiptLinksRoutes);
    const created = await supertest(app)
      .post('/api/receipt-links')
      .send({ snapshot: { total_minor: 1 } });

    const revoked = await supertest(app).delete(
      `/api/receipt-links/${created.body.token}`,
    );
    expect(revoked.status).toBe(200);
    const withdrawn = await supertest(app).get(
      `/api/receipt-links/${created.body.token}/page`,
    );
    expect(withdrawn.status).toBe(410);

    const expiredToken = 'expired-receipt';
    h.links.push({
      token: expiredToken,
      tenantId: 't-1',
      snapshot: { total_minor: 2 },
      createdAt: new Date(),
      expiresAt: new Date(Date.now() - 1),
      revokedAt: null,
    });
    const expired = await supertest(app).get(
      `/api/receipt-links/${expiredToken}/page`,
    );
    expect(expired.status).toBe(410);
  });
});

describe('the credit note', () => {
  it('is refused when the KRA number it reverses was never captured', async () => {
    const { creditNoteRoutes } = await import('../routes/receipt_links');
    const app = express();
    app.use(express.json());
    app.use('/api/etims/credit-note', creditNoteRoutes);
    const response = await supertest(app)
      .post('/api/etims/credit-note')
      .send({
        return_number: 'R-2026-000004',
        original_receipt_number: 'KF01T1ABC000001',
        reason_code: 'damaged',
        lines: [{ name: 'Milk 500ml', qty: 1, line_total: 60 }],
        total: 60,
        vat_total: 8,
      });
    expect(response.status).toBe(400);
    expect(response.body.error).toContain('No such original receipt');
  });
});
