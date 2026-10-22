import { Request, Response } from 'express';
import { prisma } from '../lib/prisma.js';
import { queryTransactionStatus } from '../services/payhero.js';
import { log } from '../lib/observability.js';

// PayHero webhook callback - no auth required
export const handlePayheroCallback = async (req: Request, res: Response) => {
  try {
    const { reference } = req.body;

    if (typeof reference !== 'string' || !/^DUKA-[0-9a-f-]{36}$/.test(reference)) {
      return res.status(400).json({ error: 'reference required' });
    }

    // Find payment by reference
    const payment = await prisma.payment.findUnique({
      where: { reference },
      include: { tenant: true }
    });

    if (!payment) {
      return res.status(404).json({ error: 'Payment not found' });
    }

    // Verify status with PayHero (don't trust webhook body alone). The webhook
    // is an out-of-band signal, so it bypasses the poll cooldown — but the
    // queried response is still bound to this exact reference, and an
    // unverified or mismatched response is treated as inconclusive rather
    // than as proof that money arrived.
    const status = await queryTransactionStatus(reference, { force: true });

    if (status.status === 'SUCCESS') {
      await finalizeSale(payment.id);
    } else if (status.status === 'FAILED') {
      await prisma.payment.update({
        where: { id: payment.id },
        data: { status: 'FAILED' }
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

  if (!payment || payment.saleId) return payment?.saleId; // Already finalized

  const rawCartItems = payment.cartSnapshot as Array<{ product_id: string; product_name: string; qty: number; portion?: 'full' | 'half' | 'quarter'; portion_ml?: number; stock_units?: number; unit_price: number; unit_cost: number }>;
  const cartItems = rawCartItems.map((item) => ({
    ...item,
    portion: item.portion ?? 'full',
    portion_ml: item.portion_ml ?? 0,
    stock_units: item.stock_units ?? item.qty,
  }));
  if (!Array.isArray(cartItems) || cartItems.length === 0) throw new Error('Payment cart is invalid');
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

  // Create sale and update stock
  const result = await prisma.$transaction(async (tx) => {
    const currentPayment = await tx.payment.findUnique({ where: { id: paymentId } });
    if (!currentPayment || currentPayment.saleId) return null;
    let total = 0;
    let profit = 0;
    // One lookup per distinct product, not per cart line: the same bottle can
    // appear under several portions and must be decremented once.
    const products = new Map<string, { id: string; name: string; sellPrice: unknown; costPrice: unknown }>();
    const productIds = [...stockUnitsByProduct.keys()];
    for (const product of await tx.product.findMany({
      where: { id: { in: productIds }, tenantId: payment.tenantId },
    })) {
      products.set(product.id, product);
    }
    for (const [productId, stockUnits] of stockUnitsByProduct) {
      if (!products.has(productId)) {
        const missing = cartItems.find((item) => item.product_id === productId);
        throw new Error(`Product unavailable: ${missing?.product_name ?? productId}`);
      }
    }

    // Conditional updates make finalization safe when two callbacks race:
    // the second transaction waits for the row lock and then gets count 0
    // instead of allowing stock to become negative.
    for (const [productId, stockUnits] of stockUnitsByProduct) {
      const updated = await tx.product.updateMany({
        where: { id: productId, tenantId: payment.tenantId, stockQty: { gte: stockUnits } },
        data: { stockQty: { decrement: stockUnits } },
      });
      if (updated.count !== 1) {
        const offending = cartItems.find((item) => item.product_id === productId);
        throw new Error(`Insufficient stock for ${offending?.product_name ?? productId}`);
      }
    }
    for (const item of cartItems) {
      total += item.qty * item.unit_price;
      profit += item.qty * (item.unit_price - item.unit_cost);
    }
    const sale = await tx.sale.create({
      data: {
        tenantId: payment.tenantId,
        staffId: payment.initiatedBy,
        staffName: payment.staffName,
        paymentMethod: 'mpesa',
        paymentReference: payment.reference,
        total,
        profit
      }
    });

    for (const item of cartItems) {
      await tx.saleItem.create({
        data: {
          tenantId: payment.tenantId,
          saleId: sale.id,
          productId: item.product_id,
          productName: item.product_name,
          qty: item.qty,
          unitPrice: item.unit_price,
          unitCost: item.unit_cost,
          portion: item.portion,
          portionMl: item.portion_ml,
        }
      });

    }

    await tx.payment.update({
      where: { id: paymentId },
      data: { status: 'SUCCESS', saleId: sale.id }
    });

    return sale;
  });

  return result?.id;
}
