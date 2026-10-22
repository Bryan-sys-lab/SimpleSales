import { describe, expect, it } from 'vitest';
import {
  canViewShopKpis,
  rollUpPortfolio,
  viewableTenantIds,
  type ShopKpi,
} from '../lib/portfolio.js';

describe('portfolio roll-up', () => {
  const shop = (over: Partial<ShopKpi>): ShopKpi => ({
    tenantId: 't1',
    shopName: 'Amina Duka',
    role: 'admin',
    revenue: 0,
    profit: 0,
    transactions: 0,
    averageBasket: 0,
    topPaymentMethod: null,
    ...over,
  });

  it('sums the parts into a whole', () => {
    const total = rollUpPortfolio([
      shop({ revenue: 4000, profit: 1200, transactions: 20 }),
      shop({ tenantId: 't2', revenue: 9000, profit: 3000, transactions: 60 }),
    ]);
    expect(total.revenue).toBe(13000);
    expect(total.profit).toBe(4200);
    expect(total.transactions).toBe(80);
    expect(total.shopCount).toBe(2);
  });

  it("computes the whole's average from the whole's totals", () => {
    // The whole point of rollUpPortfolio: averaging the shops' averages gives
    // 5050, and the true portfolio average is 10000/10 = 1000.
    const total = rollUpPortfolio([
      shop({ revenue: 1000, transactions: 10 }), // avg 100
      shop({ tenantId: 't2', revenue: 10000, transactions: 1 }), // avg 10000
    ]);
    expect(total.averageBasket).toBe(1000);
  });

  it('reports a zero average for shops that sold nothing, not NaN', () => {
    const total = rollUpPortfolio([shop({}), shop({ tenantId: 't2' })]);
    expect(total.averageBasket).toBe(0);
    expect(Number.isNaN(total.averageBasket)).toBe(false);
  });

  it('reports a real zero for an empty portfolio', () => {
    const total = rollUpPortfolio([]);
    expect(total).toEqual({
      shopCount: 0,
      revenue: 0,
      profit: 0,
      transactions: 0,
      averageBasket: 0,
    });
  });

  it('does not leak a shop count that disagrees with the rows', () => {
    const shops = [shop({}), shop({ tenantId: 't2' }), shop({ tenantId: 't3' })];
    expect(rollUpPortfolio(shops).shopCount).toBe(shops.length);
  });
});

describe('portfolio ownership', () => {
  it('an owner or a manager may see a shop', () => {
    expect(canViewShopKpis('admin')).toBe(true);
    expect(canViewShopKpis('manager')).toBe(true);
  });

  it('a cashier may not see a shop, and may not assert ownership', () => {
    expect(canViewShopKpis('cashier')).toBe(false);
    // An absent, empty or invented role is a no, never a default-yes.
    expect(canViewShopKpis(undefined)).toBe(false);
    expect(canViewShopKpis(null)).toBe(false);
    expect(canViewShopKpis('')).toBe(false);
    expect(canViewShopKpis('ADMIN')).toBe(false);
    expect(canViewShopKpis('owner')).toBe(false);
  });

  it('scopes to the tenants the caller owns, dropping the rest', () => {
    expect(
      viewableTenantIds([
        { tenantId: 't1', role: 'admin' },
        { tenantId: 't2', role: 'cashier' },
        { tenantId: 't3', role: 'manager' },
      ]),
    ).toEqual(['t1', 't3']);
  });

  it('a caller who is a cashier everywhere gets an empty tenant list', () => {
    expect(
      viewableTenantIds([
        { tenantId: 't1', role: 'cashier' },
        { tenantId: 't2', role: 'cashier' },
      ]),
    ).toEqual([]);
  });

  it('ownership is per-shop: running one duka grants nothing over the next', () => {
    // The same person is admin of t1 and a cashier of t2. They see t1 only.
    expect(
      viewableTenantIds([
        { tenantId: 't1', role: 'admin' },
        { tenantId: 't2', role: 'cashier' },
      ]),
    ).toEqual(['t1']);
  });
});
