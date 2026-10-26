import crypto from 'node:crypto';
import type { CommercialContributionProjection } from './commercial_ledger';
import { aggregateCommercialRows, isEligibleForCommercialOutput } from './commercial_controls';

export const COMMERCIAL_FRESHNESS_DAYS = 35;

export type CommercialQualityInput = Pick<CommercialContributionProjection,
  | 'recordId' | 'batchId' | 'periodStart' | 'periodEnd' | 'currency'
  | 'businessProfile' | 'categoryFamily' | 'unitKind'
  | 'transactionCount' | 'grossRevenueMinor' | 'discountMinor'
  | 'refundMinor' | 'cogsMinor' | 'stockoutCount' | 'paymentMethodMix'
  | 'coverageLevel' | 'qualityFlags' | 'status' | 'retentionState'
  | 'deletedAt' | 'consentPurposeVersion' | 'payloadChecksum'
>;

export type CommercialQualityReport = {
  asOfUtc: string;
  sourceRowCount: number;
  eligibleRowCount: number;
  excludedRowCount: number;
  duplicateRowCount: number;
  expectedRowCount: number | null;
  countGap: number | null;
  currencies: string[];
  mixedCurrency: boolean;
  coverage: {
    complete: number;
    partial: number;
    unknown: number;
    completeRatio: number;
  };
  qualityFlagCounts: Record<string, number>;
  freshness: {
    latestPeriodEndUtc: string | null;
    ageDays: number | null;
    status: 'fresh' | 'stale' | 'no_data';
    thresholdDays: number;
  };
  suppression: {
    cohortCount: number;
    suppressedCohortCount: number;
    publishableCohortCount: number;
  };
  reproducibilityFingerprint: string;
  qualityNotes: string[];
};

/**
 * Removes replayed contribution rows before any count or sum is performed.
 * Record IDs are the primary idempotency key; a repeated payload checksum is
 * also treated as a replay when a producer minted a new record ID on retry.
 */
export function dedupeCommercialRows(rows: CommercialQualityInput[]): CommercialQualityInput[];
export function dedupeCommercialRows(rows: CommercialQualityInput[]): CommercialQualityInput[] {
  const seen = new Set<string>();
  return rows.filter((row) => {
    const key = row.payloadChecksum.trim() || row.recordId;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function qualityFlags(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((flag): flag is string => typeof flag === 'string' && flag.trim().length > 0);
}

function fingerprint(rows: CommercialQualityInput[]): string {
  const canonical = rows
    .map((row) => ({
      recordId: row.recordId,
      batchId: row.batchId,
      periodStart: row.periodStart.toISOString(),
      periodEnd: row.periodEnd.toISOString(),
      currency: row.currency,
      transactionCount: row.transactionCount,
      grossRevenueMinor: row.grossRevenueMinor,
      discountMinor: row.discountMinor,
      refundMinor: row.refundMinor,
      cogsMinor: row.cogsMinor,
      stockoutCount: row.stockoutCount,
      paymentMethodMix: row.paymentMethodMix,
      coverageLevel: row.coverageLevel,
      qualityFlags: qualityFlags(row.qualityFlags).sort(),
    }))
    .sort((a, b) => a.recordId.localeCompare(b.recordId));
  return crypto.createHash('sha256').update(JSON.stringify(canonical)).digest('hex');
}

export function buildCommercialQualityReport(
  sourceRows: CommercialQualityInput[],
  options: { now?: Date; expectedRowCount?: number } = {},
): CommercialQualityReport {
  const now = options.now ?? new Date();
  const eligible = sourceRows.filter(isEligibleForCommercialOutput);
  const deduped = dedupeCommercialRows(eligible);
  const duplicateRowCount = eligible.length - deduped.length;
  const currencies = [...new Set(deduped.map((row) => row.currency))].sort();
  const coverage = {
    complete: deduped.filter((row) => row.coverageLevel === 'complete').length,
    partial: deduped.filter((row) => row.coverageLevel === 'partial').length,
    unknown: deduped.filter((row) => row.coverageLevel === 'unknown').length,
  };
  const latestPeriodEnd = deduped.reduce<Date | null>(
    (latest, row) => latest === null || row.periodEnd > latest ? row.periodEnd : latest,
    null,
  );
  const ageDays = latestPeriodEnd === null
    ? null
    : Math.max(0, Math.floor((now.getTime() - latestPeriodEnd.getTime()) / 86_400_000));
  const aggregates = aggregateCommercialRows(deduped);
  const qualityFlagCounts: Record<string, number> = {};
  for (const row of deduped) {
    for (const flag of qualityFlags(row.qualityFlags)) {
      qualityFlagCounts[flag] = (qualityFlagCounts[flag] ?? 0) + 1;
    }
  }
  const expectedRowCount = options.expectedRowCount ?? null;
  const qualityNotes: string[] = [];
  if (duplicateRowCount > 0) qualityNotes.push(`${duplicateRowCount} replayed contribution row(s) excluded before aggregation`);
  if (currencies.length > 1) qualityNotes.push('Mixed currencies require separate cohorts before publication');
  if (coverage.unknown > 0) qualityNotes.push(`${coverage.unknown} contribution row(s) have unknown coverage`);
  if (ageDays !== null && ageDays > COMMERCIAL_FRESHNESS_DAYS) qualityNotes.push('Latest eligible period is outside the freshness threshold');
  if (aggregates.some((aggregate) => aggregate.suppressed)) qualityNotes.push('One or more cohorts remain suppressed by disclosure thresholds');
  if (expectedRowCount !== null && expectedRowCount !== deduped.length) qualityNotes.push('Observed eligible rows do not match the expected contribution count');

  return {
    asOfUtc: now.toISOString(),
    sourceRowCount: sourceRows.length,
    eligibleRowCount: deduped.length,
    excludedRowCount: sourceRows.length - eligible.length,
    duplicateRowCount,
    expectedRowCount,
    countGap: expectedRowCount === null ? null : deduped.length - expectedRowCount,
    currencies,
    mixedCurrency: currencies.length > 1,
    coverage: {
      ...coverage,
      completeRatio: deduped.length === 0 ? 0 : coverage.complete / deduped.length,
    },
    qualityFlagCounts,
    freshness: {
      latestPeriodEndUtc: latestPeriodEnd?.toISOString() ?? null,
      ageDays,
      status: latestPeriodEnd === null ? 'no_data' : ageDays! <= COMMERCIAL_FRESHNESS_DAYS ? 'fresh' : 'stale',
      thresholdDays: COMMERCIAL_FRESHNESS_DAYS,
    },
    suppression: {
      cohortCount: aggregates.length,
      suppressedCohortCount: aggregates.filter((aggregate) => aggregate.suppressed).length,
      publishableCohortCount: aggregates.filter((aggregate) => !aggregate.suppressed).length,
    },
    reproducibilityFingerprint: fingerprint(deduped),
    qualityNotes,
  };
}
