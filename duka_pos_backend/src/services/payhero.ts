const PAYHERO_BASE = process.env.PAYHERO_BASE_URL || 'https://backend.payhero.co.ke/api/v2';
const PAYHERO_TIMEOUT_MS = 15_000;

export type PayHeroChannelType = 'till' | 'paybill' | 'bank';

export class PayHeroError extends Error {
  constructor(
    message: string,
    readonly statusCode?: number,
  ) {
    super(message);
    this.name = 'PayHeroError';
  }
}

function payHeroHeaders(): Record<string, string> {
  const configured = process.env.PAYHERO_AUTH_TOKEN?.trim();
  if (!configured) throw new PayHeroError('PAYHERO_AUTH_TOKEN not configured');
  const authorization = /^Basic\s+/i.test(configured)
    ? configured
    : `Basic ${configured}`;
  return {
    Authorization: authorization,
    'Content-Type': 'application/json',
  };
}

async function fetchWithTimeout(
  input: string,
  init: RequestInit,
  timeoutMs = PAYHERO_TIMEOUT_MS,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } catch (error) {
    throw new PayHeroError(
      error instanceof Error ? error.message : 'PayHero request failed',
    );
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Finds or registers the merchant's destination using the platform's PayHero
 * account. Merchant-facing clients send only the Till/Paybill details; the
 * PayHero credential and account id never leave this backend.
 */
export async function registerPaymentChannel(params: {
  channelType: PayHeroChannelType;
  shortCode: string;
  accountNumber?: string;
  description?: string;
}): Promise<{ id: number; channelType: PayHeroChannelType; shortCode: string }> {
  const accountId = Number(process.env.PAYHERO_ACCOUNT_ID);
  if (!Number.isSafeInteger(accountId) || accountId <= 0) {
    throw new Error('PAYHERO_ACCOUNT_ID not configured');
  }
  const shortCode = params.shortCode.trim();
  const accountNumber = params.accountNumber?.trim() ?? '';
  const headers = payHeroHeaders();

  const existingResponse = await fetchWithTimeout(
    `${PAYHERO_BASE}/payment_channels?is_active=true`,
    { headers },
  );
  if (!existingResponse.ok) {
    throw new PayHeroError(
      `PayHero channel lookup failed (${existingResponse.status})`,
      existingResponse.status,
    );
  }
  const existing = (await existingResponse.json()) as { payment_channels?: unknown };
  const channels = Array.isArray(existing.payment_channels)
    ? existing.payment_channels
    : [];
  const match = channels.find((raw): raw is Record<string, unknown> => {
    if (!raw || typeof raw !== 'object') return false;
    const row = raw as Record<string, unknown>;
    return Number(row.account_id) === accountId &&
        row.channel_type === params.channelType &&
        String(row.short_code ?? '') === shortCode &&
        String(row.account_number ?? '') === accountNumber &&
        row.is_active === true;
  });
  if (match && Number.isSafeInteger(Number(match.id))) {
    return {
      id: Number(match.id),
      channelType: params.channelType,
      shortCode,
    };
  }

  const response = await fetchWithTimeout(`${PAYHERO_BASE}/payment_channels`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      channel_type: params.channelType,
      account_id: accountId,
      short_code: shortCode,
      // PayHero requires this field for both channel types; Till collections
      // do not use an account number, so an empty string is intentional. Bank
      // channels use it as the destination account.
      account_number: accountNumber,
      description: params.description?.trim() || `SimpleSales ${params.channelType} ${shortCode}`,
    }),
  });
  const body = await response.json().catch(() => ({})) as Record<string, unknown>;
  const id = Number(body.id);
  if (!response.ok || !Number.isSafeInteger(id) || id <= 0) {
    throw new PayHeroError(`PayHero channel registration failed: ${response.status}`, response.status);
  }
  return { id, channelType: params.channelType, shortCode };
}

export async function initiateStkPush(params: {
  amount: number;
  phoneNumber: string;
  channelId: number;
  externalReference: string;
  customerName?: string;
  callbackUrl: string;
  credentialId?: string;
}) {
  const headers = payHeroHeaders();
  const res = await fetchWithTimeout(`${PAYHERO_BASE}/payments`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      amount: Math.round(params.amount),
      phone_number: params.phoneNumber,
      channel_id: params.channelId,
      provider: 'm-pesa',
      external_reference: params.externalReference,
      customer_name: params.customerName,
      callback_url: params.callbackUrl,
      ...(params.credentialId && { credential_id: params.credentialId }),
    }),
  });
  // PayHero's shape varies by deployment: the field arrives camelCased on some
  // accounts and snake_cased on others. Both spellings are checked before the
  // response is considered valid.
  const body = await res.json().catch(() => ({})) as Record<string, unknown>;
  if (!res.ok) {
    throw new PayHeroError(`PayHero STK push failed: ${res.status}`, res.status);
  }
  const checkoutRequestId = body?.CheckoutRequestID ?? body?.checkout_request_id;
  if (typeof checkoutRequestId !== 'string' || checkoutRequestId.length > 160) {
    throw new PayHeroError('PayHero response did not contain a valid checkout request ID');
  }
  return {
    raw: body,
    reference: params.externalReference,
    checkoutRequestId,
  };
}

export async function queryTransactionStatus(
  reference: string,
) {
  const headers = payHeroHeaders();
  const res = await fetchWithTimeout(`${PAYHERO_BASE}/transaction-status?reference=${encodeURIComponent(reference)}`, {
    headers,
  });
  const body = await res.json().catch(() => ({})) as Record<string, unknown>;
  if (!res.ok) {
    throw new PayHeroError(`PayHero status query failed: ${res.status}`, res.status);
  }
  return body;
}
