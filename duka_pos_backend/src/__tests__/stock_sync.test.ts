import { beforeAll, describe, expect, it } from 'vitest';

let stockMovementChangesProductBalance: (movementType: string) => boolean;
let orderedStockMovements: <T extends { productId?: string | null; localId: number; deviceId?: string }>(records: T[]) => T[];

beforeAll(async () => {
  process.env.OIDC_ISSUER_URL = 'https://id.example.test/realms/duka';
  process.env.OIDC_AUDIENCE = 'duka-api';
  process.env.DATABASE_URL ??= 'postgresql://localhost:5432/duka_pos_test';
  ({ stockMovementChangesProductBalance, orderedStockMovements } = await import('../routes/operational_sync'));
});

describe('stock movement replay', () => {
  it('does not apply sale movements twice', () => {
    expect(stockMovementChangesProductBalance('sale')).toBe(false);
  });

  it('does not treat opening snapshots as deltas', () => {
    expect(stockMovementChangesProductBalance('opening')).toBe(false);
  });

  it('applies receipts, returns, and adjustments once', () => {
    expect(stockMovementChangesProductBalance('receipt')).toBe(true);
    expect(stockMovementChangesProductBalance('sale_return')).toBe(true);
    expect(stockMovementChangesProductBalance('adjustment')).toBe(true);
  });

  it('orders multi-till product movements deterministically', () => {
    const records = [
      { productId: 'product-z', localId: 2, deviceId: 'till-b' },
      { productId: 'product-a', localId: 8, deviceId: 'till-a' },
      { productId: 'product-a', localId: 4, deviceId: 'till-a' },
    ];
    expect(orderedStockMovements(records).map((record) => record.localId))
      .toEqual([4, 8, 2]);
  });
});
