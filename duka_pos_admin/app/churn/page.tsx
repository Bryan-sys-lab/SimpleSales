'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ChurnSnapshot } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

const RISK_ORDER: Record<string, number> = { none: 0, low: 1, medium: 2, high: 3 };
const getRiskSortValue = (snapshot: ChurnSnapshot) => RISK_ORDER[snapshot.risk] ?? 0;

export default function ChurnPage() {
  const [data, setData] = useState<ChurnSnapshot[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetchJson<{ snapshots: ChurnSnapshot[] }>('/api/admin/churn?limit=100');
      setData(res.snapshots);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load churn data');
    } finally {
      setLoading(false);
    }
  }, []);
  useAdminLiveRefresh(load, ['churn']);

  useEffect(() => {
    load();
  }, [load]);

  const riskBadge = (risk: string) => {
    const variants: Record<string, string> = {
      none: 'bg-sage-50 text-sage-800 border-sage-200',
      low: 'bg-electric-50 text-electric-800 border-electric-200',
      medium: 'bg-coral-50 text-coral-800 border-coral-200',
      high: 'bg-coral-100 text-coral-900 border-coral-300',
    };
    return variants[risk] || variants.none;
  };

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-semibold tracking-tight text-base-900">Churn risk</h1>
            <p className="text-sm text-base-500">Churn snapshots across all tenant shops.</p>
          </div>
        </div>

        {error && (
          <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">
            {error}
          </div>
        )}

        <DataTable
          caption="Churn risk records"
          initialSort={{ key: 'risk', direction: 'desc' }}
          columns={[
            { key: 'tenant.shopName', label: 'Shop', sortable: true },
            { key: 'streakDays', label: 'Inactive streak (days)', sortable: true, align: 'right' },
            { key: 'daysSinceLastActive', label: 'Days since last active', sortable: true, align: 'right' },
            { key: 'risk', label: 'Risk', sortable: true, sortValue: getRiskSortValue },
            { key: 'score', label: 'Score', sortable: true, align: 'right' },
            { key: 'dropReason', label: 'Drop reason', sortable: true },
            { key: 'computedAt', label: 'Last computed', sortable: true },
          ]}
          data={data}
          rowKey={(r) => `${r.tenantId}-${r.computedAt}`}
          renderCell={(row, key) => {
            if (key === 'tenant.shopName') {
              return <span className="text-base-900">{row.tenant?.shopName ?? row.tenantId}</span>;
            }
            if (key === 'risk') {
              return (
                <span className={`badge ${riskBadge(row.risk)}`}>{row.risk}</span>
              );
            }
            if (key === 'score') {
              return <span className="font-mono tabular-nums text-base-900">{Number(row.score).toFixed(2)}</span>;
            }
            if (key === 'dropReason') {
              return <span className="text-sm text-base-700">{row.dropReason ?? '—'}</span>;
            }
            if (key === 'computedAt') {
              return <span className="text-sm text-base-500">{new Date(row.computedAt).toLocaleString()}</span>;
            }
            const v = row[key as keyof ChurnSnapshot];
            return <span className="text-base-900">{v == null ? '--' : String(v)}</span>;
          }}
          emptyMessage="No churn snapshots"
        />
      </div>
    </ShellLayout>
  );
}
