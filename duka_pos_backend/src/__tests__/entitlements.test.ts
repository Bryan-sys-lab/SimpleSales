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
