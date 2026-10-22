// The admin dashboard's arithmetic: pure functions, no Prisma, no Express.
//
// The dashboard's numbers are the ones an operator will screenshot and send to
// a shop, and a total computed in JS on hydrated rows is a total that silently
// disagrees with the SQL aggregates beside it — which is how an operator ends
// up quoting a shop's weekly revenue as 1,204,500 when the database says
// 1,402,500. Kept here so every roll-up is testable without a database, and
// every rule about outliers is stated once.
//
// The one rule this exists to enforce: an aggregate is computed from the
// WHOLE's totals, never averaged from the parts' averages, and an average over
// an empty set is a zero rather than a NaN.

/** One sale as the dashboard needs it. */
export interface SaleRow {
  tenantId: string;
  tenantName?: string;
  createdAt: Date | string;
  total: number;
  profit: number;
  paymentMethod: string | null;
  /** The id of the profile that rang the sale, when known. */
  staffId?: string | null;
  staffName?: string | null;
  itemCount?: number;
}

export interface SalesTotals {
  salesCount: number;
  totalSales: number;
  totalProfit: number;
  averageBasket: number;
  /** Margin on turnover, as a percentage. Zero when nothing has sold. */
  marginPercent: number;
  /** Sales divided by days, over the span of the data. A day with no sales is
   * a zero, not a division by the number of active days — a shop that closed
   * for two days does not get double its apparent rate. */
  averagePerDay: number;
}

/** A day's row of the series. */
export interface DayBucket {
  day: string;
  salesCount: number;
  totalSales: number;
  totalProfit: number;
}

/**
 * Dates only, without a time.
 *
 * The ISO date is the bucket key everywhere: a local date string is what a
 * shop owner reads on a chart, and a UTC instant is what a database stores.
 * Collapsing them at the boundary of a midnight the owner cares about is the
 * one common way a daily chart lies.
 */
export function dayKeyOf(value: Date | string): string {
  const date = typeof value === 'string' ? new Date(value) : value;
  if (Number.isNaN(date.getTime())) return 'unknown';
  return date.toISOString().slice(0, 10);
}

/** Sums a set of sales into the totals an operator reads. */
export function rollUpSales(sales: readonly SaleRow[]): SalesTotals {
  const totals = sales.reduce(
    (acc, sale) => ({
      salesCount: acc.salesCount + 1,
      totalSales: acc.totalSales + sale.total,
      totalProfit: acc.totalProfit + sale.profit,
    }),
    { salesCount: 0, totalSales: 0, totalProfit: 0 },
  );

  return {
    salesCount: totals.salesCount,
    totalSales: totals.totalSales,
    totalProfit: totals.totalProfit,
    averageBasket: totals.salesCount > 0 ? Math.round(totals.totalSales / totals.salesCount) : 0,
    marginPercent:
      totals.totalSales > 0 ? Math.round((totals.totalProfit / totals.totalSales) * 1000) / 10 : 0,
    averagePerDay: averagePerDay(sales),
  };
}

/**
 * The daily rate, spread over the span the data covers rather than the days
 * that happen to have sales.
 *
 * `from`/`to` bound the window when the caller supplies them, because a shop
 * that opened on Wednesday has sold for one day in a week's report — and
 * quoting its weekly average as (total ÷ 7) understates it sevenfold.
 */
export function averagePerDay(
  sales: readonly SaleRow[],
  window?: { from: Date | string; to: Date | string },
): number {
  if (sales.length === 0) return 0;
  const stamps = sales.map((sale) => new Date(sale.createdAt).getTime()).filter((n) => Number.isFinite(n));
  if (stamps.length === 0) return 0;
  const first = window ? new Date(window.from).getTime() : Math.min(...stamps);
  const last = window ? new Date(window.to).getTime() : Math.max(...stamps);
  const span = Math.max(1, Math.ceil((last - first) / (24 * 60 * 60 * 1000)) + 1);
  return Math.round(sales.reduce((sum, sale) => sum + sale.total, 0) / span);
}

/** The daily series: one bucket per day in the window, including the empty ones. */
export function dailySeries(
  sales: readonly SaleRow[],
  window: { from: Date | string; to: Date | string },
): DayBucket[] {
  const byDay = new Map<string, { salesCount: number; totalSales: number; totalProfit: number }>();
  for (const sale of sales) {
    const key = dayKeyOf(sale.createdAt);
    const bucket = byDay.get(key) ?? { salesCount: 0, totalSales: 0, totalProfit: 0 };
    bucket.salesCount += 1;
    bucket.totalSales += sale.total;
    bucket.totalProfit += sale.profit;
    byDay.set(key, bucket);
  }

  // Walk the whole span rather than the days that appear, so a gap renders as
  // a zero: a missing day in a revenue chart is a day the shop sold nothing,
  // and a chart that skips it draws a line the shop never had.
  const from = new Date(window.from);
  const to = new Date(window.to);
  if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime()) || to < from) {
    return [...byDay.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([day, bucket]) => ({ day, ...bucket }));
  }

  const buckets: DayBucket[] = [];
  for (const cursor = new Date(from); cursor <= to; cursor.setUTCDate(cursor.getUTCDate() + 1)) {
    const key = cursor.toISOString().slice(0, 10);
    const bucket = byDay.get(key);
    buckets.push({
      day: key,
      salesCount: bucket?.salesCount ?? 0,
      totalSales: bucket?.totalSales ?? 0,
      totalProfit: bucket?.totalProfit ?? 0,
    });
  }
  return buckets;
}

export interface PaymentMixRow {
  method: string;
  salesCount: number;
  totalSales: number;
  /** Share of turnover, as a percentage of this set's total. */
  sharePercent: number;
}

/**
 * The tender mix, ordered by turnover.
 *
 * `cash` is spelled in full rather than left as an empty string: a
 * `paymentMethod` of '' reaches the dashboard from a sale recorded before the
 * column was mandatory, and an unnamed slice in a pie chart is a slice nobody
 * can identify.
 */
export function paymentMix(sales: readonly SaleRow[]): PaymentMixRow[] {
  const byMethod = new Map<string, { salesCount: number; totalSales: number }>();
  for (const sale of sales) {
    const method = normalizeMethod(sale.paymentMethod);
    const row = byMethod.get(method) ?? { salesCount: 0, totalSales: 0 };
    row.salesCount += 1;
    row.totalSales += sale.total;
    byMethod.set(method, row);
  }
  const totalSales = [...byMethod.values()].reduce((sum, row) => sum + row.totalSales, 0);
  return [...byMethod.entries()]
    .map(([method, row]) => ({
      method,
      salesCount: row.salesCount,
      totalSales: row.totalSales,
      sharePercent: totalSales > 0 ? Math.round((row.totalSales / totalSales) * 1000) / 10 : 0,
    }))
    .sort((a, b) => b.totalSales - a.totalSales);
}

/** The wire spelling of a tender, or `cash` when the row carries none. */
export function normalizeMethod(method: string | null | undefined): string {
  const value = (method ?? '').trim().toLowerCase();
  return value.length > 0 ? value : 'cash';
}

export interface StaffRow {
  staffId: string | null;
  staffName: string;
  salesCount: number;
  totalSales: number;
  averageBasket: number;
}

/**
 * What each till operator rang up.
 *
 * A cashier's standing, so the name is NOT optional: an unnamed operator is
 * rendered as 'Unknown till' rather than dropped, because a leaderboard that
 * silently omits a row for a sale that certainly happened is a leaderboard that
 * hides a staffing problem.
 */
export function staffLeaderboard(sales: readonly SaleRow[]): StaffRow[] {
  const byStaff = new Map<string, { staffName: string; salesCount: number; totalSales: number }>();
  for (const sale of sales) {
    const staffId = sale.staffId ?? '';
    const staffName = sale.staffName?.trim() || 'Unknown till';
    const key = staffId.length > 0 ? staffId : `name:${staffName}`;
    const row = byStaff.get(key) ?? { staffName, salesCount: 0, totalSales: 0 };
    row.salesCount += 1;
    row.totalSales += sale.total;
    byStaff.set(key, row);
  }
  return [...byStaff.entries()]
    .map(([key, row]) => ({
      staffId: key.startsWith('name:') ? null : key,
      staffName: row.staffName,
      salesCount: row.salesCount,
      totalSales: row.totalSales,
      averageBasket: row.salesCount > 0 ? Math.round(row.totalSales / row.salesCount) : 0,
    }))
    .sort((a, b) => b.totalSales - a.totalSales);
}

export interface TenantRow {
  tenantId: string;
  tenantName: string;
  totals: SalesTotals;
  paymentMix: PaymentMixRow[];
}

/**
 * Per-shop drill-down, ordered by turnover.
 *
 * The same roll-up as the portfolio endpoint applies, from the same helper —
 * a dashboard whose per-shop figure differs from the phone's is a dashboard
 * nobody trusts, and the two computations agreeing is the whole reason this
 * file exists.
 */
export function tenantBreakdown(sales: readonly SaleRow[]): TenantRow[] {
  const byTenant = new Map<string, SaleRow[]>();
  for (const sale of sales) {
    const key = sale.tenantId;
    byTenant.set(key, [...(byTenant.get(key) ?? []), sale]);
  }
  return [...byTenant.entries()]
    .map(([tenantId, rows]) => ({
      tenantId,
      tenantName: rows.find((row) => row.tenantName)?.tenantName ?? tenantId,
      totals: rollUpSales(rows),
      paymentMix: paymentMix(rows),
    }))
    .sort((a, b) => b.totals.totalSales - a.totals.totalSales);
}

/**
 * The whole drill-down for a window: totals, series, mix, staff, per shop.
 *
 * The shape the dashboard's client reads directly, so it is a function with
 * stable keys rather than a shape assembled at the call site — an
 * agent-consumable endpoint whose keys depend on which query ran is an
 * endpoint nobody can script against.
 */
export interface Drilldown {
  from: string | null;
  to: string | null;
  totals: SalesTotals;
  byDay: DayBucket[];
  paymentMix: PaymentMixRow[];
  staff: StaffRow[];
  byTenant: TenantRow[];
  /** Shops present in the data, so a client can label a zero-row shop. */
  shopCount: number;
}

export function buildDrilldown(
  sales: readonly SaleRow[],
  window?: { from?: Date | string; to?: Date | string },
): Drilldown {
  return {
    from: window?.from ? new Date(window.from).toISOString() : null,
    to: window?.to ? new Date(window.to).toISOString() : null,
    totals: rollUpSales(sales),
    byDay: window?.from && window.to ? dailySeries(sales, { from: window.from, to: window.to }) : [],
    paymentMix: paymentMix(sales),
    staff: staffLeaderboard(sales),
    byTenant: tenantBreakdown(sales),
    shopCount: tenantBreakdown(sales).length,
  };
}

/**
 * The window a drill-down covers when the caller did not ask for one.
 *
 * Thirty days: long enough for a weekly pattern to show, short enough that a
 * shop's first month of trading is not flattened into an average that hides it.
 */
export function defaultDrilldownWindow(now: Date = new Date()): { from: Date; to: Date } {
  return { from: new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000), to: now };
}

/**
 * Whether a requested window is usable at all.
 *
 * A reversed range and an unparseable date are the same failure to a caller
 * that typed one of them, and both produce an empty series rather than an
 * error — an operator exploring the dashboard should not be told off for
 * dragging a date picker the wrong way.
 */
export function isWindowUsable(from: Date | string | undefined, to: Date | string | undefined): boolean {
  if (!from || !to) return false;
  const first = new Date(from).getTime();
  const last = new Date(to).getTime();
  if (!Number.isFinite(first) || !Number.isFinite(last)) return false;
  return first <= last;
}
