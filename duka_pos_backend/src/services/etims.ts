/**
 * eTIMS orchestration.
 *
 * Everything between "a till recorded a sale" and "KRA issued an invoice for
 * it". The KRA client knows how to sign and transmit; this file knows what to
 * file, in what order, what to do when KRA refuses, and what a Z-report must
 * contain.
 *
 * ## The money boundary
 *
 * The till sends integer **minor units** (cents) because that is how it stores
 * money and how it prints it. This backend stores **Decimal major units**
 * because that is what KRA, the PayHero webhook and every other producer of a
 * figure into this database speaks. The conversion happens here, once, in
 * `toMinor`/`fromMinor`, and nowhere else.
 *
 * The alternative — storing cents everywhere — would mean a second representation
 * of money in the database and a conversion that could be forgotten at any call
 * site. The failure mode of that is a tax invoice that is out by a factor of
 * one hundred, which is both catastrophic and entirely invisible in review.
 */

import { prisma } from '../lib/prisma';
import { log } from '../lib/observability';
import {
  DEFAULT_BRANCH_ID,
  TAX_TYPE_VAT,
  kraBaseUrl,
  fetchCodeList,
  fetchZReport,
  initialiseDevice,
  receiptLabel,
  saveSalesTransactions,
  KraError,
  type KraCredentials,
  type ReceiptType,
  type SaveSalesItemResult,
  type TransactionType,
} from './kra';

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

/**
 * Cents to a KES string with exactly two decimal places.
 *
 * Integer division and remainder, never floating point. `8060 / 100` in JS is
 * 80.6, and `80.6.toFixed(2)` is fine, but `0.1 + 0.2` style drift across a
 * day's invoices is not — and the fix is one line of integer arithmetic.
 */
export function toMajor(minorUnits: number): string {
  if (!Number.isFinite(minorUnits)) throw new RangeError('amount is not a finite number');
  if (!Number.isInteger(minorUnits)) {
    throw new RangeError('the till must send integer minor units, not a fraction');
  }
  const negative = minorUnits < 0;
  const abs = Math.abs(minorUnits);
  const major = Math.floor(abs / 100);
  const cents = abs % 100;
  return `${negative ? '-' : ''}${major}.${cents.toString().padStart(2, '0')}`;
}

/** A KES Decimal string back to integer cents, for comparing to till figures. */
export function fromMajor(major: string | number): number {
  const value = typeof major === 'number' ? major : Number.parseFloat(major);
  if (!Number.isFinite(value)) throw new RangeError('amount is not a finite number');
  // Rounded, not truncated: a half-cent must never silently become a cent less.
  return Math.round(value * 100);
}

// ---------------------------------------------------------------------------
// Invoice construction
// ---------------------------------------------------------------------------

export interface InvoiceItemInput {
  name: string;
  qty: number;
  unitPrice: number; // minor units
  unitCost: number; // minor units
  /** Optional because the wire schema defaults it; a full bottle has neither. */
  portion?: string;
  portionMl?: number;
  vatAmount: number; // minor units, already extracted by the till
  lineTotal: number; // minor units
}

export interface InvoiceInput {
  receiptNumber: string;
  issuedAt: string;
  paymentMethod: string;
  paymentReference?: string;
  total: number; // minor units
  vatRatePercent: number;
  items: InvoiceItemInput[];
  /** Business-customer details, when the till captured them (spec 7.6). */
  buyerName?: string;
  buyerTin?: string;
}

/**
 * Builds KRA's sales-transaction document, in the field names OSCU uses.
 *
 * Item totals are recomputed here as `qty * unitPrice` and *checked* against the
 * line total the till sent. They are not trusted: the till's figure is what the
 * customer was charged and what the receipt says, and if the two disagree the
 * invoice is refused rather than silently adjusted, because a tax invoice that
 * quietly corrects the till is one nobody can reconcile against the paper.
 *
 * Amounts leave as strings. KRA's schema is `Decimal`; a JSON number here is a
 * rounding error that only surfaces at reconciliation.
 */
export function buildKraInvoice(
  input: InvoiceInput,
  opts: { itemCodeFor?: (item: InvoiceItemInput, index: number) => string } = {},
): {
  invoiceNumber: string;
  totalAmount: string;
  totalTaxAmount: string;
  paymentModeCode: string;
  paymentAmount: string;
  buyerName?: string;
  buyerTin?: string;
  items: Array<{
    itemCode: string;
    itemName: string;
    quantity: number;
    price: string;
    supplyAmount: string;
    taxTypeCode: string;
    taxAmount: string;
    quantityUnit?: string;
    quantityUnitAmount?: number;
  }>;
} {
  if (input.items.length === 0) {
    throw new RangeError('a tax invoice with no items is not an invoice');
  }

  let itemTotalMinor = 0;
  const items = input.items.map((item, index) => {
    const lineTotalMinor = Math.round(item.qty * item.unitPrice);
    if (lineTotalMinor !== item.lineTotal) {
      throw new RangeError(
        `line ${index + 1} (${item.name}) totals ${item.lineTotal} but its quantity and price come to ${lineTotalMinor}`,
      );
    }
    itemTotalMinor += lineTotalMinor;
    return {
      // KRA validates the item against its registered classification, so the
      // code is not the product name. Falls back to the name because an
      // unregistered code must produce a visible KRA refusal rather than a
      // silently wrong filing.
      itemCode: opts.itemCodeFor?.(item, index) ?? item.name.slice(0, 60),
      itemName: item.name,
      quantity: item.qty,
      price: toMajor(item.unitPrice),
      supplyAmount: toMajor(item.lineTotal),
      taxTypeCode: item.vatAmount > 0 ? TAX_TYPE_VAT : TAX_TYPE_VAT,
      taxAmount: toMajor(item.vatAmount),
      // A partial serving declares its volume, which is what makes a half
      // bottle distinguishable from a full one on a taxed document. A full
      // bottle declares neither: KRA reads its volume from the catalogue.
      ...(item.portion && item.portion !== 'full'
        ? item.portionMl && item.portionMl > 0
          ? { quantityUnit: 'Bottle', quantityUnitAmount: item.portionMl }
          : {}
        : {}),
    };
  });

  if (itemTotalMinor !== input.total) {
    throw new RangeError(
      `invoice total ${input.total} does not equal the sum of its lines (${itemTotalMinor})`,
    );
  }

  const taxTotalMinor = input.items.reduce((sum, item) => sum + item.vatAmount, 0);

  return {
    invoiceNumber: input.receiptNumber,
    totalAmount: toMajor(input.total),
    totalTaxAmount: toMajor(taxTotalMinor),
    paymentModeCode: paymentModeCodeFor(input.paymentMethod),
    paymentAmount: toMajor(input.total),
    // Buyer details ride the document when the till captured them; absent
    // fields are omitted rather than sent as empty strings, which KRA reads
    // as a business customer with a blank PIN and rejects.
    ...(input.buyerName || input.buyerTin ? { buyerName: input.buyerName, buyerTin: input.buyerTin } : {}),
    items,
  };
}

/**
 * The receipt label a till should have printed for a given submission.
 *
 * A reprint is not a normal receipt. KRA requires "TIS shall print only one
 * original receipt. Reprints shall have a watermark with mention Copy" — so a
 * reprint is filed as a `COPY`/`CS`, which is a materially different statement
 * to a tax authority, and the paper is watermarked to match.
 */
export function labelForSubmission(opts: {
  isReprint: boolean;
  transactionType?: TransactionType;
}): { receiptType: ReceiptType; transactionType: TransactionType; label: string } {
  const transactionType = opts.transactionType ?? 'SALE';
  const receiptType: ReceiptType = opts.isReprint ? 'COPY' : 'NORMAL';
  return { receiptType, transactionType, label: receiptLabel(receiptType, transactionType) };
}

/**
 * KRA's payment-mode vocabulary.
 *
 * Unknown values map to `Cash` rather than being passed through: KRA rejects an
 * unrecognised code outright, so a till that invents `mobile_money_manual` would
 * produce an unissued invoice and no useful error.
 */
export function paymentModeCodeFor(paymentMethod: string): string {
  switch (paymentMethod) {
    case 'card':
      return 'Card';
    case 'mpesa':
      return 'MPEZA';
    case 'mobile_money_manual':
      return 'MobileMoney';
    case 'bank_transfer':
      return 'BankTransfer';
    case 'credit':
      // A sale recorded on account is filed as a credit sale, not as Cash:
      // filing it as Cash reports money the shop never received that day.
      return 'Credit';
    case 'cash':
    default:
      return 'Cash';
  }
}

// ---------------------------------------------------------------------------
// Device lifecycle
// ---------------------------------------------------------------------------

export type EtimsIssueOutcome =
  | { status: 'issued'; receiptNumber: string; qrPayload: string | null }
  | { status: 'already_issued'; receiptNumber: string; qrPayload: string | null }
  | { status: 'pending' }
  | { status: 'rejected'; reason: string };

/**
 * Registers (or re-registers) this shop's device with KRA.
 *
 * KRA issues `AccessKey` and `EncryptionKey` exactly once. If a second
 * registration is attempted the existing keys are returned untouched rather
 * than overwritten: re-registering mints new keys, which orphans every invoice
 * already signed with the old ones.
 */
/**
 * Fails loudly when the deployment has no KRA account configured.
 *
 * Without this, the first symptom is a KRA `401` on the first live sale, which
 * reads as "our credentials are wrong" and sends the operator looking at a
 * username that does not exist. Saying so at registration time turns an
 * ambiguous mid-sale failure into an actionable setup error.
 */
export function assertKraConfigured(): void {
  if (kraCredentialsFromEnv()) return;
  throw new KraError(
    'misconfigured',
    'This server has no KRA account configured. Set KRA_USERNAME and KRA_PASSWORD before enabling eTIMS.',
  );
}

export async function registerDevice(params: {
  tenantId: string;
  shopName: string;
  tin: string;
  /** The device serial the shop chose; KRA echoes it as `dvcSrlNo`. */
  deviceId: string;
  deviceName?: string;
  /** KRA's branch code. '00' for a single-branch taxpayer. */
  branchId?: string;
  /** The taxpayer's KRA account, needed for the bearer token. */
  credentials?: KraCredentials;
}) {
  assertKraConfigured();

  const existing = await prisma.etimsDevice.findUnique({ where: { tenantId: params.tenantId } });
  if (existing?.status === 'active') {
    return existing;
  }

  const branchId = params.branchId ?? DEFAULT_BRANCH_ID;
  const clientOptions = {
    baseUrl: kraBaseUrl(),
    credentials: params.credentials ?? kraCredentialsFromEnv(),
  };

  try {
    const result = await initialiseDevice(
      {
        tin: params.tin,
        branchId,
        deviceSerial: params.deviceId,
        deviceName: params.deviceName ?? params.shopName,
      },
      clientOptions,
    );

    const device = await prisma.etimsDevice.upsert({
      where: { tenantId: params.tenantId },
      create: {
        tenantId: params.tenantId,
        tin: params.tin,
        deviceId: params.deviceId,
        deviceName: params.deviceName ?? params.shopName,
        status: 'active',
        accessKey: result.accessKey,
        encryptionKey: result.encryptionKey,
        deviceSerial: result.deviceSerial,
        initialisedAt: new Date(),
      },
      update: {
        // Never overwritten once set: see the note above.
        ...(existing?.accessKey ? {} : { accessKey: result.accessKey }),
        ...(existing?.encryptionKey ? {} : { encryptionKey: result.encryptionKey }),
        tin: params.tin,
        deviceId: params.deviceId,
        deviceName: params.deviceName ?? params.shopName,
        status: 'active',
        deviceSerial: result.deviceSerial,
        initialisedAt: new Date(),
        lastError: null,
      },
    });

    // The standard code list KRA validates every invoice against. Fetched right
    // after registration rather than lazily, because the first sale of a new
    // category is otherwise the thing that discovers the list was never
    // retrieved — usually with a queue behind it.
    try {
      await fetchCodeList(
        {
          tin: params.tin,
          branchId,
          deviceId: params.deviceId,
          accessKey: result.accessKey,
          encryptionKey: result.encryptionKey,
        },
        clientOptions,
      );
    } catch (error) {
      // Not fatal to registration: the device is registered and invoices will
      // still be filed. Recorded so the owner sees that classifications may be
      // missing rather than discovering it as a rejected invoice.
      log('warn', 'etims.code_list_failed', {
        tenantId: params.tenantId,
        message: error instanceof Error ? error.message : 'unknown',
      });
    }

    return device;
  } catch (error) {
    const reason = error instanceof KraError ? error.message : 'Device registration failed';
    log('error', 'etims.register_device_failed', { tenantId: params.tenantId, reason });
    await prisma.etimsDevice.upsert({
      where: { tenantId: params.tenantId },
      create: {
        tenantId: params.tenantId,
        tin: params.tin,
        deviceId: params.deviceId,
        status: 'unregistered',
        lastError: reason,
      },
      update: { status: 'unregistered', lastError: reason },
    });
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Receipt issuance
// ---------------------------------------------------------------------------

/**
 * Files one receipt for the till.
 *
 * The receipt row is written *before* the network call and updated after, so a
 * crash mid-flight leaves a `pending` row rather than no record at all. A sale
 * that exists only in the till's memory until KRA answers is a sale that can be
 * lost.
 */
export async function issueReceipt(params: {
  tenantId: string;
  deviceId?: string | null;
  input: InvoiceInput;
  /** A reprint is filed as a COPY, per KRA's one-original-receipt rule. */
  isReprint?: boolean;
  /** The taxpayer's KRA account, for the bearer token. */
  credentials?: KraCredentials;
}): Promise<EtimsIssueOutcome> {
  const device = await prisma.etimsDevice.findUnique({ where: { tenantId: params.tenantId } });
  if (!device || device.status !== 'active' || !device.accessKey || !device.encryptionKey) {
    // Not configured is a permanent condition until the shop registers. It is
    // thrown rather than returned as `pending` so the till stops retrying and
    // shows the owner what to fix.
    throw new KraError('misconfigured', 'This shop has no active KRA device registration');
  }

  const vatTotalMinor = params.input.items.reduce((sum, item) => sum + item.vatAmount, 0);

  const existing = await prisma.etimsReceipt.findUnique({
    where: { tenantId_receiptNumber: { tenantId: params.tenantId, receiptNumber: params.input.receiptNumber } },
  });
  if (existing?.status === 'issued' && existing.kraReceiptNumber) {
    return { status: 'already_issued', receiptNumber: existing.kraReceiptNumber, qrPayload: existing.qrPayload };
  }
  const receipt = existing
    ? await prisma.etimsReceipt.update({
        where: { id: existing.id },
        data: { status: 'pending', rejectionReason: null },
      })
    : await prisma.etimsReceipt.create({
      data: {
      tenantId: params.tenantId,
      deviceId: device.id,
      receiptNumber: params.input.receiptNumber,
      payload: params.input as unknown as object,
      total: toMajor(params.input.total),
      vatTotal: toMajor(vatTotalMinor),
      vatRatePercent: params.input.vatRatePercent,
      itemCount: params.input.items.length,
      paymentMethod: params.input.paymentMethod,
      paymentReference: params.input.paymentReference ?? null,
      status: 'pending',
      },
    });

  if (receipt.status === 'issued' && receipt.kraReceiptNumber) {
    return { status: 'already_issued', receiptNumber: receipt.kraReceiptNumber, qrPayload: null };
  }

  const invoice = buildKraInvoice(params.input);
  const label = labelForSubmission({ isReprint: params.isReprint === true });

  try {
    const batch = await saveSalesTransactions(
      {
        tin: device.tin,
        branchId: DEFAULT_BRANCH_ID,
        deviceId: device.deviceId,
        accessKey: device.accessKey,
        encryptionKey: device.encryptionKey,
        invoiceNumber: invoice.invoiceNumber,
        receiptType: label.receiptType,
        transactionType: label.transactionType,
        receiptLabel: label.label as 'NS' | 'NC' | 'CS' | 'CC' | 'TS' | 'TC' | 'PS',
        totalAmount: invoice.totalAmount,
        totalTaxAmount: invoice.totalTaxAmount,
        paymentModeCode: invoice.paymentModeCode,
        paymentAmount: invoice.paymentAmount,
          ...(params.input.paymentReference
            ? { paymentReference: params.input.paymentReference }
            : {}),
          ...(params.input.buyerName || params.input.buyerTin
            ? { buyerName: params.input.buyerName, buyerTin: params.input.buyerTin }
            : {}),
          items: invoice.items,
        },
        { baseUrl: kraBaseUrl(), credentials: params.credentials ?? kraCredentialsFromEnv() },
      );

    const result: SaveSalesItemResult | undefined = batch.saveSalesItems[0];
    if (!result?.receiptNumber) {
      const reason = result?.rejectionReason ??
        'KRA acknowledged the invoice but issued no receipt number';
      await markRejected(receipt.id, reason);
      return { status: 'rejected', reason };
    }

    await prisma.etimsReceipt.update({
      where: { id: receipt.id },
      data: {
        status: 'issued',
        kraReceiptNumber: result.receiptNumber,
        issuedAt: new Date(),
        // Stored as submitted, including the label. A disputed invoice has to be
        // reproducible exactly as KRA received it.
        payload: { input: params.input, label } as unknown as object,
        rejectionReason: null,
      },
    });

    return { status: 'issued', receiptNumber: result.receiptNumber, qrPayload: result.qrCode };
  } catch (error) {
    // A transport failure leaves the row `pending`: the sale is committed, the
    // invoice is outstanding, and the till will try again. Only a refusal by
    // KRA itself is terminal.
    const reason = error instanceof KraError ? error.message : 'Unexpected failure while filing with KRA';
    const terminal = error instanceof KraError && (error.kind === 'rejected' || error.kind === 'misconfigured');
    log('warn', 'etims.issue_receipt_failed', {
      tenantId: params.tenantId,
      receiptNumber: params.input.receiptNumber,
      terminal,
      reason,
    });
    if (terminal) {
      await markRejected(receipt.id, reason);
      return { status: 'rejected', reason };
    }
    return { status: 'pending' };
  }
}

async function markRejected(receiptId: string, reason: string): Promise<void> {
  await prisma.etimsReceipt.update({
    where: { id: receiptId },
    data: { status: 'rejected', rejectionReason: reason.slice(0, 500) },
  });
}

// ---------------------------------------------------------------------------
// Offline batch upload
// ---------------------------------------------------------------------------

/** The credit-note payload receipt_links.ts queues, snake_case as stored. */
export interface CreditNotePayload {
  document_type: 'credit_note';
  original_receipt_number?: string;
  reason_code?: string;
  lines?: unknown[];
  total?: number;
  vat_total?: number;
  buyer_name?: string;
  buyer_tin?: string;
}

/**
 * Normalises a queued credit note into the InvoiceInput the invoice builder
 * already validates, so a credit note can never be mis-filed as a sale: the
 * label comes out 'NC', the transaction type 'CREDIT NOTE', and the line
 * arithmetic is checked exactly like an invoice's.
 *
 * The payment mode mirrors the ORIGINAL sale's — a credit note reverses that
 * payment, not a fresh one. When the original cannot be read it files as
 * `Credit` (on account) rather than as money changing hands again.
 */
export function creditNoteInvoiceInput(
  payload: CreditNotePayload,
  opts: { receiptNumber: string; originalPaymentMethod?: string | null },
): InvoiceInput {
  const lines = Array.isArray(payload.lines) ? payload.lines : [];
  if (lines.length === 0) throw new RangeError('a credit note with no lines is not a document');
  const items = lines.map((raw, index) => {
    const line = (raw ?? {}) as Record<string, unknown>;
    const name = typeof line.name === 'string' && line.name.trim() !== '' ? line.name : `line ${index + 1}`;
    const qty = Number(line.qty ?? 0);
    const unitPrice = Number(line.unit_price ?? 0);
    const lineTotal = Number(line.line_total ?? 0);
    if (!Number.isFinite(qty) || !Number.isFinite(unitPrice) || !Number.isFinite(lineTotal)) {
      throw new RangeError(`credit note line ${index + 1} (${name}) carries a non-numeric amount`);
    }
    const portionMl = Number(line.portion_ml);
    return {
      name,
      qty,
      unitPrice,
      // A reversal restocks what the sale consumed; it does not price the
      // goods again, so cost stays out of the filed document.
      unitCost: 0,
      ...(typeof line.portion === 'string' ? { portion: line.portion } : {}),
      ...(Number.isFinite(portionMl) && portionMl > 0 ? { portionMl } : {}),
      vatAmount: Number.isFinite(Number(line.vat_amount)) ? Number(line.vat_amount) : 0,
      lineTotal,
    };
  });
  const total = Number(payload.total ?? 0);
  if (!Number.isFinite(total) || total <= 0) {
    throw new RangeError('the credit note total must be a positive number');
  }
  return {
    receiptNumber: opts.receiptNumber,
    issuedAt: new Date().toISOString(),
    paymentMethod: opts.originalPaymentMethod ?? 'credit',
    ...(payload.buyer_name?.trim() ? { buyerName: payload.buyer_name.trim() } : {}),
    ...(payload.buyer_tin?.trim() ? { buyerTin: payload.buyer_tin.trim() } : {}),
    total,
    vatRatePercent: 0,
    items,
  };
}

/**
 * Uploads every outstanding receipt in issue order.
 *
 * Oldest first, deliberately. KRA validates the device's invoice sequence, and
 * a batch submitted newest-first leaves a permanent hole at the point the
 * oldest invoice is eventually sent — which then rejects that invoice. Ordering
 * is a correctness requirement here, not a preference.
 *
 * Returns the ids that are still outstanding so the caller can tell the till
 * whether its queue has drained.
 */
export async function uploadPendingBatch(params: {
  tenantId: string;
  limit?: number;
  /** The taxpayer's KRA account, for the bearer token. */
  credentials?: KraCredentials;
}): Promise<{ uploaded: number; stillPending: string[]; rejected: Array<{ receiptNumber: string; reason: string }> }> {
  const limit = params.limit ?? 100;
  const device = await prisma.etimsDevice.findUnique({ where: { tenantId: params.tenantId } });
  if (!device || device.status !== 'active') {
    throw new KraError('misconfigured', 'This shop has no active KRA device registration');
  }

  const outstanding = await prisma.etimsReceipt.findMany({
    where: { tenantId: params.tenantId, status: { in: ['pending', 'rejected'] } },
    orderBy: { receiptNumber: 'asc' },
    take: limit,
  });

  if (outstanding.length === 0) return { uploaded: 0, stillPending: [], rejected: [] };

  // One OSCU call per receipt, in issue order.
  //
  // KRA validates the device's invoice sequence, so a run has to be contiguous.
  // The loop stops at the first receipt KRA does not accept, rather than
  // carrying on: a refusal usually means a stale clock, an uninitialised device
  // or a bad TIN, and none of those improves for the next receipt — while
  // carrying on would file a later receipt over a gap and make the gap
  // permanent.
  //
  // Credit notes are their own document type and are built as such; a row
  // whose payload does not build is marked rejected here rather than poisoning
  // the run — the rows are independent submissions and a malformed payload
  // would otherwise be retried forever.
  const documents: Array<{
    receipt: (typeof outstanding)[number];
    invoice: ReturnType<typeof buildKraInvoice>;
    label: ReturnType<typeof labelForSubmission>;
  }> = [];
  const rejected: Array<{ receiptNumber: string; reason: string }> = [];

  for (const receipt of outstanding) {
    try {
      const isCreditNote = receipt.documentType === 'credit_note';
      const input = isCreditNote
        ? creditNoteInvoiceInput(receipt.payload as unknown as CreditNotePayload, {
            receiptNumber: receipt.receiptNumber,
            originalPaymentMethod: receipt.originalReceiptNumber
              ? (
                  await prisma.etimsReceipt.findFirst({
                    where: {
                      tenantId: params.tenantId,
                      OR: [
                        { kraReceiptNumber: receipt.originalReceiptNumber },
                        { receiptNumber: receipt.originalReceiptNumber },
                      ],
                    },
                    select: { paymentMethod: true },
                  })
                )?.paymentMethod ?? null
              : null,
          })
        : (receipt.payload as unknown as InvoiceInput);
      documents.push({
        receipt,
        invoice: buildKraInvoice(input),
        label: labelForSubmission({
          isReprint: false,
          transactionType: isCreditNote ? 'CREDIT NOTE' : 'SALE',
        }),
      });
    } catch (error) {
      const reason = error instanceof Error ? error.message : 'malformed document';
      await markRejected(receipt.id, reason);
      rejected.push({ receiptNumber: receipt.receiptNumber, reason });
    }
  }

  if (documents.length === 0) return { uploaded: 0, stillPending: [], rejected };

  const stillPending: string[] = [];

  try {
    let uploaded = 0;

    for (const { receipt, invoice, label } of documents) {
      const batch = await saveSalesTransactions(
        {
          tin: device.tin,
          branchId: DEFAULT_BRANCH_ID,
          deviceId: device.deviceId,
          accessKey: device.accessKey!,
          encryptionKey: device.encryptionKey!,
          invoiceNumber: invoice.invoiceNumber,
          receiptType: label.receiptType,
          transactionType: label.transactionType,
          receiptLabel: label.label as 'NS' | 'NC' | 'CS' | 'CC' | 'TS' | 'TC' | 'PS',
          totalAmount: invoice.totalAmount,
          totalTaxAmount: invoice.totalTaxAmount,
          paymentModeCode: invoice.paymentModeCode,
          paymentAmount: invoice.paymentAmount,
          ...(invoice.buyerName || invoice.buyerTin
            ? { buyerName: invoice.buyerName, buyerTin: invoice.buyerTin }
            : {}),
          items: invoice.items,
        },
        { baseUrl: kraBaseUrl(), credentials: params.credentials ?? kraCredentialsFromEnv() },
      );

      const item: SaveSalesItemResult | undefined = batch.saveSalesItems[0];
      if (item?.status === 'issued' && item.receiptNumber) {
        await prisma.etimsReceipt.update({
          where: { id: receipt.id },
          data: { status: 'issued', kraReceiptNumber: item.receiptNumber, issuedAt: new Date(), rejectionReason: null },
        });
        uploaded++;
      } else if (item?.status === 'rejected') {
        const reason = item.rejectionReason ?? 'KRA refused this invoice';
        await markRejected(receipt.id, reason);
        rejected.push({ receiptNumber: receipt.receiptNumber, reason });
        // Stop the run. A refusal usually means a stale clock, an uninitialised
        // device or a bad TIN, and none of those improves on the next receipt.
        break;
      } else {
        // No answer for this one. Left pending rather than guessed at, and the
        // run stops so the sequence stays contiguous.
        stillPending.push(receipt.receiptNumber);
        break;
      }
    }
    return { uploaded, stillPending, rejected };
  } catch (error) {
    // The whole batch failed, so nothing is marked. The till will retry the
    // same receipts in the same order, which KRA dedupes on.
    log('warn', 'etims.batch_failed', {
      tenantId: params.tenantId,
      count: outstanding.length,
      message: error instanceof Error ? error.message : 'unknown',
    });
    if (error instanceof KraError && (error.kind === 'rejected' || error.kind === 'misconfigured')) {
      // A refusal applies to the batch as a whole — usually a stale clock or an
      // uninitialised device — so it is recorded against every receipt rather
      // than guessed at one.
      for (const receipt of documents.map((d) => d.receipt)) {
        await markRejected(receipt.id, error.message);
        rejected.push({ receiptNumber: receipt.receiptNumber, reason: error.message });
      }
      return { uploaded: 0, stillPending: [], rejected };
    }
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Z-report
// ---------------------------------------------------------------------------

/**
 * The taxpayer's KRA account, from the environment.
 *
 * Read per call rather than at module load so a rotated credential does not need
 * a process restart, and returned as null rather than an empty object when unset
 * — `KraCredentials` with blank fields produces a well-formed request that KRA
 * refuses, which reads as a credential problem rather than as "this deployment
 * has not been configured".
 */
export function kraCredentialsFromEnv(): KraCredentials | undefined {
  const username = process.env.KRA_USERNAME;
  const password = process.env.KRA_PASSWORD;
  if (!username || !password) return undefined;
  return { username, password };
}

/** Business date, normalised to UTC midnight so the unique key is stable. */
export function businessDateFor(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

/**
 * Builds the end-of-day report KRA requires.
 *
 * Two things are deliberate here:
 *
 *  - the totals are summed from the receipt rows that KRA has actually issued,
 *    not from the till's sales table. A Z-report that agrees with itself while
 *    disagreeing with the authority is worse than one that reports a gap;
 *  - `pendingCount` is reported *at all*. Hiding outstanding invoices would
 *    make the day's figures look complete when they are not.
 */
export async function buildZReport(params: { tenantId: string; date: Date }) {
  const businessDate = businessDateFor(params.date);
  const nextDay = new Date(businessDate.getTime() + 24 * 60 * 60 * 1000);
  const dayStart = businessDate;
  const device = await prisma.etimsDevice.findUnique({ where: { tenantId: params.tenantId } });

  const issued = await prisma.etimsReceipt.findMany({
    where: {
      tenantId: params.tenantId,
      status: 'issued',
      issuedAt: { gte: dayStart, lt: nextDay },
    },
    select: { total: true, vatTotal: true },
  });
  const outstanding = await prisma.etimsReceipt.count({
    where: {
      tenantId: params.tenantId,
      status: { in: ['pending', 'rejected'] },
      createdAt: { gte: dayStart, lt: nextDay },
    },
  });

  const totalMinor =
    issued.reduce((sum, row) => sum + fromMajor(`${row.total ?? 0}`), 0);
  const vatMinor =
    issued.reduce((sum, row) => sum + fromMajor(`${row.vatTotal ?? 0}`), 0);

  // Z-number is absolute per device, so it is the count of reports ever issued
  // plus one — never a per-day counter, which would make any day look like the
  // shop's first.
  const zNumber =
    (await prisma.etimsZReport.count({ where: { tenantId: params.tenantId } })) + 1;

  return {
    zNumber,
    businessDate,
    invoiceCount: issued.length,
    total: toMajor(totalMinor),
    vatTotal: toMajor(vatMinor),
    pendingCount: outstanding,
    deviceReady: Boolean(device && device.status === 'active'),
  };
}

/**
 * Files the Z-report with KRA and records the outcome.
 *
 * The row is upserted rather than created, so generating the same day's report
 * twice replaces it instead of producing two Z-numbers for one day — which
 * KRA's own audit trail would then show as a gap.
 */
export async function publishZReport(params: {
  tenantId: string;
  date: Date;
  credentials?: KraCredentials;
}) {
  const device = await prisma.etimsDevice.findUnique({ where: { tenantId: params.tenantId } });
  if (!device || device.status !== 'active' || !device.accessKey || !device.encryptionKey) {
    throw new KraError('misconfigured', 'This shop has no active KRA device registration');
  }

  const summary = await buildZReport(params);
  const dateText = summary.businessDate.toISOString().slice(0, 10);

  let rejectedCount = 0;
  try {
    const remote = await fetchZReport(
      {
        tin: device.tin,
        branchId: DEFAULT_BRANCH_ID,
        deviceId: device.deviceId,
        accessKey: device.accessKey,
        encryptionKey: device.encryptionKey,
        date: dateText,
      },
      { baseUrl: kraBaseUrl(), credentials: params.credentials ?? kraCredentialsFromEnv() },
    );

    return await prisma.etimsZReport.upsert({
      where: { tenantId_businessDate: { tenantId: params.tenantId, businessDate: summary.businessDate } },
      create: {
        tenantId: params.tenantId,
        deviceId: device.id,
        zNumber: remote.zNumber || summary.zNumber,
        businessDate: summary.businessDate,
        invoiceCount: summary.invoiceCount,
        total: summary.total,
        vatTotal: summary.vatTotal,
        pendingCount: summary.pendingCount,
        rejectedCount,
        status: 'issued',
      },
      update: {
        invoiceCount: summary.invoiceCount,
        total: summary.total,
        vatTotal: summary.vatTotal,
        pendingCount: summary.pendingCount,
        status: 'issued',
        failureReason: null,
      },
    });
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'Z-report failed';
    log('warn', 'etims.z_report_failed', { tenantId: params.tenantId, date: dateText, reason });

    // Recorded locally even on failure. A Z-report that was attempted and
    // failed is evidence a shop needed and did not get; silently dropping it
    // makes the absence invisible.
    rejectedCount = await prisma.etimsReceipt.count({
      where: {
        tenantId: params.tenantId,
        status: 'rejected',
        createdAt: { gte: summary.businessDate, lt: new Date(summary.businessDate.getTime() + 24 * 60 * 60 * 1000) },
      },
    });
    await prisma.etimsZReport.upsert({
      where: { tenantId_businessDate: { tenantId: params.tenantId, businessDate: summary.businessDate } },
      create: {
        tenantId: params.tenantId,
        deviceId: device.id,
        zNumber: summary.zNumber,
        businessDate: summary.businessDate,
        invoiceCount: summary.invoiceCount,
        total: summary.total,
        vatTotal: summary.vatTotal,
        pendingCount: summary.pendingCount,
        rejectedCount,
        status: 'failed',
        failureReason: reason.slice(0, 500),
      },
      update: { status: 'failed', rejectedCount, failureReason: reason.slice(0, 500) },
    });
    throw error;
  }
}
