'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { TaxComplianceReturn } from '@/lib/types';
import { ShellLayout } from '@/components/layout';

const inputClass = 'rounded-md border border-base-300 bg-white px-3 py-2 text-sm text-base-900 shadow-sm focus:border-accent-600 focus:outline-none focus:ring-2 focus:ring-accent-100';

function statusClass(status: string): string {
  if (status === 'accepted' || status === 'settled') return 'bg-emerald-50 text-emerald-700';
  if (status === 'rejected') return 'bg-red-50 text-red-700';
  return 'bg-amber-50 text-amber-700';
}

function money(value: number | undefined): string {
  return new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format(value ?? 0);
}

function period(row: TaxComplianceReturn): string {
  return `${new Date(row.period_start).toLocaleDateString()} – ${new Date(row.period_end).toLocaleDateString()}`;
}

function ComplianceTable({ rows }: { rows: TaxComplianceReturn[] }) {
  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-left text-sm">
        <caption className="sr-only">Tax compliance period evidence</caption>
        <thead className="bg-base-50 text-xs uppercase tracking-wide text-base-500">
          <tr>
            <th scope="col" className="px-5 py-3">Taxpayer</th>
            <th scope="col" className="px-5 py-3">Period</th>
            <th scope="col" className="px-5 py-3">Evidence</th>
            <th scope="col" className="px-5 py-3">Status</th>
            <th scope="col" className="px-5 py-3">Updated</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-base-100">
          {rows.map((row) => (
            <tr key={`${row.tax_type}-${row.id}`}>
              <td className="px-5 py-4">
                <div className="font-medium text-base-900">{row.tax_entity.displayLabel}</div>
                <div className="text-xs text-base-500">{row.tax_entity.legalForm}</div>
              </td>
              <td className="px-5 py-4 text-base-600">{period(row)}</td>
              <td className="px-5 py-4 text-base-600">
                {row.tax_type === 'vat'
                  ? <span>Output {money(row.output_vat)} · Input {money(row.eligible_input_vat)} · Adjustments {money(row.adjustments)} · Net {money(row.net_payable)}</span>
                  : <span>Gross {money(row.gross_sales)} · Estimate {money(row.estimate)}</span>}
              </td>
              <td className="px-5 py-4">
                <span className={`rounded-full px-2 py-1 text-xs font-medium ${statusClass(row.status)}`}>{row.status}</span>
                {row.rejection_reason && <div className="mt-1 max-w-xs text-xs text-red-700">{row.rejection_reason}</div>}
                {!!row.status_events?.length && <div className="mt-1 text-xs text-base-500">{row.status_events.length} audited transition{row.status_events.length === 1 ? '' : 's'}</div>}
              </td>
              <td className="px-5 py-4 text-xs text-base-500">{new Date(row.updated_at).toLocaleString()}</td>
            </tr>
          ))}
          {rows.length === 0 && <tr><td className="px-5 py-8 text-center text-base-500" colSpan={5}>No period evidence matches this filter.</td></tr>}
        </tbody>
      </table>
    </div>
  );
}

export default function TaxCompliancePage() {
  const [vatReturns, setVatReturns] = useState<TaxComplianceReturn[]>([]);
  const [totReturns, setTotReturns] = useState<TaxComplianceReturn[]>([]);
  const [status, setStatus] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const query = status ? `?status=${encodeURIComponent(status)}` : '';
      const response = await fetchJson<{ vat_returns: TaxComplianceReturn[]; tot_returns: TaxComplianceReturn[] }>(`/api/admin/tax-compliance${query}`);
      setVatReturns(response.vat_returns);
      setTotReturns(response.tot_returns);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load compliance evidence');
    } finally {
      setLoading(false);
    }
  }, [status]);

  useEffect(() => { void load(); }, [load]);

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h2 className="text-2xl font-semibold tracking-tight text-base-900">Tax compliance evidence</h2>
            <p className="text-sm text-base-500">Cross-tenant review of prepared VAT/TOT evidence. These records are not KRA submissions.</p>
          </div>
          <label className="text-sm text-base-700">Status
            <select className={`${inputClass} ml-2`} value={status} onChange={(event) => setStatus(event.target.value)}>
              <option value="">All statuses</option>
              {['prepared', 'submitted', 'accepted', 'rejected', 'settled'].map((value) => <option key={value} value={value}>{value}</option>)}
            </select>
          </label>
        </div>
        {error && <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        {loading && <div role="status" className="rounded-md border border-base-200 bg-white p-5 text-sm text-base-500">Loading compliance evidence…</div>}
        {!loading && !error && <>
          <section className="rounded-xl border border-base-200 bg-white shadow-sm">
            <div className="border-b border-base-200 px-5 py-4"><h3 className="font-semibold text-base-900">VAT returns</h3></div>
            <ComplianceTable rows={vatReturns} />
          </section>
          <section className="rounded-xl border border-base-200 bg-white shadow-sm">
            <div className="border-b border-base-200 px-5 py-4"><h3 className="font-semibold text-base-900">TOT returns</h3></div>
            <ComplianceTable rows={totReturns} />
          </section>
        </>}
      </div>
    </ShellLayout>
  );
}
