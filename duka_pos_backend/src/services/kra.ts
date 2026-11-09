import {
  createHmac,
  createCipheriv,
  createDecipheriv,
  randomBytes,
  createHash,
} from 'node:crypto';
import { log } from '../lib/observability';

// ---------------------------------------------------------------------------
// Endpoints
//
// These are KRA's own, from the OSCU specification and the taxpayer portal
// documentation. They are NOT interchangeable with the VSCU endpoints, and
// neither is interchangeable with a third-party aggregator's REST API — three
// different shapes that all appear in search results for "KRA eTIMS API".
//
//   Production: https://etims-api.kra.go.ke/etims-api
//   Sandbox:    https://etims-api-sbx.kra.go.ke
//
// `KRA_BASE_URL` overrides both, and `KRA_USE_SANDBOX` picks the default.
// There is deliberately no guessing and no fallback to a plausible-looking
// public URL: a wrong host fails with an opaque DNS or TLS error that looks
// exactly like an outage, and the shop's receipts stop filing.
// ---------------------------------------------------------------------------

export const KRA_PRODUCTION_URL = 'https://etims-api.kra.go.ke/etims-api';
export const KRA_SANDBOX_URL = 'https://etims-api-sbx.kra.go.ke';

export function kraBaseUrl(): string {
  const override = process.env.KRA_BASE_URL;
  if (override && override.trim() !== '') return override.trim();
  return process.env.KRA_USE_SANDBOX === 'true' ? KRA_SANDBOX_URL : KRA_PRODUCTION_URL;
}

/** Request timeout. A till is blocked on this while waiting to close a sale. */
const REQUEST_TIMEOUT_MS = Number(process.env.KRA_TIMEOUT_MS ?? 15_000);

/**
 * OSCU endpoints.
 *
 * Named as constants rather than inlined at each call site so the whole contract
 * with KRA can be read in one place, and so a VSCU swap changes one map rather
 * than a dozen strings scattered through the transport.
 */
export const KRA_ENDPOINTS = {
  /** Bearer token for the taxpayer's KRA account. Every other call needs one. */
  token: '/auth/get-token',
  /** Registers the Sales Control Unit and returns its keys. One-time. */
  initialise: '/init-osdc-info',
  /** Standard code lists KRA validates invoice data against. */
  codeList: '/select-code-list',
  /** Files a batch of sales transactions and invoices. */
  saveSales: '/save-sales-trns',
  /** Reads back the day's Z-report. */
  zReport: '/report',
} as const;

/** The default branch code. KRA uses '00' for a single-branch taxpayer. */
export const DEFAULT_BRANCH_ID = '00';

// ---------------------------------------------------------------------------
// Signing
// ---------------------------------------------------------------------------

/**
 * KRA's OSCU "signature": base64 of an HMAC-SHA512 over the timestamp, the
 * taxpayer PIN and the nonce, keyed by the access key KRA issued at
 * initialisation.
 *
 * `key` is decoded from base64 rather than used as an ASCII string. OSCU keys
 * are base64 in every KRA sample and treat them as opaque bytes; signing with
 * the ASCII of a base64 key produces a signature that is well-formed and
 * always rejected, which is a genuinely painful thing to debug.
 */
export function signRequest(
  timestamp: string,
  tin: string,
  deviceId: string,
  nonce: string,
  accessKeyBase64: string,
): string {
  const payload = `${timestamp}${tin}${deviceId}${nonce}`;
  const key = Buffer.from(accessKeyBase64, 'base64');
  return createHmac('sha512', key).update(payload, 'utf8').digest('base64');
}

/** A fresh nonce. 16 random bytes, base64 — the length OSCU specifies. */
export function createNonce(): string {
  return randomBytes(16).toString('base64');
}

/**
 * Decrypts an OSCU AES-256-CBC payload.
 *
 * KRA returns `InitializationVector` and `EncryptedPayload` as base64, with the
 * ciphertext shaped IV || ciphertext || HMAC. The HMAC is verified before
 * anything is decrypted: an unauthenticated payload is exactly what an attacker
 * would substitute, and decrypting it first would mean acting on it.
 */
export function decryptPayload(
  encryptionKeyBase64: string,
  ivBase64: string,
  encryptedPayloadBase64: string,
): { plaintext: string; hmacValid: boolean } {
  const key = Buffer.from(encryptionKeyBase64, 'base64');
  const iv = Buffer.from(ivBase64, 'base64');
  const raw = Buffer.from(encryptedPayloadBase64, 'base64');

  // Trailing 64 bytes are the HMAC. Everything before is IV || ciphertext.
  const body = raw.subarray(0, raw.length - 64);
  const hmac = raw.subarray(raw.length - 64);
  const expected = createHash('sha512').update(body).digest();
  const hmacValid = timingSafeEqual(hmac, expected);

  const decipher = createDecipheriv('aes-256-cbc', key, iv);
  const plaintext = Buffer.concat([decipher.update(body.subarray(iv.length)), decipher.final()]).toString('utf8');
  return { plaintext, hmacValid };
}

/** Encrypts a request body the same way KRA expects one. */
export function encryptPayload(
  encryptionKeyBase64: string,
  body: unknown,
): { InitializationVector: string; EncryptedPayload: string } {
  const key = Buffer.from(encryptionKeyBase64, 'base64');
  const iv = randomBytes(16);
  const cipher = createCipheriv('aes-256-cbc', key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify(body), 'utf8'),
    cipher.final(),
  ]);
  const hmac = createHash('sha512').update(Buffer.concat([iv, ciphertext])).digest();
  return {
    InitializationVector: iv.toString('base64'),
    EncryptedPayload: Buffer.concat([iv, ciphertext, hmac]).toString('base64'),
  };
}

function timingSafeEqual(a: Buffer, b: Buffer): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/**
 * Why a KRA call did not produce a receipt.
 *
 * The distinction is load-bearing, not diagnostic detail. A `network` or
 * `timeout` failure means "try again later" and the till keeps the sale queued;
 * a `rejected` failure means KRA has considered and refused it, so retrying
 * forever achieves nothing and the shop has to be told.
 */
// ---------------------------------------------------------------------------
// Receipt vocabulary
// ---------------------------------------------------------------------------

/**
 * KRA's receipt *types*.
 *
 * A TIS must label every receipt, and the label is a legal statement: "this is
 * a training receipt" and "this is a duplicate of a real one" are different
 * claims to a tax authority. The type is what makes them distinguishable.
 */
export type ReceiptType = 'NORMAL' | 'COPY' | 'TRAINING' | 'PROFORMA';

/** What the receipt is *about*. */
export type TransactionType = 'SALE' | 'CREDIT NOTE' | 'DEBIT NOTE';

/**
 * The two-letter label printed on the receipt.
 *
 * Derived, never stored. KRA matches on the label, and a shop that could set it
 * freely would be able to print a `CC` over a real sale.
 */
export type ReceiptLabel = 'NS' | 'NC' | 'CS' | 'CC' | 'TS' | 'TC' | 'PS';

export function receiptLabel(type: ReceiptType, transaction: TransactionType): ReceiptLabel {
  switch (type) {
    case 'NORMAL':
      return transaction === 'CREDIT NOTE' ? 'NC' : 'NS';
    case 'COPY':
      return transaction === 'CREDIT NOTE' ? 'CC' : 'CS';
    case 'TRAINING':
      return transaction === 'CREDIT NOTE' ? 'TC' : 'TS';
    case 'PROFORMA':
      return 'PS';
  }
}

/**
 * KRA's tax-type code.
 *
 * `V` is VAT, the rate Kenyan retail sales run at. The other letters are KRA's
 * exemption categories. Anything else is refused rather than passed through:
 * KRA rejects an unrecognised `taxTyCd` outright, so an invented code produces
 * an unissued invoice and no useful error.
 */
export const TAX_TYPE_VAT = 'V';

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------

/**
 * KRA issues a bearer token from the taxpayer's account credentials, and every
 * other OSCU call must carry it.
 *
 * This was the single biggest correction from the first implementation, which
 * skipped authentication entirely and signed each request with the device key.
 * Both layers exist in OSCU — the bearer token authorises the *account*, and the
 * device key signs the *payload* — but the token comes first, and a request
 * without one is rejected before the signature is ever examined.
 */
export interface KraCredentials {
  username: string;
  password: string;
}

export interface TokenResult {
  accessToken: string;
  /** KRA returns the expiry in seconds since the epoch. */
  expiresAt: number;
}

const tokenCache = new Map<string, TokenResult>();

/**
 * Fetches a bearer token, reusing one that has not expired.
 *
 * Cached per base URL because the sandbox and production are separate
 * authorities with separate accounts; sharing a cache between them would send a
 * sandbox token to production and produce a 401 that looks like bad
 * credentials.
 *
 * A 60-second safety margin: KRA's clock and ours differ, and a token that
 * expires mid-flight turns every request into an intermittent failure.
 */
export async function getAccessToken(
  credentials: KraCredentials,
  options: KraClientOptions = {},
): Promise<string> {
  const baseUrl = options.baseUrl ?? kraBaseUrl();
  const cacheKey = `${baseUrl}|${credentials.username}`;
  const cached = tokenCache.get(cacheKey);
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (cached && cached.expiresAt - nowSeconds > 60) return cached.accessToken;

  const doFetch = options.fetchImpl ?? fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), options.timeoutMs ?? REQUEST_TIMEOUT_MS);
  try {
    const response = await doFetch(`${baseUrl.replace(/\/$/, '')}${KRA_ENDPOINTS.token}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      // OSCU takes the credentials in the body as username/password. Base64
      // Basic is the alternative seen in some SDKs; both appear in the wild, so
      // this sends the documented field names and lets an override supply the
      // other shape.
      body: JSON.stringify({
        username: credentials.username,
        password: credentials.password,
      }),
      signal: controller.signal,
    });

    const text = await response.text();
    if (!response.ok) {
      log('warn', 'kra.token_rejected', { status: response.status });
      throw new KraError(
        'rejected',
        'KRA rejected the account credentials. Check the username and password on the taxpayer account.',
      );
    }
    const envelope = parseJson<Record<string, unknown>>(text, KRA_ENDPOINTS.token);
    const token = pickString(envelope, 'access_token') ?? pickString(envelope, 'accessToken');
    if (!token) {
      throw new KraError('network', 'KRA returned no access token');
    }
    const expiresIn = pickNumber(envelope, 'expires_in') ?? 3600;
    tokenCache.set(cacheKey, { accessToken: token, expiresAt: nowSeconds + expiresIn });
    return token;
  } catch (error) {
    if (error instanceof KraError) throw error;
    if (isAbort(error)) throw new KraError('timeout', 'KRA did not issue an access token in time');
    // Never the raw message: it can carry the URL, and this text reaches the till.
    throw new KraError('network', 'Could not reach KRA to authenticate');
  } finally {
    clearTimeout(timer);
  }
}

/** Test seam. The cache is module state, so tests need to be able to clear it. */
export function clearTokenCache(): void {
  tokenCache.clear();
}

export type KraFailureKind = 'network' | 'timeout' | 'rejected' | 'misconfigured';

export class KraError extends Error {
  constructor(
    readonly kind: KraFailureKind,
    message: string,
    /** KRA's own code, when it supplied one. Shown to the operator. */
    readonly kraCode?: string,
  ) {
    super(message);
    this.name = 'KraError';
  }
}

export interface InitialisationResult {
  /** KRA's own serial for the registered Sales Control Unit. */
  deviceSerial: string;
  /** The signing key every invoice from this shop is signed with. One-time. */
  accessKey: string;
  /** The AES key every payload is sealed with. One-time. */
  encryptionKey: string;
  /** The key OSCU uses to verify its own response to this device. */
  communicationKey?: string;
}

/** One transaction's outcome as KRA reported it. */
export interface SaveSalesItemResult {
  /** KRA's receipt number. Null when KRA refused the line. */
  receiptNumber: string | null;
  /** The verification QR payload, or null when KRA sent none. */
  qrCode: string | null;
  /** The document number KRA allocated. */
  documentNumber?: string;
  status: 'issued' | 'rejected';
  rejectionReason?: string;
}

export interface SaveSalesBatchResult {
  saveSalesItems: SaveSalesItemResult[];
}

export interface ZReportResult {
  zNumber: number;
  total: number;
  vatTotal: number;
  /** Receipts KRA has recorded but this device has not yet had accepted. */
  pendingCount: number;
}

// ---------------------------------------------------------------------------
// Transport
// ---------------------------------------------------------------------------

export interface KraClientOptions {
  baseUrl?: string;
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
  /** The taxpayer's KRA account. Required for every call except the token. */
  credentials?: KraCredentials;
}

/**
 * POSTs a signed, encrypted OSCU payload and unwraps the response.
 *
 * Every OSCU endpoint except the token takes the same envelope: the request body
 * is AES-encrypted with the device key and signed with HMAC-SHA512 over
 * timestamp + PIN + device id + nonce. `deviceTime` and `signature` are
 * generated here rather than accepted from the caller — a signature over a stale
 * clock is the most common cause of an OSCU rejection and is entirely avoidable
 * by never letting it be caller-supplied.
 */
async function callEndpoint<T>(
  path: string,
  opts: {
    tin: string;
    branchId: string;
    deviceId: string;
    accessKey: string;
    encryptionKey: string;
    body: Record<string, unknown>;
  },
  options: KraClientOptions = {},
): Promise<T> {
  const baseUrl = options.baseUrl ?? kraBaseUrl();
  const doFetch = options.fetchImpl ?? fetch;
  const timeoutMs = options.timeoutMs ?? REQUEST_TIMEOUT_MS;

  const deviceTime = new Date().toISOString();
  const nonce = createNonce();
  const signature = signRequest(deviceTime, opts.tin, opts.deviceId, nonce, opts.accessKey);

  const requestBody = {
    ...opts.body,
    tin: opts.tin,
    bhfId: opts.branchId,
    dvcSrlNo: opts.deviceId,
    deviceTime,
    nonce,
    signature,
  };

  const encrypted = encryptPayload(opts.encryptionKey, requestBody);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const token = options.credentials
      ? await getAccessToken(options.credentials, options)
      : undefined;

    const response = await doFetch(`${baseUrl.replace(/\/$/, '')}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(encrypted),
      signal: controller.signal,
    });

    const text = await response.text();
    if (!response.ok) {
      // A 4xx from KRA is a considered refusal; a 5xx is their problem, and
      // retrying the latter is right while retrying the former achieves nothing.
      const kind: KraFailureKind = response.status >= 500 ? 'network' : 'rejected';
      log('warn', 'kra.http_error', { path, status: response.status });
      if (response.status === 401 || response.status === 403) {
        // Almost always a stale or absent token rather than bad device keys, and
        // retrying with a fresh token is exactly right.
        clearTokenCache();
        throw new KraError('rejected', `KRA rejected the access token for ${path}`);
      }
      throw new KraError(kind, `KRA rejected ${path} with status ${response.status}`);
    }

    const envelope = parseJson<Record<string, unknown>>(text, path);
    return decryptBody<T>(envelope, opts.encryptionKey, path);
  } catch (error) {
    if (error instanceof KraError) throw error;
    if (isAbort(error)) {
      throw new KraError('timeout', `KRA did not answer ${path} within ${timeoutMs}ms`);
    }
    log('warn', 'kra.transport_error', {
      path,
      message: error instanceof Error ? error.message : 'unknown',
    });
    // Never the raw error: it can carry a URL with a token in it, and this text
    // reaches the till.
    throw new KraError('network', `Could not reach KRA for ${path}`);
  } finally {
    clearTimeout(timer);
  }
}

function parseJson<T>(text: string, path: string): T {
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new KraError('network', `KRA returned a non-JSON body for ${path}`);
  }
}

/**
 * Unwraps OSCU's `{ Description, Result: { ... } }` envelope.
 *
 * A `Description` of anything other than "Success" means the *operation* was
 * refused even though the HTTP call succeeded — which is the shape KRA uses for
 * a duplicate receipt number, an invalid TIN or a stale device clock. Those are
 * permanent and must not be retried, so they become `rejected` rather than
 * falling through as a network problem.
 */
function decryptBody<T>(envelope: Record<string, unknown>, encryptionKey: string, path: string): T {
  const description = pickString(envelope, 'Description') ?? '';
  if (description !== '' && description.toLowerCase() !== 'success') {
    // KRA puts the machine code in `Result.RejectReason` when it supplies one.
    const result = envelope.Result;
    const code =
      typeof result === 'object' && result !== null
        ? pickString(result as Record<string, unknown>, 'RejectReason')
        : undefined;
    throw new KraError('rejected', description, code);
  }

  const result = envelope.Result;
  if (typeof result !== 'object' || result === null) {
    throw new KraError('network', `KRA returned no result for ${path}`);
  }
  const record = result as Record<string, unknown>;

  const iv = pickString(record, 'InitializationVector');
  const payload = pickString(record, 'EncryptedPayload');
  if (!iv || !payload) {
    // Some endpoints return an unencrypted result before the taxpayer has
    // completed initialisation. Accepting it is what lets the first
    // initialisation call itself succeed.
    return record as T;
  }

  const { plaintext, hmacValid } = decryptPayload(encryptionKey, iv, payload);
  if (!hmacValid) {
    throw new KraError('network', `KRA payload for ${path} failed its integrity check`);
  }
  return parseJson<T>(plaintext, path);
}

function pickString(source: Record<string, unknown>, ...keys: string[]): string | undefined {
  for (const key of keys) {
    const value = source[key];
    if (typeof value === 'string' && value.trim() !== '') return value;
  }
  return undefined;
}

function pickNumber(source: Record<string, unknown>, ...keys: string[]): number | undefined {
  for (const key of keys) {
    const value = source[key];
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    if (typeof value === 'string') {
      const parsed = Number(value);
      if (Number.isFinite(parsed)) return parsed;
    }
  }
  return undefined;
}

function isAbort(error: unknown): boolean {
  return error instanceof Error && (error.name === 'AbortError' || error.name === 'TimeoutError');
}

// ---------------------------------------------------------------------------
// Endpoints
// ---------------------------------------------------------------------------

/**
 * Registers the Sales Control Unit with KRA and returns its keys.
 *
 * `bhfId` is the branch code and `dvcSrlNo` the device serial. KRA issues
 * `access_key` and `encryption_key` exactly once, and every invoice this shop
 * will ever file is signed with them, so this is deliberately not idempotent
 * from the caller's side — re-registering mints a new pair and orphans
 * everything already issued.
 */
export async function initialiseDevice(
  params: {
    tin: string;
    branchId: string;
    deviceSerial: string;
    deviceName?: string;
  },
  options: KraClientOptions = {},
): Promise<InitialisationResult> {
  if (!params.tin || !params.deviceSerial) {
    throw new KraError('misconfigured', 'A TIN and a device serial are required to initialise');
  }

  const result = await callEndpoint<Record<string, unknown>>(
    KRA_ENDPOINTS.initialise,
    {
      tin: params.tin,
      branchId: params.branchId,
      deviceId: params.deviceSerial,
      // Before any keys exist there is nothing to sign with, so OSCU signs the
      // initialisation request with the taxpayer PIN itself.
      accessKey: Buffer.from(params.tin, 'utf8').toString('base64'),
      encryptionKey: Buffer.from(params.tin, 'utf8').toString('base64'),
      body: { deviceName: params.deviceName ?? 'Simple POS', type: 'normal' },
    },
    options,
  );

  const accessKey = pickString(result, 'access_key', 'accessKey');
  const encryptionKey = pickString(result, 'encryption_key', 'encryptionKey');
  if (!accessKey || !encryptionKey) {
    throw new KraError('rejected', 'KRA initialisation returned no device keys');
  }
  return {
    accessKey,
    encryptionKey,
    deviceSerial: pickString(result, 'dvcSrlNo') ?? params.deviceSerial,
    communicationKey: pickString(result, 'communication_key', 'communicationKey'),
  };
}

/**
 * Fetches the standard code lists KRA validates invoice data against.
 *
 * KRA rejects an invoice whose item classification or tax code is not on file.
 * Calling this before the first real invoice is not optional politeness: without
 * the code list the first sale of a new category fails, usually on a day with a
 * queue behind it.
 */
export async function fetchCodeList(
  params: {
    tin: string;
    branchId: string;
    deviceId: string;
    accessKey: string;
    encryptionKey: string;
    /** KRA pages by last-requested date; omit for everything not yet seen. */
    lastRequestAt?: string;
  },
  options: KraClientOptions = {},
): Promise<Record<string, unknown>> {
  return callEndpoint<Record<string, unknown>>(
    KRA_ENDPOINTS.codeList,
    {
      tin: params.tin,
      branchId: params.branchId,
      deviceId: params.deviceId,
      accessKey: params.accessKey,
      encryptionKey: params.encryptionKey,
      // KRA pages by "last requested date"; an empty string asks for everything
      // the taxpayer has not yet seen.
      body: { lastReqDt: params.lastRequestAt ?? '' },
    },
    options,
  );
}

/**
 * One line of a sales transaction, in KRA's field names.
 *
 * Amounts are strings, not numbers. KRA's schema is `Decimal`, and a JSON float
 * here is a rounding error that only surfaces when a filed invoice is
 * reconciled against the till.
 */
export interface SalesTransactionItem {
  itemCode: string;
  itemName: string;
  quantity: number;
  price: string;
  supplyAmount: string;
  taxTypeCode: string;
  taxAmount: string;
  /** Present only for a partial serving, which KRA requires be declared. */
  quantityUnit?: string;
  quantityUnitAmount?: number;
}

export interface SaveSalesParams {
  tin: string;
  branchId: string;
  deviceId: string;
  accessKey: string;
  encryptionKey: string;
  invoiceNumber: string;
  /** The label the till printed. KRA matches on it. */
  receiptLabel: ReceiptLabel;
  receiptType: ReceiptType;
  transactionType: TransactionType;
  buyerPin?: string;
  /** Business-customer details, when the till captured them (spec 7.6). */
  buyerName?: string;
  buyerTin?: string;
  totalAmount: string;
  totalTaxAmount: string;
  paymentModeCode: string;
  paymentAmount: string;
  paymentReference?: string;
  items: SalesTransactionItem[];
}

/**
 * Files a batch of sales transactions with KRA.
 *
 * One call for the whole batch rather than one per receipt. OSCU's
 * `save-sales-trns` takes an array, and a till that was offline has a *sequence*
 * of receipts to file in order — sending them individually would let a
 * transport failure interleave two of them and leave a permanent gap in the
 * device's invoice sequence, which KRA then rejects.
 */
export async function saveSalesTransactions(
  params: SaveSalesParams,
  options: KraClientOptions = {},
): Promise<SaveSalesBatchResult> {
  if (params.items.length === 0) return { saveSalesItems: [] };

  const result = await callEndpoint<Record<string, unknown>>(
    KRA_ENDPOINTS.saveSales,
    {
      tin: params.tin,
      branchId: params.branchId,
      deviceId: params.deviceId,
      accessKey: params.accessKey,
      encryptionKey: params.encryptionKey,
      body: {
        salesTrnsItems: params.items.map((item) => ({
          itemCd: item.itemCode,
          itemNm: item.itemName,
          qty: item.quantity,
          prc: item.price,
          splyAmt: item.supplyAmount,
          taxTyCd: item.taxTypeCode,
          taxAmt: item.taxAmount,
          ...(item.quantityUnit
            ? { qtyUnit: item.quantityUnit, qtyUnitAmt: item.quantityUnitAmount }
            : {}),
        })),
        // The invoice header. KRA wraps the transaction and the invoice together
        // in one request, which is why this is not two calls.
        invoice: {
          invcNo: params.invoiceNumber,
          rcptLabel: params.receiptLabel,
          rceiptType: params.receiptType,
          transactionType: params.transactionType,
          buyerPin: params.buyerPin,
          ...(params.buyerName || params.buyerTin
            ? { buyerDtls: { buyerNm: params.buyerName, buyerTin: params.buyerTin } }
            : {}),
          totlAmt: params.totalAmount,
          taxAmt: params.totalTaxAmount,
          prdtDet: params.items.map((item) => ({
            itemCd: item.itemCode,
            itemNm: item.itemName,
            qty: item.quantity,
            prc: item.price,
            splyAmt: item.supplyAmount,
            taxTyCd: item.taxTypeCode,
            taxAmt: item.taxAmount,
          })),
          pmntDtls: [
            {
              pmntCd: params.paymentModeCode,
              amt: params.paymentAmount,
              ...(params.paymentReference ? { pmtRef: params.paymentReference } : {}),
            },
          ],
        },
      },
    },
    options,
  );

  const rawItems = Array.isArray(result.saveSalesItems) ? result.saveSalesItems : [];
  return {
    saveSalesItems: rawItems.map((raw) => {
      const item = raw as Record<string, unknown>;
      const receiptNumber = pickString(item, 'invReceiptNo', 'InvoiceReceiptNumber');
      const rejection = pickString(item, 'rejectReason', 'RejectReason');
      return {
        receiptNumber: receiptNumber ?? null,
        qrCode: pickString(item, 'qrCode', 'QRCode') ?? null,
        ...(pickString(item, 'docNo', 'DocumentNumber')
          ? { documentNumber: pickString(item, 'docNo', 'DocumentNumber') }
          : {}),
        status: receiptNumber ? ('issued' as const) : ('rejected' as const),
        ...(receiptNumber
          ? {}
          : { rejectionReason: rejection ?? 'KRA issued no receipt number' }),
      };
    }),
  };
}

/** Fetches the Z-report for a business date, `YYYY-MM-DD`. */
export async function fetchZReport(
  params: {
    tin: string;
    branchId: string;
    deviceId: string;
    accessKey: string;
    encryptionKey: string;
    date: string;
  },
  options: KraClientOptions = {},
): Promise<ZReportResult> {
  const result = await callEndpoint<Record<string, unknown>>(
    KRA_ENDPOINTS.zReport,
    {
      tin: params.tin,
      branchId: params.branchId,
      deviceId: params.deviceId,
      accessKey: params.accessKey,
      encryptionKey: params.encryptionKey,
      body: { reportType: 'Z-REPORT', date: params.date },
    },
    options,
  );

  return {
    zNumber: pickNumber(result, 'zNo', 'ZNumber') ?? 0,
    total: pickNumber(result, 'totlAmt', 'TotalAmount') ?? 0,
    vatTotal: pickNumber(result, 'taxAmt', 'TaxAmount') ?? 0,
    pendingCount: pickNumber(result, 'pdngInvCnt', 'PendingInvoiceCount') ?? 0,
  };
}
