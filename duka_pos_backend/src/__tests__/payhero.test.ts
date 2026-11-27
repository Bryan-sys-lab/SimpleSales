import { afterEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  tenant: { findFirst: vi.fn() },
  registration: {
    findUnique: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    updateMany: vi.fn(),
  },
}));

vi.mock('../lib/prisma', () => ({
  prisma: {
    tenant: mocks.tenant,
    payHeroChannelRegistration: mocks.registration,
  },
}));

import {
  initiateStkPush,
  normalizeMpesaPhone,
  payHeroCallbackUrl,
  payHeroConfigurationStatus,
  queryTransactionStatus,
  registerPaymentChannel,
} from '../services/payhero';
import { payheroReferenceFromCallback } from '../routes/payhero-callback';

const accountId = 42;

function configurePayHero() {
  process.env.PAYHERO_AUTH_TOKEN = 'server-only-token';
  process.env.PAYHERO_ACCOUNT_ID = String(accountId);
  process.env.PAYHERO_CHANNEL_SETTLEMENT_CONFIRMED = 'true';
  process.env.PAYHERO_AMOUNT_VERIFICATION_CONFIRMED = 'true';
  process.env.PUBLIC_API_URL = 'https://api.example.test/';
}

function providerResponse(data: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => data,
  } as Response;
}

function walletResponse(id = accountId): Response {
  return providerResponse({ account_id: id });
}

function channelResponse(params: {
  id: number;
  channelType: 'till' | 'paybill' | 'bank';
  shortCode: string;
  accountNumber: string;
}): Response {
  return providerResponse({
    id: params.id,
    account_id: accountId,
    channel_type: params.channelType,
    short_code: params.shortCode,
    account_number: params.accountNumber,
    description: 'SimpleSales channel',
    is_active: true,
  }, 201);
}

describe('PayHero integration', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
    for (const key of [
      'PAYHERO_AUTH_TOKEN',
      'PAYHERO_ACCOUNT_ID',
      'PAYHERO_CHANNEL_SETTLEMENT_CONFIRMED',
      'PAYHERO_AMOUNT_VERIFICATION_CONFIRMED',
      'PUBLIC_API_URL',
    ]) {
      delete process.env[key];
    }
  });

  it('refuses channel registration until central settlement ownership is confirmed', async () => {
    process.env.PAYHERO_AUTH_TOKEN = 'server-only-token';
    process.env.PAYHERO_ACCOUNT_ID = String(accountId);
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    await expect(registerPaymentChannel({
      tenantId: 'tenant-a',
      channelType: 'till',
      shortCode: '12345',
    })).rejects.toThrow('Central-account merchant settlement has not been confirmed');

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('reuses an exact active channel after verifying the configured PayHero account', async () => {
    configurePayHero();
    mocks.registration.findUnique.mockResolvedValue(null);
    mocks.registration.create.mockResolvedValue({});
    mocks.tenant.findFirst.mockResolvedValue(null);
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(walletResponse())
      .mockResolvedValueOnce(providerResponse({
        payment_channels: [{
          id: 9,
          account_id: accountId,
          channel_type: 'till',
          short_code: '12345',
          account_number: '',
          is_active: true,
        }],
        pagination: { next_page: null },
      }));
    vi.stubGlobal('fetch', fetchMock);

    await expect(registerPaymentChannel({
      tenantId: 'tenant-a',
      channelType: 'till',
      shortCode: '12345',
    })).resolves.toEqual({ id: 9, channelType: 'till', shortCode: '12345' });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(mocks.registration.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ tenantId: 'tenant-a', channelId: 9, status: 'ACTIVE' }),
    }));
  });

  it('registers a PayBill and verifies the returned channel identity', async () => {
    configurePayHero();
    mocks.registration.findUnique.mockResolvedValue(null);
    mocks.registration.create.mockResolvedValue({});
    mocks.registration.update.mockResolvedValue({});
    mocks.tenant.findFirst.mockResolvedValue(null);
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(walletResponse())
      .mockResolvedValueOnce(providerResponse({
        payment_channels: [],
        pagination: { next_page: null },
      }))
      .mockResolvedValueOnce(channelResponse({
        id: 10,
        channelType: 'paybill',
        shortCode: '54321',
        accountNumber: '',
      }));
    vi.stubGlobal('fetch', fetchMock);

    await expect(registerPaymentChannel({
      tenantId: 'tenant-a',
      channelType: 'paybill',
      shortCode: '54321',
    })).resolves.toEqual({ id: 10, channelType: 'paybill', shortCode: '54321' });

    const request = fetchMock.mock.calls[2][1] as RequestInit;
    expect(JSON.parse(String(request.body))).toMatchObject({
      channel_type: 'paybill',
      account_id: accountId,
      short_code: '54321',
      account_number: '',
    });
    expect((request.headers as Record<string, string>).Authorization)
      .toBe('Basic server-only-token');
    expect(mocks.registration.update).toHaveBeenCalledWith(expect.objectContaining({
      data: { status: 'ACTIVE', channelId: 10 },
    }));
  });

  it('checks every advertised page and refuses ambiguous duplicate channels', async () => {
    configurePayHero();
    const channel = {
      id: 9,
      account_id: accountId,
      channel_type: 'till',
      short_code: '12345',
      account_number: '',
      is_active: true,
    };
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(walletResponse())
      .mockResolvedValueOnce(providerResponse({
        payment_channels: [channel],
        pagination: { next_page: 2 },
      }))
      .mockResolvedValueOnce(providerResponse({
        payment_channels: [{ ...channel, id: 10 }],
        pagination: { next_page: null },
      }));
    vi.stubGlobal('fetch', fetchMock);

    await expect(registerPaymentChannel({
      tenantId: 'tenant-a',
      channelType: 'till',
      shortCode: '12345',
    })).rejects.toThrow('PayHero contains duplicate active channels');

    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(String(fetchMock.mock.calls[2][0])).toContain('page=2');
    expect(mocks.registration.create).not.toHaveBeenCalled();
  });

  it('requires a bank account number and sends it only for bank registration', async () => {
    configurePayHero();
    await expect(registerPaymentChannel({
      tenantId: 'tenant-a',
      channelType: 'bank',
      shortCode: '802200',
    })).rejects.toThrow('PayHero channel destination is incomplete');
    expect(mocks.registration.findUnique).not.toHaveBeenCalled();
  });

  it('initiates STK using Basic auth and captures the distinct provider reference', async () => {
    configurePayHero();
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(walletResponse())
      .mockResolvedValueOnce(providerResponse({
        success: true,
        status: 'QUEUED',
        reference: 'provider-123',
        CheckoutRequestID: 'checkout-123',
      }, 201));
    vi.stubGlobal('fetch', fetchMock);

    await expect(initiateStkPush({
      amount: 125,
      phoneNumber: '0712345678',
      channelId: 9,
      externalReference: 'DUKA-00000000-0000-0000-0000-000000000001',
      customerName: 'Shop owner',
      callbackUrl: 'https://api.example.test/webhooks/payhero-callback',
    })).resolves.toMatchObject({
      providerReference: 'provider-123',
      checkoutRequestId: 'checkout-123',
    });

    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      'https://backend.payhero.co.ke/api/v2/payments',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({ Authorization: 'Basic server-only-token' }),
        body: JSON.stringify({
          amount: 125,
          phone_number: '254712345678',
          channel_id: 9,
          provider: 'm-pesa',
          external_reference: 'DUKA-00000000-0000-0000-0000-000000000001',
          customer_name: 'Shop owner',
          callback_url: 'https://api.example.test/webhooks/payhero-callback',
        }),
      }),
    );
  });

  it('keeps STK collection disabled until both provider confirmations are configured', async () => {
    configurePayHero();
    process.env.PAYHERO_AMOUNT_VERIFICATION_CONFIRMED = 'false';
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    await expect(initiateStkPush({
      amount: 125,
      phoneNumber: '0712345678',
      channelId: 9,
      externalReference: 'DUKA-00000000-0000-0000-0000-000000000001',
      callbackUrl: 'https://api.example.test/webhooks/payhero-callback',
    })).rejects.toThrow('PayHero settlement requirements have not been confirmed');

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('rejects credentials that authenticate as a different PayHero account', async () => {
    configurePayHero();
    const fetchMock = vi.fn().mockResolvedValueOnce(walletResponse(999));
    vi.stubGlobal('fetch', fetchMock);

    await expect(queryTransactionStatus('provider-123'))
      .rejects.toThrow('PayHero token does not match PAYHERO_ACCOUNT_ID');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('normalizes Kenyan M-Pesa phone numbers before submission', () => {
    expect(normalizeMpesaPhone('0712345678')).toBe('254712345678');
    expect(normalizeMpesaPhone('+254712345678')).toBe('254712345678');
    expect(normalizeMpesaPhone('712345678')).toBe('254712345678');
  });

  it('rejects a status response for a different provider reference', async () => {
    configurePayHero();
    vi.stubGlobal('fetch', vi.fn()
      .mockResolvedValueOnce(walletResponse())
      .mockResolvedValueOnce(providerResponse({
        success: true,
        status: 'SUCCESS',
        reference: 'other-reference',
        provider: 'm-pesa',
      })));

    await expect(queryTransactionStatus('provider-123')).rejects.toThrow(
      'PayHero status response did not match the documented transaction',
    );
  });

  it('queries status using the provider-generated reference', async () => {
    configurePayHero();
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(walletResponse())
      .mockResolvedValueOnce(providerResponse({
        success: true,
        status: 'SUCCESS',
        reference: 'PAY/123',
        provider: 'm-pesa',
      }));
    vi.stubGlobal('fetch', fetchMock);

    await expect(queryTransactionStatus('PAY/123')).resolves.toMatchObject({
      status: 'SUCCESS',
      reference: 'PAY/123',
    });
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      'https://backend.payhero.co.ke/api/v2/transaction-status?reference=PAY%2F123',
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: 'Basic server-only-token' }),
      }),
    );
  });

  it('builds the callback URL only from a configured HTTPS origin', () => {
    process.env.PUBLIC_API_URL = 'https://api.example.test/';
    expect(payHeroCallbackUrl())
      .toBe('https://api.example.test/webhooks/payhero-callback');
    process.env.PUBLIC_API_URL = 'http://api.example.test';
    expect(() => payHeroCallbackUrl()).toThrow('PUBLIC_API_URL must be an HTTPS origin');
  });

  it('reports account/configuration state without returning credential material', async () => {
    configurePayHero();
    process.env.PAYHERO_CHANNEL_SETTLEMENT_CONFIRMED = 'false';
    process.env.PAYHERO_AMOUNT_VERIFICATION_CONFIRMED = 'false';
    vi.stubGlobal('fetch', vi.fn().mockResolvedValueOnce(walletResponse()));

    const status = await payHeroConfigurationStatus();

    expect(status).toMatchObject({
      credentialConfigured: true,
      accountIdConfigured: true,
      accountIdentityVerified: true,
      channelSettlementConfirmed: false,
      amountVerificationConfirmed: false,
      callbackUrlConfigured: true,
      collectionsEnabled: false,
    });
    expect(JSON.stringify(status)).not.toContain('server-only-token');
  });

  it('extracts only the documented nested external reference', () => {
    expect(payheroReferenceFromCallback({
      status: true,
      response: { ExternalReference: 'DUKA-00000000-0000-0000-0000-000000000001' },
    })).toBe('DUKA-00000000-0000-0000-0000-000000000001');
    expect(payheroReferenceFromCallback({ reference: 'DUKA-ref' })).toBeUndefined();
    expect(payheroReferenceFromCallback(null)).toBeUndefined();
  });
});
