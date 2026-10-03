import { Router, Request } from 'express';
import { prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import { requireRole } from '../middleware/auth';

const router = Router();

// Reports are read by a small till over a mobile connection, so the row count
// is capped. A busy tenant's ledger outgrows a single JSON body long before it
// outgrows the database, and hydrating the whole 30-day window into Node on
// every request is what made this endpoint unbounded.
const MAX_REPORT_ROWS = 1000;
const MAX_PAGE_SIZE = 500;

router.get('/sales', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res) => {
  const from = typeof req.query.from === 'string' ? new Date(req.query.from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const to = typeof req.query.to === 'string' ? new Date(req.query.to) : new Date();
  if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from > to) return res.status(400).json({ error: 'Invalid report date range' });

  const limit = Math.min(
    Math.max(Number(req.query.limit) || MAX_PAGE_SIZE, 1),
    MAX_PAGE_SIZE,
  );
  const offset = Math.max(Number(req.query.offset) || 0, 0);

  const where = {
    tenantId: req.user!.tenantId,
    ...(req.user!.role === 'cashier' ? { staffId: req.user!.id } : {}),
    createdAt: { gte: from, lte: to },
  };

  // Totals are computed in SQL rather than by reducing every hydrated sale in
  // Node, so the cost of the report is the same however long the ledger gets.
  const [grouped, count, total, profit] = await Promise.all([
    prisma.sale.groupBy({
      by: ['paymentMethod'],
      where,
      _count: { _all: true },
      _sum: { total: true },
    }),
    prisma.sale.count({ where }),
    prisma.sale.aggregate({ where, _sum: { total: true } }),
    prisma.sale.aggregate({ where, _sum: { profit: true } }),
  ]);

  const byPaymentMethod: Record<string, number> = {};
  for (const row of grouped) {
    byPaymentMethod[row.paymentMethod || 'cash'] = Number(row._sum.total ?? 0);
  }

  const sales = await prisma.sale.findMany({
    where,
    select: { id: true, total: true, profit: true, paymentMethod: true, staffName: true, createdAt: true },
    orderBy: { createdAt: 'asc' },
    take: limit,
    skip: offset,
  });

  res.json({
    from: from.toISOString(),
    to: to.toISOString(),
    totals: {
      count,
      total: Number(total._sum.total ?? 0),
      profit: Number(profit._sum.profit ?? 0),
      byPaymentMethod,
    },
    pagination: {
      limit,
      offset,
      returned: sales.length,
      hasMore: offset + sales.length < Math.min(count, MAX_REPORT_ROWS),
      // Callers that need to page past the cap must narrow the date range
      // rather than pull an unbounded history into one response.
      truncated: count > MAX_REPORT_ROWS,
    },
    sales,
  });
}));

export default router;
