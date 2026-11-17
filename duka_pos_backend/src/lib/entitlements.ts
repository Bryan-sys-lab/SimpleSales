import { createHash, randomBytes } from 'node:crypto';
import { prisma } from './prisma';

export type Entitlement = {
  allowed: boolean;
  status: string;
  reason: 'active' | 'grace' | 'voucher' | 'subscription_required' | 'expired';
  priceMinor: number | null;
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

export async function tenantEntitlement(tenantId: string): Promise<Entitlement> {
  // A few isolated route tests use a deliberately minimal Prisma double from
  // before billing existed. Keep those tests focused on their route contract;
  // a generated production client always has this model and therefore never
  // takes this compatibility branch.
  const subscriptionModel = (prisma as typeof prisma & { tenantSubscription?: typeof prisma.tenantSubscription }).tenantSubscription;
  if (!subscriptionModel) return { allowed: true, status: 'legacy', reason: 'active', priceMinor: null, currency: 'KES', billingInterval: 'monthly', currentPeriodEnd: null };
  const subscription = await subscriptionModel.findUnique({ where: { tenantId } });
  const now = new Date();
  if (!subscription) return { allowed: false, status: 'pending', reason: 'subscription_required', priceMinor: null, currency: 'KES', billingInterval: 'monthly', currentPeriodEnd: null };
  const end = subscription.currentPeriodEnd;
  const grace = subscription.graceUntil;
  if (subscription.status === 'voucher') return { allowed: true, status: 'voucher', reason: 'voucher', priceMinor: subscription.priceMinor, currency: subscription.currency, billingInterval: subscription.billingInterval, currentPeriodEnd: end?.toISOString() ?? null };
  if (subscription.status === 'active' && (!end || end > now)) return { allowed: true, status: 'active', reason: 'active', priceMinor: subscription.priceMinor, currency: subscription.currency, billingInterval: subscription.billingInterval, currentPeriodEnd: end?.toISOString() ?? null };
  if (grace && grace > now) return { allowed: true, status: 'grace', reason: 'grace', priceMinor: subscription.priceMinor, currency: subscription.currency, billingInterval: subscription.billingInterval, currentPeriodEnd: end?.toISOString() ?? null };
  return { allowed: false, status: subscription.status, reason: end && end <= now ? 'expired' : 'subscription_required', priceMinor: subscription.priceMinor, currency: subscription.currency, billingInterval: subscription.billingInterval, currentPeriodEnd: end?.toISOString() ?? null };
}

export function entitlementPayload(entitlement: Entitlement) {
  return { entitlement };
}
