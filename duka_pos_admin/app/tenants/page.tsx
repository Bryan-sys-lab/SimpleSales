'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { Tenant } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';

export default function TenantsPage() {
  const [data, setData] = useState<Tenant[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchJson<{ tenants: Tenant[] }>('/api/admin/tenants');
      setData(res.tenants);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load tenants');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const act = async (id: string, action: 'activate' | 'deactivate' | 'delete') => {
    try {
      await fetchJson(`/api/admin/tenants/${encodeURIComponent(id)}/${action}`, { method: 'POST' });
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Action failed');
    }
  };

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">Tenants</h2>
          <p className="text-sm text-base-500">Tenant directory with profile and sale counts. Actions are audit-logged.</p>
        </div>

        {error && (
          <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">
            {error}
          </div>
        )}

        <DataTable
          columns={[
            { key: 'shopName', label: 'Shop name' },
            { key: 'admin', label: 'Admin' },
            { key: '_count.profiles', label: 'Active profiles', sortable: true, align: 'right' },
            { key: '_count.sales', label: 'Total sales', sortable: true, align: 'right' },
            { key: 'settings', label: 'Settings' },
            { key: 'actions', label: 'Actions' },
          ]}
          data={data}
          rowKey={(t) => t.id}
          renderCell={(row, key) => {
            if (key === 'shopName') return <span className="text-base-900">{row.shopName}</span>;
            if (key === 'admin') return <span className="text-base-900">{row.admin ?? '—'}</span>;
            if (key === '_count.profiles') return <span className="font-mono tabular-nums text-base-900">{row._count?.profiles ?? 0}</span>;
            if (key === '_count.sales') return <span className="font-mono tabular-nums text-base-900">{row._count?.sales ?? 0}</span>;
            if (key === 'settings') {
              const s = row.settings ?? {};
              return (
                <span className="text-xs flex gap-1">
                  {s.mpesa ? <span className="rounded bg-emerald-50 px-1.5 py-0.5 text-emerald-700">M-Pesa</span> : null}
                  {s.etims ? <span className="rounded bg-blue-50 px-1.5 py-0.5 text-blue-700">eTIMS</span> : null}
                  {s.payhero ? <span className="rounded bg-amber-50 px-1.5 py-0.5 text-amber-700">PayHero</span> : null}
                  {!s.mpesa && !s.etims && !s.payhero && <span className="text-base-400">—</span>}
                </span>
              );
            }
            if (key === 'actions') {
              return (
                <div className="flex gap-1">
                  <button className="button-secondary text-xs" onClick={() => act(row.id, 'deactivate')}>Deactivate</button>
                  <button className="button-secondary text-xs" onClick={() => act(row.id, 'delete')}>Delete</button>
                </div>
              );
            }
            const value = row[key as keyof Tenant];
            return <span className="text-base-900">{typeof value === 'object' ? '—' : value ?? '—'}</span>;
          }}
          emptyMessage={loading ? 'Loading tenants…' : 'No tenants'}
        />
      </div>
    </ShellLayout>
  );
}
