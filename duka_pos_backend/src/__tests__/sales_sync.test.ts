import { beforeAll, describe, expect, it } from 'vitest';

let orderedStockProductIds: (required: ReadonlyMap<string, number>) => string[];

beforeAll(async () => {
  process.env.OIDC_ISSUER_URL = 'https://id.example.test/realms/duka';
  process.env.OIDC_AUDIENCE = 'duka-api';
  process.env.DATABASE_URL ??= 'postgresql://localhost:5432/duka_pos_test';
  ({ orderedStockProductIds } = await import('../routes/sales'));
});

describe('multi-till sale stock ordering', () => {
  it('locks every product in a stable order regardless of basket order', () => {
    const firstTill = new Map([['product-z', 1], ['product-a', 1]]);
    const secondTill = new Map([['product-a', 1], ['product-z', 1]]);

    expect(orderedStockProductIds(firstTill)).toEqual(['product-a', 'product-z']);
    expect(orderedStockProductIds(secondTill)).toEqual(['product-a', 'product-z']);
  });
});
