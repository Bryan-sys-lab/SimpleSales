const SAFARICOM_TIMEOUT_MS = 15_000;

export type SafaricomQrErrorKind = 'misconfigured' | 'network' | 'rejected';

export class SafaricomQrError extends Error {
  constructor(
    message: string,
    readonly kind: SafaricomQrErrorKind,
    readonly statusCode?: number,
  ) {
    super(message);
    this.name = 'SafaricomQrError';
  }
}

function baseUrl(): string {
  return (process.env.SAFARICOM_QR_BASE_URL || process.env.SAFARICOM_BASE_URL ||
    (process.env.SAFARICOM_QR_ENV === 'production' || process.env.SAFARICOM_ENV === 'production'
      ? 'https://api.safaricom.co.ke'
      : 'https://sandbox.safaricom.co.ke')).replace(/\/$/, '');
}

function configuredCredentials(): { key: string; secret: string } {
  const key = (process.env.SAFARICOM_QR_CONSUMER_KEY || process.env.SAFARICOM_CONSUMER_KEY)?.trim();
  const secret = (process.env.SAFARICOM_QR_CONSUMER_SECRET || process.env.SAFARICOM_CONSUMER_SECRET)?.trim();
  if (!key || !secret) {
    throw new SafaricomQrError('Safaricom Dynamic QR credentials are not configured', 'misconfigured');
  }
  return { key, secret };
}

async function fetchWithTimeout(input: string, init: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), SAFARICOM_TIMEOUT_MS);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } catch (error) {
    throw new SafaricomQrError(error instanceof Error ? error.message : 'Safaricom request failed', 'network');
  } finally {
    clearTimeout(timer);
  }
}

async function readJson(response: Response): Promise<Record<string, unknown>> {
  return await response.json().catch(() => ({})) as Record<string, unknown>;
}

async function accessToken(): Promise<string> {
  const { key, secret } = configuredCredentials();
  const response = await fetchWithTimeout(`${baseUrl()}/oauth/v1/generate?grant_type=client_credentials`, {
    headers: { Authorization: `Basic ${Buffer.from(`${key}:${secret}`).toString('base64')}` },
  });
  const body = await readJson(response);
  if (!response.ok || typeof body.access_token !== 'string') {
    throw new SafaricomQrError('Safaricom OAuth token request failed', response.ok ? 'rejected' : response.status >= 500 ? 'network' : 'rejected', response.status);
  }
  return body.access_token;
}

export async function generateDynamicQr(input: {
  merchantName: string;
  reference: string;
  amount: number;
  transactionCode: 'BG' | 'PB' | 'SM' | 'SB' | 'WA';
  creditPartyIdentifier: string;
}): Promise<{ qrCode: string; requestId?: string }> {
  const token = await accessToken();
  const response = await fetchWithTimeout(`${baseUrl()}/mpesa/qrcode/v1/generate`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      MerchantName: input.merchantName.slice(0, 80),
      RefNo: input.reference.slice(0, 80),
      Amount: Math.round(input.amount),
      TrxCode: input.transactionCode,
      CPI: input.creditPartyIdentifier,
      Size: '600',
    }),
  });
  const body = await readJson(response);
  if (!response.ok || typeof body.QRCode !== 'string' || body.QRCode.length < 20) {
    const kind = response.ok || response.status < 500 ? 'rejected' : 'network';
    throw new SafaricomQrError('Safaricom Dynamic QR generation failed', kind, response.status);
  }
  return {
    qrCode: body.QRCode,
    requestId: typeof body.RequestID === 'string' ? body.RequestID : undefined,
  };
}
