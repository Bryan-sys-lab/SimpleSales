import { describe, expect, it } from 'vitest';
import { calculateCanonicalMetricFixture, CANONICAL_QUALITY_STATES } from '../lib/canonical_metrics';

describe('canonical Patch 18 metric fixtures', () => {
  it('reconciles gross, discounts, refunds, tax and net sales without assumptions', () => {
    const result = calculateCanonicalMetricFixture({
      periodStartUtc: '2026-10-01T00:00:00.000Z',
      periodEndUtc: '2026-11-01T00:00:00.000Z',
      grossSalesMinor: 100000,
      discountMinor: 5000,
      refundMinor: 2500,
      taxMinor: 13000,
      confirmedPaymentMinor: 82000,
      receivableMinor: 15000,
      cashReceivedMinor: 82000,
      validTrackedObservation: 20,
      validStockoutObservation: 3,
      orderedQuantity: 40,
      receivedQuantity: 34,
      applicableProfileFields: 5,
      populatedOrDeclinedProfileFields: 4,
      completedSales: 50,
      completedSalesWithValidLines: 48,
      unitVolumes: [
        { quantity: 12.5, unit: 'kg' },
        { quantity: 6, unit: 'kg' },
        { quantity: 20, unit: 'litre' },
        { quantity: 3, unit: 'each' },
      ],
    });

    expect(result.netSalesExTaxMinor).toBe(79500);
    expect(result.stockoutRate).toBe(0.15);
    expect(result.poFillRate).toBe(0.85);
    expect(result.businessProfileCompleteness).toBe(0.8);
    expect(result.salesRecordCompleteness).toBe(0.96);
    expect(result.unitVolumes).toEqual({ kg: 18.5, litre: 20, each: 3 });
  });

  it('keeps missing stock and procurement facts unknown or missing instead of zero', () => {
    const result = calculateCanonicalMetricFixture({
      periodStartUtc: '2026-10-01T00:00:00.000Z',
      periodEndUtc: '2026-11-01T00:00:00.000Z',
      grossSalesMinor: 0,
      discountMinor: 0,
      refundMinor: 0,
      taxMinor: 0,
      confirmedPaymentMinor: 0,
      receivableMinor: 0,
      cashReceivedMinor: 0,
      validTrackedObservation: 0,
      validStockoutObservation: 0,
      orderedQuantity: null,
      receivedQuantity: null,
      applicableProfileFields: 0,
      populatedOrDeclinedProfileFields: 0,
      completedSales: 0,
      completedSalesWithValidLines: 0,
      unitVolumes: [{ quantity: 1, unit: 'service_hour' }],
    });

    expect(result.stockoutRate).toBeNull();
    expect(result.poFillRate).toBeNull();
    expect(result.businessProfileCompleteness).toBeNull();
    expect(result.salesRecordCompleteness).toBeNull();
    expect(result.qualityStates.stockSnapshot).toBe('unknown');
    expect(result.qualityStates.serviceInventory).toBe('not_applicable');
  });

  it('exports all required quality states without conflating missing and zero', () => {
    expect(CANONICAL_QUALITY_STATES).toEqual([
      'valid',
      'mapped',
      'unmapped',
      'missing',
      'unknown',
      'not_applicable',
      'unverified',
      'stale',
      'rejected',
    ]);
  });
});
