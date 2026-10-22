import { Router, Request, Response } from 'express';
import { randomUUID } from 'node:crypto';
import { prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import { parseBody, paymentSchema } from '../lib/validation';
import { initiateStkPush, queryTransactionStatus } from '../services/payhero';
import { finalizeSale } from './payhero-callback';
import { requireRole } from '../middleware/auth';
import { log } from '../lib/observability';

const router = Router();

router.post('/initiate', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(paymentSchema, req.body);
  const user = req.user!;
  const ids = [...new Set(input.items.map((item) => item.product_id))];
  const products = await prisma.product.findMany({ where: { tenantId: user.tenantId, id: { in: ids }, active: true } });
  const byId = new Map(products.map((product) => [product.id, product]));
  if (products.length !== ids.length) return res.status(400).json({ error: 'One or more products are unavailable' });
  const stockRequested = new Map<string, number>();
  for (const item of input.items) {
    const factor = item.portion === 'half' ? 0.5 : item.portion === 'quarter' ? 0.25 : 1;
    stockRequested.set(item.product_id, (stockRequested.get(item.product_id) ?? 0) + item.qty * factor);
  }
  for (const [productId, requested] of stockRequested) {
    const product = byId.get(productId)!;
    if (Number(product.stockQty) < requested) return res.status(409).json({ error: `Insufficient stock for ${product.name}` });
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
  if (!tenant?.mpesaEnabled || !tenant.payheroChannelId) return res.status(409).json({ error: 'M-Pesa is not configured for this shop' });
  if (!process.env.PUBLIC_API_URL) return res.status(503).json({ error: 'Payment service is not configured' });
  let initiatedBy = user.id;
  if (input.staff_profile_id) {
    const cashier = await prisma.profile.findFirst({
      where: { id: input.staff_profile_id, tenantId: user.tenantId, role: { in: ['cashier', 'manager'] }, active: true },
    });
    if (!cashier) return res.status(403).json({ error: 'Cashier profile is not active' });
    if (user.role === 'cashier' && cashier.id !== user.id) return res.status(403).json({ error: 'A cashier may only record sales under their own profile' });
    initiatedBy = cashier.id;
  }
  const cashierProfile = await prisma.profile.findFirst({ where: { id: initiatedBy, tenantId: user.tenantId, active: true } });
  if (!cashierProfile) return res.status(403).json({ error: 'Cashier profile is not active' });
  const reference = `DUKA-${randomUUID()}`;
  const payment = await prisma.payment.create({ data: { tenantId: user.tenantId, initiatedBy, staffName: cashierProfile.name, reference, phoneNumber: input.phone_number, amount, cartSnapshot, status: 'QUEUED' } });
  try {
    const push = await initiateStkPush({ amount, phoneNumber: input.phone_number, channelId: tenant.payheroChannelId, externalReference: reference, customerName: input.customer_name, callbackUrl: `${process.env.PUBLIC_API_URL}/webhooks/payhero-callback`, credentialId: tenant.payheroCredentialId ?? undefined });
    await prisma.payment.update({ where: { id: payment.id }, data: { status: 'PENDING', checkoutRequestId: push.checkoutRequestId } });
    return res.status(201).json({ reference, amount });
  } catch (error) {
    await prisma.payment.update({ where: { id: payment.id }, data: { status: 'FAILED' } });
    throw error;
  }
}));

router.get('/status', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const reference = typeof req.query.reference === 'string' ? req.query.reference : '';
  if (!reference || reference.length > 80) return res.status(400).json({ error: 'reference required' });
  const payment = await prisma.payment.findFirst({ where: { reference, tenantId: req.user!.tenantId } });
  if (!payment) return res.status(404).json({ error: 'Payment not found' });
  if (payment.status === 'PENDING' || payment.status === 'QUEUED') {
    try {
      // `queryTransactionStatus` is rate-limited internally, so the till's
      // 3-second poll loop cannot turn into a live provider request per poll.
      // A too-fresh push has no provider answer yet; a stale cached answer is
      // better than hammering a third party for a result that cannot change.
      const settledForMs = Date.now() - payment.createdAt.getTime();
      const remote = settledForMs < 5_000
        ? null
        : await queryTransactionStatus(reference);
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
