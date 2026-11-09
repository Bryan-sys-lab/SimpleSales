import { describe, expect, it } from 'vitest';
import { isReportRangeAllowed, MAX_REPORT_RANGE_DAYS } from '../lib/report_range';

describe('online report range', () => {
  const start = new Date('2026-01-01T00:00:00.000Z');

  it('accepts a one-year window including a leap-day boundary', () => {
    const end = new Date(start.getTime() + MAX_REPORT_RANGE_DAYS * 24 * 60 * 60 * 1000);
    expect(isReportRangeAllowed(start, end)).toBe(true);
  });

  it('rejects a window beyond one year', () => {
    const end = new Date(start.getTime() + (MAX_REPORT_RANGE_DAYS + 1) * 24 * 60 * 60 * 1000);
    expect(isReportRangeAllowed(start, end)).toBe(false);
  });

  it('rejects reversed, equal and invalid dates', () => {
    expect(isReportRangeAllowed(start, start)).toBe(false);
    expect(isReportRangeAllowed(new Date('invalid'), new Date())).toBe(false);
    expect(isReportRangeAllowed(new Date('2026-01-02'), start)).toBe(false);
  });
});
