import { Router, Request, Response } from 'express';
import { requireOwner, requireRole } from '../middleware/auth';
import { asyncHandler } from '../lib/http';
import { prisma } from '../lib/prisma';
import { log } from '../lib/observability';
import { parseBody, etimsDeviceSchema, etimsReceiptSchema } from '../lib/validation';
import { KraError } from '../services/kra';
import {
  issueReceipt,
  registerDevice,
  toMajor,
  uploadPendingBatch,
  publishZReport,
  buildZReport,
  type InvoiceInput,
  type InvoiceItemInput,
} from '../services/etims';

const router = Router();

/**
 * The only device fields this API will ever hand back.
 *
 * `access_key` and `encryption_key` sign every invoice the shop will file, and
 * they are deliberately absent. They are not filtered in the response builder —
 * they are not fetched at all, so no future edit to the response can leak them
 * by accident. Exported so a test can assert the projection rather than the
 * JSON, which is what actually has to stay true.
 */
/**
 * What the public verification page may return.
 *
 * Exactly the fields already printed on the paper the customer is holding.
 * Exported so the guarantee is testable as a value: the risk being guarded
 * against is someone widening this projection to include the tenant, the TIN or
 * the device, which would turn a customer-facing page into a shop-data leak.
 */
export const publicReceiptSelect = {
  receiptNumber: true,
  kraReceiptNumber: true,
  status: true,
  total: true,
  vatTotal: true,
  vatRatePercent: true,
  issuedAt: true,
} as const;

export const etimsDeviceStatusSelect = {
  tin: true,
  status: true,
  deviceId: true,
  deviceSerial: true,
  lastError: true,
} as const;


/**
 * The page a customer lands on when they scan the receipt's QR code.
 *
 * Public and unauthenticated on purpose: the person scanning is the customer,
 * who has no account and will never have one. Mounted *before* the auth
 * middleware — putting it on the protected router would make the QR on every
 * receipt lead to a 401 for the only person who is meant to follow it.
 *
 * It therefore reveals nothing beyond what is already printed on the paper: the
 * receipt number, the total, the VAT and whether KRA accepted it. Never the
 * shop's TIN, never device credentials, never another tenant's data.
 */
export const publicEtimsRouter = Router();

publicEtimsRouter.get('/:receiptNumber', asyncHandler(async (req: Request, res) => {
  // A KRA receipt number, not the till's own. The till's number is only unique
  // within a shop — "T1-000001" is a number several shops reach independently —
  // so resolving on it with no tenant filter would let one shop's customer read
  // another's totals. KRA receipt numbers are globally unique, and the schema
  // carries a unique index on them so this lookup is deterministic.
  const kraReceiptNumber = String(req.params.receiptNumber ?? '').slice(0, 64);
  if (!kraReceiptNumber) return res.status(400).json({ error: 'Receipt number required' });

  const receipt = await prisma.etimsReceipt.findFirst({
    where: { kraReceiptNumber },
    select: publicReceiptSelect,
    // No tenant filter, and nothing beyond what is printed on the paper. Safe
    // because the key is globally unique and the projection is exactly the
    // fields the customer can already read off the receipt in their hand.
  });

  if (!receipt) return res.status(404).json({ error: 'No such receipt' });
  res.json({
    receipt_number: receipt.receiptNumber,
    kra_receipt_number: receipt.kraReceiptNumber,
    status: receipt.status,
    total: receipt.total.toString(),
    vat_total: receipt.vatTotal.toString(),
    vat_rate_percent: receipt.vatRatePercent,
    issued_at: receipt.issuedAt?.toISOString() ?? null,
    verified: receipt.status === 'issued' && Boolean(receipt.kraReceiptNumber),
  });
}));

/**
 * Registers this shop's device with KRA.
 *
 * Owner-only. Registration mints the signing keys every invoice from this shop
 * is signed with, so it is a shop-administration action and not something a
 * cashier can trigger.
 */
router.post('/device', requireOwner, asyncHandler(async (req: Request, res) => {
  const { tin, device_id, device_name } = parseBody(etimsDeviceSchema, req.body);
  const tenant = await prisma.tenant.findUnique({
    where: { id: req.user!.tenantId },
    select: { shopName: true },
  });
  if (!tenant) return res.status(404).json({ error: 'Shop not found' });

  const device = await registerDevice({
    tenantId: req.user!.tenantId,
    shopName: tenant.shopName,
    tin: tin.toUpperCase(),
    deviceId: device_id,
    deviceName: device_name,
  });

  // Never the keys. They sign every invoice this shop will ever file; a
  // response body is not a place to put a signing key.
  res.status(201).json({
    registered: device.status === 'active',
    status: device.status,
    tin: device.tin,
    device_id: device.deviceId,
    device_serial: device.deviceSerial,
    initialised_at: device.initialisedAt?.toISOString() ?? null,
    ...(device.lastError ? { error: device.lastError } : {}),
  });
}));

/**
 * Issues a KRA receipt for one recorded sale.
 *
 * Cashiers may call this: filing the tax invoice for a sale they just made is
 * part of making the sale, not an administrative act. The tenant's own
 * `etims_enabled` flag is honoured, so a shop that has not opted in can never
 * have an invoice filed in its name by mistake.
 */
router.post('/receipts', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res) => {
  const body = parseBody(etimsReceiptSchema, req.body);
  const tenantId = req.user!.tenantId;

  const tenant = await prisma.tenant.findUnique({
    where: { id: tenantId },
    select: { etimsEnabled: true },
  });
  if (!tenant?.etimsEnabled) {
    return res.status(409).json({ error: 'eTIMS is not switched on for this shop' });
  }

  const input: InvoiceInput = {
    receiptNumber: body.receipt_number,
    issuedAt: body.issued_at,
    paymentMethod: body.payment_method,
    ...(body.payment_reference ? { paymentReference: body.payment_reference } : {}),
    total: body.total,
    vatRatePercent: body.vat_rate_percent,
    items: body.items.map(
      (item): InvoiceItemInput => ({
        name: item.name,
        qty: item.qty,
        unitPrice: item.unit_price,
        unitCost: item.unit_cost,
        portion: item.portion,
        portionMl: item.portion_ml,
        vatAmount: item.vat_amount,
        lineTotal: item.line_total,
      }),
    ),
  };

  const outcome = await issueReceipt({ tenantId, deviceId: body.device_id ?? null, input });

  switch (outcome.status) {
    case 'issued':
      return res.status(201).json({
        status: 'issued',
        kra_receipt_number: outcome.receiptNumber,
        verification_url: verificationUrl(outcome.receiptNumber),
        // The exact string for the receipt's QR code. KRA's verification page
        // expects specific parameters, so the till encodes this rather than
        // building a URL of its own.
        qr_payload: outcome.qrPayload ?? verificationUrl(outcome.receiptNumber),
      });
    case 'already_issued':
      return res.status(200).json({
        status: 'issued',
        kra_receipt_number: outcome.receiptNumber,
        verification_url: verificationUrl(outcome.receiptNumber),
        qr_payload: outcome.qrPayload ?? verificationUrl(outcome.receiptNumber),
      });
    case 'rejected':
      // 422: the payload is well-formed and the request authenticated, but KRA
      // refused the content. A retry would be refused identically, so the till
      // must be told rather than left looping.
      return res.status(422).json({ error: outcome.reason, status: 'rejected' });
    case 'pending':
    default:
      // 202: accepted for later. The sale is committed on the till and stays
      // there; this only says the invoice has not been issued yet.
      return res.status(202).json({
        status: 'pending',
        message: 'KRA has not issued this receipt yet. It will be retried on the next upload.',
      });
  }
}));

/** Uploads every outstanding receipt for the shop, oldest first. */
router.post('/upload', requireRole('admin', 'manager'), asyncHandler(async (req: Request, res) => {
  const limit = Number(req.query.limit ?? 100);
  const result = await uploadPendingBatch({
    tenantId: req.user!.tenantId,
    limit: Number.isFinite(limit) ? Math.min(Math.max(limit, 1), 500) : 100,
  });
  res.json(result);
}));

/** How much is outstanding, for the settings screen. */
router.get('/status', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res) => {
  const tenantId = req.user!.tenantId;
  const [device, pending, rejected, issued] = await Promise.all([
    prisma.etimsDevice.findUnique({ where: { tenantId }, select: etimsDeviceStatusSelect }),
    prisma.etimsReceipt.count({ where: { tenantId, status: 'pending' } }),
    prisma.etimsReceipt.count({ where: { tenantId, status: 'rejected' } }),
    prisma.etimsReceipt.count({ where: { tenantId, status: 'issued' } }),
  ]);

  res.json({
    configured: device?.status === 'active',
    device_status: device?.status ?? 'unregistered',
    tin: device?.tin ?? null,
    device_id: device?.deviceId ?? null,
    device_serial: device?.deviceSerial ?? null,
    pending_upload: pending,
    rejected,
    issued,
    ...(device?.lastError ? { error: device.lastError } : {}),
  });
}));

/**
 * The Z-report for a business date.
 *
 * Generated server-side because it has to reconcile against the receipts KRA
 * has actually accepted, which the till cannot know: the till can see what it
 * recorded, not what was issued.
 */
router.get('/z-report', requireRole('admin', 'manager'), asyncHandler(async (req: Request, res) => {
  const raw = typeof req.query.date === 'string' ? req.query.date : new Date().toISOString().slice(0, 10);
  const parsed = new Date(`${raw}T00:00:00.000Z`);
  if (!Number.isFinite(parsed.getTime())) {
    return res.status(400).json({ error: 'Invalid report date' });
  }

  const summary = await buildZReport({ tenantId: req.user!.tenantId, date: parsed });

  res.json({
    z_number: summary.zNumber,
    business_date: summary.businessDate.toISOString().slice(0, 10),
    invoice_count: summary.invoiceCount,
    total: summary.total,
    vat_total: summary.vatTotal,
    pending_count: summary.pendingCount,
    device_ready: summary.deviceReady,
  });
}));

/** Files today's Z-report with KRA. Explicit: publishing is not automatic. */
router.post('/z-report', requireOwner, asyncHandler(async (req: Request, res) => {
  const raw = typeof req.body?.date === 'string' ? req.body.date : new Date().toISOString().slice(0, 10);
  const parsed = new Date(`${raw}T00:00:00.000Z`);
  if (!Number.isFinite(parsed.getTime())) {
    return res.status(400).json({ error: 'Invalid report date' });
  }

  try {
    const report = await publishZReport({ tenantId: req.user!.tenantId, date: parsed });
    res.json({
      z_number: report.zNumber,
      business_date: report.businessDate.toISOString().slice(0, 10),
      invoice_count: report.invoiceCount,
      total: report.total.toString(),
      vat_total: report.vatTotal.toString(),
      pending_count: report.pendingCount,
      status: report.status,
    });
  } catch (error) {
    if (error instanceof KraError) {
      log('warn', 'etims.z_report_failed', { tenantId: req.user!.tenantId, kind: error.kind });
      return res.status(error.kind === 'misconfigured' ? 409 : 502).json({
        error: error.message,
        kind: error.kind,
      });
    }
    throw error;
  }
}));

/** A receipt this shop filed, looked up by its till receipt number. */
router.get('/receipts/:receiptNumber', requireRole('admin', 'manager'), asyncHandler(async (req: Request, res) => {
  const receipt = await prisma.etimsReceipt.findFirst({
    where: { tenantId: req.user!.tenantId, receiptNumber: String(req.params.receiptNumber) },
  });
  if (!receipt) return res.status(404).json({ error: 'Receipt not found' });
  res.json({
    receipt_number: receipt.receiptNumber,
    kra_receipt_number: receipt.kraReceiptNumber,
    status: receipt.status,
    total: toMajor(Number(receipt.total) * 100),
    vat_total: toMajor(Number(receipt.vatTotal) * 100),
    vat_rate_percent: receipt.vatRatePercent,
    issued_at: receipt.issuedAt?.toISOString() ?? null,
    ...(receipt.rejectionReason ? { error: receipt.rejectionReason } : {}),
  });
}));

/** The public verification URL for a KRA receipt number. */
function verificationUrl(kraReceiptNumber: string): string {
  const base = process.env.PUBLIC_API_URL?.replace(/\/$/, '') ?? '';
  return base ? `${base}/api/etims/verify/${encodeURIComponent(kraReceiptNumber)}` : '';
}

export default router;