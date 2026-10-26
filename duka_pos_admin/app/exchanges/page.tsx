'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ExchangeAdmin } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';

export default function ExchangesPage() {
  const [data, setData] = useState<ExchangeAdmin[]>([]);
  const [tenantId, setTenantId] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const params = new URLSearchParams({ limit: '500' });
      if (tenantId.trim()) params.set('tenantId', tenantId.trim());
      setData((await fetchJson<{ exchanges: ExchangeAdmin[] }>(`/api/admin/exchanges?${params}`)).exchanges);
    } catch (err) { setError(err instanceof Error ? err.message : 'Failed to load exchanges'); }
    finally { setLoading(false); }
  }, [tenantId]);
  useEffect(() => { load(); }, [load]);
  const fmt = (minor: number) => new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format(minor / 100);
  return <ShellLayout><div className="space-y-6">
    <div className="flex flex-wrap items-start justify-between gap-4"><div><h2 className="text-2xl font-semibold tracking-tight text-base-900">Fashion exchanges</h2><p className="text-sm text-base-500">Return, credit, replacement sale and price-difference links.</p></div><button onClick={load} disabled={loading} className="btn btn-secondary disabled:opacity-50">{loading ? 'Refreshing…' : 'Refresh'}</button></div>
    {error && <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
    <div className="card p-5"><label className="flex max-w-sm flex-col gap-2"><span className="label">Tenant</span><input className="input" value={tenantId} onChange={(event) => setTenantId(event.target.value)} placeholder="tenant ID" /></label></div>
    <DataTable columns={[{ key: 'createdAt', label: 'Created', sortable: true }, { key: 'tenant', label: 'Shop' }, { key: 'links', label: 'Linked documents' }, { key: 'difference', label: 'Difference', align: 'right' }, { key: 'reason', label: 'Reason' }]} data={data} rowKey={(row) => row.remoteId} emptyMessage={loading ? 'Loading exchanges…' : 'No exchanges found'} renderCell={(row, key) => { if (key === 'createdAt') return <span className="text-sm text-base-600">{new Date(row.createdAt).toLocaleString()}</span>; if (key === 'tenant') return <span>{row.tenant?.shopName ?? 'Unknown shop'}</span>; if (key === 'links') return <span className="font-mono text-xs">sale #{row.originalSaleLocalId} → return #{row.returnLocalId} → sale #{row.replacementSaleLocalId}</span>; if (key === 'difference') return <span className="font-mono tabular-nums">{row.differenceDirection === 'even' ? 'Even' : `${row.differenceDirection === 'customer_pays' ? '+' : '-'}${fmt(row.differenceMinor)}`}</span>; if (key === 'reason') return <span>{row.reason}</span>; return null; }} />
  </div></ShellLayout>;
}
