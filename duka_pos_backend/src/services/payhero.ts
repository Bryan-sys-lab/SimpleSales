const PAYHERO_BASE = process.env.PAYHERO_BASE_URL || 'https://backend.payhero.co.ke/api/v2';

export async function initiateStkPush(params: any) {
  const token = process.env.PAYHERO_AUTH_TOKEN;
  if (!token) {
    throw new Error('PAYHERO_AUTH_TOKEN not configured');
  }
  const res = await fetch(`${PAYHERO_BASE}/payments`, {
    method: 'POST',
    headers: {
      'Authorization': token,
      'Content-Type': 'application/json',
    },
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
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`PayHero STK push failed: ${res.status} ${JSON.stringify(body)}`);
  }
  const checkoutRequestId = body?.CheckoutRequestID || body?.checkout_request_id;
  if (typeof checkoutRequestId !== 'string' || checkoutRequestId.length > 160) {
    throw new Error('PayHero response did not contain a valid checkout request ID');
  }
  return {
    raw: body,
    reference: params.externalReference,
    checkoutRequestId,
  };
}

export async function queryTransactionStatus(reference: string) {
  const token = process.env.PAYHERO_AUTH_TOKEN;
  if (!token) {
    throw new Error('PAYHERO_AUTH_TOKEN not configured');
  }
  const res = await fetch(`${PAYHERO_BASE}/transaction-status?reference=${encodeURIComponent(reference)}`, {
    headers: { 'Authorization': token },
  });
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`PayHero status query failed: ${res.status}`);
  }
  return body;
}
