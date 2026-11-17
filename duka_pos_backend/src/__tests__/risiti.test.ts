import { describe, expect, it, vi } from 'vitest';
import { buildRisitiInvoiceRequest, RisitiError, submissionOutcome, submitInvoice } from '../services/risiti';
import { taxReportingStatus } from '../services/tax_reporting';

describe('Risiti tax provider boundary', () => {
  it('maps a till invoice to the platform contract with stable identities', () => {
    const request = buildRisitiInvoiceRequest({
      tenantId: 'shop-1',
      merchantId: 'merchant-1',
      receiptNumber: 'TILL-0007',
      issuedAt: '2026-10-24T10:00:00.000Z',
      paymentMethod: 'mpesa',
      items: [{ name: 'Water big cup', qty: 2, unitPrice: 150, vatAmount: 41, lineTotal: 300 }],
    });

    expect(request.merchant_id).toBe('merchant-1');
    expect(request.external_id).toBe('shop-1:TILL-0007');
    expect(request.payment_method).toBe('06');
    expect(request.items[0]).toMatchObject({
      external_id: 'shop-1:TILL-0007:1',
      unit_price: 1.5,
      tax_type: 'B',
    });
  });

  it('never treats an accepted-but-processing invoice as issued', () => {
    expect(submissionOutcome({ terminal: false, succeeded: false, state: 'waiting_for_kra' })).toBe('pending');
    expect(submissionOutcome({ terminal: true, succeeded: false, state: 'action_required' })).toBe('action_required');
    expect(submissionOutcome({ terminal: true, succeeded: true, state: 'completed' })).toBe('issued');
  });

  it('keeps KRA inactive while exposing local VAT reporting and the planned provider', () => {
    const previous = process.env.TAX_REPORTING_ACTIVATED;
    delete process.env.TAX_REPORTING_ACTIVATED;
    try {
      expect(taxReportingStatus()).toMatchObject({
        provider: 'risiti',
        provider_name: 'Risiti by PesaStack Limited',
        tax_reporting_activated: false,
        kra_activated: false,
        local_vat_reporting: true,
      });
    } finally {
      if (previous === undefined) delete process.env.TAX_REPORTING_ACTIVATED;
      else process.env.TAX_REPORTING_ACTIVATED = previous;
    }
  });

  it('reflects an explicitly activated deployment in the status contract', () => {
    const previous = process.env.TAX_REPORTING_ACTIVATED;
    process.env.TAX_REPORTING_ACTIVATED = 'true';
    try {
      expect(taxReportingStatus()).toMatchObject({
        tax_reporting_activated: true,
        kra_activated: true,
        local_vat_reporting: true,
      });
    } finally {
      if (previous === undefined) delete process.env.TAX_REPORTING_ACTIVATED;
      else process.env.TAX_REPORTING_ACTIVATED = previous;
    }
  });

  it('treats provider rate limits as retryable and preserves the request metadata', async () => {
    const previousKey = process.env.RISITI_API_KEY;
    process.env.RISITI_API_KEY = 'test-key';
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      error: { code: 'rate_limited', message: 'Try again later' },
    }), {
      status: 429,
      headers: { 'content-type': 'application/json', 'retry-after': '7', 'x-request-id': 'req-7' },
    }));
    vi.stubGlobal('fetch', fetchMock);
    try {
      await expect(submitInvoice({
        merchant_id: 'merchant-1',
        external_id: 'shop-1:receipt-1',
        payment_method: '06',
        items: [{ external_id: 'line-1', name: 'Water', quantity: 1, unit_price: 1, tax_type: 'D' }],
      })).rejects.toMatchObject({
        name: 'RisitiError',
        kind: 'network',
        requestId: 'req-7',
        statusCode: 429,
        retryAfterSeconds: 7,
      } satisfies Partial<RisitiError>);
    } finally {
      vi.unstubAllGlobals();
      if (previousKey === undefined) delete process.env.RISITI_API_KEY;
      else process.env.RISITI_API_KEY = previousKey;
    }
  });
});
