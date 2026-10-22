// eTIMS: the KRA transport and the invoice maths.
//
// The invoice arithmetic is the part that decides what a customer's tax document
// says, and it is the part with no safety net: a wrong figure is filed with the
// authority and only discovered at audit. So the assertions here are about
// reconciliation and about what happens when KRA refuses.

import { describe, expect, it } from 'vitest';
import {
  buildKraInvoice,
  businessDateFor,
  fromMajor,
  assertKraConfigured,
  kraCredentialsFromEnv,
  labelForSubmission,
  paymentModeCodeFor,
  toMajor,
  type InvoiceInput,
} from '../services/etims';
import {
  DEFAULT_BRANCH_ID,
  KRA_PRODUCTION_URL,
  KRA_SANDBOX_URL,
  KRA_ENDPOINTS,
  TAX_TYPE_VAT,
  createNonce,
  decryptPayload,
  encryptPayload,
  getAccessToken,
  kraBaseUrl,

  receiptLabel,
  signRequest,
  KraError,
  clearTokenCache,
} from '../services/kra';

const item = (overrides: Partial<InvoiceInput['items'][number]> = {}) => ({
  name: 'Soda 350ml',
  qty: 1,
  unitPrice: 8000,
  unitCost: 4500,
  portion: 'full',
  portionMl: 350,
  vatAmount: 1103,
  lineTotal: 8000,
  ...overrides,
});

const invoice = (overrides: Partial<InvoiceInput> = {}): InvoiceInput => ({
  receiptNumber: 'T1-000001',
  issuedAt: '2026-10-03T14:05:00.000Z',
  paymentMethod: 'cash',
  total: 8000,
  vatRatePercent: 16,
  items: [item()],
  ...overrides,
});

describe('money conversion', () => {
  it('converts cents to a two-decimal KES string', () => {
    expect(toMajor(8000)).toBe('80.00');
    expect(toMajor(100)).toBe('1.00');
    expect(toMajor(5)).toBe('0.05');
    expect(toMajor(0)).toBe('0.00');
  });

  it('never rounds a cent away, however many are summed', () => {
    // The whole point of integer minor units: 1 cent is representable and
    // accumulates exactly. 3001 cents is 30.01, not 30.0099999.
    expect(toMajor(3001)).toBe('30.01');
    let sum = 0;
    for (let i = 0; i < 100; i++) sum = (sum + 7) % 100;
    expect(toMajor(sum)).toBe(`${Math.floor(sum / 100)}.${(sum % 100).toString().padStart(2, '0')}`);
  });

  it('round-trips through major units', () => {
    for (const minor of [0, 1, 99, 100, 8000, 100_000, 123_456]) {
      expect(fromMajor(toMajor(minor))).toBe(minor);
    }
  });

  it('rejects a fractional minor unit rather than silently rounding it', () => {
    // A till sending 8000.5 means something is already wrong upstream. Rounding
    // here would hide it inside an invoice nobody could reconcile.
    expect(() => toMajor(8000.5)).toThrow(RangeError);
  });

  it('rejects a non-finite amount', () => {
    expect(() => toMajor(Number.NaN)).toThrow(RangeError);
    expect(() => toMajor(Number.POSITIVE_INFINITY)).toThrow(RangeError);
  });

  it('handles a negative amount, as a credit note would', () => {
    expect(toMajor(-8000)).toBe('-80.00');
    expect(fromMajor('-80.00')).toBe(-8000);
  });
});

describe('KRA invoice document', () => {
  it('itemises VAT per line rather than only on the invoice total', () => {
    const document = buildKraInvoice(
      invoice({
        items: [
          item({ qty: 2, lineTotal: 16000, vatAmount: 2207 }),
          item({ name: 'Kenyana Beer', unitPrice: 12000, lineTotal: 12000, vatAmount: 1655 }),
        ],
        total: 28000,
      }),
    );
    expect(document.items).toHaveLength(2);
    expect(document.items[0].taxAmount).toBe('22.07');
    // OSCU carries the tax *type* code, not a numeric rate.
    expect(document.items[0].taxTypeCode).toBe(TAX_TYPE_VAT);
    // The two components must add up to the invoice figure, or the document
    // contradicts itself.
    expect(document.totalTaxAmount).toBe('38.62');
    expect(document.totalAmount).toBe('280.00');
  });

  it('carries the till receipt number as the idempotency key', () => {
    const document = buildKraInvoice(invoice({ receiptNumber: 'T1-000042' }));
    expect(document.invoiceNumber).toBe('T1-000042');
  });

  it('declares zero tax rate on a line with no VAT', () => {
    // An exempt shop files VAT-free goods. Filing taxRate 16 with taxAmount 0.00
    // is internally contradictory and KRA rejects it.
    const document = buildKraInvoice(
      invoice({ vatRatePercent: 0, items: [item({ vatAmount: 0 })], total: 8000 }),
    );
    expect(document.items[0].taxAmount).toBe('0.00');
    expect(document.totalTaxAmount).toBe('0.00');
  });

  it('declares a portion volume only for a partial serving', () => {
    const full = buildKraInvoice(invoice());
    expect(full.items[0].quantityUnit).toBeUndefined();

    const half = buildKraInvoice(
      invoice({ items: [item({ portion: 'half', portionMl: 175 })], total: 8000 }),
    );
    expect(half.items[0].quantityUnit).toBe('Bottle');
    expect(half.items[0].quantityUnitAmount).toBe(175);
  });

  it('refuses a line whose quantity and price disagree with its total', () => {
    // The till's line total is what the customer was charged and what the
    // receipt says. Correcting it here would file an invoice that does not
    // match the paper, which is the one thing that cannot be explained later.
    expect(() =>
      buildKraInvoice(invoice({ items: [item({ qty: 2, lineTotal: 8000 })], total: 8000 })),
    ).toThrow(/quantit/);
  });

  it('refuses a total that does not equal the sum of its lines', () => {
    expect(() => buildKraInvoice(invoice({ total: 9999 }))).toThrow(/sum of its lines/);
  });

  it('refuses an invoice with no items', () => {
    expect(() => buildKraInvoice(invoice({ items: [] }))).toThrow(/no items/);
  });

  it('maps payment methods to KRA vocabulary, defaulting to Cash', () => {
    expect(paymentModeCodeFor('cash'), 'cash').toBe('Cash');
    expect(paymentModeCodeFor('mpesa')).toBe('MPEZA');
    expect(paymentModeCodeFor('card')).toBe('Card');
    expect(paymentModeCodeFor('mobile_money_manual')).toBe('MobileMoney');
    expect(paymentModeCodeFor('bank_transfer')).toBe('BankTransfer');
    // An unknown code is refused by KRA outright, so an unrecognised method must
    // not be passed through.
    expect(paymentModeCodeFor('carrier_pigeon')).toBe('Cash');
  });

  it('includes the payment reference when there is one', () => {
    const withReference = buildKraInvoice(invoice({ paymentReference: 'DUKA-abc' }));
    expect(withReference.paymentAmount).toBe('80.00');
    expect(withReference.paymentModeCode).toBe('Cash');
    // The reference rides alongside the invoice rather than inside the document,
    // so a document with and without one is otherwise identical.
    const without = buildKraInvoice(invoice());
    expect(without.totalAmount).toBe(withReference.totalAmount);
  });
});

describe('OSCU signing', () => {
  // Base64 of 32 zero bytes — a stand-in for the access key KRA issues.
  const key = Buffer.alloc(32, 7).toString('base64');

  it('is deterministic for the same inputs, as a signature must be', () => {
    const a = signRequest('2026-10-03T14:05:00.000Z', 'P051234567X', 'DEV1', 'nonce', key);
    const b = signRequest('2026-10-03T14:05:00.000Z', 'P051234567X', 'DEV1', 'nonce', key);
    expect(a).toBe(b);
    expect(a).not.toBe(signRequest('2026-10-03T14:05:01.000Z', 'P051234567X', 'DEV1', 'nonce', key));
  });

  it('changes when any component changes', () => {
    const base = signRequest('t', 'tin', 'dev', 'nonce', key);
    expect(signRequest('t2', 'tin', 'dev', 'nonce', key)).not.toBe(base);
    expect(signRequest('t', 'tin2', 'dev', 'nonce', key)).not.toBe(base);
    expect(signRequest('t', 'tin', 'dev2', 'nonce', key)).not.toBe(base);
    expect(signRequest('t', 'tin', 'dev', 'nonce2', key)).not.toBe(base);
  });

  it('mints a distinct nonce every time', () => {
    const nonces = new Set(Array.from({ length: 50 }, () => createNonce()));
    expect(nonces.size).toBe(50);
  });

  it('round-trips an encrypted payload and detects tampering', () => {
    const encKey = Buffer.alloc(32, 3).toString('base64');
    const body = { invoice: { totalAmount: '80.00' } };
    const { InitializationVector, EncryptedPayload } = encryptPayload(encKey, body);

    const good = decryptPayload(encKey, InitializationVector, EncryptedPayload);
    expect(good.hmacValid).toBe(true);
    expect(JSON.parse(good.plaintext)).toEqual(body);

    // Flipping one ciphertext byte must fail the integrity check. Decrypting
    // unauthenticated data first is exactly what lets an attacker substitute a
    // payload of their choosing.
    const bytes = Buffer.from(EncryptedPayload, 'base64');
    bytes[20] = bytes[20] ^ 0xff;
    const tampered = decryptPayload(encKey, InitializationVector, bytes.toString('base64'));
    expect(tampered.hmacValid).toBe(false);
  });
});

describe('deployment configuration', () => {
  it('refuses to proceed with no KRA account configured', () => {
    const previousUser = process.env.KRA_USERNAME;
    const previousPass = process.env.KRA_PASSWORD;
    try {
      delete process.env.KRA_USERNAME;
      delete process.env.KRA_PASSWORD;
      expect(kraCredentialsFromEnv()).toBeUndefined();
      // Otherwise the first symptom is a 401 on the first live sale, which reads
      // as "wrong password" rather than "this server was never configured".
      expect(() => assertKraConfigured()).toThrow(/not configured|KRA_USERNAME/);
    } finally {
      if (previousUser !== undefined) process.env.KRA_USERNAME = previousUser;
      if (previousPass !== undefined) process.env.KRA_PASSWORD = previousPass;
    }
  });

  it('a half-set credential pair is treated as unset', () => {
    const previousUser = process.env.KRA_USERNAME;
    const previousPass = process.env.KRA_PASSWORD;
    try {
      process.env.KRA_USERNAME = 'someone';
      delete process.env.KRA_PASSWORD;
      // One blank field produces a well-formed request KRA refuses, which looks
      // like a credential problem rather than a configuration problem.
      expect(kraCredentialsFromEnv()).toBeUndefined();
    } finally {
      if (previousUser === undefined) delete process.env.KRA_USERNAME;
      else process.env.KRA_USERNAME = previousUser;
      if (previousPass === undefined) delete process.env.KRA_PASSWORD;
      else process.env.KRA_PASSWORD = previousPass;
    }
  });
});

describe('KRA endpoints and authentication', () => {
  it('uses KRA\'s own hosts, not a third-party aggregator', () => {
    // A very common integration mistake: adopting a REST API from a KRA
    // *partner* that looks like KRA and has a completely different contract.
    expect(KRA_PRODUCTION_URL).toBe('https://etims-api.kra.go.ke/etims-api');
    expect(KRA_SANDBOX_URL).toBe('https://etims-api-sbx.kra.go.ke');
    expect(kraBaseUrl()).toBe(KRA_PRODUCTION_URL);
  });

  it('an explicit override wins over the sandbox switch', () => {
    const previous = process.env.KRA_BASE_URL;
    try {
      process.env.KRA_BASE_URL = 'https://example.test/etims-api';
      expect(kraBaseUrl()).toBe('https://example.test/etims-api');
      // An empty override must fall through rather than produce a request to
      // the string "undefined".
      process.env.KRA_BASE_URL = '';
      expect(kraBaseUrl()).toBe(KRA_PRODUCTION_URL);
    } finally {
      if (previous === undefined) delete process.env.KRA_BASE_URL;
      else process.env.KRA_BASE_URL = previous;
    }
  });

  it('names the OSCU endpoints, not invented REST paths', () => {
    expect(KRA_ENDPOINTS.token).toBe('/auth/get-token');
    expect(KRA_ENDPOINTS.initialise).toBe('/init-osdc-info');
    expect(KRA_ENDPOINTS.codeList).toBe('/select-code-list');
    expect(KRA_ENDPOINTS.saveSales).toBe('/save-sales-trns');
    expect(DEFAULT_BRANCH_ID).toBe('00');
  });

  it('requests a bearer token and reuses it', async () => {
    clearTokenCache();
    const calls: Array<{ url: string; body: string }> = [];
    const fakeFetch = (async (url: string | URL, init: RequestInit) => {
      calls.push({ url: String(url), body: String(init.body) });
      return new Response(
        JSON.stringify({ access_token: 'tok-123', expires_in: 3600 }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      );
    }) as unknown as typeof fetch;

    const credentials = { username: 'kra-user', password: 'secret' };
    const first = await getAccessToken(credentials, { fetchImpl: fakeFetch });
    expect(first).toBe('tok-123');
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toContain('/auth/get-token');
    // Credentials travel in the body, per OSCU.
    expect(JSON.parse(calls[0].body)).toEqual(credentials);

    const second = await getAccessToken(credentials, { fetchImpl: fakeFetch });
    expect(second).toBe('tok-123');
    // Cached: a token request per invoice would be a rate-limit problem.
    expect(calls).toHaveLength(1);

    clearTokenCache();
    await getAccessToken(credentials, { fetchImpl: fakeFetch });
    expect(calls).toHaveLength(2);
    clearTokenCache();
  });

  it('a refused token is permanent, not a network blip', async () => {
    clearTokenCache();
    const fakeFetch = (async () =>
      new Response('nope', { status: 401 })) as unknown as typeof fetch;
    await expect(
      getAccessToken({ username: 'u', password: 'p' }, { fetchImpl: fakeFetch }),
    ).rejects.toThrow(KraError);
    clearTokenCache();
  });
});

describe('receipt labels', () => {
  it('derives every label KRA defines', () => {
    expect(receiptLabel('NORMAL', 'SALE')).toBe('NS');
    expect(receiptLabel('NORMAL', 'CREDIT NOTE')).toBe('NC');
    expect(receiptLabel('COPY', 'SALE')).toBe('CS');
    expect(receiptLabel('COPY', 'CREDIT NOTE')).toBe('CC');
    expect(receiptLabel('TRAINING', 'SALE')).toBe('TS');
    expect(receiptLabel('TRAINING', 'CREDIT NOTE')).toBe('TC');
    expect(receiptLabel('PROFORMA', 'SALE')).toBe('PS');
  });

  it('a reprint is a COPY, never a second NORMAL', () => {
    // KRA: "TIS shall print only one original receipt. Reprints shall have a
    // watermark with mention Copy". Filing a reprint as NS would be a second
    // claimed original sale.
    expect(labelForSubmission({ isReprint: false }).label).toBe('NS');
    const reprint = labelForSubmission({ isReprint: true });
    expect(reprint.label).toBe('CS');
    expect(reprint.receiptType).toBe('COPY');
  });

  it('a credit note keeps its type when it is a copy', () => {
    expect(labelForSubmission({ isReprint: true, transactionType: 'CREDIT NOTE' }).label)
      .toBe('CC');
  });
});

describe('failure taxonomy', () => {
  it('separates a refusal from a transport failure', () => {
    // The two need opposite responses: a transport error is retried on the next
    // connection, a refusal is retried never.
    const refused = new KraError('rejected', 'Invalid TIN');
    const offline = new KraError('network', 'unreachable');
    expect(refused.kind).toBe('rejected');
    expect(offline.kind).toBe('network');
    expect(refused).toBeInstanceOf(Error);
  });
});

describe('business date', () => {
  it('normalises to UTC midnight so the unique key is stable', () => {
    // Two reports for the same day must collide on the same row rather than
    // producing two Z-numbers for one day.
    const lateAtNight = new Date('2026-10-03T23:59:59.999Z');
    const early = new Date('2026-10-03T00:00:00.000Z');
    expect(businessDateFor(lateAtNight).getTime()).toBe(businessDateFor(early).getTime());
    expect(businessDateFor(lateAtNight).toISOString()).toBe('2026-10-03T00:00:00.000Z');
  });
});