import { z } from 'zod';

export const parseBody = (schema: z.ZodSchema<any>, body: any) => schema.parse(body);

const boundedName = z.string().trim().min(1).max(120);

/**
 * First-time shop provisioning.
 */
export const provisionSchema = z.object({
  shopName: boundedName,
  ownerName: boundedName,
  email: z.string().trim().toLowerCase().email().max(254),
});

/**
 * Tenant settings (M-Pesa, eTIMS, PayHero channel).
 */
export const settingsSchema = z.object({
  mpesaEnabled: z.boolean().optional(),
  etimsEnabled: z.boolean().optional(),
  payheroChannelId: z.number().int().positive().max(2000000).nullable().optional(),
}).strict();

/**
 * Bulk product sync (upsert).
 */
export const productSyncSchema = z.object({
  products: z.array(z.object({
    id: z.number().int().positive().optional(),
    remoteId: z.string().uuid().optional().nullable(),
    name: boundedName,
    category: z.string().trim().max(80).default('General'),
    costPrice: z.number().finite().nonnegative().max(100000000),
    sellPrice: z.number().finite().nonnegative().max(100000000),
    stockQty: z.number().finite().nonnegative().max(2000000),
    reorderLevel: z.number().int().nonnegative().max(2000000),
    bottleMl: z.number().int().positive().max(10000).default(750),
    halfPrice: z.number().finite().nonnegative().max(100000000).nullable().optional(),
    quarterPrice: z.number().finite().nonnegative().max(100000000).nullable().optional(),
    exciseStampBatch: z.string().trim().max(120).optional().nullable(),
    active: z.boolean().default(true),
  })).max(2000),
});

/**
 * M-Pesa payment initiation.
 */
export const paymentSchema = z.object({
  items: z.array(z.object({
    product_id: z.string().uuid(),
    qty: z.number().finite().positive().max(10000),
    portion: z.enum(['full', 'half', 'quarter']).default('full'),
  })).min(1).max(100),
  phone_number: z.string().trim().regex(/^\+?[0-9]{9,15}$/),
  staff_name: boundedName,
  staff_profile_id: z.string().uuid().optional(),
  customer_name: z.string().trim().max(120).optional(),
}).superRefine((value, context) => {
  const keys = value.items.map((item: any) => `${item.product_id}:${item.portion}`);
  if (new Set(keys).size !== keys.length) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['items'], message: 'Each product may appear only once per sale' });
  }
});

/**
 * Bulk staff sync (upsert).
 */
export const staffSyncSchema = z.object({
  staff: z.array(z.object({
    localId: z.number().int().positive(),
    remoteId: z.string().uuid().optional().nullable(),
    name: boundedName,
    role: z.enum(['cashier', 'manager']).default('cashier'),
    active: z.boolean().default(true),
  })).max(500),
}).strict();

/**
 * Staff deletion (tombstone).
 */
export const deletionSchema = z.object({
  reason: z.string().trim().max(240).optional(),
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
  payload: z.record(z.unknown()),
  deviceId: z.string().min(1).optional(),
});

/**
 * Register a TIN and eTIMS device.
 */
export const etimsDeviceSchema = z.object({
  tin: z.string().trim().min(1).max(50),
  deviceId: z.string().trim().min(1).max(100),
  deviceName: z.string().trim().max(120).optional(),
});

// ---------------------------------------------------------------------------
// Stock adjustment (per-product, immediate)
// ---------------------------------------------------------------------------

export const stockAdjustSchema = z.object({
  product_id: z.string().uuid(),
  delta: z.number().int().min(-1000000).max(1000000),
  reason: z.string().trim().max(240).optional(),
  staff_profile_id: z.string().uuid().optional(),
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

/**
 * Admin audit log entry (POST /api/admin/audit).
 */
export const adminAuditSchema = z.object({
  action: z.string().trim().min(1).max(120),
  targetType: z.string().trim().min(1).max(120).optional().nullable(),
  targetId: z.string().trim().min(1).max(200).optional().nullable(),
  tenantId: z.string().trim().min(1).optional().nullable(),
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
