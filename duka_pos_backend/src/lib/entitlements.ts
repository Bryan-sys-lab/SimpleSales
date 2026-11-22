import { createHash, randomBytes } from 'node:crypto';
import { prisma } from './prisma';

export type Entitlement = {
  allowed: boolean;
  status: string;
  reason: 'active' | 'grace' | 'voucher' | 'subscription_required' | 'expired';
  priceMinor: number | null;
  discountPercent: number;
  currency: string;
  billingInterval: string;
  currentPeriodEnd: string | null;
};

const secret = () => process.env.AUTH_JWT_SECRET ?? 'development-entitlement-secret';

export function hashVoucher(code: string): string {
  return createHash('sha256').update(`${secret()}:${code.trim().toUpperCase()}`).digest('hex');
}

export function generateVoucher(): { code: string; hash: string; prefix: string } {
  const code = `SS-${randomBytes(9).toString('base64url').toUpperCase()}`;
  return { code, hash: hashVoucher(code), prefix: code.slice(0, 8) };
}

export function addCalendarMonths(date: Date, months: number): Date {
  if (!Number.isInteger(months) || months < 1) {
    throw new RangeError('Subscription duration must be a positive whole number of months');
  }
  const result = new Date(date);
  const day = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(
    result.getUTCFullYear(),
    result.getUTCMonth() + 1,
    0,
  )).getUTCDate();
  result.setUTCDate(Math.min(day, lastDay));
  return result;
}

export async function tenantEntitlement(tenantId: string): Promise<Entitlement> {
  // A few isolated route tests use a deliberately minimal Prisma double from
  // before billing existed. Keep those tests focused on their route contract;
  // a generated production client always has this model and therefore never
  // takes this compatibility branch.
  const subscriptionModel = (prisma as typeof prisma & { tenantSubscription?: typeof prisma.tenantSubscription }).tenantSubscription;
  // Missing billing schema must never silently grant production access. This
  // also makes partial migrations fail closed until the database is repaired.
  if (!subscriptionModel) return { allowed: false, status: 'pending', reason: 'subscription_required', priceMinor: null, discountPercent: 0, currency: 'KES', billingInterval: 'monthly', currentPeriodEnd: null };
  const subscription = await subscriptionModel.findUnique({ where: { tenantId } });
  const now = new Date();
  if (!subscription) return { allowed: false, status: 'pending', reason: 'subscription_required', priceMinor: null, discountPercent: 0, currency: 'KES', billingInterval: 'monthly', currentPeriodEnd: null };
  const end = subscription.currentPeriodEnd;
  const grace = subscription.graceUntil;
  // A voucher is a time-bounded entitlement, just like a paid period.  The
  // original check accepted every voucher record regardless of its end date,
  // which meant a first-month voucher kept a shop unlocked indefinitely.
  // Keep vouchers with no expiry valid for the explicit no-expiry admin case,
  // but never let an elapsed first-month voucher bypass the paywall.
  if (subscription.status === 'voucher' && (!end || end > now)) {
    return { allowed: true, status: 'voucher', reason: 'voucher', priceMinor: subscription.priceMinor, discountPercent: subscription.discountPercent ?? 0, currency: subscription.currency, billingInterval: subscription.billingInterval, currentPeriodEnd: end?.toISOString() ?? null };
  }
  if (subscription.status === 'active' && (!end || end > now)) return { allowed: true, status: 'active', reason: 'active', priceMinor: subscription.priceMinor, discountPercent: subscription.discountPercent ?? 0, currency: subscription.currency, billingInterval: subscription.billingInterval, currentPeriodEnd: end?.toISOString() ?? null };
  if (grace && grace > now) return { allowed: true, status: 'grace', reason: 'grace', priceMinor: subscription.priceMinor, discountPercent: subscription.discountPercent ?? 0, currency: subscription.currency, billingInterval: subscription.billingInterval, currentPeriodEnd: end?.toISOString() ?? null };
  return { allowed: false, status: subscription.status, reason: end && end <= now ? 'expired' : 'subscription_required', priceMinor: subscription.priceMinor, discountPercent: subscription.discountPercent ?? 0, currency: subscription.currency, billingInterval: subscription.billingInterval, currentPeriodEnd: end?.toISOString() ?? null };
}

export function entitlementPayload(entitlement: Entitlement) {
  return { entitlement };
}
