'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { DashboardStats, Tenant } from '@/lib/types';
import { ShellLayout, useAdminAccess } from '@/components/layout';
import { MetricCard } from '@/components/metric-card';
import { DataTable } from '@/components/data-table';
import { EmptyState } from '@/components/empty-state';
import { useAdminLiveRefresh, useWebSocket } from '@/components/websocket-provider';

type ObservabilityRange = '24h' | '7d' | '30d';
type TelemetrySummary = {
  range: ObservabilityRange;
  from: string;
  eventCount: number;
  eventTypes: Array<{ name: string; count: number }>;
  trend: Array<{ hour: string; count: number }>;
};
type DiagnosticsSummary = {
  range: ObservabilityRange;
  from: string;
  deviceCount: number;
  entries: Array<{ kind: string; count: number }>;
};
function makeTrendBuckets(summary: TelemetrySummary | null, range: ObservabilityRange) {
  const count = range === '24h' ? 24 : range === '7d' ? 7 : 30;
  const step = range === '24h' ? 60 * 60 * 1000 : 24 * 60 * 60 * 1000;
  const end = Math.floor(Date.now() / step) * step + step;
  const start = end - count * step;
  const buckets = Array.from({ length: count }, (_, index) => ({
    label: new Date(start + (index + 1) * step).toLocaleString(undefined, range === '24h'
      ? { hour: 'numeric' }
      : { month: 'short', day: 'numeric' }),
    count: 0,
  }));
  for (const point of summary?.trend ?? []) {
    const index = Math.floor((Date.parse(point.hour) - start) / step);
    if (index >= 0 && index < buckets.length) buckets[index].count += point.count;
  }
  return buckets;
}

export default function DashboardPage() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sys, setSys] = useState<any>(null);
  const [range, setRange] = useState<ObservabilityRange>('24h');
  const [telemetry, setTelemetry] = useState<TelemetrySummary | null>(null);
  const [diagnostics, setDiagnostics] = useState<DiagnosticsSummary | null>(null);
  const [observabilityError, setObservabilityError] = useState('');
  const { access, can } = useAdminAccess();
  const { connected, activity } = useWebSocket();
  const canReadTelemetry = can('sessions:read');
  const canReadDiagnostics = can('diagnostics:read');

  const loadOverview = useCallback(async () => {
    setLoading(true);
    try {
      const [statsRes, tenantsRes, sysRes] = await Promise.all([
        fetchJson<DashboardStats>('/api/admin/dashboard'),
        fetchJson<{ tenants: Tenant[] }>('/api/admin/tenants?limit=8&activity=30d'),
        fetchJson<any>('/api/system/analytics'),
      ]);
      setStats(statsRes);
      setTenants(tenantsRes.tenants.map((tenant) => ({
        ...tenant,
        activeProfiles: tenant._count?.profiles ?? 0,
        salesCount: tenant.activity30d?.salesCount ?? 0,
        lastSaleAt: tenant.activity30d?.lastSaleAt ?? null,
      })));
      setSys(sysRes);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load dashboard');
    } finally {
      setLoading(false);
    }
  }, []);
  useAdminLiveRefresh(loadOverview, ['dashboard']);
  useEffect(() => { void loadOverview(); }, [loadOverview]);

  const loadTelemetry = useCallback(async () => {
    if (!canReadTelemetry) { setTelemetry(null); return; }
    try {
      setTelemetry(await fetchJson<TelemetrySummary>(`/api/admin/observability/telemetry?range=${range}`));
      setObservabilityError('');
    } catch (cause) {
      setObservabilityError(cause instanceof Error ? cause.message : 'Failed to load telemetry summary');
    }
  }, [canReadTelemetry, range]);
  useAdminLiveRefresh(loadTelemetry, ['telemetry'], canReadTelemetry);
  useEffect(() => { if (access) void loadTelemetry(); }, [access, loadTelemetry]);

  const loadDiagnostics = useCallback(async () => {
    if (!canReadDiagnostics) { setDiagnostics(null); return; }
    try {
      setDiagnostics(await fetchJson<DiagnosticsSummary>(`/api/admin/observability/diagnostics?range=${range}`));
      setObservabilityError('');
    } catch (cause) {
      setObservabilityError(cause instanceof Error ? cause.message : 'Failed to load diagnostics summary');
    }
  }, [canReadDiagnostics, range]);
  useAdminLiveRefresh(loadDiagnostics, ['diagnostics'], canReadDiagnostics);
  useEffect(() => { if (access) void loadDiagnostics(); }, [access, loadDiagnostics]);

  const trendBuckets = useMemo(() => makeTrendBuckets(telemetry, range), [range, telemetry]);
  const maxTrend = Math.max(1, ...trendBuckets.map((bucket) => bucket.count));
  const diagnosticCounts = Object.fromEntries((diagnostics?.entries ?? []).map((entry) => [entry.kind, entry.count]));

  const riskColors: Record<string, string> = {
    none: 'bg-sage-50 text-sage-800 border-sage-200',
    low: 'bg-electric-50 text-electric-800 border-electric-200',
    medium: 'bg-coral-50 text-coral-800 border-coral-200',
    high: 'bg-coral-100 text-coral-900 border-coral-300',
  };

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-base-900">Overview</h1>
          <p className="text-sm text-base-500">Platform metrics across all tenant shops.</p>
        </div>

        {access && (canReadTelemetry || canReadDiagnostics) && (
          <section className="space-y-4" aria-label="Live observability overview">
            <div className="flex flex-wrap items-end justify-between gap-3">
              <div>
                <p className="text-sm font-semibold text-accent-800">Observability</p>
                <h2 className="text-xl font-semibold tracking-tight">Live app health</h2>
                <p className="text-sm text-base-500">Sanitized telemetry and uploaded device failures. Cloudflare platform and GitHub Actions logs are not included.</p>
              </div>
              <div className="flex items-center gap-3">
                <span className={`inline-flex items-center gap-2 text-sm ${connected ? 'text-sage-800' : 'text-base-500'}`}>
                  <span className={`h-2 w-2 rounded-full ${connected ? 'bg-sage-500' : 'bg-base-400'}`} />
                  {connected ? 'Live connection' : 'Reconnecting'}
                </span>
                <label className="sr-only" htmlFor="observability-range">Time range</label>
                <select id="observability-range" className="input min-h-10" value={range} onChange={(event) => setRange(event.target.value as ObservabilityRange)}>
                  <option value="24h">Last 24 hours</option>
                  <option value="7d">Last 7 days</option>
                  <option value="30d">Last 30 days</option>
                </select>
              </div>
            </div>
            {observabilityError && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{observabilityError}</p>}
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              {canReadTelemetry && <MetricCard label={`App events · ${range}`} value={telemetry?.eventCount ?? (loading ? '…' : '--')} />}
              {canReadDiagnostics && <MetricCard label="Reporting devices" value={diagnostics?.deviceCount ?? (loading ? '…' : '--')} />}
              {canReadDiagnostics && <MetricCard label="Crashes" value={diagnosticCounts.crash ?? 0} />}
              {canReadDiagnostics && <MetricCard label="Errors and warnings" value={(diagnosticCounts.error ?? 0) + (diagnosticCounts.warning ?? 0)} />}
            </div>
            <div className="grid gap-4 xl:grid-cols-3">
              {canReadTelemetry && <div className="card p-5 xl:col-span-2">
                <div className="mb-4 flex items-center justify-between">
                  <h3 className="text-sm font-semibold">Event volume</h3>
                  <span className="text-xs text-base-500">{range === '24h' ? 'Hourly' : 'Daily'} · UTC window</span>
                </div>
                {telemetry ? <div className="flex h-40 items-end gap-1" role="img" aria-label={`App event volume for the last ${range}`}>
                  {trendBuckets.map((bucket, index) => <div key={`${bucket.label}-${index}`} className="group flex h-full min-w-0 flex-1 flex-col items-center justify-end">
                    <span className="mb-1 text-[10px] text-base-500 opacity-0 group-hover:opacity-100" aria-hidden="true">{bucket.count}</span>
                    <div className="w-full min-h-[2px] rounded-t bg-accent-600" style={{ height: `${Math.max(2, (bucket.count / maxTrend) * 88)}%` }} title={`${bucket.label}: ${bucket.count} events`} />
                    {(index % (range === '24h' ? 4 : range === '7d' ? 1 : 5) === 0 || index === trendBuckets.length - 1) &&
                      <span className="mt-2 truncate text-[9px] text-base-500">{bucket.label}</span>}
                  </div>)}
                </div> : <p className="text-sm text-base-500">Loading event trend…</p>}
              </div>}
              {canReadTelemetry && <div className="card p-5">
                <h3 className="mb-4 text-sm font-semibold">Top event types</h3>
                <div className="space-y-3">
                  {(telemetry?.eventTypes ?? []).map((item) => <div key={item.name} className="flex items-center justify-between gap-3 text-sm">
                    <span className="truncate text-base-600">{item.name.replaceAll('_', ' ')}</span><span className="font-mono tabular-nums">{item.count}</span>
                  </div>)}
                  {telemetry?.eventTypes.length === 0 && <EmptyState message="No app events in this range." compact />}
                  {!telemetry && <p className="text-sm text-base-500">Loading event types…</p>}
                </div>
              </div>}
            </div>
            <div className="card overflow-hidden">
              <div className="flex items-center justify-between border-b border-base-200 p-4">
                <h3 className="text-sm font-semibold">Live event stream</h3>
                <span className="text-xs text-base-500">{activity.length} recent</span>
              </div>
              {activity.length === 0 ? <EmptyState message="Waiting for app telemetry or a device diagnostic upload." compact /> : (
                <ol className="divide-y divide-base-100">
                  {activity.map((event) => <li key={event.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 text-sm">
                    <span className="font-medium">{event.label}</span>
                    <span className="text-base-500">{event.detail} · {new Date(event.at).toLocaleTimeString()}</span>
                  </li>)}
                </ol>
              )}
            </div>
          </section>
        )}

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
            <h2 className="text-sm font-semibold text-base-900 mb-4">Churn distribution</h2>
            <div className="space-y-3">
              {Object.entries(stats?.churnByRisk ?? {}).map(([risk, count]) => (
                <div key={risk} className="flex items-center justify-between text-sm">
                  <span className="text-base-600 capitalize">{risk}</span>
                  <span className="font-mono tabular-nums text-base-900">{count}</span>
                </div>
              ))}
              {Object.keys(stats?.churnByRisk ?? {}).length === 0 && (
                <EmptyState message="No churn data" compact />
              )}
            </div>
          </div>

          <div className="card p-5">
            <h2 className="text-sm font-semibold text-base-900">Shop activity</h2>
            <p className="mb-4 mt-1 text-xs text-base-500">Sales recorded in the last 30 days; active profiles are current.</p>
            <DataTable
              caption="Recent shop activity"
              columns={[
                { key: 'shopName', label: 'Shop', sortable: true },
                { key: 'activeProfiles', label: 'Active profiles', sortable: true, align: 'right' },
                { key: 'salesCount', label: 'Sales · 30d', sortable: true, align: 'right' },
                { key: 'lastSaleAt', label: 'Latest sale · 30d', sortable: true },
              ]}
              data={tenants}
              rowKey={(t) => t.id}
              renderCell={(row, key) => {
                if (key === 'shopName') return <span className="text-base-900">{row.shopName}</span>;
                if (key === 'activeProfiles') return <span>{row.activeProfiles ?? 0}</span>;
                if (key === 'salesCount') return <span>{row.salesCount ?? 0}</span>;
                if (key === 'lastSaleAt') return <span>{row.lastSaleAt ? new Date(row.lastSaleAt).toLocaleDateString() : 'No sales'}</span>;
                return null;
              }}
              emptyMessage="No tenants"
            />
          </div>
        </div>
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div className="card p-5">
            <h2 className="text-sm font-semibold text-base-900 mb-4">Sales by payment method</h2>
            <div className="space-y-3">
              {Object.entries(Object.values(sys?.byTenant ?? {}).reduce((acc: any, t: any) => {
                  Object.entries(t.byPaymentMethod ?? {}).forEach(([m, v]) => { acc[m] = (acc[m] ?? 0) + (v as number); });
                  return acc;
                }, {} as Record<string, number>) as Record<string, number>).map(([method, total]) => {
                const max = Math.max(...Object.values(Object.values(sys?.byTenant ?? {}).reduce((acc: any, t: any) => { Object.entries(t.byPaymentMethod ?? {}).forEach(([m, v]) => { acc[m] = (acc[m] ?? 0) + (v as number); }); return acc; }, {} as Record<string, number>) as Record<string, number>), 1);
                return (
                  <div key={method}>
                    <div className="flex items-center justify-between text-sm mb-1">
                      <span className="text-base-600">{method}</span>
                      <span className="font-mono tabular-nums text-base-900">{new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format((total as number) / 100)}</span>
                    </div>
                    <div className="h-2.5 rounded-full bg-base-100 overflow-hidden">
                      <div className="h-full rounded-full bg-accent-600" style={{ width: `${((total as number) / max) * 100}%` }} />
                    </div>
                  </div>
                );
              })}
              {Object.keys(sys?.byTenant ?? {}).length === 0 && <EmptyState message="No payment data" compact />}
            </div>
          </div>

        </div>
      </div>
    </ShellLayout>
  );
}
