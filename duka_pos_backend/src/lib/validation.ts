import { z } from 'zod';

export const parseBody = <T>(schema: z.ZodType<T>, body: unknown): T =>
  schema.parse(body);

const boundedName = z.string().trim().min(1).max(120);
// Keep accepting legacy UUIDs created by the offline client (including the
// all-zero/version-less form) while still enforcing UUID shape. Zod 4's
// `.uuid()` only accepts RFC-versioned UUIDs.
const uuid = z.string().regex(
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
);

/**
 * First-time shop provisioning.
 */
export const provisionSchema = z.object({
  shopName: boundedName,
  ownerName: boundedName,
  email: z.string().trim().toLowerCase().email().max(254),
  businessProfile: z.enum(['drinks', 'duka', 'fashion', 'open']).default('duka'),
});

/**
 * Tenant settings (M-Pesa, eTIMS, PayHero channel).
 */
export const settingsSchema = z.object({
  mpesaEnabled: z.boolean().optional(),
  etimsEnabled: z.boolean().optional(),
  payheroChannelId: z.number().int().positive().max(2000000).nullable().optional(),
  businessProfile: z.enum(['drinks', 'duka', 'fashion', 'open']).optional(),
}).strict();

export const taxEntitySchema = z.object({
  legalForm: z.enum(['individual', 'sole_proprietor', 'partnership', 'company', 'other']),
  displayLabel: boundedName,
  kraPin: z.string().trim().min(4).max(40).optional(),
  registeredTaxObligations: z.array(z.string().trim().min(1).max(80)).max(20).default([]),
  accountingPeriodStartMonth: z.number().int().min(1).max(12).default(1),
  status: z.enum(['needs_review', 'reviewed', 'active', 'inactive']).default('needs_review'),
  etimsOnboardingStatus: z.enum(['not_started', 'in_progress', 'onboarded', 'needs_review', 'not_applicable']).default('not_started'),
  etimsMethod: z.enum(['online', 'oscu', 'vscu', 'epos', 'non_vat_lite', 'other']).nullable().optional(),
  effectiveFrom: z.string().datetime({ offset: true }),
  outletReference: z.string().trim().max(120).optional().nullable(),
}).strict();

export const taxRuleSchema = z.object({
  taxEntityId: z.string().trim().min(1).max(80),
  taxType: z.enum(['vat', 'tot', 'income_tax', 'etims', 'withholding', 'excise', 'payroll']),
  scope: z.string().trim().min(1).max(120),
  jurisdiction: z.string().trim().min(2).max(20).default('KE'),
  rateBasisPoints: z.number().int().nonnegative().max(100000).nullable().optional(),
  taxBase: z.enum(['gross_sales', 'taxable_supply', 'net_profit', 'fixed_amount', 'none']),
  filingFrequency: z.enum(['monthly', 'quarterly', 'annual', 'none']).default('none'),
  filingDueDay: z.number().int().min(1).max(31).nullable().optional(),
  thresholdMinor: z.number().int().nonnegative().max(10_000_000_000).nullable().optional(),
  effectiveFrom: z.string().datetime({ offset: true }),
  effectiveTo: z.string().datetime({ offset: true }).nullable().optional(),
  sourceUrl: z.string().url().max(2048),
  sourceReference: z.string().trim().max(500).optional().nullable(),
  approvalNote: z.string().trim().max(1000).optional().nullable(),
}).strict();

export const mpesaChannelSchema = z.object({
  channelType: z.enum(['till', 'paybill']),
  shortCode: z.string().trim().regex(/^\d{5,12}$/),
  description: z.string().trim().max(120).optional(),
}).strict();

/**
 * Bulk product sync (upsert).
 */
export const productSyncSchema = z.object({
  products: z.array(z.object({
    id: z.number().int().positive().optional(),
    remoteId: uuid.optional().nullable(),
    syncKey: z.string().trim().min(1).max(200).optional().nullable(),
    name: boundedName,
    category: z.string().trim().max(80).default('General'),
    costPrice: z.number().finite().nonnegative().max(100000000),
    sellPrice: z.number().finite().nonnegative().max(100000000),
    stockQty: z.number().finite().nonnegative().max(2000000),
    openingStockQty: z.number().finite().nonnegative().max(2000000).optional(),
    reorderLevel: z.number().int().nonnegative().max(2000000),
    bottleMl: z.number().int().positive().max(200000).default(750),
    unit: z.enum(['each', 'ml', 'litre', 'cup', 'kilogram']).default('each'),
    mlPerKg: z.number().finite().nonnegative().max(1000000).default(0),
    halfPrice: z.number().finite().nonnegative().max(100000000).nullable().optional(),
    quarterPrice: z.number().finite().nonnegative().max(100000000).nullable().optional(),
    exciseStampBatch: z.string().trim().max(120).optional().nullable(),
    active: z.boolean().default(true),
  })).max(2000),
});

export const vatReturnStatusSchema = z.object({
  periodStart: z.string().datetime({ offset: true }),
  periodEnd: z.string().datetime({ offset: true }),
  status: z.enum(['prepared', 'submitted', 'accepted', 'rejected', 'settled']),
  rejectionReason: z.string().trim().max(1000).optional().nullable(),
});

/** Offline sale batches. Amounts are integer minor units from the till. */
export const salesSyncSchema = z.object({
  sales: z.array(z.object({
    localId: z.number().int().positive(),
    deviceId: z.string().trim().min(1).max(120).optional(),
    staffName: boundedName,
    buyerName: z.string().trim().min(1).max(120).optional(),
    buyerTin: z.string().trim().max(50).optional(),
    paymentMethod: z.string().trim().min(1).max(40),
    paymentReference: z.string().trim().max(120).nullable().optional(),
    total: z.number().int().nonnegative(),
    profit: z.number().int(),
    amountTendered: z.number().int().nonnegative(),
    changeGiven: z.number().int().nonnegative(),
    createdAt: z.string().datetime({ offset: true }),
    tenders: z.array(z.object({
      localUuid: z.string().trim().min(1).max(120),
      method: z.string().trim().min(1).max(40),
      amountMinor: z.number().int().positive(),
      tenderedMinor: z.number().int().nonnegative().optional().nullable(),
      changeMinor: z.number().int().nonnegative().optional().nullable(),
      reference: z.string().trim().max(120).optional().nullable(),
      status: z.string().trim().min(1).max(20).default('confirmed'),
      createdAt: z.string().datetime({ offset: true }),
    })).max(20).optional(),
    items: z.array(z.object({
      productId: z.string().trim().min(1).nullable().optional(),
      productName: boundedName,
      qty: z.number().finite().positive().max(100000),
      unitPrice: z.number().int().nonnegative(),
      unitCost: z.number().int().nonnegative(),
    vatMinor: z.number().int().nonnegative().nullable().optional(),
    taxableMinor: z.number().int().nonnegative().nullable().optional(),
    taxClass: z.string().trim().min(1).max(80).optional(),
    taxRuleId: z.string().trim().min(1).max(80).nullable().optional(),
    taxRuleVersion: z.number().int().positive().nullable().optional(),
    vatRateBps: z.number().int().nonnegative().max(100000).nullable().optional(),
      portion: z.string().trim().min(1).max(20).default('full'),
      portionMl: z.number().int().nonnegative().default(0),
    })).min(1).max(200),
  })).max(500),
}).strict();

/**
 * M-Pesa payment initiation.
 */
export const paymentSchema = z.object({
  items: z.array(z.object({
    product_id: uuid,
    qty: z.number().finite().positive().max(10000),
    // A row of stock may appear on two lines — a client that sent qty 1
    // twice instead of qty 2 built the same basket, and refusing it at the
    // door lost a sale the till builds routinely. Whether the shelf can
    // fulfil it is a STOCK question, answered in /initiate, not a shape
    // question, answered here.
    portion: z.enum(['full', 'half', 'quarter']).default('full'),
  })).min(1).max(100),
  phone_number: z.string().trim().regex(/^\+?[0-9]{9,15}$/),
  staff_name: boundedName,
  staff_profile_id: uuid.optional(),
  // Named by the till: whose cart this was, for the receipt. Free of charge,
  // free of a customer record — the account's owner is a later feature.
  customer_name: z.string().trim().max(120).optional(),
});

/**
 * Bulk staff sync (upsert).
 */
export const staffSyncSchema = z.object({
  staff: z.array(z.object({
    localId: z.number().int().positive(),
    remoteId: uuid.optional().nullable(),
    name: boundedName,
    username: z.string().trim().min(1).max(120).nullable().optional(),
    role: z.enum(['cashier', 'manager']).default('cashier'),
    active: z.boolean().default(true),
    // Self-describing PBKDF2 verifier from the till. Never accept a plain PIN.
    pinHash: z.string().trim().max(400).nullable().optional(),
  })).max(500),
}).strict();

/**
 * Staff deletion (tombstone).
 */
export const deletionSchema = z.object({
  reason: z.string().trim().max(240).optional(),
}).strict();

/** Opaque client-encrypted full-workspace backup. */
export const cloudBackupSchema = z.object({
  workspaceKey: z.string().trim().min(1).max(200),
  payload: z.string().min(1).max(8_000_000),
  kind: z.enum(['device_bound', 'portable']).default('device_bound'),
  // SHA-256 of the clear snapshot. The server never decrypts the payload;
  // this stable id only makes a retry of the same snapshot idempotent.
  snapshotHash: z.string().regex(/^[a-f0-9]{64}$/).optional(),
}).strict();

/** Sanitized financial evidence; personal operational fields are excluded. */
export const financialEvidenceSyncSchema = z.object({
  deviceId: z.string().trim().min(1).max(120),
  events: z.array(z.object({
    localId: z.number().int().positive(),
    uuid: z.string().trim().min(1).max(120),
    eventType: z.string().trim().min(1).max(60),
    sourceType: z.string().trim().min(1).max(60),
    sourceId: z.number().int().positive().nullable().optional(),
    occurredAtUtc: z.string().datetime({ offset: true }),
    revenueMinor: z.number().int(),
    cashInMinor: z.number().int(),
    cashOutMinor: z.number().int(),
    cogsMinor: z.number().int(),
    operatingExpenseMinor: z.number().int(),
    taxCollectedMinor: z.number().int(),
    receivableDeltaMinor: z.number().int(),
    payableDeltaMinor: z.number().int(),
    customerDepositDeltaMinor: z.number().int(),
    inventoryDeltaMilliunits: z.number().int(),
    previousHash: z.string().regex(/^[a-f0-9]{64}$/).nullable().optional(),
    integrityHash: z.string().regex(/^[a-f0-9]{64}$/),
  }).strict()).max(500),
}).strict();

export const creditSyncSchema = z.object({
  customers: z.array(z.object({
    localUuid: z.string().trim().min(1).max(120),
    name: boundedName,
    phone: z.string().trim().max(40).nullable().optional(),
    tin: z.string().trim().max(40).nullable().optional(),
    notes: z.string().max(1000).nullable().optional(),
    creditLimitMinor: z.number().int().nonnegative().nullable().optional(),
    balanceMinor: z.number().int(),
    active: z.boolean(),
    createdAt: z.string().datetime({ offset: true }),
  })).max(5000),
  entries: z.array(z.object({
    localUuid: z.string().trim().min(1).max(120),
    customerUuid: z.string().trim().min(1).max(120),
    entryType: z.string().trim().min(1).max(30),
    amountMinor: z.number().int(),
    saleLocalId: z.number().int().positive().nullable().optional(),
    returnLocalId: z.number().int().positive().nullable().optional(),
    paymentMethod: z.string().trim().max(30).nullable().optional(),
    reference: z.string().trim().max(120).nullable().optional(),
    staffName: boundedName,
    note: z.string().max(1000).nullable().optional(),
    createdAt: z.string().datetime({ offset: true }),
  })).max(10000),
}).strict();

const operationalRecord = z.object({
  localId: z.number().int().positive(),
  deviceId: z.string().trim().min(1).max(120).optional(),
  createdAt: z.string().datetime({ offset: true }).optional(),
}).passthrough();

export const operationalSyncSchema = z.object({
  records: z.array(operationalRecord).max(500),
}).strict();

/** Fashion lay-by lifecycle snapshots from an offline till. */
const laybyPaymentRecord = z.object({
  localId: z.number().int().positive(),
  method: z.enum(['cash', 'card', 'bank_transfer', 'mobile_money_manual', 'mpesa', 'mpesa_till']),
  amountMinor: z.number().int().positive(),
  direction: z.enum(['in', 'out']).default('in'),
  reference: z.string().trim().max(120).nullable().optional(),
  createdAt: z.string().datetime({ offset: true }),
  staffName: boundedName,
  staffId: z.number().int().positive().nullable().optional(),
}).strict();

const laybyItemRecord = z.object({
  productId: z.string().trim().min(1).max(120).nullable().optional(),
  productName: boundedName,
  variantId: z.number().int().positive().nullable().optional(),
  variantName: z.string().trim().max(120).default(''),
  qty: z.number().finite().positive().max(100000),
  unitPriceMinor: z.number().int().nonnegative(),
  unitCostMinor: z.number().int().nonnegative(),
  discountMinor: z.number().int().nonnegative().default(0),
  totalMinor: z.number().int().nonnegative(),
}).strict();

export const laybySyncSchema = z.object({
  laybys: z.array(z.object({
    localId: z.number().int().positive(),
    deviceId: z.string().trim().min(1).max(120).optional(),
    uuid: z.string().trim().min(1).max(120),
    customerUuid: z.string().trim().min(1).max(120),
    status: z.enum(['open', 'completed', 'cancelled', 'expired']),
    totalMinor: z.number().int().positive(),
    paidMinor: z.number().int().nonnegative(),
    dueAt: z.string().datetime({ offset: true }),
    createdAt: z.string().datetime({ offset: true }),
    staffName: boundedName,
    staffId: z.number().int().positive().nullable().optional(),
    saleLocalId: z.number().int().positive().nullable().optional(),
    completedAt: z.string().datetime({ offset: true }).nullable().optional(),
    cancelledAt: z.string().datetime({ offset: true }).nullable().optional(),
    items: z.array(laybyItemRecord).min(1).max(200),
    payments: z.array(laybyPaymentRecord).max(500),
  }).strict()).max(500),
}).strict();

/** Fashion exchange snapshots linking the return, credit and replacement sale. */
export const exchangeSyncSchema = z.object({
  exchanges: z.array(z.object({
    localId: z.number().int().positive(),
    deviceId: z.string().trim().min(1).max(120).optional(),
    uuid: z.string().trim().min(1).max(120),
    originalSaleLocalId: z.number().int().positive(),
    returnLocalId: z.number().int().positive(),
    replacementSaleLocalId: z.number().int().positive(),
    status: z.enum(['completed']),
    returnedTotalMinor: z.number().int().nonnegative(),
    replacementTotalMinor: z.number().int().nonnegative(),
    differenceMinor: z.number().int().nonnegative(),
    differenceDirection: z.enum(['customer_pays', 'customer_receives', 'even']),
    reason: z.string().trim().min(1).max(500),
    staffName: boundedName,
    staffId: z.number().int().positive().nullable().optional(),
    createdAt: z.string().datetime({ offset: true }),
  }).strict()).max(500),
}).strict();

/** Append-only stock ledger rows from offline tills. */
const stockMovementRecord = z.object({
  localId: z.number().int().positive(),
  deviceId: z.string().trim().min(1).max(120).optional(),
  uuid: z.string().trim().min(1).max(120),
  // Prisma product ids are cuid values in this service (older deployments
  // may use UUIDs). Keep the wire contract identifier-shaped without
  // incorrectly rejecting either format.
  productId: z.string().trim().regex(/^[A-Za-z0-9_-]{1,120}$/).nullable().optional(),
  variantId: z.number().int().positive().nullable().optional(),
  movementType: z.enum([
    'opening', 'sale', 'sale_return', 'receipt', 'receipt_void',
    'adjustment', 'count', 'writeoff', 'import', 'correction', 'repack',
  ]),
  qtyDelta: z.number().finite().min(-2000000).max(2000000),
  unitCostMinor: z.number().int().nullable().optional(),
  referenceType: z.string().trim().max(40).nullable().optional(),
  referenceId: z.number().int().positive().nullable().optional(),
  batchId: z.number().int().positive().nullable().optional(),
  staffId: z.number().int().positive().nullable().optional(),
  staffName: z.string().trim().max(120).nullable().optional(),
  note: z.string().trim().max(500).nullable().optional(),
  balanceAfter: z.number().finite().min(0).max(2000000),
  createdAt: z.string().datetime({ offset: true }),
}).strict();

export const stockMovementsSyncSchema = z.object({
  stockMovements: z.array(stockMovementRecord).max(500),
}).strict();

// ---------------------------------------------------------------------------
// Auth (app verification flow)
// ---------------------------------------------------------------------------

/**
 * Step 1: request a 6-digit verification code by email.
 */
export const authLinkSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  pin: z.string().trim().min(4).max(8),
  shopName: boundedName,
  ownerName: boundedName,
});

/**
 * Step 2: confirm the code and mint session tokens.
 */
export const authVerifySchema = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  pin: z.string().trim().min(4).max(8),
  code: z.string().trim().length(6),
});

/**
 * Refresh an app session using its refresh token.
 */
export const authRefreshSchema = z.object({
  refreshToken: z.string().min(1),
});

/**
 * Step 1 of Forgot PIN: request a reset code by email.
 */
export const pinResetRequestSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
});

/**
 * Step 2 of Forgot PIN: confirm the code and set a new PIN hash locally.
 */
export const pinResetConfirmSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  challengeId: z.string().min(1),
  code: z.string().trim().length(6),
});

// ---------------------------------------------------------------------------
// eTIMS (KRA tax compliance)
// ---------------------------------------------------------------------------

/**
 * Issue a KRA receipt for a completed sale.
 */
export const etimsReceiptSchema = z.object({
  receipt_number: z.string().trim().min(1).max(120),
  issued_at: z.string().datetime({ offset: true }),
  payment_method: z.string().trim().min(1).max(40),
  payment_reference: z.string().trim().max(120).nullable().optional(),
  total: z.number().int().nonnegative(),
  vat_rate_percent: z.number().finite().min(0).max(100),
  buyer_name: z.string().trim().max(120).optional(),
  buyer_tin: z.string().trim().max(50).optional(),
  items: z.array(z.object({
    name: boundedName,
    qty: z.number().positive(),
    unit_price: z.number().int().nonnegative(),
    unit_cost: z.number().int().nonnegative(),
    portion: z.string().trim().max(40).optional().nullable(),
    portion_ml: z.number().int().positive().optional().nullable(),
    vat_amount: z.number().int().nonnegative(),
    line_total: z.number().int().nonnegative(),
  })).min(1).max(100),
  device_id: z.string().trim().min(1).max(100).optional(),
}).transform(({ device_id, ...payload }) => ({ ...payload, deviceId: device_id }));

/**
 * Register a TIN and eTIMS device.
 */
export const etimsDeviceSchema = z.object({
  tin: z.string().trim().min(1).max(50),
  device_id: z.string().trim().min(1).max(100).optional(),
  deviceId: z.string().trim().min(1).max(100).optional(),
  device_name: z.string().trim().max(120).optional(),
  deviceName: z.string().trim().max(120).optional(),
}).transform((value) => ({
  tin: value.tin,
  deviceId: value.deviceId ?? value.device_id ?? '',
  deviceName: value.deviceName ?? value.device_name,
})).refine((value) => value.deviceId.length > 0, { message: 'device_id is required' });

// ---------------------------------------------------------------------------
// Stock adjustment (per-product, immediate)
// ---------------------------------------------------------------------------

export const stockAdjustSchema = z.object({
  product_id: uuid,
  // Measured goods can lose a fraction of one stock unit during a spill or
  // tank dip. Keep the same bounded contract while accepting that quantity.
  delta: z.number().finite().min(-1000000).max(1000000),
  reason: z.string().trim().max(240).optional(),
  staff_profile_id: uuid.optional(),
});

// ---------------------------------------------------------------------------
// Staff authenticate (local till PIN check against backend)
// ---------------------------------------------------------------------------

export const staffAuthenticateSchema = z.object({
  username: z.string().trim().min(1).max(120),
  pin: z.string().trim().min(4).max(8),
});

// ---------------------------------------------------------------------------
// Telemetry (device -> backend event ingestion)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// System administration
// ---------------------------------------------------------------------------

/**
 * List/query parameters shared by admin churn, sales and sessions endpoints.
 */
export const adminListQuerySchema = z.object({
  from: z.string().datetime().optional().nullable(),
  to: z.string().datetime().optional().nullable(),
  tenantId: z.string().trim().min(1).optional().nullable(),
  limit: z.coerce.number().int().positive().max(500).default(100),
});

/** Restricted, server-side filters for the minimized commercial ledger. */
export const commercialLedgerQuerySchema = z.object({
  profile: z.enum(['drinks', 'duka', 'fashion', 'open']).optional(),
  categoryFamily: z.string().trim().min(1).max(80).optional(),
  batchId: z.string().trim().min(1).max(120).optional(),
  status: z.enum(['accepted', 'superseded', 'withdrawn', 'deleted']).optional(),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
  cursor: z.string().trim().min(1).max(120).optional(),
  limit: z.coerce.number().int().positive().max(100).default(50),
}).superRefine((value, context) => {
  if (value.from && value.to && new Date(value.from) > new Date(value.to)) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['to'], message: 'to must be after from' });
  }
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

/** A platform-wide, non-tenant announcement authored by a system admin. */
export const platformAnnouncementSchema = z.object({
  title: z.string().trim().min(1).max(120),
  body: z.string().trim().min(1).max(500),
  active: z.boolean().default(true),
}).strict();

// ---------------------------------------------------------------------------
// Support tickets (device -> backend ingestion)
// ---------------------------------------------------------------------------

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
