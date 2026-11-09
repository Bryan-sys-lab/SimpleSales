import { describe, expect, it } from 'vitest';
import { aggregateCommercialRows, assertAggregatePartnerScope, isEligibleForCommercialOutput, prepareCommercialAggregateOutput } from '../lib/commercial_controls';

const row = (record: Partial<Parameters<typeof aggregateCommercialRows>[0]> = {}) => ({
  businessProfile: 'duka', periodStart: new Date('2026-10-01T00:00:00.000Z'), periodEnd: new Date('2026-11-01T00:00:00.000Z'),
  currency: 'KES', categoryFamily: 'general', unitKind: 'item', transactionCount: 2,
  grossRevenueMinor: 1000, discountMinor: 0, refundMinor: 0, cogsMinor: 500, stockoutCount: 0,
  paymentMethodMix: { cash: 2 }, ...record,
});

describe('commercial disclosure controls', () => {
  it('suppresses groups until both contributor and transaction thresholds pass', () => {
    const suppressed = aggregateCommercialRows([row({ transactionCount: 3 }), row({ transactionCount: 3 }), row({ transactionCount: 3 }), row({ transactionCount: 3 })]);
    expect(suppressed[0]).toMatchObject({ suppressed: true, suppressionReason: 'minimum_contributor_threshold' });
    const published = aggregateCommercialRows([row({ transactionCount: 3 }), row({ transactionCount: 3 }), row({ transactionCount: 3 }), row({ transactionCount: 3 }), row({ transactionCount: 3 })]);
    expect(published[0]).toMatchObject({ suppressed: false, suppressionReason: null, contributorCount: 5, transactionCount: 15 });
  });

  it('excludes withdrawn and expired rows from future output', () => {
    expect(isEligibleForCommercialOutput({ status: 'accepted', retentionState: 'active', deletedAt: null, consentPurposeVersion: 'v1' })).toBe(true);
    expect(isEligibleForCommercialOutput({ status: 'withdrawn', retentionState: 'withdrawn', deletedAt: null, consentPurposeVersion: 'v1' })).toBe(false);
    expect(isEligibleForCommercialOutput({ status: 'accepted', retentionState: 'expired', deletedAt: null, consentPurposeVersion: 'v1' })).toBe(false);
  });

  it('rejects every non-aggregate partner scope', () => {
    expect(() => assertAggregatePartnerScope('ledger')).toThrow('cannot access');
    expect(() => assertAggregatePartnerScope('approved_aggregate_dataset')).not.toThrow();
  });

  it('never prepares suppressed cohorts for a partner output', () => {
    const aggregates = aggregateCommercialRows([
      row({ transactionCount: 3 }), row({ transactionCount: 3 }), row({ transactionCount: 3 }),
    ]);
    expect(prepareCommercialAggregateOutput('approved_aggregate_dataset', aggregates)).toEqual([]);
    expect(() => prepareCommercialAggregateOutput('ledger', aggregates)).toThrow('cannot access');
  });
});
