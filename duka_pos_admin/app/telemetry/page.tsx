'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { EmptyState } from '@/components/empty-state';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

type TelemetryEvent = {
  id: string;
  tenantId: string;
  tenant: { id: string; shopName: string } | null;
  deviceId: string | null;
  name: string;
  at: string;
  route: string | null;
  createdAt: string;
};

type TelemetryPage = {
  events: TelemetryEvent[];
  nextCursor: string | null;
};

type Filters = { tenantId: string; name: string; from: string; to: string };

function dateBound(value: string, endOfDay: boolean): string {
  if (!value) return '';
  return new Date(`${value}T${endOfDay ? '23:59:59.999' : '00:00:00'}`).toISOString();
}

export default function TelemetryPage() {
  const [filters, setFilters] = useState<Filters>({ tenantId: '', name: '', from: '', to: '' });
  const [appliedFilters, setAppliedFilters] = useState<Filters>(filters);
  const [events, setEvents] = useState<TelemetryEvent[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState('');
  const load = useCallback(async (cursor?: string, append = false) => {
    if (append) setLoadingMore(true);
    else setLoading(true);
    try {
      const params = new URLSearchParams({ limit: '100' });
      if (appliedFilters.tenantId.trim()) params.set('tenantId', appliedFilters.tenantId.trim());
      if (appliedFilters.name.trim()) params.set('name', appliedFilters.name.trim());
      if (appliedFilters.from) params.set('from', dateBound(appliedFilters.from, false));
      if (appliedFilters.to) params.set('to', dateBound(appliedFilters.to, true));
      if (cursor) params.set('cursor', cursor);
      const result = await fetchJson<TelemetryPage>(`/api/admin/telemetry/events?${params.toString()}`);
      setEvents((current) => append ? [...current, ...result.events] : result.events);
      setNextCursor(result.nextCursor);
      setError('');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Failed to load telemetry events');
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [appliedFilters]);
  useAdminLiveRefresh(load, ['telemetry']);

  useEffect(() => {
    void load();
  }, [load]);

  function applyFilters() {
    setAppliedFilters({ ...filters });
  }

  function clearFilters() {
    const empty = { tenantId: '', name: '', from: '', to: '' };
    setFilters(empty);
    setAppliedFilters(empty);
  }

  return (
    <ShellLayout>
      <div className="space-y-6">
        <header>
          <p className="text-sm font-semibold text-accent-800">Security and activity</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">App telemetry</h1>
          <p className="mt-1 max-w-3xl text-sm text-base-600">
            Browse sanitized app events received by the backend. Devices must be online and authenticated to upload; events older than the 90-day retention window are purged. This does not include Cloudflare Worker or GitHub Actions logs.
          </p>
        </header>

        {error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</p>}

        <section className="card grid gap-3 p-4 sm:grid-cols-2 lg:grid-cols-4" aria-label="Telemetry filters">
          <div>
            <label className="label" htmlFor="telemetry-tenant">Shop ID</label>
            <input id="telemetry-tenant" className="input" value={filters.tenantId} onChange={(event) => setFilters({ ...filters, tenantId: event.target.value })} placeholder="All shops" />
          </div>
          <div>
            <label className="label" htmlFor="telemetry-name">Event name</label>
            <input id="telemetry-name" className="input" value={filters.name} onChange={(event) => setFilters({ ...filters, name: event.target.value })} placeholder="e.g. app_open" />
          </div>
          <div>
            <label className="label" htmlFor="telemetry-from">From</label>
            <input id="telemetry-from" className="input" type="date" value={filters.from} onChange={(event) => setFilters({ ...filters, from: event.target.value })} />
          </div>
          <div>
            <label className="label" htmlFor="telemetry-to">Through</label>
            <input id="telemetry-to" className="input" type="date" value={filters.to} onChange={(event) => setFilters({ ...filters, to: event.target.value })} />
          </div>
          <div className="flex flex-wrap gap-2 sm:col-span-2 lg:col-span-4">
            <button type="button" className="button-primary min-h-10" onClick={applyFilters}>Apply filters</button>
            <button type="button" className="button-secondary min-h-10" onClick={clearFilters}>Clear filters</button>
            <button type="button" className="button-secondary min-h-10" onClick={() => void load()}>Refresh</button>
          </div>
        </section>

        <section className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h2 className="text-lg font-semibold">Received events</h2>
            <span className="text-sm text-base-500">{events.length} loaded</span>
          </div>
          {loading && events.length === 0 ? (
            <div className="card p-5 text-sm text-base-500" role="status">Loading telemetry…</div>
          ) : events.length === 0 ? (
            <div className="card"><EmptyState message="No telemetry events match these filters. Offline or signed-out devices may still have events waiting to upload." /></div>
          ) : (
            <>
              <DataTable
                caption="App telemetry events"
                columns={[
                  { key: 'at', label: 'Occurred', sortable: true },
                  { key: 'shop', label: 'Shop', sortable: true },
                  { key: 'name', label: 'Event', sortable: true },
                  { key: 'route', label: 'Route' },
                  { key: 'deviceId', label: 'Device' },
                  { key: 'createdAt', label: 'Received', sortable: true },
                ]}
                data={events}
                rowKey={(event) => event.id}
                renderCell={(event, key) => {
                  if (key === 'at' || key === 'createdAt') return <time className="text-xs text-base-600">{new Date(event[key]).toLocaleString()}</time>;
                  if (key === 'shop') return <span>{event.tenant?.shopName ?? event.tenantId}</span>;
                  if (key === 'name') return <span className="font-medium">{event.name}</span>;
                  if (key === 'route') return <span className="font-mono text-xs">{event.route ?? '—'}</span>;
                  if (key === 'deviceId') return event.deviceId
                    ? <span className="font-mono text-xs" title={event.deviceId}>{event.deviceId.slice(0, 12)}…</span>
                    : <span>Unknown</span>;
                  return null;
                }}
                emptyMessage="No telemetry events"
              />
              {nextCursor && (
                <div className="flex justify-center">
                  <button type="button" className="button-secondary min-h-10" disabled={loadingMore} onClick={() => void load(nextCursor, true)}>
                    {loadingMore ? 'Loading…' : 'Load more events'}
                  </button>
                </div>
              )}
            </>
          )}
        </section>
      </div>
    </ShellLayout>
  );
}
