'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { TaxComplianceReturn } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

const inputClass = 'input';

function statusClass(status: string): string {
  if (status === 'accepted' || status === 'settled') return 'bg-sage-50 text-sage-800';
  if (status === 'rejected') return 'bg-coral-50 text-coral-800';
  return 'bg-electric-50 text-electric-800';
}

function money(value: number | undefined): string {
  return new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format(value ?? 0);
}

function period(row: TaxComplianceReturn): string {
  return `${new Date(row.period_start).toLocaleDateString()} – ${new Date(row.period_end).toLocaleDateString()}`;
}

function ComplianceTable({ rows, caption }: { rows: TaxComplianceReturn[]; caption: string }) {
  return (
    <DataTable
      caption={caption}
      columns={[
        { key: 'taxpayer', label: 'Taxpayer' },
        { key: 'period', label: 'Period', sortable: true },
        { key: 'evidence', label: 'Evidence' },
        { key: 'status', label: 'Status' },
        { key: 'updated', label: 'Updated', sortable: true },
      ]}
      data={rows}
      rowKey={(row) => `${row.tax_type}-${row.id}`}
      renderCell={(row, key) => {
        if (key === 'taxpayer') return <span><strong className="block font-medium">{row.tax_entity.displayLabel}</strong><span className="text-sm text-base-600">{row.tax_entity.legalForm}</span></span>;
        if (key === 'period') return <span>{period(row)}</span>;
        if (key === 'evidence') return row.tax_type === 'vat'
          ? <span>Output {money(row.output_vat)} · Input {money(row.eligible_input_vat)} · Adjustments {money(row.adjustments)} · Net {money(row.net_payable)}</span>
          : <span>Gross {money(row.gross_sales)} · Estimate {money(row.estimate)}</span>;
        if (key === 'status') return <span><span className={`badge ${statusClass(row.status)}`}>{row.status}</span>{row.rejection_reason && <span className="mt-1 block text-sm text-red-700">{row.rejection_reason}</span>}{!!row.status_events?.length && <span className="mt-1 block text-sm text-base-600">{row.status_events.length} audited transition{row.status_events.length === 1 ? '' : 's'}</span>}</span>;
        if (key === 'updated') return <span>{new Date(row.updated_at).toLocaleString()}</span>;
        return null;
      }}
      emptyMessage="No period evidence matches this filter."
    />
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
  useAdminLiveRefresh(load, ['tax-compliance']);

  useEffect(() => { void load(); }, [load]);

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 className="text-2xl font-semibold tracking-tight text-base-900">Tax compliance evidence</h1>
            <p className="text-sm text-base-500">Cross-tenant review of prepared VAT/TOT evidence. These records are not KRA submissions.</p>
          </div>
          <label className="text-sm text-base-700" htmlFor="compliance-status">Status
            <select id="compliance-status" name="status" className={inputClass} value={status} onChange={(event) => setStatus(event.target.value)}>
              <option value="">All statuses</option>
              {['prepared', 'submitted', 'accepted', 'rejected', 'settled'].map((value) => <option key={value} value={value}>{value}</option>)}
            </select>
          </label>
        </div>
        {error && <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        {loading && <div role="status" className="rounded-md border border-base-200 bg-white p-5 text-sm text-base-500">Loading compliance evidence…</div>}
        {!loading && !error && <>
          <section className="rounded-xl border border-base-200 bg-white shadow-sm">
            <div className="border-b border-base-200 px-5 py-4"><h2 className="font-semibold text-base-900">VAT returns</h2></div>
            <div className="p-4 sm:p-5"><ComplianceTable caption="VAT return evidence" rows={vatReturns} /></div>
          </section>
          <section className="rounded-xl border border-base-200 bg-white shadow-sm">
            <div className="border-b border-base-200 px-5 py-4"><h2 className="font-semibold text-base-900">TOT returns</h2></div>
            <div className="p-4 sm:p-5"><ComplianceTable caption="Turnover tax return evidence" rows={totReturns} /></div>
          </section>
        </>}
      </div>
    </ShellLayout>
  );
}
