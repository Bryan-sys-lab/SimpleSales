'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { LaybyAdmin } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';

const STATUS_STYLES: Record<string, string> = {
  open: 'bg-amber-50 text-amber-800 border-amber-100',
  completed: 'bg-emerald-50 text-emerald-800 border-emerald-100',
  cancelled: 'bg-red-50 text-red-800 border-red-100',
  expired: 'bg-base-100 text-base-700 border-base-200',
};

export default function LaybysPage() {
  const [data, setData] = useState<LaybyAdmin[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState('all');
  const [tenantId, setTenantId] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const params = new URLSearchParams({ limit: '500' });
      if (tenantId.trim()) params.set('tenantId', tenantId.trim());
      const response = await fetchJson<{ laybys: LaybyAdmin[] }>(`/api/admin/laybys?${params}`);
      setData(response.laybys);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load lay-bys');
    } finally {
      setLoading(false);
    }
  }, [tenantId]);

  useEffect(() => { load(); }, [load]);

  const filtered = useMemo(
    () => status === 'all' ? data : data.filter((layby) => layby.status === status),
    [data, status],
  );
  const fmt = (minor: number) => new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format(minor / 100);
  const openCount = data.filter((layby) => layby.status === 'open').length;

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <h2 className="text-2xl font-semibold tracking-tight text-base-900">Fashion lay-bys</h2>
            <p className="text-sm text-base-500">Reservations and deposits across tenant shops.</p>
          </div>
          <button onClick={load} disabled={loading} className="btn btn-secondary disabled:opacity-50">
            {loading ? 'Refreshing…' : 'Refresh'}
          </button>
        </div>

        {error && <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div className="card p-4"><p className="text-xs font-medium text-base-500">Visible lay-bys</p><p className="text-lg font-semibold text-base-900">{loading ? '…' : filtered.length}</p></div>
          <div className="card p-4"><p className="text-xs font-medium text-base-500">Open reservations</p><p className="text-lg font-semibold text-base-900">{loading ? '…' : openCount}</p></div>
          <div className="card p-4"><p className="text-xs font-medium text-base-500">Open balance</p><p className="text-lg font-semibold text-base-900">{fmt(data.filter((layby) => layby.status === 'open').reduce((sum, layby) => sum + layby.totalMinor - layby.paidMinor, 0))}</p></div>
        </div>

        <div className="card p-5">
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <label className="flex flex-col gap-2"><span className="label">Status</span><select className="input" value={status} onChange={(event) => setStatus(event.target.value)}><option value="all">All statuses</option><option value="open">Open</option><option value="completed">Completed</option><option value="cancelled">Cancelled</option><option value="expired">Expired</option></select></label>
            <label className="flex flex-col gap-2"><span className="label">Tenant</span><input className="input" value={tenantId} onChange={(event) => setTenantId(event.target.value)} placeholder="tenant ID" /></label>
          </div>
        </div>

        {loading && data.length === 0 ? <div className="card p-8 text-sm text-base-500">Loading lay-bys…</div> : (
          <DataTable
            columns={[
              { key: 'createdAt', label: 'Created', sortable: true },
              { key: 'tenant', label: 'Shop' },
              { key: 'status', label: 'Status', sortable: true },
              { key: 'totalMinor', label: 'Total', sortable: true, align: 'right' },
              { key: 'paidMinor', label: 'Paid', sortable: true, align: 'right' },
              { key: 'dueAt', label: 'Due', sortable: true },
              { key: 'items', label: 'Items' },
            ]}
            data={filtered}
            rowKey={(layby) => layby.remoteId}
            emptyMessage="No lay-bys match the selected filters"
            renderCell={(row, key) => {
              if (key === 'createdAt' || key === 'dueAt') return <span className="text-sm text-base-600">{new Date(row[key]).toLocaleString()}</span>;
              if (key === 'tenant') return <span className="text-base-900">{row.tenant?.shopName ?? 'Unknown shop'}</span>;
              if (key === 'status') return <span className={`badge ${STATUS_STYLES[row.status] ?? STATUS_STYLES.expired}`}>{row.status}</span>;
              if (key === 'totalMinor' || key === 'paidMinor') return <span className="font-mono tabular-nums text-base-900">{fmt(row[key])}</span>;
              if (key === 'items') return <span className="text-base-700">{row.items.map((item) => `${item.productName}${item.variantName ? ` · ${item.variantName}` : ''} × ${item.qty}`).join(', ')}</span>;
              return null;
            }}
          />
        )}
      </div>
    </ShellLayout>
  );
}
