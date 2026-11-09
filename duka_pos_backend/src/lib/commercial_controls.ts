import type { CommercialContributionProjection } from './commercial_ledger';

/** Disclosure thresholds apply after every filter, not only to dashboards. */
export const COMMERCIAL_DISCLOSURE_THRESHOLDS = Object.freeze({
  minimumContributions: 5,
  minimumTransactions: 10,
});

export const COMMERCIAL_RETENTION_DAYS = 365;

export function commercialRetentionCutoff(now = new Date(), olderThanDays = COMMERCIAL_RETENTION_DAYS): Date {
  return new Date(now.getTime() - olderThanDays * 24 * 60 * 60 * 1000);
}

export function isEligibleForCommercialOutput(
  row: Pick<CommercialContributionProjection, 'status' | 'retentionState' | 'deletedAt' | 'consentPurposeVersion'>,
): boolean {
  return row.status === 'accepted'
    && row.retentionState === 'active'
    && row.deletedAt === null
    && row.consentPurposeVersion.trim().length > 0;
}

type AggregateInput = Pick<CommercialContributionProjection,
  | 'businessProfile' | 'periodStart' | 'periodEnd' | 'currency' | 'categoryFamily'
  | 'unitKind' | 'transactionCount' | 'grossRevenueMinor' | 'discountMinor'
  | 'refundMinor' | 'cogsMinor' | 'stockoutCount' | 'paymentMethodMix'
>;

export type CommercialAggregate = {
  periodStart: string;
  periodEnd: string;
  businessProfile: string;
  categoryFamily: string;
  unitKind: string;
  currency: string;
  contributorCount: number;
  transactionCount: number;
  grossRevenueMinor: number;
  discountMinor: number;
  refundMinor: number;
  cogsMinor: number;
  stockoutCount: number;
  paymentMethodMix: Record<string, number>;
  suppressed: boolean;
  suppressionReason: string | null;
};

/**
 * Deterministic aggregation used by every future commercial output. A group
 * is returned as suppressed metadata until both thresholds pass; callers must
 * never remove the suppressed rows and then re-aggregate around them.
 */
export function aggregateCommercialRows(rows: AggregateInput[]): CommercialAggregate[] {
  const groups = new Map<string, CommercialAggregate>();
  for (const row of rows) {
    const periodStart = row.periodStart.toISOString();
    const periodEnd = row.periodEnd.toISOString();
    const key = [periodStart, periodEnd, row.businessProfile, row.categoryFamily, row.unitKind, row.currency].join('|');
    const existing = groups.get(key);
    if (existing) {
      existing.contributorCount += 1;
      existing.transactionCount += row.transactionCount;
      existing.grossRevenueMinor += row.grossRevenueMinor;
      existing.discountMinor += row.discountMinor;
      existing.refundMinor += row.refundMinor;
      existing.cogsMinor += row.cogsMinor;
      existing.stockoutCount += row.stockoutCount;
      for (const [method, count] of Object.entries(row.paymentMethodMix as Record<string, number>)) {
        existing.paymentMethodMix[method] = (existing.paymentMethodMix[method] ?? 0) + count;
      }
      existing.suppressed = existing.contributorCount < COMMERCIAL_DISCLOSURE_THRESHOLDS.minimumContributions
        || existing.transactionCount < COMMERCIAL_DISCLOSURE_THRESHOLDS.minimumTransactions;
      existing.suppressionReason = existing.suppressed ? suppressionReason(existing) : null;
      continue;
    }
    const aggregate: CommercialAggregate = {
      periodStart,
      periodEnd,
      businessProfile: row.businessProfile,
      categoryFamily: row.categoryFamily,
      unitKind: row.unitKind,
      currency: row.currency,
      contributorCount: 1,
      transactionCount: row.transactionCount,
      grossRevenueMinor: row.grossRevenueMinor,
      discountMinor: row.discountMinor,
      refundMinor: row.refundMinor,
      cogsMinor: row.cogsMinor,
      stockoutCount: row.stockoutCount,
      paymentMethodMix: { ...(row.paymentMethodMix as Record<string, number>) },
      suppressed: true,
      suppressionReason: null,
    };
    aggregate.suppressionReason = suppressionReason(aggregate);
    groups.set(key, aggregate);
  }
  return [...groups.values()].sort((a, b) => a.periodStart.localeCompare(b.periodStart));
}

function suppressionReason(aggregate: Pick<CommercialAggregate, 'contributorCount' | 'transactionCount'>): string | null {
  const reasons: string[] = [];
  if (aggregate.contributorCount < COMMERCIAL_DISCLOSURE_THRESHOLDS.minimumContributions) reasons.push('minimum_contributor_threshold');
  if (aggregate.transactionCount < COMMERCIAL_DISCLOSURE_THRESHOLDS.minimumTransactions) reasons.push('minimum_transaction_threshold');
  return reasons.length ? reasons.join(',') : null;
}

/** Partner scope is aggregate-only; ledger records are never a valid scope. */
export function assertAggregatePartnerScope(scope: string): void {
  if (scope !== 'approved_aggregate_dataset') {
    throw new Error('Partner scope cannot access commercial contribution records');
  }
}

/** One shared boundary for any future partner/API/export aggregate writer. */
export function prepareCommercialAggregateOutput(
  scope: string,
  aggregates: CommercialAggregate[],
): CommercialAggregate[] {
  assertAggregatePartnerScope(scope);
  return aggregates.filter((aggregate) => !aggregate.suppressed);
}
