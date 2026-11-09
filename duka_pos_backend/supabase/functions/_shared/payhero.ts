// Thin client for PayHero's documented API (docs.payhero.co.ke). Both the
// Basic auth token and the API base stay server-side only — this file is
// imported by Edge Functions, never bundled into the Flutter app.
//
// The Basic auth token is generated from your PayHero API username/password
// (from the PayHero dashboard's "API Keys" section) as base64("username:password").
// Set it as a Supabase secret, never a source constant:
//   supabase secrets set PAYHERO_AUTH_TOKEN="Basic <your base64 token>"

const PAYHERO_BASE = "https://backend.payhero.co.ke/api/v2";

function authHeader(): string {
  const token = Deno.env.get("PAYHERO_AUTH_TOKEN");
  if (!token) throw new Error("PAYHERO_AUTH_TOKEN secret is not set");
  return token; // expected to already include the "Basic " prefix
}

export interface StkPushParams {
  amount: number;
  phoneNumber: string; // format PayHero expects, e.g. 0787677676
  channelId: number;
  externalReference: string;
  customerName?: string;
  callbackUrl: string;
  credentialId?: string;
}

export interface StkPushResult {
  raw: unknown;
  reference: string;
  checkoutRequestId?: string;
}

export async function initiateStkPush(params: StkPushParams): Promise<StkPushResult> {
  const res = await fetch(`${PAYHERO_BASE}/payments`, {
    method: "POST",
    headers: { "Authorization": authHeader(), "Content-Type": "application/json" },
    body: JSON.stringify({
      amount: Math.round(params.amount), // PayHero expects an integer amount
      phone_number: params.phoneNumber,
      channel_id: params.channelId,
      provider: "m-pesa",
      external_reference: params.externalReference,
      customer_name: params.customerName,
      callback_url: params.callbackUrl,
      ...(params.credentialId ? { credential_id: params.credentialId } : {}),
    }),
  });
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`PayHero STK push failed: ${res.status} ${JSON.stringify(body)}`);
  }
  return {
    raw: body,
    reference: params.externalReference,
    checkoutRequestId: body?.CheckoutRequestID ?? body?.checkout_request_id,
  };
}

export interface TransactionStatus {
  success: boolean;
  status: "QUEUED" | "SUCCESS" | "FAILED" | string;
  reference: string;
}

/// Used both by the polling endpoint (payment-status Edge Function) and as
/// a trust-but-verify double-check inside the webhook handler — see the
/// comment in payhero-callback/index.ts for why the webhook body alone
/// isn't treated as sufficient proof of payment.
///
/// The queried reference is the only thing tying this response to a specific
/// payment, so a response that names a different reference is rejected rather
/// than accepted as proof. An unsuccessful response is likewise inconclusive,
/// not a failure: the callback must not mark a payment FAILED just because
/// the provider could not be reached.
export async function queryTransactionStatus(reference: string): Promise<TransactionStatus> {
  const url = `${PAYHERO_BASE}/transaction-status?reference=${encodeURIComponent(reference)}`;
  const res = await fetch(url, { headers: { "Authorization": authHeader() } });
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`PayHero status query failed: ${res.status} ${JSON.stringify(body)}`);
  }
  const status = body as TransactionStatus;
  if (typeof status?.reference === "string" && status.reference !== reference) {
    throw new Error("PayHero status response did not match the requested reference");
  }
  if (status?.success !== true) {
    throw new Error("PayHero status query returned an unsuccessful response");
  }
  return status;
}
