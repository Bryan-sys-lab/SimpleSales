'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { Tenant } from '@/lib/types';
import { ShellLayout, useAdminAccess } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import Link from 'next/link';

export default function TenantsPage() {
  const { can } = useAdminAccess(); const canManageTenants = can('tenants:manage');
  const [data, setData] = useState<Tenant[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchJson<{ tenants: Tenant[] }>('/api/admin/tenants');
      setData(res.tenants.map((tenant) => ({
        ...tenant,
        activeProfiles: tenant._count?.profiles ?? 0,
        salesCount: tenant._count?.sales ?? 0,
      })));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load tenants');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const act = async (id: string, setting: 'mpesaEnabled' | 'etimsEnabled', value: boolean) => {
    try {
      await fetchJson(`/api/system/tenants/${encodeURIComponent(id)}/settings`, { method: 'PATCH', body: JSON.stringify({ [setting]: value }) });
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
            { key: 'activeProfiles', label: 'Active profiles', sortable: true, align: 'right' },
            { key: 'salesCount', label: 'Sales count', sortable: true, align: 'right' },
            { key: 'mpesaEnabled', label: 'M-Pesa' },
            { key: 'etimsEnabled', label: 'eTIMS' },
            { key: 'businessContext', label: 'Business details' },
            ...(canManageTenants ? [{ key: 'actions', label: 'Controls' }] : []),
          ]}
          data={data}
          rowKey={(t) => t.id}
          renderCell={(row, key) => {
            if (key === 'shopName') return <span className="text-base-900">{row.shopName}</span>;
            if (key === 'admin') return <span className="text-base-900">{row.admin ?? '—'}</span>;
            if (key === 'activeProfiles') return <span className="font-mono tabular-nums text-base-900">{row.activeProfiles ?? 0}</span>;
            if (key === 'salesCount') return <span className="font-mono tabular-nums text-base-900">{row.salesCount ?? 0}</span>;
            if (key === 'mpesaEnabled') return <span className={`badge ${(row as any).mpesaEnabled ? 'badge-none' : 'badge-high'}`}>{(row as any).mpesaEnabled ? 'On' : 'Off'}</span>;
            if (key === 'etimsEnabled') return <span className={`badge ${(row as any).etimsEnabled ? 'badge-none' : 'badge-high'}`}>{(row as any).etimsEnabled ? 'On' : 'Off'}</span>;
            if (key === 'businessContext') return <Link className="button-secondary inline-flex min-h-11 items-center" href={`/tenants/${encodeURIComponent(row.id)}/business-context`} onClick={(e) => e.stopPropagation()}>View details</Link>;
            if (key === 'actions') {
              return (
                <div className="flex flex-wrap gap-1">
                  <button className="button-secondary min-h-10 text-xs" onClick={(e) => { e.stopPropagation(); void act(row.id, 'mpesaEnabled', !(row as any).mpesaEnabled); }}>{(row as any).mpesaEnabled ? 'Turn M-Pesa off' : 'Turn M-Pesa on'}</button>
                  <button className="button-secondary min-h-10 text-xs" onClick={(e) => { e.stopPropagation(); void act(row.id, 'etimsEnabled', !(row as any).etimsEnabled); }}>{(row as any).etimsEnabled ? 'Turn eTIMS off' : 'Turn eTIMS on'}</button>
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
