'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

type Policy = {
  policyId: string;
  version: string;
  status: string;
  collectionEnabled: boolean;
  purpose: string;
  disclosure: string;
  allowlist: string[];
  prohibited: string[];
  scopes: string[];
  legalGates: Record<string, string>;
};

export default function CommercialPolicyPage() {
  const [policy, setPolicy] = useState<Policy | null>(null);
  const [consentStatus, setConsentStatus] = useState<{ collectionEnabled: boolean; statusCounts: Record<string, number> } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [response, consentResponse] = await Promise.all([
        fetchJson<{ policy: Policy }>('/api/admin/commercial/policy'),
        fetchJson<{ collectionEnabled: boolean; statusCounts: Record<string, number> }>('/api/admin/commercial/consent-status'),
      ]);
      setPolicy(response.policy);
      setConsentStatus(consentResponse);
      setError(null);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Failed to load policy');
    }
  }, []);
  useAdminLiveRefresh(load, ['commercial-policy']);
  useEffect(() => { void load(); }, [load]);

  return (
    <ShellLayout>
      <div className="max-w-5xl space-y-6">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">Commercial data policy</h2>
          <p className="text-sm text-base-500">Purpose and field boundary for future commercial intelligence.</p>
        </div>
        {error && <div className="card border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        {!policy && !error && <div className="card p-5 text-sm text-base-500">Loading policy…</div>}
        {policy && (
          <>
            <div className="card space-y-4 p-5">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p className="text-xs uppercase tracking-wide text-base-500">{policy.policyId} · {policy.version}</p>
                  <h3 className="mt-1 text-lg font-semibold text-base-900">{policy.status}</h3>
                </div>
                <span className="rounded-full border border-amber-200 bg-amber-50 px-3 py-1 text-xs font-semibold text-amber-800">
                  Collection {policy.collectionEnabled ? 'enabled' : 'disabled'}
                </span>
              </div>
              <p className="text-sm leading-6 text-base-700">{policy.purpose}</p>
              <p className="rounded-lg bg-base-50 p-3 text-sm leading-6 text-base-600">{policy.disclosure}</p>
              {consentStatus && (
                <dl className="grid gap-3 text-sm sm:grid-cols-3">
                  <div className="rounded bg-base-50 p-3"><dt className="text-base-500">Active grants</dt><dd className="mt-1 text-lg font-semibold text-base-900">{consentStatus.statusCounts.active ?? 0}</dd></div>
                  <div className="rounded bg-base-50 p-3"><dt className="text-base-500">Withdrawn grants</dt><dd className="mt-1 text-lg font-semibold text-base-900">{consentStatus.statusCounts.withdrawn ?? 0}</dd></div>
                  <div className="rounded bg-base-50 p-3"><dt className="text-base-500">Production collection</dt><dd className="mt-1 text-lg font-semibold text-amber-800">{consentStatus.collectionEnabled ? 'enabled' : 'disabled'}</dd></div>
                </dl>
              )}
            </div>
            <div className="grid gap-4 lg:grid-cols-2">
              <section className="card p-5">
                <h3 className="mb-3 text-sm font-semibold text-base-900">Granular consent scopes</h3>
                <ul className="space-y-2 text-sm text-base-700">
                  {(policy.scopes ?? []).map((scope) => <li key={scope} className="rounded bg-base-50 px-3 py-2">{scope}</li>)}
                </ul>
              </section>
              <section className="card p-5">
                <h3 className="mb-3 text-sm font-semibold text-base-900">Legal release gates</h3>
                <dl className="space-y-2 text-sm">
                  {Object.entries(policy.legalGates ?? {}).map(([key, value]) => (
                    <div key={key} className="flex items-start justify-between gap-3 rounded bg-amber-50 px-3 py-2">
                      <dt className="text-base-700">{key}</dt><dd className="text-right font-medium text-amber-800">{value}</dd>
                    </div>
                  ))}
                </dl>
              </section>
              <section className="card p-5">
                <h3 className="mb-3 text-sm font-semibold text-base-900">Approved aggregate fields</h3>
                <ul className="space-y-2 text-sm text-base-700">
                  {policy.allowlist.map((field) => <li key={field} className="rounded bg-emerald-50 px-3 py-2">{field}</li>)}
                </ul>
              </section>
              <section className="card p-5">
                <h3 className="mb-3 text-sm font-semibold text-base-900">Never permitted</h3>
                <ul className="space-y-2 text-sm text-base-700">
                  {policy.prohibited.map((field) => <li key={field} className="rounded bg-red-50 px-3 py-2">{field}</li>)}
                </ul>
              </section>
            </div>
          </>
        )}
      </div>
    </ShellLayout>
  );
}
