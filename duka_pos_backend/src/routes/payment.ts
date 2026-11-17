import { Router, Request, Response } from 'express';
import { randomUUID } from 'node:crypto';
import { prisma } from '../lib/prisma';
import { asyncHandler, HttpError } from '../lib/http';
import { parseBody, paymentQrSchema, paymentSchema } from '../lib/validation';
import { generateDynamicQr, SafaricomQrError } from '../services/safaricom_qr';
import { initiateStkPush, PayHeroError, queryTransactionStatus } from '../services/payhero';
import { finalizeSale } from './payhero-callback';
import { requireRole } from '../middleware/auth';
import { log } from '../lib/observability';

const router = Router();

type PaymentInput = {
  items: Array<{ product_id: string; qty: number; portion: 'full' | 'half' | 'quarter' }>;
  phone_number?: string;
  staff_name: string;
  staff_profile_id?: string;
  customer_name?: string;
};

async function createPaymentDraft(input: PaymentInput, user: NonNullable<Request['user']>, paymentMode: 'stk' | 'qr') {
  const ids = [...new Set(input.items.map((item) => item.product_id))];
  const products = await prisma.product.findMany({ where: { tenantId: user.tenantId, id: { in: ids }, active: true } });
  const byId = new Map(products.map((product) => [product.id, product]));
  if (products.length !== ids.length) throw new HttpError(400, 'One or more products are unavailable');
  const stockRequested = new Map<string, number>();
  for (const item of input.items) {
    const factor = item.portion === 'half' ? 0.5 : item.portion === 'quarter' ? 0.25 : 1;
    stockRequested.set(item.product_id, (stockRequested.get(item.product_id) ?? 0) + item.qty * factor);
  }
  for (const [productId, requested] of stockRequested) {
    const product = byId.get(productId)!;
    if (Number(product.stockQty) < requested) throw new HttpError(409, `Insufficient stock for ${product.name}`);
  }
  const cartSnapshot = input.items.map((item) => {
    const product = byId.get(item.product_id)!;
    const factor = item.portion === 'half' ? 0.5 : item.portion === 'quarter' ? 0.25 : 1;
    const unitPrice = item.portion === 'half' ? Number(product.halfPrice ?? Number(product.sellPrice) / 2)
      : item.portion === 'quarter' ? Number(product.quarterPrice ?? Number(product.sellPrice) / 4) : Number(product.sellPrice);
    return { product_id: product.id, product_name: product.name, qty: item.qty, portion: item.portion, portion_ml: Math.round(product.bottleMl * factor), stock_units: item.qty * factor, unit_price: unitPrice, unit_cost: Number(product.costPrice) * factor };
  });
  const amount = cartSnapshot.reduce((sum, item) => sum + item.qty * item.unit_price, 0);
  const tenant = await prisma.tenant.findUnique({ where: { id: user.tenantId } });
  if (!tenant?.mpesaEnabled || !tenant.payheroChannelId) throw new HttpError(409, 'M-Pesa is not configured for this shop');
  if (paymentMode === 'stk' && !process.env.PUBLIC_API_URL) throw new HttpError(503, 'Payment service is not configured');
  let initiatedBy = user.id;
  if (input.staff_profile_id) {
    const cashier = await prisma.profile.findFirst({
      where: { id: input.staff_profile_id, tenantId: user.tenantId, role: { in: ['cashier', 'manager'] }, active: true },
    });
    if (!cashier) throw new HttpError(403, 'Cashier profile is not active');
    if (user.role === 'cashier' && cashier.id !== user.id) throw new HttpError(403, 'A cashier may only record sales under their own profile');
    initiatedBy = cashier.id;
  }
  const cashierProfile = await prisma.profile.findFirst({ where: { id: initiatedBy, tenantId: user.tenantId, active: true } });
  if (!cashierProfile) throw new HttpError(403, 'Cashier profile is not active');
  const reference = `DUKA-${randomUUID()}`;
  const payment = await prisma.payment.create({ data: { tenantId: user.tenantId, initiatedBy, staffName: cashierProfile.name, reference, phoneNumber: input.phone_number ?? 'QR', amount, cartSnapshot, status: 'QUEUED', paymentMode } });
  return { tenant, payment, reference, amount };
}

router.post('/initiate', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(paymentSchema, req.body);
  const user = req.user!;
  const draft = await createPaymentDraft(input, user, 'stk');
  const { tenant, payment, reference, amount } = draft;
  try {
    const push = await initiateStkPush({ amount, phoneNumber: input.phone_number, channelId: tenant.payheroChannelId!, externalReference: reference, customerName: input.customer_name, callbackUrl: `${process.env.PUBLIC_API_URL}/webhooks/payhero-callback`, credentialId: tenant.payheroCredentialId ?? undefined });
    await prisma.payment.update({ where: { id: payment.id }, data: { status: 'PENDING', checkoutRequestId: push.checkoutRequestId } });
    return res.status(201).json({ reference, amount });
  } catch (error) {
    // A timeout or transport failure is ambiguous: PayHero may have accepted
    // the STK request even though this process did not receive its response.
    // Keep the durable payment pending so callback/status reconciliation can
    // settle it, and never encourage a duplicate STK push.
    const providerStatusCode = error instanceof PayHeroError ? error.statusCode : undefined;
    const providerResponseIsAmbiguous = error instanceof PayHeroError && (
      providerStatusCode === undefined || providerStatusCode === 408 || providerStatusCode === 425 ||
      providerStatusCode === 429 || providerStatusCode >= 500
    );
    if (providerResponseIsAmbiguous) {
      return res.status(202).json({ reference, amount, status: 'QUEUED', reconciliation_pending: true });
    }
    await prisma.payment.update({ where: { id: payment.id }, data: { status: 'FAILED' } });
    throw error;
  }
}));

router.post('/qr', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(paymentQrSchema, req.body);
  const user = req.user!;
  const { tenant, payment, reference, amount } = await createPaymentDraft(input, user, 'qr');
  if (!tenant.mpesaQrCpi || !tenant.mpesaQrTrxCode || !['BG', 'PB'].includes(tenant.mpesaQrTrxCode)) {
    await prisma.payment.update({ where: { id: payment.id }, data: { status: 'FAILED' } });
    return res.status(409).json({ error: 'Dynamic QR is not configured for this shop till or paybill' });
  }
  try {
    const qr = await generateDynamicQr({
      merchantName: tenant.shopName,
      reference,
      amount,
      transactionCode: tenant.mpesaQrTrxCode as 'BG' | 'PB',
      creditPartyIdentifier: tenant.mpesaQrCpi,
    });
    await prisma.payment.update({
      where: { id: payment.id },
      data: { status: 'PENDING', qrCodeData: qr.qrCode },
    });
    return res.status(201).json({
      reference,
      amount,
      status: 'PENDING',
      qr_code: qr.qrCode,
      request_id: qr.requestId,
    });
  } catch (error) {
    await prisma.payment.update({ where: { id: payment.id }, data: { status: 'FAILED' } });
    if (error instanceof SafaricomQrError) {
      return res.status(error.kind === 'misconfigured' ? 409 : error.kind === 'network' ? 503 : 502).json({
        error: error.message,
        provider: 'safaricom_dynamic_qr',
      });
    }
    throw error;
  }
}));

router.get('/status', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const reference = typeof req.query.reference === 'string' ? req.query.reference : '';
  if (!reference || reference.length > 80) return res.status(400).json({ error: 'reference required' });
  const payment = await prisma.payment.findFirst({ where: { reference, tenantId: req.user!.tenantId } });
  if (!payment) return res.status(404).json({ error: 'Payment not found' });
  if ((payment.status === 'PENDING' || payment.status === 'QUEUED') && payment.paymentMode !== 'qr') {
    try {
      // Persist the provider check time so multiple tills/processes cannot
      // turn the client poll loop into a request per poll.
      const now = Date.now();
      const checkedAt = payment.providerCheckedAt?.getTime() ?? 0;
      const canRefresh = now - checkedAt >= 10_000;
      let remote: Awaited<ReturnType<typeof queryTransactionStatus>> | null = null;
      if (canRefresh) {
        const claimed = await prisma.payment.updateMany({
          where: {
            id: payment.id,
            status: { in: ['PENDING', 'QUEUED'] },
            OR: [{ providerCheckedAt: null }, { providerCheckedAt: { lt: new Date(now - 10_000) } }],
          },
          data: { providerCheckedAt: new Date(now) },
        });
        if (claimed.count === 1) {
          remote = await queryTransactionStatus(reference);
          await prisma.payment.update({
            where: { id: payment.id },
            data: { providerStatus: typeof remote?.status === 'string' ? remote.status : null },
          });
        }
      }
      if (remote?.status === 'SUCCESS') {
        await finalizeSale(payment.id);
      } else if (remote?.status === 'FAILED') {
        await prisma.payment.update({ where: { id: payment.id }, data: { status: 'FAILED' } });
      }
    } catch (error) {
      log('warn', 'payment.status_refresh_failed', { requestId: req.requestId, paymentId: payment.id, message: error instanceof Error ? error.message : 'unknown' });
    }
  }
  const refreshed = await prisma.payment.findUnique({ where: { id: payment.id } });
  return res.json({ reference, status: refreshed?.status ?? payment.status, saleId: refreshed?.saleId ?? payment.saleId });
}));

export default router;
