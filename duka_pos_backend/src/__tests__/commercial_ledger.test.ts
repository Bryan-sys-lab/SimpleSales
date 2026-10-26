import { describe, expect, it } from 'vitest';
import {
  commercialContributionSelect,
  projectCommercialContribution,
} from '../lib/commercial_ledger';

describe('restricted commercial contribution ledger', () => {
  it('projects only minimized fields and keeps provenance traceable', () => {
    const row = {
      recordId: 'record-1',
      batchId: 'batch-1',
      policyVersion: 'v1-draft',
      schemaVersion: 'commercial-contribution-v1',
      businessProfile: 'duka',
      periodStart: new Date('2026-10-01T00:00:00.000Z'),
      periodEnd: new Date('2026-11-01T00:00:00.000Z'),
      currency: 'KES',
      categoryFamily: 'general',
      unitKind: 'item',
      transactionCount: 4,
      grossRevenueMinor: 12000,
      discountMinor: 100,
      refundMinor: 0,
      cogsMinor: 7000,
      stockoutCount: 1,
      paymentMethodMix: { cash: 3, mpesa: 1 },
      coverageLevel: 'complete',
      normalizedVersion: 'normalizer-v1',
      status: 'accepted',
      consentPurposeVersion: 'commercial-intelligence-v1',
      qualityFlags: [],
      payloadChecksum: 'a'.repeat(64),
      aggregationJobVersion: 'aggregate-v1',
      datasetSnapshotId: 'dataset-1',
      partnerExportRefs: ['export-1'],
      supersedesRecordId: null,
      retentionState: 'active',
      deletedAt: null,
      acceptedAt: new Date('2026-11-02T00:00:00.000Z'),
    };

    const projection = projectCommercialContribution(row);
    expect(projection.provenance).toMatchObject({
      normalizedVersion: 'normalizer-v1',
      aggregationJobVersion: 'aggregate-v1',
      datasetSnapshotId: 'dataset-1',
      partnerExportRefs: ['export-1'],
    });
    expect(projection).not.toHaveProperty('tenantId');
    expect(projection).not.toHaveProperty('shopId');
    expect(projection).not.toHaveProperty('customerName');
    expect(projection).not.toHaveProperty('sourceTransactionId');
    expect(projection).not.toHaveProperty('payload');
  });

  it('uses an explicit select list that cannot include source identifiers', () => {
    const selectedFields = Object.keys(commercialContributionSelect);
    expect(selectedFields).not.toContain('tenantId');
    expect(selectedFields).not.toContain('customerId');
    expect(selectedFields).not.toContain('sourceTransactionId');
    expect(selectedFields).not.toContain('payload');
    expect(selectedFields).toContain('datasetSnapshotId');
    expect(selectedFields).toContain('aggregationJobVersion');
  });
});
