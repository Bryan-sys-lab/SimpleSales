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

/**
 * The shop's own admin PIN, as the till sends it.
 *
 * Exactly SIX digits, and nothing else, because that is the only thing the
 * local account asks for. The backend cannot verify it against a local
 * database it does not have — it is bound into the challenge instead, so the
 * person who started the link is the person who finishes it.
 *
 * It was FOUR digits, and the app made it six: the owner's PIN is an ADMIN
 * PIN, asked for in front of the things it guards — deleting the account,
 * changing the shop's settings — and a four-digit admin PIN is a password
 * somebody can guess while they wait for the till to think. A STAFF PIN is
 * still four digits; it is a different PIN, typed forty times a day at a
 * counter, and it never comes here.
 */
const adminPin = z.string().regex(/^\d{6}$/, 'The admin PIN is exactly 6 digits');

export const linkSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  pin: adminPin,
  shopName: boundedName,
  ownerName: boundedName,
}).strict();

/**
 * The code presented back, plus the PIN again.
 *
 * Re-sending the PIN rather than trusting the one from `/link` is what makes
 * the second half of the flow a second factor rather than a replay: a code
 * overheard in a mailbox is not enough without the device that holds the PIN.
 */
export const verificationCodeSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  pin: adminPin,
  code: z.string().regex(/^\d{6}$/, 'The verification code is exactly 6 digits'),
  shopName: boundedName.optional(),
  ownerName: boundedName.optional(),
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

/// Whether a staff member's account is usable.
///
/// A single boolean, `.strict()`, so a payload that carries anything else — a
/// role, a name — is rejected rather than half-applied.
export const staffActiveSchema = z.object({
  active: z.boolean(),
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

// ---------------------------------------------------------------------------
// The till's records: sales, shifts, returns, purchases, shot cups.
//
// THE MONEY CONVENTION AT THIS BOUNDARY
//
// These endpoints take money in MINOR UNITS — the integer cents a till keeps
// its ledger in. The stored columns are DECIMAL major units, so the
// conversion happens ONCE, on the way in.
//
// The alternative — taking doubles of shillings — loses a cent the moment a
// price like 40.55 shillings becomes a float, and a ledger that is a cent out
// is a ledger that does not reconcile against the drawer.
//
// The conversion is `minor / 100` in DECIMAL arithmetic, which is exact for
// every integer number of minor units.
// ---------------------------------------------------------------------------

/** Money in minor units: the integer cents a till counts in. */
const minorAmount = z.number().int().min(-100_000_000).max(100_000_000);

/** A quantity of stock, to three places: 1.5 bottles, 0.25 of a portion. */
const stockAmount = z.number().finite().min(0).max(1_000_000);

/** How a line was poured: the whole thing, half, a quarter, or a measured shot. */
const portion = z.enum(['full', 'half', 'quarter', 'measured']).default('full');

/**
 * The ledger, pushed from a till.
 *
 * A till writes its sales OFFLINE, so the same sale arrives more than once
 * unless the server can tell it from the first one. `localId` is that: the
 * till's own id for the sale, unique within a shop.
 */
export const saleSyncSchema = z.object({
  sales: z.array(z.object({
    localId: z.number().int().positive(),
    staffName: boundedName,
    staffProfileId: z.string().uuid().optional().nullable(),
    paymentMethod: z.string().trim().min(1).max(40).default('cash'),
    paymentReference: z.string().trim().max(200).optional().nullable(),
    /** The whole sale, in minor units. */
    total: minorAmount,
    /** The margin on the sale, in minor units. */
    profit: minorAmount,
    /** The cash handed over, in minor units. */
    amountTendered: minorAmount.optional(),
    /** The change given back, in minor units. */
    changeGiven: minorAmount.optional(),
    createdAt: z.string().datetime(),
    items: z.array(z.object({
      productId: z.string().uuid().optional().nullable(),
      productName: boundedName,
      qty: stockAmount.positive(),
      unitPrice: minorAmount,
      unitCost: minorAmount,
      portion,
      portionMl: z.number().int().min(0).max(100_000).default(0),
    })).min(1).max(200),
  })).max(1_000),
}).strict();

/**
 * A shift, pushed from a till.
 *
 * A shift is opened OFFLINE: a shop with one device and its staff on it has
 * no signal half the time, and a shift that needs a server is a shift nobody
 * opens.
 */
export const shiftSyncSchema = z.object({
  shifts: z.array(z.object({
    localId: z.number().int().positive(),
    staffName: boundedName,
    staffProfileId: z.string().uuid().optional().nullable(),
    startTime: z.string().datetime(),
    endTime: z.string().datetime().optional().nullable(),
    startFloat: minorAmount,
    endFloat: minorAmount,
    expectedCash: minorAmount,
    countedCash: minorAmount,
    status: z.enum(['open', 'closed']).default('open'),
  })).max(500),
}).strict();

/**
 * A return or a credit note.
 *
 * `kind` says what happened to the money: a refund hands it back, a credit
 * note leaves the customer holding the goods and the shop owing them.
 */
export const returnSchema = z.object({
  localId: z.number().int().positive(),
  /** The till's id for the sale being returned, when there was one. */
  originalSaleLocalId: z.number().int().positive().optional().nullable(),
  kind: z.enum(['refund', 'credit_note']).default('refund'),
  reason: z.string().trim().min(1).max(240),
  /** The money given back, in minor units. */
  total: minorAmount,
  /** The margin given back, in minor units. */
  profit: minorAmount,
  staffName: boundedName,
  staffProfileId: z.string().uuid().optional().nullable(),
  createdAt: z.string().datetime(),
  items: z.array(z.object({
    productId: z.string().uuid().optional().nullable(),
    productName: boundedName,
    qty: stockAmount.positive(),
    unitPrice: minorAmount,
    unitCost: minorAmount,
    portion,
    portionMl: z.number().int().min(0).max(100_000).default(0),
  })).min(1).max(200),
}).strict();

/**
 * A purchase: stock arriving at the shop, and what it cost.
 */
export const purchaseSchema = z.object({
  localId: z.number().int().positive(),
  supplierName: z.string().trim().min(1).max(120),
  invoiceNumber: z.string().trim().max(80).optional().nullable(),
  /** What the whole delivery cost, in minor units. */
  total: minorAmount,
  staffName: boundedName,
  staffProfileId: z.string().uuid().optional().nullable(),
  createdAt: z.string().datetime(),
  items: z.array(z.object({
    productId: z.string().uuid().optional().nullable(),
    productName: boundedName,
    qty: stockAmount.positive(),
    /** What one unit cost the shop, in minor units. */
    unitCost: minorAmount,
  })).min(1).max(500),
}).strict();

/**
 * A shot cup: a named serving poured from a drink.
 *
 * `capacityMl` is OPTIONAL, and zero means "the size is not known": a cup
 * with a size earns its cost exactly, and a cup without one is counted at its
 * full price. A negative size is a mistake and is refused.
 */
export const shotCupSyncSchema = z.object({
  shotCups: z.array(z.object({
    localId: z.number().int().positive(),
    productId: z.string().uuid().optional().nullable(),
    productName: boundedName,
    label: z.string().trim().min(1).max(80),
    capacityMl: z.number().int().min(0).max(100_000).default(0),
    /** What one of these sells for, in minor units. */
    price: minorAmount,
    active: z.boolean().default(true),
  })).max(1_000),
}).strict();

// ---------------------------------------------------------------------------
// Carried over from the older branch: the staff sign-in check, the device
// telemetry, the churn snapshot, the platform administration queries and the
// support tickets.
//
// The routes that use these are all still in use — the till pushes telemetry,
// the app has a support form, and the operator dashboard reads the
// administration queries — and the newer branch's schema had lost them.
// ---------------------------------------------------------------------------

export const staffAuthenticateSchema = z.object({
  username: z.string().trim().min(1).max(120),
  pin: z.string().trim().min(4).max(8),
});

/**
 * A single telemetry event pushed from a till phone. Route names, feature
 * names and timestamps only — never secrets or PII.
 */
export const telemetryEventSchema = z.object({
  deviceId: z.string().trim().min(1).max(200).optional().nullable(),
  name: z.string().trim().min(1).max(120),
  at: z.string().datetime().optional().nullable(),
  route: z.string().trim().max(200).optional().nullable(),
  detail: z.string().trim().max(1000).optional().nullable(),
});

/**
 * Bulk telemetry ingestion: max 500 events per request.
 */
export const ingestTelemetrySchema = z.object({
  events: z.array(telemetryEventSchema).min(1).max(500),
}).strict();

/**
 * Telemetry event list query parameters.
 */
export const telemetryQuerySchema = z.object({
  from: z.string().datetime().optional().nullable(),
  to: z.string().datetime().optional().nullable(),
  name: z.string().trim().min(1).optional().nullable(),
  deviceId: z.string().trim().min(1).optional().nullable(),
  limit: z.coerce.number().int().positive().max(1000).default(100),
});

/**
 * Churn snapshot pushed from a till phone (phone computes the ChurnAnalysis
 * locally; backend only stores/delivers the snapshot).
 */
export const churnSnapshotSchema = z.object({
  deviceId: z.string().min(1).max(100),
  date: z.string().datetime(),
  streakDays: z.number().int().nonnegative(),
  daysSinceLastActive: z.number().int().nonnegative(),
  totalSessions: z.number().int().nonnegative(),
  risk: z.enum(['none', 'low', 'medium', 'high']),
  score: z.number().finite().min(0).max(1),
});

/**
 * List/query parameters shared by admin churn, sales and sessions endpoints.
 */
export const adminListQuerySchema = z.object({
  from: z.string().datetime().optional().nullable(),
  to: z.string().datetime().optional().nullable(),
  tenantId: z.string().trim().min(1).optional().nullable(),
  limit: z.coerce.number().int().positive().max(500).default(100),
});

/**
 * Admin audit log entry (POST /api/admin/audit).
 */
export const adminAuditSchema = z.object({
  action: z.string().trim().min(1).max(120),
  targetType: z.string().trim().min(1).max(120).optional().nullable(),
  targetId: z.string().trim().min(1).max(200).optional().nullable(),
  tenantId: z.string().trim().min(1).optional().nullable(),
}).strict();

/**
 * A single support ticket or feature request pushed from a till phone.
 */
export const supportTicketSchema = z.object({
  deviceId: z.string().min(1).max(100).optional(),
  type: z.enum(['ticket', 'request']),
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().min(1).max(2000),
  status: z.enum(['open', 'in_progress', 'resolved']).default('open'),
});

/**
 * Bulk support ticket ingestion: max 100 items per request.
 */
export const ingestSupportSchema = z.object({
  items: z.array(supportTicketSchema).min(1).max(100),
}).strict();
