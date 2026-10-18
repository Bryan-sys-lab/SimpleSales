'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { AppSession } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';

export default function SessionsPage() {
  const [data, setData] = useState<AppSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetchJson<{ sessions: AppSession[] }>('/api/admin/sessions?limit=100');
        if (!cancelled) setData(res.sessions);
      } catch (err) {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Failed to load sessions');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">App sessions</h2>
          <p className="text-sm text-base-500">Active app sessions across all tenants.</p>
        </div>

        {error && (
          <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">
            {error}
          </div>
        )}

        <DataTable
          columns={[
            { key: 'tenant.shopName', label: 'Tenant' },
            { key: 'device', label: 'Device' },
            { key: 'createdAt', label: 'Created at', sortable: true },
            { key: 'expiresAt', label: 'Expires at', sortable: true },
          ]}
          data={data}
          rowKey={(r) => r.id}
          renderCell={(row, key) => {
            if (key === 'tenant.shopName') {
              return <span className="text-base-900">{row.tenant?.shopName ?? row.tenantId}</span>;
            }
            if (key === 'device') {
              return <span className="text-base-900">{row.device ?? '—'}</span>;
            }
            if (key === 'createdAt' || key === 'expiresAt') {
              return (
                <span className="text-sm text-base-500">
                  {new Date(row[key as keyof AppSession] as string).toLocaleString()}
                </span>
              );
            }
            const v = row[key as keyof AppSession];
            return <span className="text-base-900">{v == null ? '—' : String(v)}</span>;
          }}
          emptyMessage="No sessions"
        />
      </div>
    </ShellLayout>
  );
}
