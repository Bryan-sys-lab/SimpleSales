'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { SupportTicket } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';

export default function SupportPage() {
  const [data, setData] = useState<SupportTicket[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('');

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const params = new URLSearchParams({ limit: '100' });
        if (statusFilter) params.set('status', statusFilter);
        const res = await fetchJson<{ tickets: SupportTicket[] }>(
          `/api/admin/support-tickets?${params.toString()}`,
        );
        if (!cancelled) setData(res.tickets);
      } catch (err) {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Failed to load support tickets');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [statusFilter]);

  const filtered = useMemo(
    () => data.filter((t) => !statusFilter || t.status === statusFilter),
    [data, statusFilter],
  );

  const statusBadge = (status: string) => {
    const variants: Record<string, string> = {
      open: 'bg-red-50 text-red-700 border-red-100',
      in_progress: 'bg-blue-50 text-blue-700 border-blue-100',
      resolved: 'bg-emerald-50 text-emerald-700 border-emerald-100',
      closed: 'bg-base-200 text-base-600 border-base-300',
    };
    return variants[status] || variants.open;
  };

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-2xl font-semibold tracking-tight text-base-900">Support tickets</h2>
            <p className="text-sm text-base-500">Support tickets and requests across all tenants.</p>
          </div>
          <div className="flex items-center gap-2">
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="input text-sm"
              aria-label="Filter by status"
            >
              <option value="">All statuses</option>
              <option value="open">Open</option>
              <option value="in_progress">In progress</option>
              <option value="resolved">Resolved</option>
              <option value="closed">Closed</option>
            </select>
          </div>
        </div>

        {error && (
          <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">
            {error}
          </div>
        )}

        <DataTable
          columns={[
            { key: 'type', label: 'Type' },
            { key: 'title', label: 'Title' },
            { key: 'description', label: 'Description' },
            { key: 'status', label: 'Status', sortable: true },
            { key: 'createdAt', label: 'Created at', sortable: true },
            { key: 'deviceId', label: 'Device ID' },
          ]}
          data={filtered}
          rowKey={(t) => t.id}
          renderCell={(row, key) => {
            if (key === 'type') {
              return (
                <span className="rounded-md border border-base-300 bg-base-100 px-2 py-0.5 text-xs text-base-700">
                  {row.type}
                </span>
              );
            }
            if (key === 'status') {
              return <span className={`badge ${statusBadge(row.status)}`}>{row.status.replace(/_/g, ' ')}</span>;
            }
            if (key === 'description') {
              return (
                <span className="text-base-500 line-clamp-1">{row.description ?? '—'}</span>
              );
            }
            if (key === 'createdAt') {
              return (
                <span className="text-sm text-base-500">{new Date(row.createdAt).toLocaleString()}</span>
              );
            }
            const v = row[key as keyof SupportTicket];
            return <span className="text-base-900">{v == null ? '—' : String(v)}</span>;
          }}
          emptyMessage="No support tickets"
        />
      </div>
    </ShellLayout>
  );
}
