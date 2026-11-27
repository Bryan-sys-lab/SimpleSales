import { Router, Request, Response } from 'express';
import { randomUUID } from 'node:crypto';
import { prisma } from '../lib/prisma';
import { asyncHandler, HttpError } from '../lib/http';
import { parseBody, paymentQrSchema, paymentSchema } from '../lib/validation';
import { generateDynamicQr, SafaricomQrError } from '../services/safaricom_qr';
import { initiateStkPush, PayHeroError, payHeroCallbackUrl, payHeroSettlementContractConfirmed, queryTransactionStatus } from '../services/payhero';
import { requireRole } from '../middleware/auth';
import { log } from '../lib/observability';
import { toMajorUnits, toMinorUnits, wholeShillingsFromMinor } from '../lib/money';

const router = Router();

type PaymentInput = {
  items: Array<{ product_id: string; qty: number; portion: 'full' | 'half' | 'quarter' }>;
  phone_number?: string;
  staff_name: string;
  staff_profile_id?: string;
  customer_name?: string;
  operation_id?: string;
};

async function createPaymentDraft(input: PaymentInput, user: NonNullable<Request['user']>, paymentMode: 'stk' | 'qr') {
  if (input.operation_id) {
    const existing = await prisma.payment.findFirst({
      where: { operationId: input.operation_id, tenantId: user.tenantId },
    });
    if (existing) {
      return {
        tenant: await prisma.tenant.findUnique({ where: { id: user.tenantId } }),
        payment: existing,
        reference: existing.reference,
        amount: Number(existing.amount),
        existing: true,
      };
    }
  }
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
    const rawUnitPrice = item.portion === 'half' ? Number(product.halfPrice ?? Number(product.sellPrice) / 2)
      : item.portion === 'quarter' ? Number(product.quarterPrice ?? Number(product.sellPrice) / 4) : Number(product.sellPrice);
    let unitPriceMinor: number;
    let unitCostMinor: number;
    try {
      unitPriceMinor = toMinorUnits(rawUnitPrice);
      unitCostMinor = toMinorUnits(Number(product.costPrice) * factor);
    } catch {
      throw new HttpError(422, 'Product prices must use no more than two decimal places for M-Pesa');
    }
    return { product_id: product.id, product_name: product.name, qty: item.qty, portion: item.portion, portion_ml: Math.round(product.bottleMl * factor), stock_units: item.qty * factor, unit_price: toMajorUnits(unitPriceMinor), unit_cost: toMajorUnits(unitCostMinor) };
  });
  const amountMinor = cartSnapshot.reduce((sum, item) => {
    const lineMinor = item.qty * toMinorUnits(item.unit_price);
    if (!Number.isSafeInteger(lineMinor)) {
      throw new HttpError(422, 'M-Pesa quantity does not produce an exact currency amount');
    }
    return sum + lineMinor;
  }, 0);
  let amount: number;
  try {
    amount = wholeShillingsFromMinor(amountMinor);
  } catch {
    throw new HttpError(422, 'M-Pesa requires a positive whole-shilling total');
  }
  const tenant = await prisma.tenant.findUnique({ where: { id: user.tenantId } });
  if (!tenant?.mpesaEnabled || !tenant.payheroChannelId) throw new HttpError(409, 'M-Pesa is not configured for this shop');
  if (paymentMode === 'stk' && !process.env.PUBLIC_API_URL) throw new HttpError(503, 'Payment service is not configured');
  let initiatedBy = user.id;
  if (input.staff_profile_id) {
    const cashier = await prisma.profile.findFirst({
      where: {
        id: input.staff_profile_id,
        tenantId: user.tenantId,
        active: true,
        OR: [
          { role: { in: ['cashier', 'manager'] } },
          { role: 'admin', userId: null, localId: { not: null } },
        ],
      },
    });
    if (!cashier) throw new HttpError(403, 'Cashier profile is not active');
    if (user.role === 'cashier' && cashier.id !== user.id) throw new HttpError(403, 'A cashier may only record sales under their own profile');
    initiatedBy = cashier.id;
  }
  const cashierProfile = await prisma.profile.findFirst({ where: { id: initiatedBy, tenantId: user.tenantId, active: true } });
  if (!cashierProfile) throw new HttpError(403, 'Cashier profile is not active');
  const reference = input.operation_id?.startsWith('DUKA-')
    ? input.operation_id
    : `DUKA-${randomUUID()}`;
  const payment = await prisma.payment.create({ data: { tenantId: user.tenantId, operationId: input.operation_id, initiatedBy, staffName: cashierProfile.name, reference, phoneNumber: input.phone_number ?? 'QR', amount, cartSnapshot, status: 'QUEUED', paymentMode } });
  return { tenant, payment, reference, amount };
}

router.post('/initiate', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  if (!payHeroSettlementContractConfirmed()) {
    throw new HttpError(503, 'PayHero collection is disabled pending provider confirmation of merchant settlement and amount verification');
  }
  const callbackUrl = payHeroCallbackUrl();
  const input = parseBody(paymentSchema, req.body);
  const user = req.user!;
  const draft = await createPaymentDraft(input, user, 'stk');
  const { tenant, payment, reference, amount } = draft;
  if ('existing' in draft && draft.existing) {
    return res.status(200).json({ reference, amount, status: payment.status, saleId: payment.saleId });
  }
  if (!tenant?.payheroChannelId) {
    throw new HttpError(409, 'M-Pesa is not configured for this shop');
  }
  try {
    const push = await initiateStkPush({ amount, phoneNumber: input.phone_number, channelId: tenant.payheroChannelId!, externalReference: reference, customerName: input.customer_name, callbackUrl, credentialId: tenant.payheroCredentialId ?? undefined });
    await prisma.payment.update({ where: { id: payment.id }, data: { status: 'PENDING', providerReference: push.providerReference, checkoutRequestId: push.checkoutRequestId } });
    return res.status(201).json({ reference, amount });
  } catch (error) {
    // A timeout or transport failure is ambiguous: PayHero may have accepted
    // the STK request even though this process did not receive its response.
    // Keep the durable payment pending so callback/status reconciliation can
    // settle it, and never encourage a duplicate STK push.
    const providerResponseIsAmbiguous = !(error instanceof PayHeroError) || error.outcomeAmbiguous;
    if (providerResponseIsAmbiguous) {
      try {
        await prisma.payment.update({
          where: { id: payment.id },
          data: { status: 'REQUIRES_REVIEW', providerStatus: 'INITIATION_OUTCOME_UNKNOWN' },
        });
      } catch (persistenceError) {
        log('error', 'payment.ambiguous_initiation_not_persisted', {
          requestId: req.requestId,
          paymentId: payment.id,
          message: persistenceError instanceof Error ? persistenceError.message : 'unknown',
        });
      }
      return res.status(202).json({ reference, amount, status: 'REQUIRES_REVIEW', reconciliation_pending: true });
    }
    if (error instanceof PayHeroError) {
      await prisma.payment.update({ where: { id: payment.id }, data: { status: 'FAILED' } });
    } else {
      try {
        await prisma.payment.update({ where: { id: payment.id }, data: { status: 'REQUIRES_REVIEW', providerStatus: 'INITIATION_OUTCOME_UNKNOWN' } });
      } catch (persistenceError) {
        log('error', 'payment.ambiguous_initiation_not_persisted', {
          requestId: req.requestId,
          paymentId: payment.id,
          message: persistenceError instanceof Error ? persistenceError.message : 'unknown',
        });
      }
      return res.status(202).json({ reference, amount, status: 'REQUIRES_REVIEW', reconciliation_pending: true });
    }
    throw error;
  }
}));

router.post('/qr', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(paymentQrSchema, req.body);
  const user = req.user!;
  const draft = await createPaymentDraft(input, user, 'qr');
  const { tenant, payment, reference, amount } = draft;
  if ('existing' in draft && draft.existing) {
    return res.status(200).json({
      reference,
      amount,
      status: payment.status,
      qr_code: payment.qrCodeData,
      saleId: payment.saleId,
    });
  }
  if (!tenant) {
    throw new HttpError(404, 'Shop not found');
  }
  const supportedQrCodes = ['BG', 'PB', 'SM', 'SB', 'WA'] as const;
  if (!tenant.mpesaQrCpi || !tenant.mpesaQrTrxCode || !supportedQrCodes.includes(tenant.mpesaQrTrxCode as typeof supportedQrCodes[number])) {
    await prisma.payment.update({ where: { id: payment.id }, data: { status: 'FAILED' } });
    return res.status(409).json({ error: 'Dynamic QR is not configured for this shop till or paybill' });
  }
  try {
    const qr = await generateDynamicQr({
      merchantName: tenant.shopName,
      reference,
      amount,
      transactionCode: tenant.mpesaQrTrxCode as 'BG' | 'PB' | 'SM' | 'SB' | 'WA',
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
  if (['PENDING', 'QUEUED', 'REQUIRES_REVIEW'].includes(payment.status) && payment.paymentMode !== 'qr') {
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
            status: { in: ['PENDING', 'QUEUED', 'REQUIRES_REVIEW'] },
            OR: [{ providerCheckedAt: null }, { providerCheckedAt: { lt: new Date(now - 10_000) } }],
          },
          data: { providerCheckedAt: new Date(now) },
        });
        if (claimed.count === 1) {
          if (!payment.providerReference) {
            await prisma.payment.update({
              where: { id: payment.id },
              data: { status: 'REQUIRES_REVIEW', providerStatus: 'PROVIDER_REFERENCE_MISSING' },
            });
          } else {
            remote = await queryTransactionStatus(payment.providerReference);
          }
        }
        if (remote) {
          await prisma.payment.update({
            where: { id: payment.id },
            data: { providerStatus: typeof remote?.status === 'string' ? remote.status : null },
          });
        }
      }
      if (remote?.status === 'SUCCESS') {
        await prisma.payment.updateMany({
          where: { id: payment.id, status: { in: ['PENDING', 'QUEUED', 'REQUIRES_REVIEW'] }, saleId: null },
          data: { status: 'REQUIRES_REVIEW', providerStatus: 'SUCCESS_AWAITING_AMOUNT_CONFIRMATION' },
        });
      } else if (remote?.status === 'FAILED') {
        await prisma.payment.updateMany({
          where: { id: payment.id, status: { in: ['PENDING', 'QUEUED', 'REQUIRES_REVIEW'] }, saleId: null },
          data: { status: 'FAILED', providerStatus: 'FAILED' },
        });
      }
    } catch (error) {
      log('warn', 'payment.status_refresh_failed', { requestId: req.requestId, paymentId: payment.id, message: error instanceof Error ? error.message : 'unknown' });
    }
  }
  const refreshed = await prisma.payment.findUnique({ where: { id: payment.id } });
  return res.json({ reference, status: refreshed?.status ?? payment.status, saleId: refreshed?.saleId ?? payment.saleId });
}));

export default router;
