import { z } from 'zod';

const boundedName = z.string().trim().min(1).max(120);

export const provisionSchema = z.object({
  shopName: boundedName,
  ownerName: boundedName,
  email: z.string().trim().toLowerCase().email().max(254),
});

export const settingsSchema = z.object({
  mpesaEnabled: z.boolean().optional(),
  etimsEnabled: z.boolean().optional(),
  payheroChannelId: z.number().int().positive().max(2_000_000).nullable().optional(),
}).strict();

export const productSyncSchema = z.object({
  products: z.array(z.object({
    id: z.number().int().positive().optional(),
    remoteId: z.string().uuid().optional().nullable(),
    name: boundedName,
    category: z.string().trim().max(80).default('General'),
    costPrice: z.number().finite().nonnegative().max(100_000_000),
    sellPrice: z.number().finite().nonnegative().max(100_000_000),
    stockQty: z.number().finite().nonnegative().max(2_000_000),
    reorderLevel: z.number().int().nonnegative().max(2_000_000),
    bottleMl: z.number().int().positive().max(10_000).default(750),
    halfPrice: z.number().finite().nonnegative().max(100_000_000).nullable().optional(),
    quarterPrice: z.number().finite().nonnegative().max(100_000_000).nullable().optional(),
    exciseStampBatch: z.string().trim().max(120).optional().nullable(),
    active: z.boolean().default(true),
  })).max(2_000),
});

export const paymentSchema = z.object({
  items: z.array(z.object({
    product_id: z.string().uuid(),
    qty: z.number().finite().positive().max(10_000),
    portion: z.enum(['full', 'half', 'quarter']).default('full'),
  })).min(1).max(100),
  phone_number: z.string().trim().regex(/^\+?[0-9]{9,15}$/),
  staff_name: boundedName,
  staff_profile_id: z.string().uuid().optional(),
  customer_name: z.string().trim().max(120).optional(),
}).superRefine((value, context) => {
  // The same product may legitimately appear more than once under *different*
  // portions — one full bottle plus one half of that bottle is a cart the till
  // builds routinely (the local cart is keyed on (product, portion), and
  // `recordSale` in database_helper.dart explicitly supports it).
  //
  // Rejecting repeated products outright used to fail the request at the door,
  // so the customer was never charged. The real constraint is how much stock
  // the basket consumes in total, which `/initiate` and `finalizeSale` both
  // accumulate per product and check against real availability.
  const lines = new Map<string, number>();
  value.items.forEach((item, index) => {
    const factor = item.portion === 'half' ? 0.5 : item.portion === 'quarter' ? 0.25 : 1;
    const units = item.qty * factor;
    lines.set(item.product_id, (lines.get(item.product_id) ?? 0) + units);
    // A single line asking for more than the maximum bottle count is a client
    // bug, not a stock question, so it is rejected here.
    if (item.qty * factor > 2_000_000) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['items', index, 'qty'],
        message: 'Quantity exceeds the maximum stock for this product',
      });
    }
  });
});
export const staffSyncSchema = z.object({
  staff: z.array(z.object({
    localId: z.number().int().positive(),
    remoteId: z.string().uuid().optional().nullable(),
    name: boundedName,
    role: z.enum(['cashier', 'manager']).default('cashier'),
    active: z.boolean().default(true),
  })).max(500),
}).strict();

/// A stock correction made at the till.
///
/// `/products/sync` deliberately does not carry `stockQty` for existing rows,
/// because the server is the authority there (M-Pesa finalization decrements
/// it). This endpoint is how a real-world correction — a break, a delivery, a
/// count — reaches the server, and it is recorded in `stock_adjustments` so
/// shrinkage stays attributable per cashier.
export const stockAdjustmentSchema = z.object({
  product_id: z.string().uuid(),
  delta: z.number().int().min(-2_000_000).max(2_000_000).refine((value) => value !== 0, {
    message: 'Adjustment must not be zero',
  }),
  reason: z.string().trim().max(240).optional(),
  staff_profile_id: z.string().uuid().optional(),
}).strict();

export const deletionSchema = z.object({
  reason: z.string().trim().max(240).optional(),
}).strict();

export function parseBody<T>(schema: z.ZodSchema<T>, body: unknown): T {
  return schema.parse(body);
}
