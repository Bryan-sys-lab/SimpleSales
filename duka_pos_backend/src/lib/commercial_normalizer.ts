import { COMMERCIAL_POLICY } from './commercial_policy';

export type CommercialProfile = 'drinks' | 'duka' | 'fashion' | 'open';

export type CommercialContributionInput = {
  profile: CommercialProfile;
  periodStartUtc: string;
  periodEndUtc: string;
  currency: string;
  categoryFamily: string;
  unitKind: string;
  transactionCount: number;
  grossRevenueMinorAggregate: number;
  discountMinorAggregate: number;
  refundMinorAggregate: number;
  cogsMinorAggregate: number;
  stockoutCountAggregate: number;
  paymentMethodMixAggregate: Record<string, number>;
  coverageLevel: 'complete' | 'partial' | 'unknown';
};

export type NormalizedCommercialContribution = CommercialContributionInput & {
  schemaVersion: string;
  policyId: string;
  policyVersion: string;
};

const profiles = new Set<CommercialProfile>(['drinks', 'duka', 'fashion', 'open']);

/**
 * One normalization boundary for every profile. This function is pure and
 * currently has no caller that enables collection; it exists so a future
 * approved batch cannot grow four profile-specific commercial pipelines.
 */
export function normalizeCommercialContribution(
  input: CommercialContributionInput,
): NormalizedCommercialContribution {
  if (!profiles.has(input.profile)) throw new Error('Unsupported business profile');
  if (input.periodStartUtc >= input.periodEndUtc) throw new Error('Invalid contribution period');
  if (!/^[A-Z]{3}$/.test(input.currency)) throw new Error('Currency must be ISO uppercase');
  for (const value of [
    input.transactionCount,
    input.grossRevenueMinorAggregate,
    input.discountMinorAggregate,
    input.refundMinorAggregate,
    input.cogsMinorAggregate,
    input.stockoutCountAggregate,
  ]) {
    if (!Number.isInteger(value) || value < 0) throw new Error('Contribution values must be non-negative integers');
  }
  if (!COMMERCIAL_POLICY.allowlist.includes('payment_method_mix_aggregate')) {
    throw new Error('Commercial policy does not allow payment mix');
  }
  return {
    ...input,
    categoryFamily: input.categoryFamily.trim(),
    unitKind: input.unitKind.trim(),
    schemaVersion: 'commercial-contribution-v1',
    policyId: COMMERCIAL_POLICY.policyId,
    policyVersion: COMMERCIAL_POLICY.version,
  };
}
