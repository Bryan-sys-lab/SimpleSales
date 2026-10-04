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

/**
 * One line on a tax invoice as the till sends it.
 *
 * `vat_amount` and `line_total` are integer minor units, matching the till's
 * internal representation and the exact figures it printed on the customer's
 * receipt. `line_total` is checked against `qty * unit_price` in
 * services/etims.ts rather than here: `qty` is a decimal, so that check is
 * arithmetic, and doing it in the same place that performs the rounding keeps
 * the two from drifting.
 */
export const etimsInvoiceItemSchema = z.object({
  name: z.string().trim().min(1).max(240),
  qty: z.number().positive().max(10_000),
  unit_price: z.number().int().min(0),
  unit_cost: z.number().int().min(0),
  portion: z.string().trim().max(16).default('full'),
  portion_ml: z.number().int().min(0).max(100_000).default(0),
  vat_amount: z.number().int().min(0),
  line_total: z.number().int().min(0),
});

export const etimsReceiptSchema = z.object({
  receipt_number: z.string().trim().min(3).max(64),
  issued_at: z.string().min(10).max(40),
  payment_method: z.string().trim().max(32).default('cash'),
  payment_reference: z.string().trim().max(120).optional(),
  total: z.number().int().min(0),
  vat_rate_percent: z.number().int().min(0).max(100).default(16),
  device_id: z.string().trim().max(120).optional(),
  // Bounded at 500: comfortably the largest realistic single till upload, and a
  // hard cap so one request cannot make the API hold an unbounded JSON body.
  items: z.array(etimsInvoiceItemSchema).min(1).max(500),
});

export const etimsDeviceSchema = z.object({
  tin: z.string().trim().regex(/^[A-Za-z0-9]{9,20}$/, 'A TIN is the taxpayer PIN exactly as KRA issued it'),
  device_id: z.string().trim().min(4).max(120),
  device_name: z.string().trim().max(120).optional(),
});

/**
 * Parses `body` against `schema` and returns the schema's *output* type.
 *
 * Generic over the schema rather than over a bare type parameter. With
 * `parseBody<T>(schema: z.ZodSchema<T>, ...)` a schema whose input and output
 * differ — any schema using `.default()` — is not assignable, so TypeScript
 * silently widened `T` and every `.default()`-ed field came back as
 * `string | undefined`. That surfaced on the eTIMS receipt schema, where it
 * turned `total` into an optional number the route then had to cast away.
 * Inferring from `z.infer` keeps `.default()`'s guarantee intact.
 */
export function parseBody<S extends z.ZodTypeAny>(schema: S, body: unknown): z.infer<S> {
  return schema.parse(body) as z.infer<S>;
}
