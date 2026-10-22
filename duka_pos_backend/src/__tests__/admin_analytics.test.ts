// The dashboard's arithmetic, asserted without a database.
//
// The properties under test are the ones an operator would have to take on
// trust otherwise: that a whole is summed from its parts and never averaged
// from their averages, that a day with no sales renders as a zero rather than
// vanishing, that an empty set produces zeros rather than NaN, and that the
// per-shop breakdown agrees with the roll-up it is built from — because a
// dashboard that disagrees with the phone in a shop owner's pocket is a
// dashboard nobody will look at twice.

import { describe, expect, it } from 'vitest';
import {
  averagePerDay,
  buildDrilldown,
  dailySeries,
  defaultDrilldownWindow,
  isWindowUsable,
  normalizeMethod,
  paymentMix,
  rollUpSales,
  staffLeaderboard,
  tenantBreakdown,
  type SaleRow,
} from '../lib/admin_analytics.js';

const AT = '2026-10-05T09:30:00.000Z';

function sale(over: Partial<SaleRow> = {}): SaleRow {
  return {
    tenantId: 't1',
    createdAt: AT,
    total: 1000,
    profit: 400,
    paymentMethod: 'cash',
    ...over,
  };
}

describe('roll-up', () => {
  it('sums the parts, and never averages their averages', () => {
    const totals = rollUpSales([
      sale({ total: 1000, profit: 400 }),
      sale({ total: 2000, profit: 800 }),
    ]);
    expect(totals.salesCount).toBe(2);
    expect(totals.totalSales).toBe(3000);
    expect(totals.totalProfit).toBe(1200);
    // The mean of the two baskets equals the average basket here, but the
    // point is the computation: from the whole's totals, not from the parts.
    expect(totals.averageBasket).toBe(1500);
  });

  it('reports margin on turnover, not on cost', () => {
    const totals = rollUpSales([sale({ total: 1000, profit: 250 })]);
    expect(totals.marginPercent).toBe(25);
  });

  it('returns zeros and no NaN for an empty set', () => {
    const totals = rollUpSales([]);
    expect(totals).toEqual({
      salesCount: 0,
      totalSales: 0,
      totalProfit: 0,
      averageBasket: 0,
      marginPercent: 0,
      averagePerDay: 0,
    });
    expect(Number.isNaN(totals.averageBasket)).toBe(false);
  });

  it('averages over the span of the data, not over the days that sold', () => {
    const sales = [
      sale({ createdAt: '2026-10-01T09:00:00.000Z' }),
      sale({ createdAt: '2026-10-05T09:00:00.000Z' }),
    ];
    // Five days of trading, two with sales: the rate is total ÷ 5, not ÷ 2.
    expect(averagePerDay(sales)).toBe(400);
  });

  it('uses the caller window when given one, inclusive of both ends', () => {
    // Oct 1 to Oct 8 is eight days of trading, not seven: a shop that opened
    // on the 8th sold on the 8th.
    const sales = [sale({ createdAt: '2026-10-05T09:00:00.000Z' })];
    expect(
      averagePerDay(sales, { from: '2026-10-01T00:00:00.000Z', to: '2026-10-08T00:00:00.000Z' }),
    ).toBe(125);
  });
});

describe('the daily series', () => {
  const window = { from: '2026-10-01T00:00:00.000Z', to: '2026-10-04T00:00:00.000Z' };

  it('includes a day with no sales, as a zero', () => {
    const series = dailySeries([sale({ createdAt: '2026-10-01T10:00:00.000Z' })], window);
    expect(series.map((bucket) => bucket.day)).toEqual([
      '2026-10-01',
      '2026-10-02',
      '2026-10-03',
      '2026-10-04',
    ]);
    // A missing day is a day the shop sold nothing, so the chart shows a hole
    // rather than skipping the date and drawing a line the shop never had.
    expect(series[1]).toEqual({ day: '2026-10-02', salesCount: 0, totalSales: 0, totalProfit: 0 });
  });

  it('sums a day with several sales', () => {
    const series = dailySeries(
      [
        sale({ createdAt: '2026-10-01T08:00:00.000Z', total: 500 }),
        sale({ createdAt: '2026-10-01T12:00:00.000Z', total: 700 }),
      ],
      window,
    );
    expect(series[0]).toMatchObject({ day: '2026-10-01', salesCount: 2, totalSales: 1200 });
  });

  it('falls back to the days present when the window is unusable', () => {
    const series = dailySeries([sale({ createdAt: '2026-10-01T10:00:00.000Z' })], {
      from: 'nonsense',
      to: 'also nonsense',
    });
    expect(series).toEqual([{ day: '2026-10-01', salesCount: 1, totalSales: 1000, totalProfit: 400 }]);
  });

  it('treats an unparseable date as an unknown bucket', () => {
    const series = dailySeries([sale({ createdAt: 'not a date' })], { from: 'nonsense', to: 'nonsense' });
    expect(series[0].day).toBe('unknown');
  });
});

describe('the payment mix', () => {
  it('spells out the tenders and their shares of turnover', () => {
    const mix = paymentMix([
      sale({ paymentMethod: 'mpesa', total: 7000 }),
      sale({ paymentMethod: 'cash', total: 3000 }),
    ]);
    // By turnover, so the dominant tender is first: the pie needs a leading
    // slice to label, not to guess at.
    expect(mix.map((row) => row.method)).toEqual(['mpesa', 'cash']);
    expect(mix[0]).toEqual({ method: 'mpesa', salesCount: 1, totalSales: 7000, sharePercent: 70 });
    expect(mix[1].sharePercent).toBe(30);
  });

  it('names an empty tender cash, because that is what it was', () => {
    // A sale recorded before the column was mandatory has no method; labelling
    // the slice '' is a slice nobody can identify.
    const mix = paymentMix([sale({ paymentMethod: null, total: 1000 })]);
    expect(mix[0].method).toBe('cash');
    expect(normalizeMethod(null)).toBe('cash');
    expect(normalizeMethod('  M-PESA ')).toBe('m-pesa');
  });

  it('shares sum to 100 over the set', () => {
    const mix = paymentMix([
      sale({ paymentMethod: 'cash', total: 1111 }),
      sale({ paymentMethod: 'mpesa', total: 2222 }),
      sale({ paymentMethod: 'card', total: 3333 }),
    ]);
    const sum = mix.reduce((acc, row) => acc + row.sharePercent, 0);
    // Rounded to a tenth, so the sum is 100 within the rounding.
    expect(Math.abs(sum - 100)).toBeLessThan(0.5);
  });

  it('is empty, and not NaN, for an empty set', () => {
    expect(paymentMix([])).toEqual([]);
  });
});

describe('the staff leaderboard', () => {
  it('ranks by turnover', () => {
    const staff = staffLeaderboard([
      sale({ staffId: 's1', staffName: 'Amina', total: 1000 }),
      sale({ staffId: 's2', staffName: 'Joseph', total: 2500 }),
    ]);
    expect(staff.map((row) => row.staffName)).toEqual(['Joseph', 'Amina']);
    expect(staff[0].totalSales).toBe(2500);
  });

  it('keeps an unnamed till, rather than dropping the sale', () => {
    // A leaderboard that omits a row for a sale that certainly happened hides
    // a staffing problem behind a rounding difference.
    const staff = staffLeaderboard([sale({ staffId: null, staffName: null })]);
    expect(staff).toEqual([
      { staffId: null, staffName: 'Unknown till', salesCount: 1, totalSales: 1000, averageBasket: 1000 },
    ]);
  });

  it('separates two cashiers who share a name', () => {
    const staff = staffLeaderboard([
      sale({ staffId: 's1', staffName: 'Amina', total: 100 }),
      sale({ staffId: 's2', staffName: 'Amina', total: 200 }),
    ]);
    expect(staff).toHaveLength(2);
  });

  it('merges the same cashier\'s sales', () => {
    const staff = staffLeaderboard([
      sale({ staffId: 's1', staffName: 'Amina', total: 100 }),
      sale({ staffId: 's1', staffName: 'Amina', total: 300 }),
    ]);
    expect(staff).toHaveLength(1);
    expect(staff[0].totalSales).toBe(400);
    expect(staff[0].averageBasket).toBe(200);
  });
});

describe('the per-shop breakdown', () => {
  it('agrees with the roll-up it is built from', () => {
    // The property the whole dashboard rests on: a per-shop figure that
    // disagrees with the phone's portfolio endpoint is a figure a shop owner
    // will send back.
    const sales = [
      sale({ tenantId: 't1', total: 1000, profit: 400 }),
      sale({ tenantId: 't2', tenantName: 'Njeri Duka', total: 3000, profit: 900 }),
    ];
    const breakdown = tenantBreakdown(sales);
    expect(breakdown).toHaveLength(2);
    expect(breakdown[0].totals.totalSales).toBe(rollUpSales([sale({ tenantId: 't2', total: 3000 })]).totalSales);
    const summed = breakdown.reduce((sum, row) => sum + row.totals.totalSales, 0);
    expect(summed).toBe(rollUpSales(sales).totalSales);
  });

  it('names a shop from its own row', () => {
    const breakdown = tenantBreakdown([sale({ tenantId: 't2', tenantName: 'Njeri Duka' })]);
    expect(breakdown[0].tenantName).toBe('Njeri Duka');
  });

  it('falls back to the id when no row carries a name', () => {
    const breakdown = tenantBreakdown([sale({ tenantId: 't2' })]);
    expect(breakdown[0].tenantName).toBe('t2');
  });

  it('carries each shop\'s own tender mix', () => {
    const breakdown = tenantBreakdown([
      sale({ tenantId: 't2', paymentMethod: 'mpesa', total: 900 }),
      sale({ tenantId: 't2', paymentMethod: 'cash', total: 100 }),
    ]);
    expect(breakdown[0].paymentMix.map((row) => row.method)).toEqual(['mpesa', 'cash']);
  });
});

describe('the window', () => {
  it('defaults to thirty days back', () => {
    const now = new Date('2026-10-10T12:00:00.000Z');
    const window = defaultDrilldownWindow(now);
    expect(window.from.toISOString()).toBe('2026-09-10T12:00:00.000Z');
    expect(window.to).toBe(now);
  });

  it('rejects a reversed range, an empty one and an unparseable one', () => {
    expect(isWindowUsable('2026-10-02T00:00:00.000Z', '2026-10-01T00:00:00.000Z')).toBe(false);
    expect(isWindowUsable(undefined, '2026-10-01T00:00:00.000Z')).toBe(false);
    expect(isWindowUsable('nonsense', 'also nonsense')).toBe(false);
    expect(isWindowUsable('2026-10-01T00:00:00.000Z', '2026-10-09T00:00:00.000Z')).toBe(true);
  });
});

describe('the whole drill-down', () => {
  it('is a shape with stable keys, callable with no window at all', () => {
    const drilldown = buildDrilldown([sale()]);
    expect(Object.keys(drilldown)).toEqual([
      'from',
      'to',
      'totals',
      'byDay',
      'paymentMix',
      'staff',
      'byTenant',
      'shopCount',
    ]);
    expect(drilldown.shopCount).toBe(1);
  });

  it('omits the series when no window was given', () => {
    const drilldown = buildDrilldown([sale()], { from: undefined, to: undefined });
    expect(drilldown.byDay).toEqual([]);
  });

  it('builds the series when a window was given', () => {
    const drilldown = buildDrilldown([sale()], {
      from: '2026-10-01T00:00:00.000Z',
      to: '2026-10-02T00:00:00.000Z',
    });
    expect(drilldown.byDay).toHaveLength(2);
  });

  it('is all zeros and empty sets for an empty log', () => {
    const drilldown = buildDrilldown([]);
    expect(drilldown.totals.salesCount).toBe(0);
    expect(drilldown.paymentMix).toEqual([]);
    expect(drilldown.staff).toEqual([]);
    expect(drilldown.byTenant).toEqual([]);
    expect(drilldown.shopCount).toBe(0);
  });
});
