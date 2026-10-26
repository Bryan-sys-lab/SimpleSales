import { describe, expect, it } from 'vitest';
import { buildCommercialQualityReport, type CommercialQualityInput } from '../lib/commercial_quality';

const row = (overrides: Partial<CommercialQualityInput> = {}): CommercialQualityInput => ({
  recordId: 'record-1',
  batchId: 'batch-1',
  periodStart: new Date('2026-10-01T00:00:00.000Z'),
  periodEnd: new Date('2026-10-31T00:00:00.000Z'),
  currency: 'KES',
  transactionCount: 3,
  grossRevenueMinor: 1000,
  discountMinor: 0,
  refundMinor: 0,
  cogsMinor: 500,
  stockoutCount: 0,
  paymentMethodMix: { cash: 3 },
  coverageLevel: 'complete',
  qualityFlags: [],
  status: 'accepted',
  retentionState: 'active',
  deletedAt: null,
  consentPurposeVersion: 'commercial-v1',
  payloadChecksum: 'checksum-1',
  ...overrides,
});

describe('commercial data quality and reproducibility', () => {
  it('deduplicates replayed payloads before counts, sums and suppression', () => {
    const report = buildCommercialQualityReport([
      row(),
      row({ recordId: 'record-2' }),
      row({ recordId: 'record-3', payloadChecksum: 'checksum-3' }),
      row({ recordId: 'record-4', payloadChecksum: 'checksum-4' }),
      row({ recordId: 'record-5', payloadChecksum: 'checksum-5' }),
      row({ recordId: 'record-6', payloadChecksum: 'checksum-6' }),
    ], { now: new Date('2026-11-01T00:00:00.000Z') });

    expect(report.sourceRowCount).toBe(6);
    expect(report.eligibleRowCount).toBe(5);
    expect(report.duplicateRowCount).toBe(1);
    expect(report.suppression.publishableCohortCount).toBe(1);
    expect(report.qualityNotes).toContain('1 replayed contribution row(s) excluded before aggregation');
  });

  it('reports coverage, currency mismatch, stale freshness and quality flags', () => {
    const report = buildCommercialQualityReport([
      row({ recordId: 'complete', payloadChecksum: 'a', qualityFlags: ['missing_cost'] }),
      row({ recordId: 'partial', payloadChecksum: 'b', coverageLevel: 'partial', currency: 'USD' }),
      row({ recordId: 'unknown', payloadChecksum: 'c', coverageLevel: 'unknown' }),
    ], { now: new Date('2027-01-01T00:00:00.000Z') });

    expect(report.mixedCurrency).toBe(true);
    expect(report.coverage).toMatchObject({ complete: 1, partial: 1, unknown: 1 });
    expect(report.freshness.status).toBe('stale');
    expect(report.qualityFlagCounts).toEqual({ missing_cost: 1 });
    expect(report.qualityNotes).toEqual(expect.arrayContaining([
      'Mixed currencies require separate cohorts before publication',
      'Latest eligible period is outside the freshness threshold',
      '1 contribution row(s) have unknown coverage',
    ]));
  });

  it('produces the same fingerprint for the same eligible inputs in a different order', () => {
    const options = { now: new Date('2026-11-01T00:00:00.000Z') };
    const first = buildCommercialQualityReport([
      row({ recordId: 'a', payloadChecksum: 'a' }),
      row({ recordId: 'b', payloadChecksum: 'b' }),
    ], options);
    const second = buildCommercialQualityReport([
      row({ recordId: 'b', payloadChecksum: 'b' }),
      row({ recordId: 'a', payloadChecksum: 'a' }),
    ], options);
    expect(first.reproducibilityFingerprint).toBe(second.reproducibilityFingerprint);
  });

  it('excludes withdrawn and expired rows from the quality basis', () => {
    const report = buildCommercialQualityReport([
      row(),
      row({ recordId: 'withdrawn', payloadChecksum: 'withdrawn', status: 'withdrawn', retentionState: 'withdrawn' }),
      row({ recordId: 'expired', payloadChecksum: 'expired', retentionState: 'expired' }),
    ]);
    expect(report.sourceRowCount).toBe(3);
    expect(report.eligibleRowCount).toBe(1);
    expect(report.excludedRowCount).toBe(2);
  });
});
