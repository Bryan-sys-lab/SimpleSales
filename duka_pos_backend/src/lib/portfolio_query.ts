// The portfolio read, shared by the HTTP endpoint and the live channel.
//
// Extracted the day the live channel was added, because a live snapshot that
// did not come from the same query as `GET /tenant/portfolio` would be a
// second, quietly different answer to "how are my shops doing" — and the phone
// would show one figure on a pull-to-refresh and another on the socket stream.

import { prisma } from './prisma';
import { canViewShopKpis, rollUpPortfolio, type Portfolio, type ShopKpi } from './portfolio';

/** An owner with more shops than this gets the ones set up first, plus a flag
 * saying the rest are missing — never an unbounded number of aggregate
 * queries triggered by one request. */
export const MAX_PORTFOLIO_SHOPS = 50;

export type PortfolioWindow = { from: Date; to: Date };

export type PortfolioReading = {
  shops: ShopKpi[];
  total: Portfolio;
  /** True when the caller owns more shops than the cap will return. */
  truncated: boolean;
};

/**
 * Reads every shop the subject runs, and the whole they add up to.
 *
 * The three invariants from the route are carried here rather than restated by
 * each caller:
 *
 *   1. The tenant list is the caller's OWN profiles, always. Never a request
 *      field, never a query parameter.
 *   2. A cashier gets nothing: `role` is part of the WHERE, not a filter
 *      applied after the read.
 *   3. The read stays bounded at `MAX_PORTFOLIO_SHOPS`.
 */
export async function readPortfolio(
  oidcSubject: string | undefined,
  window: PortfolioWindow,
): Promise<PortfolioReading> {
  const subject = typeof oidcSubject === 'string' && oidcSubject ? oidcSubject : '';
  const profiles = await prisma.profile.findMany({
    where: {
      oidcSubject: subject,
      active: true,
      deletedAt: null,
      role: { in: ['admin', 'manager'] },
    },
    include: { tenant: true },
    orderBy: { createdAt: 'asc' },
    take: MAX_PORTFOLIO_SHOPS,
  });

  // Ownership is asserted per profile by the shared rule; a caller who is a
  // cashier in every shop resolves to an empty portfolio and a zeroed total.
  const owned = profiles.filter((profile) => canViewShopKpis(profile.role));

  const shops = await Promise.all(
    owned.map(async (profile): Promise<ShopKpi> => {
      const where = { tenantId: profile.tenantId, createdAt: { gte: window.from, lte: window.to } };
      const [sales, byPaymentMethod] = await Promise.all([
        prisma.sale.aggregate({
          where,
          _count: { _all: true },
          _sum: { total: true, profit: true },
        }),
        // The dominant tender per shop, not the whole distribution: the phone
        // renders one chip per shop, and a shop that is 80% M-Pesa is
        // distinguishable from one that is 80% cash at a glance. The full
        // breakdown remains available from `/report/sales` per shop.
        prisma.sale.groupBy({
          by: ['paymentMethod'],
          where,
          _count: { _all: true },
          _sum: { total: true },
          orderBy: { _sum: { total: 'desc' } },
          take: 1,
        }),
      ]);

      const transactions = sales._count._all;
      const revenue = Number(sales._sum.total ?? 0);
      return {
        tenantId: profile.tenantId,
        shopName: profile.tenant.shopName,
        role: profile.role,
        revenue,
        profit: Number(sales._sum.profit ?? 0),
        transactions,
        averageBasket: transactions > 0 ? Math.round(revenue / transactions) : 0,
        // An empty shop has no dominant tender, and inventing 'cash' would
        // claim a fact that is not in the data.
        topPaymentMethod: byPaymentMethod[0]?.paymentMethod ?? null,
      };
    }),
  );

  return {
    shops,
    // The whole, so a screen does not have to add the parts and risk
    // disagreeing with them. Rolled from the totals rather than averaged
    // across shops — see lib/portfolio.ts.
    total: rollUpPortfolio(shops),
    truncated: profiles.length === MAX_PORTFOLIO_SHOPS,
  };
}
