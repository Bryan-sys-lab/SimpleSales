// The portfolio roll-up: pure functions, no Prisma, no Express.
//
// The cross-shop KPI endpoint's correctness is arithmetic, and arithmetic is
// where a screen quietly tells an owner the wrong number. Keeping it here means
// it is testable without a database, and the route that reads rows stays a thin
// adapter over these two functions.
//
// The one rule this exists to enforce: an aggregate computed over the WHOLE is
// recomputed from the whole's totals, never averaged from the parts' averages.
// The mean of two shops' average baskets is not the portfolio's average basket
// — shop A selling ten KSh 100 baskets and shop B selling one KSh 10,000 basket
// average to KSh 5,050 each, while the actual portfolio average is KSh 1,000.

/** What one shop's ledger aggregated to over the window. */
export interface ShopKpi {
  tenantId: string;
  shopName: string;
  /** The caller's role in THIS shop, not the role in the request's tenant. */
  role: string;
  revenue: number;
  profit: number;
  transactions: number;
  /** This shop's own average basket, from its own totals. The portfolio's is
   * NOT the mean of these — see [rollUpPortfolio]. */
  averageBasket: number;
  topPaymentMethod: string | null;
}

/** The whole the shops divide, plus the shops themselves. */
export interface Portfolio {
  shopCount: number;
  revenue: number;
  profit: number;
  transactions: number;
  averageBasket: number;
}

/**
 * Sums the parts into a whole, and derives the whole's average from the whole's
 * own totals.
 *
 * An empty portfolio is a real zero rather than NaN: a caller running no shops
 * should see "nothing", not a screen that renders `NaN`.
 */
export function rollUpPortfolio(shops: ShopKpi[]): Portfolio {
  const totals = shops.reduce(
    (acc, shop) => ({
      revenue: acc.revenue + shop.revenue,
      profit: acc.profit + shop.profit,
      transactions: acc.transactions + shop.transactions,
    }),
    { revenue: 0, profit: 0, transactions: 0 },
  );

  // Guarded on transactions, not on shopCount: a portfolio of shops that each
  // sold nothing has a zero average basket, and dividing by the shop count
  // would report the average of zeroes as though sales had happened.
  const averageBasket =
    totals.transactions > 0
      ? Math.round(totals.revenue / totals.transactions)
      : 0;

  return {
    shopCount: shops.length,
    ...totals,
    averageBasket,
  };
}

/**
 * Whether a profile gives its holder the right to see a shop's figures.
 *
 * Ownership is per-shop: being an admin of one duka grants nothing over the
 * next. The role is read from the PROFILE row — the caller's standing in that
 * tenant — never from a request field, which would be a caller asserting its
 * own authority.
 */
export function canViewShopKpis(role: string | undefined | null): boolean {
  return role === 'admin' || role === 'manager';
}

/**
 * The tenant ids a caller may aggregate, derived from their own profiles.
 *
 * Scoping happens at the QUERY rather than as a filter afterwards, so there is
 * no window in which a broader set has been read and is being narrowed. This is
 * the function that keeps one customer's shops out of another's portfolio.
 */
export function viewableTenantIds(
  profiles: ReadonlyArray<{ tenantId: string; role: string }>,
): string[] {
  return profiles.filter((p) => canViewShopKpis(p.role)).map((p) => p.tenantId);
}
