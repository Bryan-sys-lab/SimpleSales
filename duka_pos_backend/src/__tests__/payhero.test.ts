import { afterEach, describe, expect, it, vi } from 'vitest';
import { registerPaymentChannel } from '../services/payhero';
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
      short_code: 54321,
      account_number: '',
    });
    expect((request.headers as Record<string, string>).Authorization)
      .toBe('server-only-token');
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
