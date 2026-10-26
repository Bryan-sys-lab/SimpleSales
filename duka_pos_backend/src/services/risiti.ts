/**
 * Server-side Risiti (PesaStack) platform client.
 *
 * The API key never crosses the mobile boundary.  This adapter deliberately
 * does not activate KRA: a merchant must be onboarded and approved before the
 * caller enables tax submission for a tenant.
 */

export const RISITI_SANDBOX_URL = 'https://sandbox-api.getrisiti.com/v1/platform';
export const RISITI_PRODUCTION_URL = 'https://api.getrisiti.com/v1/platform';

export type RisitiPaymentMethod = '01' | '02' | '03' | '04' | '05' | '06' | '07';
export type RisitiTaxType = 'A' | 'B' | 'C' | 'D' | 'E';

export type RisitiSubmission = {
  accepted_by_risiti?: boolean;
  state?: 'queued' | 'submitting_to_kra' | 'waiting_for_kra' | 'completed' | 'action_required';
  terminal?: boolean;
  succeeded?: boolean;
  will_retry_automatically?: boolean;
  attempt_count?: number;
  message?: string;
};

export type RisitiInvoiceItem = {
  external_id: string;
  name: string;
  quantity: number;
  unit_price: number;
  tax_type: RisitiTaxType;
  item_class_code?: string;
};

export type RisitiInvoiceRequest = {
  merchant_id: string;
  external_id: string;
  sales_date?: string;
  payment_method: RisitiPaymentMethod;
  buyer?: { name?: string; kra_pin?: string; phone?: string };
  items: RisitiInvoiceItem[];
};

export type RisitiAcceptedInvoice = {
  invoice_id?: string;
  request_id?: string;
  external_id?: string | null;
  submission?: RisitiSubmission;
  kra_receipt_number?: string;
  kra_invoice_number?: number;
  qr_code_data?: string;
  risiti_url?: string;
  [key: string]: unknown;
};

export class RisitiError extends Error {
  constructor(
    message: string,
    readonly kind: 'misconfigured' | 'network' | 'rejected' | 'action_required',
    readonly requestId?: string,
    readonly statusCode?: number,
  ) {
    super(message);
    this.name = 'RisitiError';
  }
}

export function risitiBaseUrl(): string {
  return (process.env.RISITI_BASE_URL || RISITI_SANDBOX_URL).replace(/\/$/, '');
}

export function assertRisitiConfigured(): void {
  if (!process.env.RISITI_API_KEY) {
    throw new RisitiError('Risiti is not configured for this deployment', 'misconfigured');
  }
}

function paymentMethodCode(method: string): RisitiPaymentMethod {
  switch (method) {
    case 'cash': return '01';
    case 'credit': return '02';
    case 'mixed': return '03';
    case 'bank_transfer': return '04';
    case 'card': return '05';
    case 'mpesa':
    case 'mobile_money_manual': return '06';
    default: return '07';
  }
}

export function buildRisitiInvoiceRequest(input: {
  tenantId: string;
  merchantId: string;
  receiptNumber: string;
  issuedAt: string;
  paymentMethod: string;
  items: Array<{ name: string; qty: number; unitPrice: number; vatAmount: number; lineTotal: number }>;
  buyerName?: string;
  buyerTin?: string;
}): RisitiInvoiceRequest {
  if (!input.items.length) throw new RangeError('a tax invoice must contain an item');
  return {
    merchant_id: input.merchantId,
    external_id: `${input.tenantId}:${input.receiptNumber}`,
    sales_date: input.issuedAt.slice(0, 10),
    payment_method: paymentMethodCode(input.paymentMethod),
    ...(input.buyerName || input.buyerTin
      ? { buyer: { ...(input.buyerName ? { name: input.buyerName } : {}), ...(input.buyerTin ? { kra_pin: input.buyerTin } : {}) } }
      : {}),
    items: input.items.map((item, index) => ({
      external_id: `${input.tenantId}:${input.receiptNumber}:${index + 1}`,
      name: item.name,
      quantity: item.qty,
      // Risiti accepts KES major units. Tax is represented by the line tax type.
      unit_price: item.unitPrice / 100,
      tax_type: item.vatAmount > 0 ? 'B' : 'D',
    })),
  };
}

async function request<T>(path: string, init: RequestInit, timeoutMs = 15_000): Promise<T> {
  assertRisitiConfigured();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${risitiBaseUrl()}${path}`, {
      ...init,
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${process.env.RISITI_API_KEY}`,
        'Content-Type': 'application/json',
        ...(init.headers ?? {}),
      },
    });
    const body = await response.json().catch(() => ({})) as Record<string, unknown>;
    const requestId = typeof body.request_id === 'string' ? body.request_id : undefined;
    if (!response.ok) {
      const error = body.error as Record<string, unknown> | undefined;
      throw new RisitiError(
        typeof error?.message === 'string' ? error.message : `Risiti request failed (${response.status})`,
        response.status >= 500 ? 'network' : 'rejected',
        requestId,
        response.status,
      );
    }
    return body as T;
  } catch (error) {
    if (error instanceof RisitiError) throw error;
    throw new RisitiError(error instanceof Error ? error.message : 'Risiti request failed', 'network');
  } finally {
    clearTimeout(timer);
  }
}

export async function submitInvoice(
  invoice: RisitiInvoiceRequest,
): Promise<{ data: RisitiAcceptedInvoice; requestId?: string }> {
  const body = await request<{ data: RisitiAcceptedInvoice; request_id?: string }>('/invoices', {
    method: 'POST',
    headers: { 'Idempotency-Key': invoice.external_id },
    body: JSON.stringify(invoice),
  });
  return { data: body.data, requestId: body.request_id };
}

export async function getInvoice(invoiceId: string): Promise<{ data: RisitiAcceptedInvoice; requestId?: string }> {
  const body = await request<{ data: RisitiAcceptedInvoice; request_id?: string }>(`/invoices/${encodeURIComponent(invoiceId)}`, { method: 'GET' });
  return { data: body.data, requestId: body.request_id };
}

export function submissionOutcome(submission?: RisitiSubmission): 'issued' | 'pending' | 'action_required' {
  if (submission?.terminal && submission.succeeded) return 'issued';
  if (submission?.terminal) return 'action_required';
  return 'pending';
}
