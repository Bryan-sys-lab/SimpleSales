'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { DeviceDiagnostic } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { useAdminLiveRefresh } from '@/components/websocket-provider';
import { EmptyState } from '@/components/empty-state';

type DiagnosticsListItem = {
  id: string;
  deviceId: string;
  tenantName: string;
  platform: string;
  osVersion: string;
  appVersion: string;
  buildNumber: string;
  locale: string;
  manufacturer: string | null;
  model: string | null;
  crashCount: number;
  errorCount: number;
  warningCount: number;
  firstSeen: string;
  lastSeen: string;
};

export default function DiagnosticsPage() {
  const [items, setItems] = useState<DiagnosticsListItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<DeviceDiagnostic | null>(null);
  const load = useCallback(async (cursor?: string, append = false, silent = false) => {
      if (append) setLoadingMore(true);
      else if (!silent) setLoading(true);
      try {
        const params = new URLSearchParams({ limit: '100' });
        if (cursor) params.set('cursor', cursor);
        const res = await fetchJson<{ diagnostics: DeviceDiagnostic[]; nextCursor: string | null }>(`/api/admin/diagnostics?${params.toString()}`);
        const page = res.diagnostics.map((d) => ({
          id: d.id, deviceId: d.deviceId, tenantName: d.tenant?.shopName ?? '(unlinked)',
          platform: d.platform, osVersion: d.osVersion, appVersion: d.appVersion,
          buildNumber: d.buildNumber, locale: d.locale, manufacturer: d.manufacturer,
          model: d.model, crashCount: d.crashCount, errorCount: d.errorCount,
          warningCount: d.warningCount, firstSeen: d.firstSeen, lastSeen: d.lastSeen,
        }));
        setItems((current) => append ? [...current, ...page] : page);
        setNextCursor(res.nextCursor);
        setError(null);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load diagnostics');
      } finally {
        if (!silent) setLoading(false);
        setLoadingMore(false);
      }
  }, []);
  const openDiagnostic = useCallback(async (id: string) => {
    try {
      const res = await fetchJson<DeviceDiagnostic>(
        `/api/admin/diagnostics/${id}`,
      );
      setSelected(res);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : 'Failed to load diagnostic',
      );
    }
  }, []);

  const refresh = useCallback(async () => {
    await load(undefined, false, true);
    if (selected?.id) await openDiagnostic(selected.id);
  }, [load, openDiagnostic, selected?.id]);
  useAdminLiveRefresh(refresh, ['diagnostics']);
  useEffect(() => { void load(); }, [load]);

  const kindColors: Record<string, string> = {
    crash: 'bg-coral-100 text-coral-900 border-coral-300',
    error: 'bg-coral-50 text-coral-800 border-coral-200',
    warning: 'bg-electric-50 text-electric-800 border-electric-200',
  };
  const selectedEntries = selected?.crashes ?? selected?.recentCrashes ?? [];

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">
            Device diagnostics
          </h2>
          <p className="text-sm text-base-500">
            Failure reports pushed from till phones. See what broke, on what
            phone, under what conditions. Reports appear only after a device is
            online, signed in, and able to upload its local diagnostics.
          </p>
        </div>

        {error && (
          <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-red-800 text-sm">
            {error}
          </div>
        )}

        <div className="card p-5">
          <h3 className="text-sm font-semibold text-base-900 mb-4">
            Reporting devices
          </h3>
          {loading ? (
            <p className="text-sm text-base-500">Loading…</p>
          ) : items.length === 0 ? (
            <EmptyState message="No devices have reported diagnostics yet. A till pushes its failure log from the Diagnostics screen." />
          ) : (
            <>
              <DataTable
                columns={[
                  { key: 'deviceId', label: 'Device id', sortable: true },
                  { key: 'tenantName', label: 'Shop', sortable: true },
                  { key: 'platform', label: 'Platform', sortable: true },
                  { key: 'appVersion', label: 'App version', sortable: true },
                  { key: 'buildNumber', label: 'Build', sortable: true },
                  { key: 'crashCount', label: 'Crashes', sortable: true },
                  { key: 'errorCount', label: 'Errors', sortable: true },
                  { key: 'warningCount', label: 'Warnings', sortable: true },
                  { key: 'lastSeen', label: 'Last seen', sortable: true },
                ]}
                data={items}
                rowKey={(r) => r.id}
                renderCell={(row, key) => {
                  const value = row[key as keyof DiagnosticsListItem];
                  if (key === 'lastSeen') {
                    return (
                      <span className="text-base-500 font-mono text-xs">
                        {new Date(value as string).toLocaleString()}
                      </span>
                    );
                  }
                  if (key === 'platform') {
                    return (
                      <span className="badge border-base-200 bg-base-100 text-base-700">{String(value)}</span>
                    );
                  }
                  return (
                    <span className="text-base-600">{String(value)}</span>
                  );
                }}
                onRowClick={(row) => openDiagnostic(row.id as string)}
                emptyMessage="No devices"
              />
              {nextCursor && (
                <div className="mt-4 flex justify-center">
                  <button type="button" className="button-secondary min-h-10" disabled={loadingMore} onClick={() => void load(nextCursor, true)}>
                    {loadingMore ? 'Loading…' : 'Load more devices'}
                  </button>
                </div>
              )}
            </>
          )}
        </div>

        {selected && (
          <div className="card p-5">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-base-900">
                Device {selected.deviceId}
              </h3>
              <button
                onClick={() => setSelected(null)}
                className="text-sm text-base-600 hover:text-base-900"
              >
                ← Back to list
              </button>
            </div>

            <div className="grid grid-cols-1 gap-3 sm:grid-cols-4 text-sm mb-6">
              <div className="bg-base-100 rounded-lg p-3">
                <div className="text-base-500 text-xs uppercase tracking-wider font-semibold">Platform</div>
                <div className="text-base-900">{selected.platform}</div>
              </div>
              <div className="bg-base-100 rounded-lg p-3">
                <div className="text-base-500 text-xs uppercase tracking-wider font-semibold">OS version</div>
                <div className="text-base-900 font-mono">{selected.osVersion}</div>
              </div>
              <div className="bg-base-100 rounded-lg p-3">
                <div className="text-base-500 text-xs uppercase tracking-wider font-semibold">App version</div>
                <div className="text-base-900">{selected.appVersion}</div>
              </div>
              <div className="bg-base-100 rounded-lg p-3">
                <div className="text-base-500 text-xs uppercase tracking-wider font-semibold">Build</div>
                <div className="text-base-900 font-mono">{selected.buildNumber}</div>
              </div>
              <div className="bg-base-100 rounded-lg p-3">
                <div className="text-base-500 text-xs uppercase tracking-wider font-semibold">Locale</div>
                <div className="text-base-900">{selected.locale}</div>
              </div>
              <div className="bg-base-100 rounded-lg p-3">
                <div className="text-base-500 text-xs uppercase tracking-wider font-semibold">Manufacturer</div>
                <div className="text-base-900">{selected.manufacturer ?? '—'}</div>
              </div>
              <div className="bg-base-100 rounded-lg p-3">
                <div className="text-base-500 text-xs uppercase tracking-wider font-semibold">Model</div>
                <div className="text-base-900 font-mono">{selected.model ?? '—'}</div>
              </div>
              <div className="bg-base-100 rounded-lg p-3">
                <div className="text-base-500 text-xs uppercase tracking-wider font-semibold">Shop</div>
                <div className="text-base-900">{selected.tenant?.shopName ?? '(unlinked)'}</div>
              </div>
            </div>

            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3 text-sm mb-6">
              <div className="bg-red-50 rounded-lg p-3">
                <div className="text-red-800 text-xs uppercase tracking-wider font-semibold">Crashes</div>
                <div className="text-red-800 font-mono text-xl">{selected.crashCount}</div>
              </div>
              <div className="bg-amber-50 rounded-lg p-3">
                <div className="text-amber-800 text-xs uppercase tracking-wider font-semibold">Errors</div>
                <div className="text-amber-800 font-mono text-xl">{selected.errorCount}</div>
              </div>
              <div className="bg-blue-50 rounded-lg p-3">
                <div className="text-blue-800 text-xs uppercase tracking-wider font-semibold">Warnings</div>
                <div className="text-blue-800 font-mono text-xl">{selected.warningCount}</div>
              </div>
            </div>

            <div className="bg-base-100 rounded-lg border border-base-200 overflow-hidden">
              <h3 className="px-4 py-3 text-xs font-semibold text-base-600 uppercase tracking-wider border-b border-base-200">
                Failure entries
              </h3>
              {selectedEntries.length === 0 ? (
                <EmptyState message="No failure entries recorded." compact />
              ) : (
                <div className="divide-y divide-base-200">
                  {selectedEntries.map((entry) => (
                    <div key={entry.id} className="p-4">
                      <div className="flex items-start gap-3 mb-1">
                        <span
                          className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${kindColors[entry.kind] ?? 'bg-base-200 text-base-600'}`}
                        >
                          {entry.kind}
                        </span>
                        <span className="ml-auto text-base-500 text-xs font-mono">
                          {new Date(entry.createdAt).toLocaleString()}
                        </span>
                      </div>
                      <div className="text-base-900 text-sm mb-1">{entry.message}</div>
                      {entry.route && (
                        <div className="text-xs text-base-500 mb-1">
                          route: {entry.route}
                          {entry.actorName ? ` · actor: ${entry.actorName}` : ''}
                          {entry.action ? ` · action: ${entry.action}` : ''}
                        </div>
                      )}
                      {entry.breadcrumbs && (
                        <div className="whitespace-pre-wrap break-words text-xs text-base-600 mb-2">
                          trail: {entry.breadcrumbs}
                        </div>
                      )}
                      {entry.stack && (
                        <div className="whitespace-pre-wrap break-words text-xs font-mono text-base-600 mt-1 max-h-48 overflow-y-auto">
                          {entry.stack}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </ShellLayout>
  );
}
