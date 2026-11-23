'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { AuditLog } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

export default function AuditPage() {
  const [data, setData] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [running, setRunning] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetchJson<{ logs: AuditLog[] }>('/api/admin/audit?limit=100');
      setData(res.logs);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load audit log');
    } finally {
      setLoading(false);
    }
  }, []);
  useAdminLiveRefresh(load, ['audit']);
  useEffect(() => { void load(); }, [load]);

  const runRetention = async () => {
    setRunning(true); setMsg(null);
    try {
      await fetchJson('/api/admin/retention/run', { method: 'POST', body: JSON.stringify({ olderThanDays: 30, dryRun: 0 }) });
      setMsg('Retention run completed.');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Retention failed');
    } finally {
      setRunning(false);
    }
  };

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-2xl font-semibold tracking-tight text-base-900">Audit log</h2>
            <p className="text-sm text-base-500">Admin audit log across all tenants.</p>
          </div>
          <button className="button-secondary" onClick={runRetention} disabled={running}>{running ? 'Running…' : 'Run retention'}</button>
        </div>

        {error && (
          <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">
            {error}
          </div>
        )}
        {msg && <div className="rounded-xl border border-accent-200 bg-accent-50 px-4 py-3 text-sm text-accent-800">{msg}</div>}

        <DataTable
          columns={[
            { key: 'adminId', label: 'Admin (sub)' },
            { key: 'action', label: 'Action', sortable: true },
            { key: 'targetType', label: 'Target type' },
            { key: 'targetId', label: 'Target ID' },
            { key: 'tenantId', label: 'Tenant' },
            { key: 'at', label: 'Timestamp', sortable: true },
          ]}
          data={data}
          rowKey={(r) => `${r.at}-${r.action}-${r.targetId}`}
          renderCell={(row, key) => {
            if (key === 'at') {
              return (
                <span className="text-sm text-base-500">{new Date(row.at).toLocaleString()}</span>
              );
            }
            const v = row[key as keyof AuditLog];
            return <span className="text-base-900">{v == null ? '—' : String(v)}</span>;
          }}
          emptyMessage="No audit entries"
        />
      </div>
    </ShellLayout>
  );
}
