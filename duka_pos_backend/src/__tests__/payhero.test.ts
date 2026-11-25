import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  initiateStkPush,
  queryTransactionStatus,
  registerPaymentChannel,
} from '../services/payhero';
import { payheroReferenceFromCallback } from '../routes/payhero-callback';

describe('PayHero merchant channel integration', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    delete process.env.PAYHERO_AUTH_TOKEN;
    delete process.env.PAYHERO_ACCOUNT_ID;
  });

  it('reuses an active channel for the platform account', async () => {
    process.env.PAYHERO_AUTH_TOKEN = 'server-only-token';
    process.env.PAYHERO_ACCOUNT_ID = '42';
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        payment_channels: [{
          id: 9,
          account_id: 42,
          channel_type: 'till',
          short_code: 12345,
          is_active: true,
        }],
      }),
    });
    vi.stubGlobal('fetch', fetchMock);

    await expect(registerPaymentChannel({
      channelType: 'till',
      shortCode: '12345',
    })).resolves.toEqual({ id: 9, channelType: 'till', shortCode: '12345' });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('registers a new channel using only the merchant destination', async () => {
    process.env.PAYHERO_AUTH_TOKEN = 'server-only-token';
    process.env.PAYHERO_ACCOUNT_ID = '42';
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: true, json: async () => ({ payment_channels: [] }) })
      .mockResolvedValueOnce({ ok: true, status: 201, json: async () => ({ id: 10 }) });
    vi.stubGlobal('fetch', fetchMock);

    await expect(registerPaymentChannel({
      channelType: 'paybill',
      shortCode: '54321',
    })).resolves.toEqual({ id: 10, channelType: 'paybill', shortCode: '54321' });

    const request = fetchMock.mock.calls[1][1] as RequestInit;
    expect(JSON.parse(String(request.body))).toMatchObject({
      channel_type: 'paybill',
      account_id: 42,
      short_code: '54321',
      account_number: '',
    });
    expect((request.headers as Record<string, string>).Authorization)
      .toBe('Basic server-only-token');
  });

  it('registers a bank channel with its destination account', async () => {
    process.env.PAYHERO_AUTH_TOKEN = 'Basic server-only-token';
    process.env.PAYHERO_ACCOUNT_ID = '42';
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: true, json: async () => ({ payment_channels: [] }) })
      .mockResolvedValueOnce({ ok: true, status: 201, json: async () => ({ id: 11 }) });
    vi.stubGlobal('fetch', fetchMock);

    await expect(registerPaymentChannel({
      channelType: 'bank',
      shortCode: '802200',
      accountNumber: '1234567890',
    })).resolves.toEqual({ id: 11, channelType: 'bank', shortCode: '802200' });

    const request = fetchMock.mock.calls[1][1] as RequestInit;
    expect(JSON.parse(String(request.body))).toMatchObject({
      channel_type: 'bank',
      short_code: '802200',
      account_number: '1234567890',
    });
    expect((request.headers as Record<string, string>).Authorization)
      .toBe('Basic server-only-token');
  });

  it('initiates an STK push with the documented request and checkout ID', async () => {
    process.env.PAYHERO_AUTH_TOKEN = 'server-only-token';
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 201,
      json: async () => ({
        success: true,
        status: 'QUEUED',
        reference: 'PAY-123',
        CheckoutRequestID: 'checkout-123',
      }),
    });
    vi.stubGlobal('fetch', fetchMock);

    await expect(initiateStkPush({
      amount: 125,
      phoneNumber: '0712345678',
      channelId: 9,
      externalReference: 'PAY-123',
      customerName: 'Shop owner',
      callbackUrl: 'https://api.example.test/webhooks/payhero-callback',
    })).resolves.toMatchObject({
      reference: 'PAY-123',
      checkoutRequestId: 'checkout-123',
    });

    expect(fetchMock).toHaveBeenCalledWith(
      'https://backend.payhero.co.ke/api/v2/payments',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({
          amount: 125,
          phone_number: '0712345678',
          channel_id: 9,
          provider: 'm-pesa',
          external_reference: 'PAY-123',
          customer_name: 'Shop owner',
          callback_url: 'https://api.example.test/webhooks/payhero-callback',
        }),
      }),
    );
  });

  it('queries transaction status using the documented reference parameter', async () => {
    process.env.PAYHERO_AUTH_TOKEN = 'server-only-token';
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        success: true,
        status: 'SUCCESS',
        reference: 'PAY/123',
        CheckoutRequestID: 'checkout-123',
      }),
    });
    vi.stubGlobal('fetch', fetchMock);

    await expect(queryTransactionStatus('PAY/123')).resolves.toMatchObject({
      success: true,
      status: 'SUCCESS',
      reference: 'PAY/123',
    });
    expect(fetchMock).toHaveBeenCalledWith(
      'https://backend.payhero.co.ke/api/v2/transaction-status?reference=PAY%2F123',
      expect.objectContaining({ headers: expect.objectContaining({
        Authorization: 'Basic server-only-token',
      }) }),
    );
  });

  it('extracts the documented nested callback reference without trusting its status', () => {
    expect(payheroReferenceFromCallback({
      status: 'success',
      response: { ExternalReference: 'DUKA-12345678-1234-1234-1234-123456789abc' },
    })).toBe('DUKA-12345678-1234-1234-1234-123456789abc');
    expect(payheroReferenceFromCallback({ reference: 'DUKA-ref' })).toBe('DUKA-ref');
    expect(payheroReferenceFromCallback(null)).toBeUndefined();
  });
});
