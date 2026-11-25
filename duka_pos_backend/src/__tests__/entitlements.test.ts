import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  tenantSubscription: { findUnique: vi.fn() },
}));

vi.mock('../lib/prisma', () => ({ prisma: mocks }));

import { tenantEntitlement } from '../lib/entitlements';

describe('tenant entitlement voucher expiry', () => {
  beforeEach(() => vi.clearAllMocks());

  it('allows an unexpired voucher', async () => {
    mocks.tenantSubscription.findUnique.mockResolvedValue({
      status: 'voucher',
      currentPeriodEnd: new Date(Date.now() + 60_000),
      graceUntil: null,
      priceMinor: null,
      currency: 'KES',
      billingInterval: 'monthly',
    });

    await expect(tenantEntitlement('tenant-1')).resolves.toMatchObject({
      allowed: true,
      reason: 'voucher',
    });
  });

  it('locks an expired voucher', async () => {
    mocks.tenantSubscription.findUnique.mockResolvedValue({
      status: 'voucher',
      currentPeriodEnd: new Date(Date.now() - 60_000),
      graceUntil: null,
      priceMinor: null,
      currency: 'KES',
      billingInterval: 'monthly',
    });

    await expect(tenantEntitlement('tenant-1')).resolves.toMatchObject({
      allowed: false,
      reason: 'expired',
    });
  });

  it('does not apply a claimed discount voucher to a different billing interval', async () => {
    mocks.tenantSubscription.findUnique.mockResolvedValue({
      status: 'pending',
      currentPeriodEnd: null,
      graceUntil: null,
      priceMinor: 10_000,
      discountPercent: 10,
      currency: 'KES',
      billingInterval: 'monthly',
      voucher: {
        voucherType: 'discount',
        discountPercent: 25,
        durationMonths: 3,
      },
    });

    await expect(tenantEntitlement('tenant-1')).resolves.toMatchObject({
      allowed: false,
      status: 'pending',
      discountPercent: 10,
      discountVoucherDurationMonths: 3,
    });
  });

  it('applies a claimed discount voucher when its term matches the admin period', async () => {
    mocks.tenantSubscription.findUnique.mockResolvedValue({
      status: 'pending',
      currentPeriodEnd: null,
      graceUntil: null,
      priceMinor: 10_000,
      discountPercent: 10,
      currency: 'KES',
      billingInterval: 'quarterly',
      voucher: {
        voucherType: 'discount',
        discountPercent: 25,
        durationMonths: 3,
      },
    });

    await expect(tenantEntitlement('tenant-1')).resolves.toMatchObject({
      discountPercent: 25,
      discountVoucherDurationMonths: 3,
    });
  });

  it('fails closed when the subscription model is unavailable', async () => {
    const model = mocks.tenantSubscription;
    delete (mocks as any).tenantSubscription;
    try {
      await expect(tenantEntitlement('tenant-1')).resolves.toMatchObject({
        allowed: false,
        reason: 'subscription_required',
      });
    } finally {
      (mocks as any).tenantSubscription = model;
    }
  });
});
