'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import { ShellLayout } from '@/components/layout';
import { fetchJson } from '@/lib/api';

type Context = {
  appProfile: string;
  primaryActivityCode: string | null;
  primaryActivityStatus: string;
  activityScheme: string | null;
  activityVersion: string | null;
  secondaryActivityCodes: string[];
  operatorRoles: string[];
  salesChannels: string[];
  countyCode: string | null;
  settlementContext: string;
  fieldProvenance: Record<string, string>;
  confirmedAt: string | null;
  updatedAt: string;
};
type ResponseData = {
  tenant: { id: string; shopName: string; businessProfile: string; businessContext: Context | null };
};

function Value({ label, value }: { label: string; value: string | null | undefined }) {
  return <div className="min-w-0 rounded-xl border border-base-200 bg-white p-4">
    <dt className="text-xs font-medium uppercase tracking-wide text-base-500">{label}</dt>
    <dd className="mt-1 break-words text-sm font-semibold text-base-900">{value || 'Not provided'}</dd>
  </div>;
}

export default function BusinessContextPage() {
  const params = useParams<{ tenantId: string }>();
  const [data, setData] = useState<ResponseData | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    fetchJson<ResponseData>(`/api/admin/tenants/${encodeURIComponent(params.tenantId)}/business-context`)
      .then((response) => { if (active) setData(response); })
      .catch((cause) => { if (active) setError(cause instanceof Error ? cause.message : 'Could not load business details'); });
    return () => { active = false; };
  }, [params.tenantId]);

  const context = data?.tenant.businessContext;
  return <ShellLayout>
    <main className="mx-auto max-w-4xl space-y-5">
      <Link href="/tenants" className="inline-flex min-h-11 items-center text-sm font-medium text-accent-800 underline">← Back to tenants</Link>
      {error && <div role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-900">{error}</div>}
      {!data && !error && <div className="card p-5 text-sm text-base-600" aria-live="polite">Loading business details…</div>}
      {data && <>
        <header className="card space-y-2 p-5">
          <p className="text-xs font-semibold uppercase tracking-wide text-accent-800">Tenant operational record</p>
          <h1 className="text-2xl font-semibold text-base-900">{data.tenant.shopName}</h1>
          <p className="text-sm leading-6 text-base-600">These details describe this shop’s POS setup and business activity. They are operational tenant data and are not a commercial contribution or proof of data sharing consent.</p>
        </header>
        {!context ? <section className="card p-5">
          <h2 className="font-semibold text-base-900">No business details recorded</h2>
          <p className="mt-1 text-sm text-base-600">The shop has not synced optional business details.</p>
        </section> : <>
          <section className="card space-y-4 p-5">
            <h2 className="text-lg font-semibold text-base-900">Classification</h2>
            <dl className="grid gap-3 sm:grid-cols-2">
              <Value label="POS profile" value={context.appProfile} />
              <Value label="Primary activity status" value={context.primaryActivityStatus.replaceAll('_', ' ')} />
              <Value label="Primary KeSIC code" value={context.primaryActivityCode} />
              <Value label="Reference" value={[context.activityScheme, context.activityVersion].filter(Boolean).join(' · ')} />
              <Value label="Secondary KeSIC codes" value={context.secondaryActivityCodes.join(', ')} />
              <Value label="County code" value={context.countyCode} />
            </dl>
          </section>
          <section className="card space-y-4 p-5">
            <h2 className="text-lg font-semibold text-base-900">How the shop operates</h2>
            <dl className="grid gap-3 sm:grid-cols-2">
              <Value label="Operator roles" value={context.operatorRoles.join(', ')} />
              <Value label="Sales channels" value={context.salesChannels.join(', ')} />
              <Value label="Settlement context" value={context.settlementContext.replaceAll('_', ' ')} />
              <Value label="Last updated" value={new Date(context.updatedAt).toLocaleString()} />
            </dl>
          </section>
          <details className="card p-5">
            <summary className="min-h-11 cursor-pointer py-2 font-semibold text-base-900">Field provenance and confirmation</summary>
            <p className="mt-2 text-sm text-base-600">Confirmed {context.confirmedAt ? new Date(context.confirmedAt).toLocaleString() : 'not recorded'}</p>
            <dl className="mt-3 grid gap-2 sm:grid-cols-2">{Object.entries(context.fieldProvenance).map(([field, source]) => <Value key={field} label={field.replaceAll('_', ' ')} value={source.replaceAll('_', ' ')} />)}</dl>
          </details>
        </>}
      </>}
    </main>
  </ShellLayout>;
}
