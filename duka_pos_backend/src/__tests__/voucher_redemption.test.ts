import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  batch: vi.fn(),
  prepare: vi.fn(),
  statements: [] as Array<{ sql: string; values: unknown[] }>,
}));

vi.mock('../lib/prisma', () => ({
  getD1DatabaseBinding: () => ({
    batch: mocks.batch,
    prepare: mocks.prepare,
  }),
}));

import { addCalendarMonths } from '../lib/entitlements';
import { redeemVoucherAtomically } from '../lib/voucher_redemption';

describe('voucher redemption D1 batch', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.statements.length = 0;
    mocks.prepare.mockImplementation((sql: string) => ({
      bind: (...values: unknown[]) => {
        const statement = { sql, values };
        mocks.statements.push(statement);
        return statement;
      },
    }));
    mocks.batch.mockResolvedValue([{ meta: { changes: 1 } }, { meta: { changes: 1 } }]);
  });

  it('claims the voucher and conditionally updates entitlement in one D1 batch', async () => {
    const now = new Date('2026-03-01T12:00:00.000Z');

    await expect(redeemVoucherAtomically({
      voucherId: 'voucher-1',
      tenantId: 'tenant-1',
      profileId: 'profile-1',
      email: 'owner@example.com',
      now,
      durationMonths: 1,
    })).resolves.toBe(true);

    expect(mocks.batch).toHaveBeenCalledTimes(1);
    expect(mocks.batch.mock.calls[0][0]).toHaveLength(2);
    expect(mocks.statements[0].sql).toContain('redeemed_at IS NULL');
    expect(mocks.statements[0].sql).toContain('voucher_type = ?');
    expect(mocks.statements[0].sql).toContain('issued_to_email = ?');
    expect(mocks.statements[0].sql).not.toContain('expires_at = ?');
    expect(mocks.statements[0].values).toContain('owner@example.com');
    expect(mocks.statements[0].values).toContain('access');
    expect(mocks.statements[1].sql).toContain('WHERE changes() = 1');
    expect(mocks.statements[1].sql).toContain('ON CONFLICT (tenant_id)');
    expect(mocks.statements[1].values).toContain('2026-04-01T12:00:00.000Z');
  });

  it('claims a discount voucher without granting voucher access', async () => {
    await expect(redeemVoucherAtomically({
      voucherId: 'discount-voucher-1',
      tenantId: 'tenant-1',
      profileId: 'profile-1',
      email: 'owner@example.com',
      now: new Date('2026-03-01T12:00:00.000Z'),
      durationMonths: 6,
      voucherType: 'discount',
    })).resolves.toBe(true);

    expect(mocks.statements[0].values).toContain('discount');
    expect(mocks.statements[1].sql).toContain("'pending'");
    expect(mocks.statements[1].sql).toContain('WHERE changes() = 1');
    expect(mocks.statements[1].sql).not.toContain('current_period_end');
    expect(mocks.statements[1].values).toEqual([
      expect.any(String),
      'tenant-1',
      'discount-voucher-1',
      '2026-03-01T12:00:00.000Z',
      '2026-03-01T12:00:00.000Z',
    ]);
  });

  it('does not report redemption when another request already claimed the voucher', async () => {
    mocks.batch.mockResolvedValue([{ meta: { changes: 0 } }, { meta: { changes: 0 } }]);

    await expect(redeemVoucherAtomically({
      voucherId: 'voucher-1',
      tenantId: 'tenant-1',
      profileId: 'profile-1',
      email: 'owner@example.com',
      now: new Date('2026-03-01T12:00:00.000Z'),
      durationMonths: 12,
    })).resolves.toBe(false);
  });

  it('adds calendar months without overflowing shorter months', () => {
    expect(addCalendarMonths(
      new Date('2026-01-31T12:00:00.000Z'),
      1,
    ).toISOString()).toBe('2026-02-28T12:00:00.000Z');
  });
});
