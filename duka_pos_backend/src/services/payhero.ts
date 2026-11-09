const PAYHERO_BASE = process.env.PAYHERO_BASE_URL || 'https://backend.payhero.co.ke/api/v2';

type PayHeroChannelType = 'till' | 'paybill';

function payHeroHeaders(): Record<string, string> {
  const token = process.env.PAYHERO_AUTH_TOKEN;
  if (!token) throw new Error('PAYHERO_AUTH_TOKEN not configured');
  return {
    Authorization: token,
    'Content-Type': 'application/json',
  };
}

/**
 * Finds or registers the merchant's destination using the platform's PayHero
 * account. Merchant-facing clients send only the Till/Paybill details; the
 * PayHero credential and account id never leave this backend.
 */
export async function registerPaymentChannel(params: {
  channelType: PayHeroChannelType;
  shortCode: string;
  description?: string;
}): Promise<{ id: number; channelType: PayHeroChannelType; shortCode: string }> {
  const accountId = Number(process.env.PAYHERO_ACCOUNT_ID);
  if (!Number.isSafeInteger(accountId) || accountId <= 0) {
    throw new Error('PAYHERO_ACCOUNT_ID not configured');
  }
  const shortCode = params.shortCode.trim();
  const headers = payHeroHeaders();

  const existingResponse = await fetch(
    `${PAYHERO_BASE}/payment_channels?is_active=true`,
    { headers },
  );
  if (existingResponse.ok) {
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
          row.is_active === true;
    });
    if (match && Number.isSafeInteger(Number(match.id))) {
      return {
        id: Number(match.id),
        channelType: params.channelType,
        shortCode,
      };
    }
  }

  const response = await fetch(`${PAYHERO_BASE}/payment_channels`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      channel_type: params.channelType,
      account_id: accountId,
      short_code: Number(shortCode),
      // PayHero requires this field for both channel types; Till collections
      // do not use an account number, so an empty string is intentional.
      account_number: '',
      description: params.description?.trim() || `SimpleSales ${params.channelType} ${shortCode}`,
    }),
  });
  const body = (await response.json()) as Record<string, unknown>;
  const id = Number(body.id);
  if (!response.ok || !Number.isSafeInteger(id) || id <= 0) {
    throw new Error(`PayHero channel registration failed: ${response.status}`);
  }
  return { id, channelType: params.channelType, shortCode };
}

export async function initiateStkPush(params: any) {
  const headers = payHeroHeaders();
  const res = await fetch(`${PAYHERO_BASE}/payments`, {
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
  const body = (await res.json()) as Record<string, unknown>;
  if (!res.ok) {
    throw new Error(`PayHero STK push failed: ${res.status} ${JSON.stringify(body)}`);
  }
  const checkoutRequestId = body?.CheckoutRequestID ?? body?.checkout_request_id;
  if (typeof checkoutRequestId !== 'string' || checkoutRequestId.length > 160) {
    throw new Error('PayHero response did not contain a valid checkout request ID');
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
  const res = await fetch(`${PAYHERO_BASE}/transaction-status?reference=${encodeURIComponent(reference)}`, {
    headers,
  });
  const body = (await res.json()) as Record<string, unknown>;
  if (!res.ok) {
    throw new Error(`PayHero status query failed: ${res.status}`);
  }
  return body;
}
