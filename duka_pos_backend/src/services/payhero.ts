import { createHash } from 'node:crypto';
import { prisma } from '../lib/prisma';

const PAYHERO_BASE = 'https://backend.payhero.co.ke/api/v2';
const PAYHERO_TIMEOUT_MS = 15_000;
const MAX_CHANNEL_PAGES = 100;
const CHANNEL_SETTLEMENT_CONFIRMED = 'PAYHERO_CHANNEL_SETTLEMENT_CONFIRMED';
const AMOUNT_VERIFICATION_CONFIRMED = 'PAYHERO_AMOUNT_VERIFICATION_CONFIRMED';

export type PayHeroChannelType = 'till' | 'paybill' | 'bank';

export class PayHeroError extends Error {
  readonly status?: number;

  constructor(
    message: string,
    readonly statusCode?: number,
    readonly outcomeAmbiguous = false,
  ) {
    super(message);
    this.name = 'PayHeroError';
    this.status = statusCode;
  }
}

function configuredAccountId(): number {
  const accountId = Number(process.env.PAYHERO_ACCOUNT_ID);
  if (!Number.isSafeInteger(accountId) || accountId <= 0) {
    throw new PayHeroError('PAYHERO_ACCOUNT_ID not configured', 503);
  }
  return accountId;
}

function payHeroHeaders(): Record<string, string> {
  const configured = process.env.PAYHERO_AUTH_TOKEN?.trim();
  if (!configured) throw new PayHeroError('PAYHERO_AUTH_TOKEN not configured', 503);

  const token = configured.replace(/^Basic\s+/i, '').trim();
  if (!token || /^Basic\b/i.test(token) || /\s/.test(token)) {
    throw new PayHeroError('PAYHERO_AUTH_TOKEN has an invalid Basic Auth format', 503);
  }
  return {
    Authorization: `Basic ${token}`,
    'Content-Type': 'application/json',
  };
}

export function normalizeMpesaPhone(phoneNumber: string): string {
  const digits = phoneNumber.trim().replace(/[\s()-]/g, '').replace(/^\+/, '');
  if (/^254(7|1)\d{8}$/.test(digits)) return digits;
  if (/^(07|01)\d{8}$/.test(digits)) return `254${digits.slice(1)}`;
  if (/^[17]\d{8}$/.test(digits)) return `254${digits}`;
  throw new PayHeroError('Invalid Kenyan M-Pesa phone number', 422);
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

async function responseBody(response: Response): Promise<Record<string, unknown>> {
  const body: unknown = await response.json().catch(() => ({}));
  return isRecord(body) ? body : {};
}

/**
 * Confirms that the API token is authenticated as the configured central
 * PayHero account using the documented read-only service-wallet endpoint.
 */
export async function verifyPayHeroAccount(): Promise<number> {
  const accountId = configuredAccountId();
  const response = await fetchWithTimeout(
    `${PAYHERO_BASE}/wallets?wallet_type=service_wallet`,
    { headers: payHeroHeaders() },
  );
  const body = await responseBody(response);
  if (!response.ok) {
    throw new PayHeroError(
      `PayHero account verification failed (${response.status})`,
      response.status,
    );
  }
  if (Number(body.account_id) !== accountId) {
    throw new PayHeroError('PayHero token does not match PAYHERO_ACCOUNT_ID', 409);
  }
  return accountId;
}

export function payHeroSettlementContractConfirmed(): boolean {
  return process.env[CHANNEL_SETTLEMENT_CONFIRMED] === 'true' &&
    process.env[AMOUNT_VERIFICATION_CONFIRMED] === 'true';
}

export function payHeroCallbackUrl(): string {
  const configured = process.env.PUBLIC_API_URL?.trim();
  if (!configured) throw new PayHeroError('PUBLIC_API_URL not configured', 503);
  let url: URL;
  try {
    url = new URL(configured);
  } catch {
    throw new PayHeroError('PUBLIC_API_URL is invalid', 503);
  }
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    (url.pathname !== '' && url.pathname !== '/')
  ) {
    throw new PayHeroError('PUBLIC_API_URL must be an HTTPS origin', 503);
  }
  const basePath = url.pathname.replace(/\/+$/, '');
  url.pathname = `${basePath}/webhooks/payhero-callback`;
  return url.toString();
}

export async function payHeroConfigurationStatus(): Promise<{
  apiHost: string;
  credentialConfigured: boolean;
  accountIdConfigured: boolean;
  accountIdentityVerified: boolean;
  channelSettlementConfirmed: boolean;
  amountVerificationConfirmed: boolean;
  callbackUrlConfigured: boolean;
  collectionsEnabled: boolean;
}> {
  const credentialConfigured = Boolean(process.env.PAYHERO_AUTH_TOKEN?.trim());
  const accountIdConfigured = Number.isSafeInteger(Number(process.env.PAYHERO_ACCOUNT_ID))
    && Number(process.env.PAYHERO_ACCOUNT_ID) > 0;
  const channelSettlementConfirmed = process.env[CHANNEL_SETTLEMENT_CONFIRMED] === 'true';
  const amountVerificationConfirmed = process.env[AMOUNT_VERIFICATION_CONFIRMED] === 'true';
  let callbackUrlConfigured = false;
  try {
    payHeroCallbackUrl();
    callbackUrlConfigured = true;
  } catch (error) {
    if (!(error instanceof PayHeroError)) throw error;
  }
  const result = {
    apiHost: new URL(PAYHERO_BASE).host,
    credentialConfigured,
    accountIdConfigured,
    accountIdentityVerified: false,
    channelSettlementConfirmed,
    amountVerificationConfirmed,
    callbackUrlConfigured,
    collectionsEnabled: false,
  };
  if (!credentialConfigured || !accountIdConfigured) return result;
  try {
    await verifyPayHeroAccount();
    return {
      ...result,
      accountIdentityVerified: true,
      collectionsEnabled: channelSettlementConfirmed &&
        amountVerificationConfirmed &&
        callbackUrlConfigured,
    };
  } catch (error) {
    if (error instanceof PayHeroError) return result;
    throw error;
  }
}

type ChannelInput = {
  tenantId: string | null;
  channelType: PayHeroChannelType;
  shortCode: string;
  accountNumber: string;
};

type ProviderChannel = {
  id: number;
  account_id: number;
  channel_type: PayHeroChannelType;
  short_code: string;
  account_number: string;
  is_active: true;
};

function parseProviderChannel(
  value: unknown,
  accountId: number,
): ProviderChannel | null {
  if (!isRecord(value)) return null;
  const id = Number(value.id);
  if (
    !Number.isSafeInteger(id) ||
    id <= 0 ||
    Number(value.account_id) !== accountId ||
    !['till', 'paybill', 'bank'].includes(String(value.channel_type)) ||
    typeof value.short_code !== 'string' ||
    typeof value.account_number !== 'string' ||
    value.is_active !== true
  ) {
    return null;
  }
  return {
    id,
    account_id: accountId,
    channel_type: value.channel_type as PayHeroChannelType,
    short_code: value.short_code,
    account_number: value.account_number,
    is_active: true,
  };
}

function isRequestedChannel(
  channel: ProviderChannel,
  input: ChannelInput,
  accountId: number,
): boolean {
  return channel.account_id === accountId &&
    channel.channel_type === input.channelType &&
    channel.short_code === input.shortCode &&
    channel.account_number === input.accountNumber;
}

async function findActiveChannel(
  input: ChannelInput,
  accountId: number,
  headers: Record<string, string>,
): Promise<ProviderChannel | null> {
  let page = 1;
  const visited = new Set<number>();
  const matches: ProviderChannel[] = [];

  for (let count = 0; count < MAX_CHANNEL_PAGES; count += 1) {
    if (visited.has(page)) {
      throw new PayHeroError('PayHero channel pagination repeated a page');
    }
    visited.add(page);
    const query = new URLSearchParams({ is_active: 'true' });
    if (page > 1) query.set('page', String(page));
    const response = await fetchWithTimeout(
      `${PAYHERO_BASE}/payment_channels?${query.toString()}`,
      { headers },
    );
    const body = await responseBody(response);
    if (!response.ok) {
      throw new PayHeroError(
        `PayHero channel lookup failed (${response.status})`,
        response.status,
      );
    }
    if (!Array.isArray(body.payment_channels) || !isRecord(body.pagination)) {
      throw new PayHeroError('PayHero channel list response was incomplete');
    }
    for (const raw of body.payment_channels) {
      const channel = parseProviderChannel(raw, accountId);
      if (channel && isRequestedChannel(channel, input, accountId)) {
        matches.push(channel);
      }
    }
    const nextPage = body.pagination.next_page;
    if (nextPage === null) break;
    if (!Number.isSafeInteger(nextPage) || Number(nextPage) < 1) {
      throw new PayHeroError('PayHero channel list returned invalid pagination');
    }
    page = Number(nextPage);
    if (count === MAX_CHANNEL_PAGES - 1) {
      throw new PayHeroError('PayHero channel list exceeded the pagination limit');
    }
  }

  if (matches.length > 1) {
    throw new PayHeroError('PayHero contains duplicate active channels for this destination');
  }
  return matches[0] ?? null;
}

function registrationFingerprint(input: ChannelInput, accountId: number): string {
  return createHash('sha256')
    .update([
      String(accountId),
      input.channelType,
      input.shortCode,
      input.accountNumber,
    ].join('\u0000'))
    .digest('hex');
}

async function assertChannelNotAssignedToAnotherTenant(
  channelId: number,
  tenantId: string | null,
): Promise<void> {
  const otherTenant = await prisma.tenant.findFirst({
    where: tenantId
      ? { payheroChannelId: channelId, id: { not: tenantId } }
      : { payheroChannelId: channelId },
    select: { id: true },
  });
  if (otherTenant) {
    throw new PayHeroError('PayHero channel is already assigned to another shop');
  }
}

export async function registerPaymentChannel(params: {
  tenantId?: string;
  channelType: PayHeroChannelType;
  shortCode: string;
  accountNumber?: string;
  description?: string;
}): Promise<{ id: number; channelType: PayHeroChannelType; shortCode: string }> {
  if (process.env[CHANNEL_SETTLEMENT_CONFIRMED] !== 'true') {
    throw new PayHeroError('Central-account merchant settlement has not been confirmed by PayHero', 409);
  }
  const input: ChannelInput = {
    tenantId: params.tenantId ?? null,
    channelType: params.channelType,
    shortCode: params.shortCode.trim(),
    accountNumber: params.accountNumber?.trim() ?? '',
  };
  if (!input.shortCode || (input.channelType === 'bank' && !input.accountNumber)) {
    throw new PayHeroError('PayHero channel destination is incomplete', 422);
  }

  const accountId = await verifyPayHeroAccount();
  const headers = payHeroHeaders();
  const fingerprint = registrationFingerprint(input, accountId);
  let registration = await prisma.payHeroChannelRegistration.findUnique({
    where: { fingerprint },
  });
  let canCreate = false;

  if (registration && registration.tenantId !== input.tenantId) {
    throw new PayHeroError('This PayHero destination is already registered to another shop');
  }

  if (registration?.status === 'FAILED') {
    const reset = await prisma.payHeroChannelRegistration.updateMany({
      where: { fingerprint, tenantId: input.tenantId, status: 'FAILED' },
      data: { status: 'REGISTERING', channelId: null },
    });
    if (reset.count !== 1) {
      throw new PayHeroError('PayHero channel registration state changed; retry after checking its status');
    }
    registration = await prisma.payHeroChannelRegistration.findUnique({
      where: { fingerprint },
    });
    canCreate = true;
  }

  const existingChannel = await findActiveChannel(input, accountId, headers);
  if (existingChannel) {
    await assertChannelNotAssignedToAnotherTenant(existingChannel.id, input.tenantId);
    if (registration?.status === 'REGISTERING' || registration?.status === 'UNKNOWN') {
      await prisma.payHeroChannelRegistration.update({
        where: { fingerprint },
        data: { status: 'ACTIVE', channelId: existingChannel.id },
      });
    } else if (!registration) {
      try {
        await prisma.payHeroChannelRegistration.create({
          data: {
            fingerprint,
            tenantId: input.tenantId,
            channelType: input.channelType,
            shortCode: input.shortCode,
            accountNumber: input.accountNumber,
            status: 'ACTIVE',
            channelId: existingChannel.id,
          },
        });
      } catch (error) {
        const raced = await prisma.payHeroChannelRegistration.findUnique({
          where: { fingerprint },
        });
        if (!raced) throw error;
        if (raced.tenantId !== input.tenantId || raced.channelId !== existingChannel.id) {
          throw new PayHeroError('Concurrent PayHero channel registration conflicts with this shop');
        }
      }
    }
    return {
      id: existingChannel.id,
      channelType: input.channelType,
      shortCode: input.shortCode,
    };
  }

  if (registration && registration.status !== 'REGISTERING') {
    await prisma.payHeroChannelRegistration.update({
      where: { fingerprint },
      data: { status: 'UNKNOWN' },
    });
    throw new PayHeroError('Previous PayHero registration is unresolved; refusing to create a duplicate');
  }

  if (!registration) {
    try {
      registration = await prisma.payHeroChannelRegistration.create({
        data: {
          fingerprint,
          tenantId: input.tenantId,
          channelType: input.channelType,
          shortCode: input.shortCode,
          accountNumber: input.accountNumber,
          status: 'REGISTERING',
        },
      });
      canCreate = true;
    } catch (error) {
      const raced = await prisma.payHeroChannelRegistration.findUnique({
        where: { fingerprint },
      });
      if (!raced) throw error;
      if (raced.tenantId !== input.tenantId) {
        throw new PayHeroError('This PayHero destination is already registered to another shop');
      }
      throw new PayHeroError('PayHero channel registration is already in progress');
    }
  } else if (!canCreate) {
    throw new PayHeroError('PayHero channel registration is already in progress');
  }

  let response: Response;
  try {
    response = await fetchWithTimeout(`${PAYHERO_BASE}/payment_channels`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        channel_type: input.channelType,
        account_id: accountId,
        short_code: input.shortCode,
        account_number: input.accountNumber,
        description: params.description?.trim() || `SimpleSales ${input.channelType} ${input.shortCode}`,
      }),
    });
  } catch (error) {
    await prisma.payHeroChannelRegistration.update({
      where: { fingerprint },
      data: { status: 'UNKNOWN' },
    });
    throw error;
  }

  const body = await responseBody(response);
  if (!response.ok) {
    await prisma.payHeroChannelRegistration.update({
      where: { fingerprint },
      data: { status: response.status < 500 ? 'FAILED' : 'UNKNOWN' },
    });
    throw new PayHeroError(
      `PayHero channel registration failed (${response.status})`,
      response.status,
    );
  }

  const created = parseProviderChannel(body, accountId);
  if (
    !created ||
    !isRequestedChannel(created, input, accountId) ||
    typeof body.description !== 'string' ||
    !body.description.trim()
  ) {
    await prisma.payHeroChannelRegistration.update({
      where: { fingerprint },
      data: { status: 'UNKNOWN' },
    });
    throw new PayHeroError('PayHero channel registration response was incomplete; manual reconciliation is required');
  }

  await assertChannelNotAssignedToAnotherTenant(created.id, input.tenantId);
  await prisma.payHeroChannelRegistration.update({
    where: { fingerprint },
    data: { status: 'ACTIVE', channelId: created.id },
  });
  return { id: created.id, channelType: input.channelType, shortCode: input.shortCode };
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
  if (!payHeroSettlementContractConfirmed()) {
    throw new PayHeroError('PayHero settlement requirements have not been confirmed', 409);
  }
  if (!Number.isSafeInteger(params.amount) || params.amount <= 0) {
    throw new PayHeroError('PayHero requires a positive whole-shilling amount', 422);
  }
  if (!Number.isSafeInteger(params.channelId) || params.channelId <= 0) {
    throw new PayHeroError('Invalid PayHero channel ID', 422);
  }
  await verifyPayHeroAccount();
  const headers = payHeroHeaders();
  const phoneNumber = normalizeMpesaPhone(params.phoneNumber);
  let res: Response;
  try {
    res = await fetchWithTimeout(`${PAYHERO_BASE}/payments`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        amount: params.amount,
        phone_number: phoneNumber,
        channel_id: params.channelId,
        provider: 'm-pesa',
        external_reference: params.externalReference,
        customer_name: params.customerName,
        callback_url: params.callbackUrl,
        ...(params.credentialId && { credential_id: params.credentialId }),
      }),
    });
  } catch {
    throw new PayHeroError('PayHero STK initiation outcome is unknown', undefined, true);
  }
  const body = await responseBody(res);
  if (!res.ok) {
    const ambiguous = res.status === 408 || res.status === 425 || res.status === 429 || res.status >= 500;
    throw new PayHeroError(`PayHero STK push failed (${res.status})`, res.status, ambiguous);
  }
  const providerReference = body.reference;
  const checkoutRequestId = body.CheckoutRequestID ?? body.checkout_request_id;
  if (
    body.success !== true ||
    body.status !== 'QUEUED' ||
    typeof providerReference !== 'string' ||
    !providerReference.trim() ||
    providerReference.length > 160 ||
    typeof checkoutRequestId !== 'string' ||
    !checkoutRequestId.trim() ||
    checkoutRequestId.length > 160
  ) {
    throw new PayHeroError('PayHero response did not contain a valid queued transaction reference', undefined, true);
  }
  return {
    raw: body,
    providerReference,
    checkoutRequestId,
  };
}

export async function queryTransactionStatus(providerReference: string) {
  if (!providerReference.trim() || providerReference.length > 160) {
    throw new PayHeroError('Invalid PayHero transaction reference');
  }
  await verifyPayHeroAccount();
  const headers = payHeroHeaders();
  const res = await fetchWithTimeout(
    `${PAYHERO_BASE}/transaction-status?reference=${encodeURIComponent(providerReference)}`,
    { headers },
  );
  const body = await responseBody(res);
  if (!res.ok) {
    throw new PayHeroError(`PayHero status query failed (${res.status})`, res.status);
  }
  if (
    body.success !== true ||
    body.reference !== providerReference ||
    body.provider !== 'm-pesa' ||
    !['QUEUED', 'SUCCESS', 'FAILED'].includes(String(body.status))
  ) {
    throw new PayHeroError('PayHero status response did not match the documented transaction');
  }
  return body;
}
