'use client';

import { useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { DashboardStats, Tenant } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { MetricCard } from '@/components/metric-card';
import { DataTable } from '@/components/data-table';

export default function DashboardPage() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [statsRes, tenantsRes] = await Promise.all([
          fetchJson<DashboardStats>('/api/admin/dashboard'),
          fetchJson<{ tenants: Tenant[] }>('/api/admin/tenants?limit=8'),
        ]);
        if (!cancelled) {
          setStats(statsRes);
          setTenants(tenantsRes.tenants);
        }
      } catch (err) {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Failed to load dashboard');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const riskColors: Record<string, string> = {
    none: 'bg-emerald-50 text-emerald-800 border-emerald-100',
    low: 'bg-blue-50 text-blue-800 border-blue-100',
    medium: 'bg-amber-50 text-amber-800 border-amber-100',
    high: 'bg-red-50 text-red-800 border-red-100',
  };

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">Overview</h2>
          <p className="text-sm text-base-500">Platform metrics across all tenant shops.</p>
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <MetricCard label="Tenants" value={stats?.tenants ?? '--'} />
          <MetricCard label="Active users" value={stats?.activeUsers ?? '--'} />
          <MetricCard
            label="Total sales"
            value={stats?.sales.total != null ? new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format(stats.sales.total) : '--'}
            trend={{
              label: 'Sales count',
              delta: stats?.sales.count ?? 0,
            }}
          />
          <MetricCard
            label="Total profit"
            value={stats?.sales.profit != null ? new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format(stats.sales.profit) : '--'}
          />
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-base-900 mb-4">Churn distribution</h3>
            <div className="space-y-3">
              {Object.entries(stats?.churnByRisk ?? {}).map(([risk, count]) => (
                <div key={risk} className="flex items-center justify-between text-sm">
                  <span className="text-base-600 capitalize">{risk}</span>
                  <span className="font-mono tabular-nums text-base-900">{count}</span>
                </div>
              ))}
              {Object.keys(stats?.churnByRisk ?? {}).length === 0 && (
                <p className="text-sm text-base-400">No churn data</p>
              )}
            </div>
          </div>

          <div className="card p-5">
            <h3 className="text-sm font-semibold text-base-900 mb-4">Tenant health</h3>
            <DataTable
              columns={[
                { key: 'shopName', label: 'Shop' },
                { key: 'activeProfiles', label: 'Active profiles', sortable: true },
                { key: 'sales', label: 'Total sales', sortable: true },
              ]}
              data={tenants}
              rowKey={(t) => t.id}
              renderCell={(row) => (
                <div className="flex items-center gap-3">
                  <span className="text-base-900">{row.shopName}</span>
                  <span className="ml-auto text-base-500">{row._count?.profiles ?? 0}</span>
                </div>
              )}
              emptyMessage="No tenants"
            />
          </div>
        </div>
      </div>
    </ShellLayout>
  );
}
