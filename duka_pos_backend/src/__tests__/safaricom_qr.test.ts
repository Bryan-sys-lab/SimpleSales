import { afterEach, describe, expect, it, vi } from 'vitest';
import { generateDynamicQr, SafaricomQrError } from '../services/safaricom_qr';

describe('Safaricom Dynamic QR boundary', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    delete process.env.SAFARICOM_CONSUMER_KEY;
    delete process.env.SAFARICOM_CONSUMER_SECRET;
    delete process.env.SAFARICOM_BASE_URL;
  });

  it('gets a bearer token and requests a dynamic QR with a stable sale reference', async () => {
    process.env.SAFARICOM_CONSUMER_KEY = 'consumer-key';
    process.env.SAFARICOM_CONSUMER_SECRET = 'consumer-secret';
    process.env.SAFARICOM_BASE_URL = 'https://sandbox.example';
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ access_token: 'token-1' }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        ResponseCode: 'ok',
        RequestID: 'qr-request-1',
        QRCode: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB',
      }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await expect(generateDynamicQr({
      merchantName: 'Nerva Shop',
      reference: 'DUKA-12345678-1234-1234-1234-123456789abc',
      amount: 1250.6,
      transactionCode: 'BG',
      creditPartyIdentifier: '174379',
    })).resolves.toEqual({
      qrCode: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB',
      requestId: 'qr-request-1',
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    const tokenRequest = fetchMock.mock.calls[0][1] as RequestInit;
    expect((tokenRequest.headers as Record<string, string>).Authorization)
      .toBe(`Basic ${Buffer.from('consumer-key:consumer-secret').toString('base64')}`);
    const qrRequest = fetchMock.mock.calls[1][1] as RequestInit;
    expect((qrRequest.headers as Record<string, string>).Authorization).toBe('Bearer token-1');
    expect(JSON.parse(String(qrRequest.body))).toMatchObject({
      RefNo: 'DUKA-12345678-1234-1234-1234-123456789abc',
      Amount: 1251,
      TrxCode: 'BG',
      CPI: '174379',
      Size: '600',
    });
  });

  it('fails closed when Daraja credentials are absent', async () => {
    await expect(generateDynamicQr({
      merchantName: 'Nerva Shop',
      reference: 'DUKA-12345678-1234-1234-1234-123456789abc',
      amount: 100,
      transactionCode: 'PB',
      creditPartyIdentifier: '123456',
    })).rejects.toMatchObject({ kind: 'misconfigured' } satisfies Partial<SafaricomQrError>);
  });
});
