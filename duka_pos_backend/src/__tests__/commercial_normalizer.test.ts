import { describe, expect, it } from 'vitest';
import { normalizeCommercialContribution, type CommercialProfile } from '../lib/commercial_normalizer';

const fixture = (profile: CommercialProfile) => ({
  profile,
  periodStartUtc: '2026-10-01T00:00:00.000Z',
  periodEndUtc: '2026-11-01T00:00:00.000Z',
  currency: 'KES',
  categoryFamily: 'general',
  unitKind: profile === 'drinks' ? 'litre' : profile === 'fashion' ? 'item' : 'transaction',
  transactionCount: 10,
  grossRevenueMinorAggregate: 10000,
  discountMinorAggregate: 100,
  refundMinorAggregate: 0,
  cogsMinorAggregate: 6000,
  stockoutCountAggregate: 1,
  paymentMethodMixAggregate: { cash: 7, mpesa: 3 },
  coverageLevel: 'complete' as const,
});

describe('commercial contribution normalizer', () => {
  it('uses one normalized contract for all four profiles', () => {
    for (const profile of ['drinks', 'duka', 'fashion', 'open'] as const) {
      const normalized = normalizeCommercialContribution(fixture(profile));
      expect(normalized.profile).toBe(profile);
      expect(normalized.schemaVersion).toBe('commercial-contribution-v1');
      expect(normalized.policyId).toBe('commercial-intelligence');
    }
  });

  it('rejects invalid periods and negative aggregates', () => {
    expect(() => normalizeCommercialContribution({
      ...fixture('duka'),
      periodEndUtc: '2026-09-01T00:00:00.000Z',
    })).toThrow('Invalid contribution period');
    expect(() => normalizeCommercialContribution({
      ...fixture('open'),
      grossRevenueMinorAggregate: -1,
    })).toThrow('non-negative integers');
  });
});
