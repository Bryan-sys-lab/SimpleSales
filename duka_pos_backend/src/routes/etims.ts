/**
 * eTIMS (KRA tax compliance) routes.
 * Uses PostgreSQL/Prisma for persistent storage.
 */
import { Router } from 'express';
import { asyncHandler } from '../lib/http';
import { parseBody } from '../lib/validation';
import { etimsReceiptSchema, etimsDeviceSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { log } from '../lib/observability';

const router = Router();

function generateReceiptNumber(): string {
  return `KRA-${Date.now().toString(36)}-${crypto.randomBytes(4).toString('hex')}`;
}

router.post(
  '/device',
  asyncHandler(async (req, res) => {
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
    if (!tenant?.etimsEnabled) return res.status(409).json({ error: 'eTIMS is not enabled for this shop' });

    const kraReceiptNumber = generateReceiptNumber();
    const receipt = await prisma.etimsReceipt.create({
      data: {
        tenantId,
        kraReceiptNumber,
        verificationUrl: `https://etims.kra.go.ke/verify/${kraReceiptNumber}`,
        qrPayload: `KRA|${kraReceiptNumber}|${tenantId}`,
        status: 'ISSUED',
        payload,
        deviceId,
      },
    });
    log('info', 'etims.receipt_issued', { tenantId, kraReceiptNumber, deviceId });
    return res.json({
      kra_receipt_number: receipt.kraReceiptNumber,
      verification_url: receipt.verificationUrl,
      qr_payload: receipt.qrPayload,
      status: receipt.status,
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
    const pending = tenantReceipts.filter((r) => r.status === 'ISSUED').length;
    const rejected = tenantReceipts.filter((r) => r.status === 'REJECTED').length;
    return res.json({
      configured: !!tenant?.etimsEnabled,
      pending_upload: pending,
      rejected,
      device_status: tenant?.etimsEnabled ? 'ACTIVE' : 'NOT_CONFIGURED',
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
