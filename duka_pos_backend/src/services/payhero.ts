const PAYHERO_BASE = process.env.PAYHERO_BASE_URL || 'https://backend.payhero.co.ke/api/v2';

interface StkPushParams {
  amount: number;
  phoneNumber: string;
  channelId: number;
  externalReference: string;
  customerName?: string;
  callbackUrl: string;
  credentialId?: string;
}

export async function initiateStkPush(params: StkPushParams) {
  const token = process.env.PAYHERO_AUTH_TOKEN;
  if (!token) throw new Error('PAYHERO_AUTH_TOKEN not configured');

  const res = await fetch(`${PAYHERO_BASE}/payments`, {
    method: 'POST',
    headers: {
      'Authorization': token,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      amount: Math.round(params.amount),
      phone_number: params.phoneNumber,
      channel_id: params.channelId,
      provider: 'm-pesa',
      external_reference: params.externalReference,
      customer_name: params.customerName,
      callback_url: params.callbackUrl,
      ...(params.credentialId && { credential_id: params.credentialId })
    })
  });

  const body = await res.json() as Record<string, unknown>;
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
    checkoutRequestId
  };
}

export interface TransactionStatus {
  success: boolean;
  status: 'QUEUED' | 'SUCCESS' | 'FAILED' | string;
  reference: string;
}

// The till polls /payments/status every few seconds for up to 90s. Without a
// cooldown every one of those polls would fan out a live provider request —
// roughly 30 third-party calls per payment, which is both slow and an easy
// way to get rate-limited out of confirming real payments.
const STATUS_COOLDOWN_MS = Number(process.env.PAYHERO_STATUS_COOLDOWN_MS ?? 5_000);
const statusCache = new Map<string, { at: number; status: TransactionStatus }>();

export function resetTransactionStatusCache() {
  statusCache.clear();
}

export async function queryTransactionStatus(
  reference: string,
  options: { force?: boolean } = {},
): Promise<TransactionStatus> {
  const cached = statusCache.get(reference);
  if (!options.force && cached && Date.now() - cached.at < STATUS_COOLDOWN_MS) {
    return cached.status;
  }

  const token = process.env.PAYHERO_AUTH_TOKEN;
  if (!token) throw new Error('PAYHERO_AUTH_TOKEN not configured');

  const res = await fetch(
    `${PAYHERO_BASE}/transaction-status?reference=${encodeURIComponent(reference)}`,
    { headers: { 'Authorization': token } }
  );

  const body = await res.json();
  if (!res.ok) {
    throw new Error(`PayHero status query failed: ${res.status}`);
  }

  const status = body as TransactionStatus;
  // The queried reference is the only thing that ties this response to our
  // payment. Without this check a response for some other transaction would be
  // accepted as proof that *this* payment succeeded, so a wrong-but-successful
  // lookup is a silent revenue error. Treat a mismatch as inconclusive rather
  // than as a failure.
  if (typeof status?.reference === 'string' && status.reference !== reference) {
    throw new Error('PayHero status response did not match the requested reference');
  }
  if (status?.success !== true) {
    throw new Error('PayHero status query returned an unsuccessful response');
  }

  statusCache.set(reference, { at: Date.now(), status });
  return status;
}
