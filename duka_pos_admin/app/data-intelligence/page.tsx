'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

type Meta = {
  generated_at_utc: string;
  period_from_utc: string | null;
  period_to_utc: string | null;
  reporting_timezone: string;
  dictionary_version: string;
  schema_version: string;
  freshness: string;
  coverage: { numerator: number; denominator: number; ratio: number | null; state: string };
  warnings: string[];
};

type Partner = {
  id: string;
  legalName: string;
  status: string;
  contractRef: string | null;
  purpose: string | null;
  grants: Array<{ id: string; productId: string; snapshotId: string; status: string; expiresAt: string }>;
  credentials: Array<{ id: string; keyPrefix: string; status: string; expiresAt: string; quotaPerDay: number }>;
  deliveries: Array<{ id: string; status: string; productId: string; snapshotId: string; createdAt: string }>;
};

export default function DataIntelligencePage() {
  const [overview, setOverview] = useState<Record<string, number | string | null> | null>(null);
  const [datasets, setDatasets] = useState<Array<Record<string, string>>>([]);
  const [meta, setMeta] = useState<Meta | null>(null);
  const [partners, setPartners] = useState<Partner[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [overviewResponse, datasetsResponse, partnerResponse] = await Promise.all([
        fetchJson<{ data: Record<string, number | string | null>; meta: Meta }>('/api/admin/commercial/data-intelligence/overview'),
        fetchJson<{ data: Array<Record<string, string>>; meta: Meta }>('/api/admin/commercial/data-intelligence/datasets'),
        fetchJson<{ partners: Partner[] }>('/api/admin/commercial/partners'),
      ]);
      setOverview(overviewResponse.data);
      setDatasets(datasetsResponse.data);
      setMeta(overviewResponse.meta);
      setPartners(partnerResponse.partners);
      setError(null);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Failed to load data intelligence');
    } finally {
      setLoading(false);
    }
  }, []);
  useAdminLiveRefresh(load, ['commercial-quality', 'commercial-ledger']);
  useEffect(() => { void load(); }, [load]);

  const revokeCredential = async (credentialId: string) => {
    await fetchJson(`/api/admin/commercial/partners/credentials/${credentialId}/revoke`, {
      method: 'POST',
      body: JSON.stringify({ reason: 'Partner access revoked by authorized Partner Manager' }),
    });
    await load();
  };

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-base-900">Data Intelligence</h1>
          <p className="text-sm text-base-500">Backend-authoritative overview, pipeline coverage and dataset snapshots.</p>
        </div>
        {loading && <div className="card p-5 text-sm text-base-500" role="status">Loading backend data…</div>}
        {error && <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800" role="alert">{error}</div>}
        {overview && meta && (
          <>
            <section className="card p-5" aria-label="Reporting metadata">
              <dl className="grid gap-3 text-sm sm:grid-cols-3">
                <div><dt className="font-medium text-base-700">Generated</dt><dd className="text-base-500">{meta.generated_at_utc}</dd></div>
                <div><dt className="font-medium text-base-700">Period</dt><dd className="text-base-500">{meta.period_from_utc ?? 'No from filter'} → {meta.period_to_utc ?? 'No to filter'} · {meta.reporting_timezone}</dd></div>
                <div><dt className="font-medium text-base-700">Freshness / coverage</dt><dd className="text-base-500">{meta.freshness} · {meta.coverage.state} · {meta.coverage.numerator}/{meta.coverage.denominator}</dd></div>
              </dl>
            </section>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {Object.entries(overview).filter(([key]) => key !== 'latest_period_end_utc').map(([key, value]) => (
                <section key={key} className="card p-4">
                  <p className="text-xs font-medium uppercase tracking-wide text-base-500">{key.replaceAll('_', ' ')}</p>
                  <p className="mt-2 text-2xl font-semibold text-base-900">{String(value ?? 'unknown')}</p>
                </section>
              ))}
            </div>
            {meta.warnings.length > 0 && (
              <section className="card p-5" aria-label="Data warnings">
                <h2 className="text-sm font-semibold text-base-900">Quality warnings</h2>
                <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-base-700">{meta.warnings.map((warning) => <li key={warning}>{warning}</li>)}</ul>
              </section>
            )}
            <section className="card p-5" aria-label="Dataset snapshots">
              <h2 className="text-sm font-semibold text-base-900">Dataset snapshots</h2>
              {datasets.length === 0
                ? <p className="mt-2 text-sm text-base-500">No published dataset snapshots are registered.</p>
                : <div className="mt-3 space-y-2">{datasets.map((dataset) => (
                    <div key={dataset.snapshot_id} className="rounded-md border border-base-200 p-3 text-sm text-base-700">
                      {dataset.snapshot_id} · {dataset.period_start_utc} → {dataset.period_end_utc} · {dataset.publish_status}
                    </div>
                  ))}</div>}
            </section>
            <section className="card p-5" aria-label="Partner grants and credentials">
              <h2 className="text-sm font-semibold text-base-900">Partner grants &amp; credentials</h2>
              {partners.length === 0
                ? <p className="mt-2 text-sm text-base-500">No partner agreements or credentials are registered.</p>
                : <div className="mt-3 space-y-3">{partners.map((partner) => (
                    <div key={partner.id} className="rounded-md border border-base-200 p-3">
                      <p className="text-sm font-medium text-base-900">{partner.legalName} · {partner.status}</p>
                      {partner.contractRef && <p className="mt-1 text-xs text-base-500">Contract: {partner.contractRef}</p>}
                      <p className="mt-1 text-xs text-base-700">{partner.grants.length} grants · {partner.credentials.length} credentials · {partner.deliveries.length} recent deliveries</p>
                      {partner.credentials.map((credential) => (
                        <div key={credential.id} className="mt-2 flex items-center justify-between rounded bg-base-50 px-3 py-2 text-xs text-base-700">
                          <span>{credential.keyPrefix}… · {credential.status} · expires {credential.expiresAt} · quota {credential.quotaPerDay}/day</span>
                          {credential.status === 'active' && (
                            <button type="button" className="ml-3 text-xs font-semibold text-red-700" onClick={() => void revokeCredential(credential.id)}>
                              Revoke
                            </button>
                          )}
                        </div>
                      ))}
                    </div>
                  ))}</div>}
            </section>
          </>
        )}
      </div>
    </ShellLayout>
  );
}
