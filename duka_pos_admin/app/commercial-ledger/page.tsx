'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';

type Contribution = {
  recordId: string;
  batchId: string;
  policyVersion: string;
  schemaVersion: string;
  businessProfile: string;
  periodStart: string;
  periodEnd: string;
  currency: string;
  categoryFamily: string;
  unitKind: string;
  transactionCount: number;
  grossRevenueMinor: number;
  discountMinor: number;
  refundMinor: number;
  cogsMinor: number;
  stockoutCount: number;
  paymentMethodMix: Record<string, number>;
  coverageLevel: string;
  status: string;
  consentPurposeVersion: string;
  qualityFlags: unknown;
  payloadChecksum: string;
  provenance: {
    normalizedVersion: string;
    acceptedAt: string;
    aggregationJobVersion: string | null;
    datasetSnapshotId: string | null;
    partnerExportRefs: unknown;
    supersedesRecordId: string | null;
    retentionState: string;
    deletedAt: string | null;
  };
};

type AggregatePreview = {
  suppressed: boolean;
  suppressionReason: string | null;
  contributorCount: number;
  transactionCount: number;
};

const formatMinor = (value: number, currency: string) =>
  `${currency} ${(value / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export default function CommercialLedgerPage() {
  const [rows, setRows] = useState<Contribution[]>([]);
  const [profile, setProfile] = useState('');
  const [status, setStatus] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [collectionEnabled, setCollectionEnabled] = useState(false);
  const [aggregatePreview, setAggregatePreview] = useState<AggregatePreview[]>([]);

  const load = useCallback(async (cancelledRef?: { current: boolean }) => {
    setLoading(true);
    setError(null);
    try {
      const params = new URLSearchParams({ limit: '100' });
      if (profile) params.set('profile', profile);
      if (status) params.set('status', status);
      const [response, aggregateResponse] = await Promise.all([
        fetchJson<{ policy: { collectionEnabled: boolean }; contributions: Contribution[] }>(`/api/admin/commercial/ledger?${params.toString()}`),
        fetchJson<{ aggregates: AggregatePreview[] }>(`/api/admin/commercial/aggregate-preview?${params.toString()}`),
      ]);
      if (!cancelledRef?.current) {
        setRows(response.contributions);
        setCollectionEnabled(response.policy.collectionEnabled);
        setAggregatePreview(aggregateResponse.aggregates);
      }
    } catch (cause) {
      if (!cancelledRef?.current) setError(cause instanceof Error ? cause.message : 'Failed to load contribution ledger');
    } finally {
      if (!cancelledRef?.current) setLoading(false);
    }
  }, [profile, status]);

  useEffect(() => {
    const cancelled = { current: false };
    void load(cancelled);
    return () => { cancelled.current = true; };
  }, [load]);

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">Contribution Ledger</h2>
          <p className="text-sm text-base-500">Sanitized Contributions (Restricted) — accepted minimized inputs and their provenance.</p>
        </div>

        <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          <strong>Restricted source layer.</strong> This view is available only to the system administrator. It contains no shop, customer, staff, receipt, or source-transaction identifiers. Commercial collection is currently {collectionEnabled ? 'enabled' : 'disabled'} by policy.
        </div>

        <div className="flex flex-wrap items-end gap-3">
          <label className="text-sm text-base-700">Profile
            <select value={profile} onChange={(event) => setProfile(event.target.value)} className="input mt-1 block min-w-36" aria-label="Filter by profile">
              <option value="">All profiles</option><option value="drinks">Drinks</option><option value="duka">Duka</option><option value="fashion">Fashion</option><option value="open">Open</option>
            </select>
          </label>
          <label className="text-sm text-base-700">Status
            <select value={status} onChange={(event) => setStatus(event.target.value)} className="input mt-1 block min-w-36" aria-label="Filter by status">
              <option value="">All statuses</option><option value="accepted">Accepted</option><option value="superseded">Superseded</option><option value="withdrawn">Withdrawn</option><option value="deleted">Deleted</option>
            </select>
          </label>
        </div>

        <section className="card p-5" aria-label="Disclosure control summary">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h3 className="text-sm font-semibold text-base-900">Disclosure controls</h3>
              <p className="mt-1 text-sm text-base-500">Suppression is applied after filters and before any aggregate output.</p>
            </div>
            <div className="text-right text-sm text-base-600">
              <span className="font-semibold text-base-900">{aggregatePreview.length}</span> cohort{aggregatePreview.length === 1 ? '' : 's'} evaluated
            </div>
          </div>
          {aggregatePreview.length > 0 && (
            <p className="mt-3 text-sm text-amber-800">{aggregatePreview.filter((aggregate) => aggregate.suppressed).length} cohort{aggregatePreview.filter((aggregate) => aggregate.suppressed).length === 1 ? '' : 's'} suppressed by minimum-contributor or transaction thresholds.</p>
          )}
        </section>

        {error && <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        {loading && <div className="card p-5 text-sm text-base-500" role="status">Loading contribution ledger…</div>}
        {!loading && !error && (
          <DataTable
            columns={[
              { key: 'recordId', label: 'Record', sortable: true },
              { key: 'batchId', label: 'Batch' },
              { key: 'businessProfile', label: 'Profile', sortable: true },
              { key: 'period', label: 'Period' },
              { key: 'categoryFamily', label: 'Category' },
              { key: 'transactionCount', label: 'Transactions', align: 'right', sortable: true },
              { key: 'grossRevenue', label: 'Gross revenue', align: 'right' },
              { key: 'status', label: 'Status', sortable: true },
              { key: 'lineage', label: 'Lineage' },
            ]}
            data={rows}
            rowKey={(row) => row.recordId}
            emptyMessage="No accepted minimized contributions"
            renderCell={(row, key) => {
              if (key === 'period') return <span className="whitespace-nowrap">{row.periodStart.slice(0, 10)} → {row.periodEnd.slice(0, 10)}</span>;
              if (key === 'grossRevenue') return <span className="whitespace-nowrap">{formatMinor(row.grossRevenueMinor, row.currency)}</span>;
              if (key === 'lineage') return <span className="text-xs text-base-600">{row.provenance.aggregationJobVersion ?? 'Not aggregated'}{row.provenance.datasetSnapshotId ? ` · ${row.provenance.datasetSnapshotId}` : ''}</span>;
              if (key === 'transactionCount') return <span>{row.transactionCount.toLocaleString()}</span>;
              const value = row[key as keyof Contribution];
              return <span>{value == null ? '—' : String(value)}</span>;
            }}
          />
        )}
      </div>
    </ShellLayout>
  );
}
