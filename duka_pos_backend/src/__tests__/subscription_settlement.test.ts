import { beforeEach, describe, expect, it, vi } from 'vitest';

type MockStatement = {
  sql: string;
  values: unknown[];
  bind(...values: unknown[]): MockStatement;
};

const mocks = vi.hoisted(() => ({
  db: {
    prepare: vi.fn(),
    batch: vi.fn(),
  },
}));

vi.mock('../lib/prisma', () => ({
  getD1DatabaseBinding: () => mocks.db,
}));

import { activateSubscriptionPaymentAtomically } from '../lib/subscription_settlement';

describe('subscription payment settlement', () => {
  let statements: MockStatement[];

  beforeEach(() => {
    vi.clearAllMocks();
    statements = [];
    mocks.db.prepare.mockImplementation((sql: string): MockStatement => {
      const statement: MockStatement = {
        sql,
        values: [],
        bind(...values: unknown[]) {
          this.values = values;
          return this;
        },
      };
      return statement;
    });
    mocks.db.batch.mockImplementation(async (batch: MockStatement[]) => {
      statements = batch;
      return [{ meta: { changes: 1 } }, { meta: { changes: 1 } }];
    });
  });

  it('updates the stored billing interval from the paid term', async () => {
    await activateSubscriptionPaymentAtomically({
      paymentId: 'payment-1',
      tenantId: 'tenant-1',
      durationMonths: 3,
      billingInterval: 'quarterly',
      receiptCode: null,
      voucherApplied: false,
    });

    expect(statements).toHaveLength(2);
    expect(statements[1]?.sql).toContain(
      'billing_interval = COALESCE(?, tenant_subscriptions.billing_interval)',
    );
    expect(statements[1]?.values[2]).toBe('quarterly');
    expect(statements[1]?.values[9]).toBe('quarterly');
  });
});
