import { Request, Response } from 'express';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { activateSubscriptionPaymentAtomically } from '../lib/subscription_settlement';
import { billingIntervalForMonths } from '../lib/subscription_pricing';
import { payHeroSettlementContractConfirmed, queryTransactionStatus } from '../services/payhero';
import { log } from '../lib/observability';
import { toMajorUnits, toMinorUnits, wholeShillingsFromMinor } from '../lib/money';

export function payheroReferenceFromCallback(body: unknown): string | undefined {
  if (!body || typeof body !== 'object') return undefined;
  const root = body as Record<string, unknown>;
  const nested = root.response && typeof root.response === 'object' && !Array.isArray(root.response)
    ? root.response as Record<string, unknown>
    : null;
  const reference = nested?.ExternalReference;
  return typeof reference === 'string' ? reference : undefined;
}

function successfulPayHeroCallback(
  body: unknown,
  expected: { reference: string; checkoutRequestId: string | null; amount: number },
): { receiptCode: string } | null {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
  const root = body as Record<string, unknown>;
  if (root.status !== true || !root.response || typeof root.response !== 'object' || Array.isArray(root.response)) {
    return null;
  }
  const response = root.response as Record<string, unknown>;
  const amount = response.Amount;
  const checkoutRequestId = response.CheckoutRequestID;
  const receiptCode = response.MpesaReceiptNumber;
  if (
    response.ExternalReference !== expected.reference ||
    response.ResultCode !== 0 ||
    typeof response.Status !== 'string' ||
    response.Status.toLowerCase() !== 'success' ||
    typeof amount !== 'number' ||
    !Number.isSafeInteger(amount) ||
    amount !== expected.amount ||
    typeof checkoutRequestId !== 'string' ||
    !checkoutRequestId.trim() ||
    !expected.checkoutRequestId ||
    checkoutRequestId !== expected.checkoutRequestId ||
    typeof response.MerchantRequestID !== 'string' ||
    !response.MerchantRequestID.trim() ||
    typeof receiptCode !== 'string' ||
    !/^[A-Z0-9]{6,20}$/i.test(receiptCode.trim())
  ) {
    return null;
  }
  return { receiptCode: receiptCode.trim().toUpperCase() };
}

function callbackCheckoutRequestId(body: unknown): string | undefined {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return undefined;
  const root = body as Record<string, unknown>;
  if (!root.response || typeof root.response !== 'object' || Array.isArray(root.response)) return undefined;
  const value = (root.response as Record<string, unknown>).CheckoutRequestID;
  return typeof value === 'string' ? value : undefined;
}

// PayHero webhook callback - no auth required
export const handlePayheroCallback = async (req: Request, res: Response) => {
  try {
    const reference = payheroReferenceFromCallback(req.body);

    if (typeof reference !== 'string' || !/^(DUKA|SUBS)-[0-9a-f-]{36}$/.test(reference)) {
      return res.status(400).json({ error: 'reference required' });
    }

    if (reference.startsWith('SUBS-')) {
      const payment = await prisma.subscriptionPayment.findUnique({ where: { reference } });
      if (!payment) return res.status(404).json({ error: 'Subscription payment not found' });
      if (
        !payment.checkoutRequestId ||
        callbackCheckoutRequestId(req.body) !== payment.checkoutRequestId
      ) return res.status(400).json({ error: 'PayHero callback did not match the pending payment' });
      if (!payment.providerReference) {
        await prisma.subscriptionPayment.update({
          where: { id: payment.id },
          data: { status: 'REQUIRES_REVIEW', providerStatus: 'PROVIDER_REFERENCE_MISSING' },
        });
        return res.status(202).json({ received: true, status: 'REQUIRES_REVIEW' });
      }
      const status = await queryTransactionStatus(payment.providerReference);
      if (status.status === 'SUCCESS') {
        if (!payHeroSettlementContractConfirmed()) {
          await prisma.subscriptionPayment.updateMany({
            where: { id: payment.id, status: { in: ['PENDING', 'REQUIRES_REVIEW'] } },
            data: { status: 'REQUIRES_REVIEW', providerStatus: 'SETTLEMENT_CONTRACT_UNCONFIRMED' },
          });
          return res.status(202).json({ received: true, status: 'REQUIRES_REVIEW' });
        }
        const callback = successfulPayHeroCallback(req.body, {
          reference,
          checkoutRequestId: payment.checkoutRequestId,
          amount: wholeShillingsFromMinor(payment.amountMinor),
        });
        if (!callback) {
          await prisma.subscriptionPayment.updateMany({
            where: { id: payment.id, status: { in: ['PENDING', 'REQUIRES_REVIEW'] } },
            data: { status: 'REQUIRES_REVIEW', providerStatus: 'SUCCESS_CALLBACK_MISMATCH' },
          });
          return res.status(202).json({ received: true, status: 'REQUIRES_REVIEW' });
        }
        const receiptCode = callback.receiptCode;
        if (payment.status !== 'SUCCESS') {
          await activateSubscriptionPaymentAtomically({
            paymentId: payment.id,
            tenantId: payment.tenantId,
            durationMonths: payment.durationMonths,
            billingInterval: billingIntervalForMonths(payment.durationMonths),
            receiptCode,
            voucherApplied: payment.voucherApplied,
          });
        }
      } else if (status.status === 'FAILED') {
        await prisma.subscriptionPayment.updateMany({
          where: { id: payment.id, status: { in: ['PENDING', 'REQUIRES_REVIEW'] } },
          data: { status: 'FAILED', providerStatus: 'FAILED' },
        });
      } else {
        await prisma.subscriptionPayment.updateMany({
          where: { id: payment.id, status: { in: ['PENDING', 'REQUIRES_REVIEW'] } },
          data: { status: 'REQUIRES_REVIEW', providerStatus: 'PROVIDER_STATUS_QUEUED' },
        });
      }
      return res.json({ received: true });
    }

    // Find payment by reference
    const payment = await prisma.payment.findUnique({
      where: { reference },
      include: { tenant: true }
    });

    if (!payment) {
      return res.status(404).json({ error: 'Payment not found' });
    }
    if (
      !payment.checkoutRequestId ||
      callbackCheckoutRequestId(req.body) !== payment.checkoutRequestId
    ) return res.status(400).json({ error: 'PayHero callback did not match the pending payment' });
    if (!payment.providerReference) {
      await prisma.payment.updateMany({
        where: { id: payment.id, status: { in: ['PENDING', 'QUEUED', 'REQUIRES_REVIEW'] }, saleId: null },
        data: { status: 'REQUIRES_REVIEW', providerStatus: 'PROVIDER_REFERENCE_MISSING' },
      });
      return res.status(202).json({ received: true, status: 'REQUIRES_REVIEW' });
    }

    // Verify status with PayHero (don't trust webhook body alone). The webhook
    // is an out-of-band signal, so it bypasses the poll cooldown — but the
    // queried response is still bound to the provider reference returned by
    // the original initiation request, and an
    // unverified or mismatched response is treated as inconclusive rather
    // than as proof that money arrived.
    const status = await queryTransactionStatus(payment.providerReference);

    if (status.status === 'SUCCESS' && ['PENDING', 'REQUIRES_REVIEW'].includes(payment.status)) {
      if (!payHeroSettlementContractConfirmed()) {
        await prisma.payment.updateMany({
          where: { id: payment.id, status: { in: ['PENDING', 'REQUIRES_REVIEW'] }, saleId: null },
          data: { status: 'REQUIRES_REVIEW', providerStatus: 'SETTLEMENT_CONTRACT_UNCONFIRMED' },
        });
        return res.status(202).json({ received: true, status: 'REQUIRES_REVIEW' });
      }
      const callback = successfulPayHeroCallback(req.body, {
        reference,
        checkoutRequestId: payment.checkoutRequestId,
        amount: Number(payment.amount),
      });
      if (!callback) {
        await prisma.payment.updateMany({
          where: { id: payment.id, status: { in: ['PENDING', 'REQUIRES_REVIEW'] }, saleId: null },
          data: { status: 'REQUIRES_REVIEW', providerStatus: 'SUCCESS_CALLBACK_MISMATCH' },
        });
        return res.status(202).json({ received: true, status: 'REQUIRES_REVIEW' });
      }
      await finalizeSale(payment.id);
    } else if (status.status === 'FAILED') {
      await prisma.payment.updateMany({
        where: { id: payment.id, status: { in: ['PENDING', 'QUEUED', 'REQUIRES_REVIEW'] }, saleId: null },
        data: { status: 'FAILED' }
      });
    } else {
      await prisma.payment.updateMany({
        where: { id: payment.id, status: { in: ['PENDING', 'QUEUED', 'REQUIRES_REVIEW'] }, saleId: null },
        data: { status: 'REQUIRES_REVIEW', providerStatus: 'PROVIDER_STATUS_QUEUED' },
      });
    }

    res.json({ received: true });
  } catch (error) {
    log('error', 'payment.webhook_failed', { requestId: req.requestId, message: error instanceof Error ? error.message : 'unknown' });
    res.status(500).json({ error: 'Webhook processing failed', requestId: req.requestId });
  }
};

// Finalize sale after successful payment
export async function finalizeSale(paymentId: string) {
  const payment = await prisma.payment.findUnique({
    where: { id: paymentId },
    include: { tenant: true }
  });

  if (!payment || payment.saleId) return payment?.saleId;
  if (!['PENDING', 'REQUIRES_REVIEW'].includes(payment.status)) return;

  const rawCartItems = payment.cartSnapshot as Array<{ product_id: string; product_name: string; qty: number; portion?: 'full' | 'half' | 'quarter'; portion_ml?: number; stock_units?: number; unit_price: number; unit_cost: number }>;
  if (!Array.isArray(rawCartItems) || rawCartItems.length === 0) throw new Error('Payment cart is invalid');
  const cartItems = rawCartItems.map((item) => ({
    ...item,
    portion: item.portion ?? 'full',
    portion_ml: item.portion_ml ?? 0,
    stock_units: item.stock_units ?? item.qty,
  }));
  // The till's cart is keyed on (product, portion), so the same bottle may
  // legitimately appear as a full bottle and a half bottle. Stock is
  // therefore accumulated per product — the same rule `/initiate` applied when
  // it accepted the basket — and the "exactly one bottle in stock" check runs
  // over each product once rather than over every cart line.
  const stockUnitsByProduct = new Map<string, number>();
  for (const item of cartItems) {
    stockUnitsByProduct.set(
      item.product_id,
      (stockUnitsByProduct.get(item.product_id) ?? 0) + item.stock_units,
    );
  }

  const productIds = [...stockUnitsByProduct.keys()].sort();
  const products = await prisma.product.findMany({
    where: { id: { in: productIds }, tenantId: payment.tenantId },
    select: { id: true },
  });
  if (products.length !== productIds.length) {
    const found = new Set(products.map((product) => product.id));
    const missing = cartItems.find((item) => !found.has(item.product_id));
    throw new Error(`Product unavailable: ${missing?.product_name ?? 'unknown product'}`);
  }

  let totalMinor = 0;
  let profitMinor = 0;
  for (const item of cartItems) {
    const itemPriceMinor = toMinorUnits(item.unit_price);
    const itemCostMinor = toMinorUnits(item.unit_cost);
    const lineTotalMinor = item.qty * itemPriceMinor;
    const lineProfitMinor = item.qty * (itemPriceMinor - itemCostMinor);
    if (!Number.isSafeInteger(lineTotalMinor) || !Number.isSafeInteger(lineProfitMinor)) {
      throw new Error('Payment cart contains an inexact monetary amount');
    }
    totalMinor += lineTotalMinor;
    profitMinor += lineProfitMinor;
  }
  const expectedMinor = toMinorUnits(Number(payment.amount));
  if (
    !Number.isSafeInteger(totalMinor) ||
    totalMinor !== expectedMinor ||
    wholeShillingsFromMinor(totalMinor) !== Number(payment.amount)
  ) {
    throw new Error('Payment amount does not match the stored sale cart');
  }
  const total = toMajorUnits(totalMinor);
  const profit = toMajorUnits(profitMinor);

  const saleId = globalThis.crypto.randomUUID();
  const stockPayload = JSON.stringify(productIds.map((id) => ({ id, qty: stockUnitsByProduct.get(id) })));
  const db = getD1DatabaseBinding();
  const statements = [
    db.prepare(`
      UPDATE payments
      SET status = 'PROCESSING', sale_id = ?
      WHERE id = ? AND status = ? AND sale_id IS NULL
    `).bind(saleId, payment.id, payment.status),
    db.prepare(`
      WITH required AS (
        SELECT json_extract(value, '$.id') AS id,
               CAST(json_extract(value, '$.qty') AS REAL) AS qty
        FROM json_each(?)
      )
      UPDATE products
      SET stock_qty = stock_qty - (SELECT qty FROM required WHERE required.id = products.id),
          updated_at = ?
      WHERE tenant_id = ?
        AND id IN (SELECT id FROM required)
        AND (
          SELECT COUNT(*)
          FROM products AS available
          JOIN required ON required.id = available.id
          WHERE available.tenant_id = ?
            AND available.stock_qty >= required.qty
            AND EXISTS (
              SELECT 1 FROM payments
              WHERE id = ? AND sale_id = ? AND status = 'PROCESSING'
            )
        ) = (SELECT COUNT(*) FROM required)
    `).bind(stockPayload, new Date().toISOString(), payment.tenantId, payment.tenantId, payment.id, saleId),
    db.prepare(`
      INSERT INTO sales (
        id, tenant_id, local_id, device_id, staff_id, staff_name,
        payment_method, payment_reference, total, profit, created_at
      )
      VALUES (
        CASE WHEN changes() = ? THEN ? ELSE NULL END, ?, NULL, 'legacy',
        ?, ?, 'mpesa', ?, ?, ?, ?
      )
    `).bind(
      productIds.length,
      saleId,
      payment.tenantId,
      payment.initiatedBy,
      payment.staffName,
      payment.reference,
      total,
      profit,
      new Date().toISOString(),
    ),
    ...cartItems.map((item) => db.prepare(`
      INSERT INTO sale_items (
        id, tenant_id, sale_id, product_id, product_name, qty, unit_price,
        unit_cost, portion, portion_ml
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      globalThis.crypto.randomUUID(),
      payment.tenantId,
      saleId,
      item.product_id,
      item.product_name,
      item.qty,
      item.unit_price,
      item.unit_cost,
      item.portion,
      item.portion_ml,
    )),
    db.prepare(`
      UPDATE payments
      SET status = 'SUCCESS'
      WHERE id = ? AND status = 'PROCESSING' AND sale_id = ?
        AND EXISTS (SELECT 1 FROM sales WHERE id = ? AND tenant_id = ?)
    `).bind(payment.id, saleId, saleId, payment.tenantId),
  ];

  try {
    await db.batch(statements);
    return saleId;
  } catch (error) {
    const current = await prisma.payment.findUnique({ where: { id: paymentId }, select: { saleId: true } });
    if (current?.saleId) return current.saleId;
    throw error;
  }
}
