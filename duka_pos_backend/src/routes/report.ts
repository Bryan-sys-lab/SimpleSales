import { Router, Request } from 'express';
import { prisma } from '../lib/prisma';
import { Prisma } from '@prisma/client';
import { asyncHandler } from '../lib/http';
import { requireRole } from '../middleware/auth';
import { isReportRangeAllowed } from '../lib/report_range';

const router = Router();

// Reports are read by a small till over a mobile connection, so the row count
// is capped. A busy tenant's ledger outgrows a single JSON body long before it
// outgrows the database, and hydrating the whole 30-day window into Node on
// every request is what made this endpoint unbounded.
const MAX_REPORT_ROWS = 1000;
const MAX_PAGE_SIZE = 500;
const toMinor = (value: unknown): number => {
  const major = Number(value ?? 0);
  return Number.isFinite(major) ? Math.round(major * 100) : 0;
};

router.get('/sales', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res) => {
  const from = typeof req.query.from === 'string' ? new Date(req.query.from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const to = typeof req.query.to === 'string' ? new Date(req.query.to) : new Date();
  // The app's local aggregates and product report use a half-open window
  // [from, to). Keep the sales report identical so an exact boundary sale is
  // never counted twice when adjacent report windows are combined.
  if (!isReportRangeAllowed(from, to)) return res.status(400).json({ error: 'Report range must be between 1 and 366 days' });

  const limit = Math.min(
    Math.max(Number(req.query.limit) || MAX_PAGE_SIZE, 1),
    MAX_PAGE_SIZE,
  );
  const offset = Math.max(Number(req.query.offset) || 0, 0);

  const where = {
    tenantId: req.user!.tenantId,
    ...(req.user!.role === 'cashier' ? { staffId: req.user!.id } : {}),
    createdAt: { gte: from, lt: to },
  };

  // Totals are computed in SQL rather than by reducing every hydrated sale in
  // Node, so the cost of the report is the same however long the ledger gets.
  const [legacyGrouped, tenderGrouped, count, total, profit, vatSummary, operational, daily] = await Promise.all([
    prisma.sale.groupBy({
      by: ['paymentMethod'],
      where: { ...where, salePayments: { none: {} } },
      _count: { _all: true },
      _sum: { total: true },
    }),
    prisma.salePayment.groupBy({
      by: ['method'],
      where: {
        tenantId: req.user!.tenantId,
        sale: {
          tenantId: req.user!.tenantId,
          ...(req.user!.role === 'cashier' ? { staffId: req.user!.id } : {}),
          createdAt: { gte: from, lt: to },
        },
      },
      _count: { _all: true },
      _sum: { amount: true },
    }),
    prisma.sale.count({ where }),
    prisma.sale.aggregate({ where, _sum: { total: true } }),
    prisma.sale.aggregate({ where, _sum: { profit: true } }),
    prisma.$queryRaw<Array<{ vat_total: unknown; taxable_total: unknown }>>(Prisma.sql`
      SELECT COALESCE(SUM(si.vat_amount), 0) AS vat_total,
             COALESCE(SUM(COALESCE(si.taxable_amount, si.qty * si.unit_price)), 0) AS taxable_total
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id AND s.tenant_id = si.tenant_id
       WHERE si.tenant_id = ${req.user!.tenantId}
         AND s.created_at >= ${from}
         AND s.created_at < ${to}
         ${req.user!.role === 'cashier' ? Prisma.sql`AND s.staff_id = ${req.user!.id}` : Prisma.empty}
    `),
    prisma.syncRecord.findMany({
      where: {
        tenantId: req.user!.tenantId,
        kind: { in: ['expenses'] },
        createdAt: { gte: from, lt: to },
      },
      select: { payload: true },
      take: 5000,
    }),
    prisma.$queryRaw<Array<{
      day: string;
      sales: unknown;
      profit: unknown;
      transactions: number;
    }>>(Prisma.sql`
      SELECT
        TO_CHAR(DATE_TRUNC('day', s.created_at), 'YYYY-MM-DD') AS day,
        COALESCE(SUM(s.total), 0) AS sales,
        COALESCE(SUM(s.profit), 0) AS profit,
        COUNT(*)::int AS transactions
      FROM sales s
      WHERE s.tenant_id = ${req.user!.tenantId}
        AND s.created_at >= ${from}
        AND s.created_at < ${to}
        ${req.user!.role === 'cashier' ? Prisma.sql`AND s.staff_id = ${req.user!.id}` : Prisma.empty}
      GROUP BY DATE_TRUNC('day', s.created_at)
      ORDER BY DATE_TRUNC('day', s.created_at) ASC
    `),
  ]);

  // Expenses are uploaded as opaque, idempotent operational records because
  // the till remains the detailed source of truth. Read only posted expenses
  // in this bounded window; never let a draft or voided payout change net
  // profit in an online report.
  const expensesMinor = operational.reduce((sum, row) => {
    const payload = row.payload as Record<string, unknown>;
    if (payload.status !== 'posted') return sum;
    const amount = Number(payload.amountMinor ?? 0);
    return sum + (Number.isFinite(amount) ? Math.round(amount) : 0);
  }, 0);

  const byPaymentMethod: Record<string, number> = {};
  const paymentMix: Array<{ method: string; sales: number; transactions: number }> = [];
  for (const row of legacyGrouped) {
    const method = row.paymentMethod || 'cash';
    byPaymentMethod[method] = toMinor(row._sum.total);
    paymentMix.push({
      method,
      sales: toMinor(row._sum.total),
      transactions: row._count._all,
    });
  }
  for (const row of tenderGrouped) {
    const method = row.method || 'cash';
    const amount = toMinor(row._sum.amount);
    byPaymentMethod[method] = (byPaymentMethod[method] ?? 0) + amount;
    paymentMix.push({
      method,
      sales: amount,
      transactions: row._count._all,
    });
  }
  // A tenant may have both legacy sale-level rows and newer tender rows for
  // the same method. Present one stable legend entry per method.
  const mergedPaymentMix = new Map<string, { method: string; sales: number; transactions: number }>();
  for (const row of paymentMix) {
    const current = mergedPaymentMix.get(row.method);
    if (current) {
      current.sales += row.sales;
      current.transactions += row.transactions;
    } else {
      mergedPaymentMix.set(row.method, { ...row });
    }
  }
  paymentMix.splice(0, paymentMix.length, ...mergedPaymentMix.values());

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
      total: toMinor(total._sum.total),
      profit: toMinor(profit._sum.profit),
      expensesMinor,
      vatMinor: toMinor(vatSummary[0]?.vat_total),
      taxableMinor: toMinor(vatSummary[0]?.taxable_total),
      byPaymentMethod,
      paymentMix,
    },
    daily: daily.map((row) => ({
      day: row.day,
      sales: toMinor(row.sales),
      profit: toMinor(row.profit),
      transactions: Number(row.transactions ?? 0),
    })),
    pagination: {
      limit,
      offset,
      returned: sales.length,
      hasMore: offset + sales.length < Math.min(count, MAX_REPORT_ROWS),
      // Callers that need to page past the cap must narrow the date range
      // rather than pull an unbounded history into one response.
      truncated: count > MAX_REPORT_ROWS,
    },
    sales: sales.map((sale) => ({
      ...sale,
      total: toMinor(sale.total),
      profit: toMinor(sale.profit),
    })),
  });
}));

router.get('/sales/:saleId', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res) => {
  const saleId = Array.isArray(req.params.saleId) ? req.params.saleId[0] : req.params.saleId;
  const sale = await prisma.sale.findFirst({
    where: {
      id: saleId,
      tenantId: req.user!.tenantId,
      ...(req.user!.role === 'cashier' ? { staffId: req.user!.id } : {}),
    },
    include: {
      items: {
        select: {
          productName: true, qty: true, unitPrice: true, unitCost: true,
          vatAmount: true, taxableAmount: true, portion: true, portionMl: true,
        },
      },
      salePayments: {
        select: { method: true, amount: true, tendered: true, change: true, reference: true, status: true },
      },
    },
  });
  if (!sale) return res.status(404).json({ error: 'Sale not found' });
  return res.json({
    id: sale.id,
    createdAt: sale.createdAt.toISOString(),
    staffName: sale.staffName,
    paymentMethod: sale.paymentMethod,
    paymentReference: sale.paymentReference,
    total: toMinor(sale.total),
    profit: toMinor(sale.profit),
    buyerName: sale.buyerName,
    buyerTin: sale.buyerTin,
    items: sale.items.map((item) => ({
      productName: item.productName,
      qty: Number(item.qty),
      unitPrice: toMinor(item.unitPrice),
      unitCost: toMinor(item.unitCost),
      vatMinor: toMinor(item.vatAmount),
      taxableMinor: toMinor(item.taxableAmount),
      portion: item.portion,
      portionMl: item.portionMl,
    })),
    tenders: sale.salePayments.map((tender) => ({
      method: tender.method,
      amount: toMinor(tender.amount),
      tendered: tender.tendered == null ? null : toMinor(tender.tendered),
      change: tender.change == null ? null : toMinor(tender.change),
      reference: tender.reference,
      status: tender.status,
    })),
  });
}));

// Product analytics uses the same tenant/date scope as the sales report. The
// aggregation stays in Postgres so an online manager can drill into a large
// catalogue without downloading every sale item to the phone.
router.get('/products', requireRole('admin', 'manager'), asyncHandler(async (req: Request, res) => {
  const from = typeof req.query.from === 'string' ? new Date(req.query.from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const to = typeof req.query.to === 'string' ? new Date(req.query.to) : new Date();
  if (!isReportRangeAllowed(from, to)) {
    return res.status(400).json({ error: 'Report range must be between 1 and 366 days' });
  }

  const tenantId = req.user!.tenantId;
  const productId = typeof req.query.productId === 'string' ? req.query.productId : null;
  const filters = [
    Prisma.sql`si.tenant_id = ${tenantId}`,
    Prisma.sql`s.tenant_id = ${tenantId}`,
    Prisma.sql`s.created_at >= ${from}`,
    Prisma.sql`s.created_at < ${to}`,
    ...(productId ? [Prisma.sql`si.product_id = ${productId}`] : []),
  ];
  const where = Prisma.join(filters, ' AND ');

  const [products, missingCostProducts, coverage] = await Promise.all([
    prisma.$queryRaw<Array<{
    product_id: string | null;
    product_name: string;
    units: number;
    net_sales: string;
    covered_sales: string;
    gross_profit: string;
    transactions: number;
  }>>(Prisma.sql`
    SELECT si.product_id,
           si.product_name,
           SUM(si.qty)::float8 AS units,
           COALESCE(SUM(si.qty * si.unit_price), 0)::text AS net_sales,
           COALESCE(SUM(CASE WHEN COALESCE(p.cost_price, 0) > 0
                             THEN si.qty * si.unit_price ELSE 0 END), 0)::text AS covered_sales,
           COALESCE(SUM(COALESCE(si.taxable_amount, si.qty * si.unit_price) -
                        si.qty * si.unit_cost), 0)::text AS gross_profit,
           COUNT(DISTINCT si.sale_id)::int AS transactions
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id AND s.tenant_id = si.tenant_id
      LEFT JOIN products p ON p.id = si.product_id AND p.tenant_id = si.tenant_id
     WHERE ${where}
     GROUP BY si.product_id, si.product_name
     ORDER BY SUM(si.qty * si.unit_price) DESC
     LIMIT 500
  `),
    prisma.product.findMany({
      where: { tenantId, active: true, costPrice: { lte: 0 } },
      select: { name: true },
      orderBy: { name: 'asc' },
      take: 500,
    }),
    // Coverage is a report total, not a top-products display metric. Keep it
    // independent of the 500-row response cap or a large catalogue will make
    // the owner's revenue and margin coverage silently too small.
    prisma.$queryRaw<Array<{ total_revenue: string; covered_revenue: string }>>(
      Prisma.sql`
        SELECT COALESCE(SUM(si.qty * si.unit_price), 0)::text AS total_revenue,
               COALESCE(SUM(CASE WHEN COALESCE(p.cost_price, 0) > 0
                                 THEN si.qty * si.unit_price ELSE 0 END), 0)::text
                 AS covered_revenue
          FROM sale_items si
          JOIN sales s ON s.id = si.sale_id AND s.tenant_id = si.tenant_id
          LEFT JOIN products p ON p.id = si.product_id AND p.tenant_id = si.tenant_id
         WHERE ${where}
      `,
    ),
  ]);

  const productRows = products.map((row) => ({
    ...row,
    net_sales: toMinor(row.net_sales),
    covered_sales: toMinor(row.covered_sales),
    gross_profit: toMinor(row.gross_profit),
  }));
  if (!productId) return res.json({
    from: from.toISOString(),
    to: to.toISOString(),
    products: productRows,
    costCoverage: {
      coveredRevenueMinor: toMinor(coverage[0]?.covered_revenue),
      totalRevenueMinor: toMinor(coverage[0]?.total_revenue),
      missingCostProductNames: missingCostProducts.map((row) => row.name),
    },
  });

  const [staff, payments, hourly, daily, records, companions, stockMovements] = await Promise.all([
    prisma.$queryRaw<Array<{ staff_name: string; transactions: number; net_sales: string }>>(Prisma.sql`
      SELECT s.staff_name, COUNT(DISTINCT s.id)::int AS transactions,
             COALESCE(SUM(si.qty * si.unit_price), 0)::text AS net_sales
        FROM sale_items si JOIN sales s ON s.id = si.sale_id AND s.tenant_id = si.tenant_id
       WHERE ${where}
       GROUP BY s.staff_name ORDER BY SUM(si.qty * si.unit_price) DESC
    `),
    // A product can be paid by more than one tender. Allocate each tender
    // against that sale's product-line total, so the product drill-down keeps
    // the same payment mix as the checkout ledger instead of collapsing every
    // split sale to the sale-level `payment_method` summary.
    prisma.$queryRaw<Array<{ payment_method: string; transactions: number; net_sales: string }>>(Prisma.sql`
      WITH product_sales AS (
        SELECT s.id AS sale_id,
               s.tenant_id,
               s.total AS sale_total,
               s.payment_method,
               SUM(si.qty * si.unit_price) AS product_total
          FROM sale_items si
          JOIN sales s ON s.id = si.sale_id AND s.tenant_id = si.tenant_id
         WHERE ${where}
         GROUP BY s.id, s.tenant_id, s.total, s.payment_method
      )
      SELECT COALESCE(sp.method, ps.payment_method) AS payment_method,
             COUNT(DISTINCT ps.sale_id)::int AS transactions,
             COALESCE(SUM(
               CASE
                 WHEN sp.id IS NULL OR ps.sale_total = 0 THEN ps.product_total
                 ELSE ps.product_total * sp.amount / ps.sale_total
               END
             ), 0)::text AS net_sales
        FROM product_sales ps
        LEFT JOIN sale_payments sp
          ON sp.sale_id = ps.sale_id AND sp.tenant_id = ps.tenant_id
       GROUP BY COALESCE(sp.method, ps.payment_method)
       ORDER BY SUM(
         CASE
           WHEN sp.id IS NULL OR ps.sale_total = 0 THEN ps.product_total
           ELSE ps.product_total * sp.amount / ps.sale_total
         END
       ) DESC
    `),
    prisma.$queryRaw<Array<{ hour: number; units: number; transactions: number; net_sales: string }>>(Prisma.sql`
      SELECT EXTRACT(HOUR FROM s.created_at)::int AS hour,
             COALESCE(SUM(si.qty), 0)::float8 AS units,
             COUNT(DISTINCT s.id)::int AS transactions,
             COALESCE(SUM(si.qty * si.unit_price), 0)::text AS net_sales
        FROM sale_items si JOIN sales s ON s.id = si.sale_id AND s.tenant_id = si.tenant_id
       WHERE ${where}
       GROUP BY EXTRACT(HOUR FROM s.created_at)
       ORDER BY hour
    `),
    prisma.$queryRaw<Array<{ day: string; transactions: number; net_sales: string; gross_profit: string }>>(Prisma.sql`
      SELECT TO_CHAR(s.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS day,
             COUNT(DISTINCT s.id)::int AS transactions,
             COALESCE(SUM(si.qty * si.unit_price), 0)::text AS net_sales,
             COALESCE(SUM(COALESCE(si.taxable_amount, si.qty * si.unit_price) -
                          si.qty * si.unit_cost), 0)::text AS gross_profit
        FROM sale_items si JOIN sales s ON s.id = si.sale_id AND s.tenant_id = si.tenant_id
       WHERE ${where}
       GROUP BY day
       ORDER BY day
    `),
    prisma.$queryRaw<Array<{ sale_id: string; created_at: Date; staff_name: string; payment_method: string; sale_total: string; product_sales: string }>>(Prisma.sql`
      SELECT s.id AS sale_id, s.created_at, s.staff_name, s.payment_method,
             s.total::text AS sale_total,
             COALESCE(SUM(si.qty * si.unit_price), 0)::text AS product_sales
        FROM sale_items si JOIN sales s ON s.id = si.sale_id AND s.tenant_id = si.tenant_id
       WHERE ${where}
       GROUP BY s.id, s.created_at, s.staff_name, s.payment_method, s.total
       ORDER BY s.created_at DESC, s.id DESC
       LIMIT 200
    `),
    prisma.$queryRaw<Array<{ product_id: string; product_name: string; baskets: number; units: number }>>(Prisma.sql`
      SELECT si2.product_id, MAX(si2.product_name) AS product_name,
             COUNT(DISTINCT s.id)::int AS baskets,
             COALESCE(SUM(si2.qty), 0)::float8 AS units
        FROM sale_items si1
        JOIN sales s ON s.id = si1.sale_id AND s.tenant_id = si1.tenant_id
        JOIN sale_items si2 ON si2.sale_id = si1.sale_id AND si2.tenant_id = si1.tenant_id
       WHERE si1.tenant_id = ${tenantId}
         AND s.tenant_id = ${tenantId}
         AND s.created_at >= ${from}
         AND s.created_at < ${to}
         AND si1.product_id = ${productId}
         AND si2.product_id IS NOT NULL
         AND si2.product_id <> ${productId}
       GROUP BY si2.product_id
       ORDER BY baskets DESC, units DESC
       LIMIT 5
    `),
    // Stock movements are append-only sync records rather than product
    // balances. Reading the same ledger here keeps the online drill-down
    // explainable when the owner is looking at a device that did the work
    // offline. The product id in the payload is the server product UUID.
    prisma.$queryRaw<Array<{ payload: Prisma.JsonValue }>>(Prisma.sql`
      SELECT payload
        FROM sync_records
       WHERE tenant_id = ${tenantId}
         AND kind = 'stock-movements'
         AND payload->>'productId' = ${productId}
         AND (payload->>'createdAt')::timestamptz >= ${from}
         AND (payload->>'createdAt')::timestamptz < ${to}
       ORDER BY (payload->>'createdAt')::timestamptz DESC, id DESC
       LIMIT 200
    `),
  ]);
  return res.json({
    from: from.toISOString(),
    to: to.toISOString(),
    products: productRows,
    staff: staff.map((row) => ({ ...row, net_sales: toMinor(row.net_sales) })),
    payments: payments.map((row) => ({ ...row, net_sales: toMinor(row.net_sales) })),
    hourly: hourly.map((row) => ({ ...row, net_sales: toMinor(row.net_sales) })),
    daily: daily.map((row) => ({
      ...row,
      net_sales: toMinor(row.net_sales),
      gross_profit: toMinor(row.gross_profit),
    })),
    records: records.map((row) => ({
      ...row,
      created_at: row.created_at.toISOString(),
      sale_total: toMinor(row.sale_total),
      product_sales: toMinor(row.product_sales),
    })),
    companions: companions.map((row) => ({
      product_id: row.product_id,
      product_name: row.product_name,
      baskets: row.baskets,
      units: row.units,
    })),
    stockTimeline: stockMovements.map(({ payload }) => {
      const row = payload as Record<string, unknown>;
      return {
        uuid: row.uuid,
        created_at: row.createdAt,
        product_id: -1,
        variant_id: row.variantId ?? null,
        movement_type: row.movementType,
        qty_delta: row.qtyDelta,
        unit_cost_minor: row.unitCostMinor ?? null,
        reference_type: row.referenceType ?? null,
        reference_id: row.referenceId ?? null,
        batch_id: row.batchId ?? null,
        staff_id: row.staffId ?? null,
        staff_name: row.staffName ?? null,
        note: row.note ?? null,
        balance_after: row.balanceAfter,
      };
    }),
  });
}));

export default router;
