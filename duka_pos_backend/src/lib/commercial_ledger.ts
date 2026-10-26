import type { Prisma } from '@prisma/client';

/**
 * The ledger is a restricted, minimized source layer. Keep this select list
 * explicit: adding a Prisma field must not silently widen the admin response.
 */
export const commercialContributionSelect = {
  recordId: true,
  batchId: true,
  policyVersion: true,
  schemaVersion: true,
  businessProfile: true,
  periodStart: true,
  periodEnd: true,
  currency: true,
  categoryFamily: true,
  unitKind: true,
  transactionCount: true,
  grossRevenueMinor: true,
  discountMinor: true,
  refundMinor: true,
  cogsMinor: true,
  stockoutCount: true,
  paymentMethodMix: true,
  coverageLevel: true,
  normalizedVersion: true,
  status: true,
  consentPurposeVersion: true,
  qualityFlags: true,
  payloadChecksum: true,
  aggregationJobVersion: true,
  datasetSnapshotId: true,
  partnerExportRefs: true,
  supersedesRecordId: true,
  retentionState: true,
  deletedAt: true,
  acceptedAt: true,
} satisfies Prisma.CommercialContributionSelect;

export type CommercialContributionProjection = Prisma.CommercialContributionGetPayload<{
  select: typeof commercialContributionSelect;
}>;

/** Convert dates to a stable API representation without exposing ORM rows. */
export function projectCommercialContribution(
  row: CommercialContributionProjection,
) {
  return {
    recordId: row.recordId,
    batchId: row.batchId,
    policyVersion: row.policyVersion,
    schemaVersion: row.schemaVersion,
    businessProfile: row.businessProfile,
    periodStart: row.periodStart.toISOString(),
    periodEnd: row.periodEnd.toISOString(),
    currency: row.currency,
    categoryFamily: row.categoryFamily,
    unitKind: row.unitKind,
    transactionCount: row.transactionCount,
    grossRevenueMinor: row.grossRevenueMinor,
    discountMinor: row.discountMinor,
    refundMinor: row.refundMinor,
    cogsMinor: row.cogsMinor,
    stockoutCount: row.stockoutCount,
    paymentMethodMix: row.paymentMethodMix,
    coverageLevel: row.coverageLevel,
    status: row.status,
    consentPurposeVersion: row.consentPurposeVersion,
    qualityFlags: row.qualityFlags,
    payloadChecksum: row.payloadChecksum,
    provenance: {
      normalizedVersion: row.normalizedVersion,
      acceptedAt: row.acceptedAt.toISOString(),
      aggregationJobVersion: row.aggregationJobVersion,
      datasetSnapshotId: row.datasetSnapshotId,
      partnerExportRefs: row.partnerExportRefs,
      supersedesRecordId: row.supersedesRecordId,
      retentionState: row.retentionState,
      deletedAt: row.deletedAt?.toISOString() ?? null,
    },
  };
}
