/**
 * eTIMS (KRA tax compliance) routes.
 * Uses PostgreSQL/Prisma for persistent storage.
 */
import { Router } from 'express';
import { asyncHandler } from '../lib/http';
import { parseBody } from '../lib/validation';
import { etimsReceiptSchema, etimsDeviceSchema } from '../lib/validation';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';

import { log } from '../lib/observability';
import { buildRisitiInvoiceRequest, RisitiError, submissionOutcome, submitInvoice } from '../services/risiti';
import { TAX_REPORTING_PROVIDER, TAX_PROVIDER_DISPLAY_NAME, taxReportingActivated, taxReportingStatus } from '../services/tax_reporting';

const taxProvider = TAX_REPORTING_PROVIDER;

/**
 * What GET /etims/status answers with.
 *
 * `accessKey` and `encryptionKey` sign every invoice the shop will ever file,
 * so they are NOT FETCHED rather than filtered on the way out — no future edit
 * to the response body can then leak them by accident.
 */
export const etimsDeviceStatusSelect = {
  tin: true,
  deviceId: true,
  deviceName: true,
  status: true,
  registeredAt: true,
} as const;

/**
 * What the public verification page (GET /etims/verify/:number) answers with.
 *
 * No tenant, no device, no payload: the person following the QR is the
 * customer, so the page may return only what is already printed on the paper
 * in their hand.
 */
export const publicReceiptSelect = {
  kraReceiptNumber: true,
  issuedAt: true,
  status: true,
  total: true,
  vatTotal: true,
  itemCount: true,
  paymentMethod: true,
} as const;

const router = Router();

// GET /etims/verify/:number — the public page behind a receipt's QR code.
//
// No auth: the person following the QR is the customer, not the shop. It
// returns ONLY what is already printed on the paper in their hand — the
// projected fields in `publicReceiptSelect` — because a shop's database row
// is not something a receipt number is entitled to read.
router.get(
  '/verify/:number',
  asyncHandler(async (req, res): Promise<void> => {
    const number = String(req.params.number ?? '').trim();
    if (number === '') {
      res.status(400).json({ error: 'A receipt number is required' });
      return;
    }
    const receipt = await prisma.etimsReceipt.findFirst({
      where: { OR: [{ kraReceiptNumber: number }, { receiptNumber: number }] },
      select: { ...publicReceiptSelect },
    });
    if (!receipt) {
      res.status(404).json({ error: 'No such receipt' });
      return;
    }
    res.json({ status: receipt.status, receipt });
  }),
);


router.post(
  '/device',
  asyncHandler(async (req, res) => {
    if (!taxReportingActivated()) {
      return res.status(409).json({
        error: 'Tax reporting is not activated for this deployment',
        provider: taxProvider,
        provider_name: TAX_PROVIDER_DISPLAY_NAME,
        kra_activated: false,
      });
    }
    const { tin, deviceId, deviceName } = parseBody(etimsDeviceSchema, req.body);
    const tenantId = req.user?.tenantId;
    if (!tenantId) return res.status(403).json({ error: 'Tenant selection required' });

    const device = await prisma.etimsDevice.upsert({
      where: { deviceId },
      update: { tin, deviceName },
      create: { tenantId, tin, deviceId, deviceName },
    });
    log('info', 'etims.device_registered', { tin, deviceId, deviceName });
    return res.json({ tin: device.tin, device_id: device.deviceId, device_name: device.deviceName, registered: true });
  })
);

router.post(
  '/receipts',
  asyncHandler(async (req, res) => {
    const { deviceId, ...payload } = parseBody(etimsReceiptSchema, req.body);
    const tenantId = req.user?.tenantId;
    if (!tenantId) return res.status(403).json({ error: 'Tenant selection required' });

    if (deviceId) {
      const device = await prisma.etimsDevice.findUnique({ where: { deviceId } });
      if (!device) return res.status(400).json({ error: 'eTIMS device not registered' });
    }

    const tenant = await prisma.tenant.findUnique({ where: { id: tenantId } });
    if (!taxReportingActivated() || !tenant?.etimsEnabled) {
      return res.status(409).json({
        error: 'Tax reporting is not activated for this shop',
        provider: taxProvider,
        provider_name: TAX_PROVIDER_DISPLAY_NAME,
        kra_activated: false,
      });
    }

    if (tenant.taxProvider !== 'risiti' || !tenant.risitiMerchantId) {
      return res.status(409).json({
        error: 'Risiti merchant onboarding is incomplete',
        provider: tenant.taxProvider,
        provider_name: TAX_PROVIDER_DISPLAY_NAME,
        kra_activated: false,
      });
    }

    const input = payload as unknown as {
      receipt_number: string;
      issued_at: string;
      payment_method: string;
      items: Array<{ name: string; qty: number; unit_price: number; vat_amount: number; line_total: number }>;
      buyer_name?: string;
      buyer_tin?: string;
    };
    const prior = await prisma.etimsReceipt.findUnique({
      where: { tenantId_receiptNumber: { tenantId, receiptNumber: input.receipt_number } },
    });
    if (prior?.status === 'issued' && prior.kraReceiptNumber) {
      return res.json({
        status: 'issued',
        kra_receipt_number: prior.kraReceiptNumber,
        verification_url: prior.verificationUrl,
        qr_payload: prior.qrPayload,
        duplicate: true,
      });
    }
    let risiti: Awaited<ReturnType<typeof submitInvoice>>;
    try {
      risiti = await submitInvoice(buildRisitiInvoiceRequest({
        tenantId,
        merchantId: tenant.risitiMerchantId,
        receiptNumber: input.receipt_number,
        issuedAt: input.issued_at,
        paymentMethod: input.payment_method,
        items: input.items.map((item) => ({
          name: item.name,
          qty: item.qty,
          unitPrice: item.unit_price,
          vatAmount: item.vat_amount,
          lineTotal: item.line_total,
        })),
        buyerName: input.buyer_name,
        buyerTin: input.buyer_tin,
      }));
    } catch (error) {
      if (error instanceof RisitiError && error.kind === 'misconfigured') {
        return res.status(409).json({
          error: 'Risiti is not configured for this deployment',
          provider: taxProvider,
          provider_name: TAX_PROVIDER_DISPLAY_NAME,
          kra_activated: false,
        });
      }
      throw error;
    }
    const outcome = submissionOutcome(risiti.data.submission);
    const status = outcome === 'issued' ? 'issued' : outcome === 'pending' ? 'pending' : 'rejected';
    const receipt = await prisma.etimsReceipt.upsert({
      where: { tenantId_receiptNumber: { tenantId, receiptNumber: input.receipt_number } },
      update: {
        status,
        payload: payload as Prisma.InputJsonValue,
        kraReceiptNumber: risiti.data.kra_receipt_number ?? null,
        verificationUrl: risiti.data.risiti_url ?? null,
        qrPayload: risiti.data.qr_code_data ?? null,
        issuedAt: status === 'issued' ? new Date() : null,
        rejectionReason: status === 'rejected' ? risiti.data.submission?.message ?? 'Risiti requires action' : null,
      },
      create: {
        tenantId,
        receiptNumber: input.receipt_number,
        status,
        payload: payload as Prisma.InputJsonValue,
        kraReceiptNumber: risiti.data.kra_receipt_number ?? null,
        verificationUrl: risiti.data.risiti_url ?? null,
        qrPayload: risiti.data.qr_code_data ?? null,
        issuedAt: status === 'issued' ? new Date() : null,
        rejectionReason: status === 'rejected' ? risiti.data.submission?.message ?? 'Risiti requires action' : null,
        deviceId,
      },
    });
    log('info', 'etims.risiti_submitted', {
      tenantId,
      receiptNumber: input.receipt_number,
      risitiInvoiceId: risiti.data.invoice_id,
      requestId: risiti.requestId,
      status,
    });
    return res.status(status === 'pending' ? 202 : 200).json({
      status,
      kra_receipt_number: receipt.kraReceiptNumber,
      verification_url: receipt.verificationUrl,
      qr_payload: receipt.qrPayload,
      risiti_invoice_id: risiti.data.invoice_id,
      request_id: risiti.requestId,
      submission: risiti.data.submission,
    });
  })
);

router.get(
  '/status',
  asyncHandler(async (req, res) => {
    const tenantId = req.user?.tenantId;
    if (!tenantId) return res.status(403).json({ error: 'Tenant selection required' });

    const tenant = await prisma.tenant.findUnique({ where: { id: tenantId } });
    const tenantReceipts = await prisma.etimsReceipt.findMany({ where: { tenantId } });
    const pending = tenantReceipts.filter((r) => r.status === 'pending').length;
    const rejected = tenantReceipts.filter((r) => r.status === 'rejected').length;
    return res.json({
      ...taxReportingStatus(),
      configured: Boolean(tenant?.etimsEnabled && taxReportingActivated()),
      activation_status: taxReportingActivated() ? 'activated' : 'not_activated',
      message: taxReportingActivated()
        ? 'Tax reporting is ready through the configured provider.'
        : 'KRA eTIMS is not activated. Sales and VAT reports remain available locally.',
      pending_upload: pending,
      rejected,
      device_status: tenant?.etimsEnabled && taxReportingActivated() ? 'ACTIVE' : 'NOT_ACTIVATED',
      tin: tenant?.tin ?? null,
    });
  })
);

router.get(
  '/z-report',
  asyncHandler(async (req, res) => {
    const tenantId = req.user?.tenantId;
    if (!tenantId) return res.status(403).json({ error: 'Tenant selection required' });

    const dateParam = typeof req.query.date === 'string' ? req.query.date : undefined;
    const targetDate = dateParam ? new Date(dateParam) : new Date();
    if (!Number.isFinite(targetDate.getTime())) return res.status(400).json({ error: 'Invalid date' });

    const start = new Date(targetDate); start.setHours(0, 0, 0, 0);
    const end = new Date(targetDate); end.setHours(23, 59, 59, 999);

    const sales = await prisma.sale.findMany({
      where: { tenantId, createdAt: { gte: start, lte: end }, paymentMethod: 'mpesa' },
      select: { id: true, total: true, profit: true, staffName: true, createdAt: true, paymentReference: true },
      orderBy: { createdAt: 'asc' },
    });

    let totalSales = 0, totalProfit = 0, receiptCount = 0;
    for (const sale of sales) {
      totalSales += Number(sale.total ?? 0);
      totalProfit += Number(sale.profit ?? 0);
      receiptCount += 1;
    }
    return res.json({
      date: targetDate.toISOString().slice(0, 10),
      tenantId,
      receiptCount,
      totalSales,
      totalProfit,
      sales,
    });
  })
);

export default router;
