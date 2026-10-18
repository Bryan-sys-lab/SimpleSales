'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { Sale } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';

export default function SalesPage() {
  const [data, setData] = useState<Sale[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<{ from: string; to: string; tenantId: string }>({
    from: '',
    to: '',
    tenantId: '',
  });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      if (filter.from) params.set('from', filter.from);
      if (filter.to) params.set('to', filter.to);
      if (filter.tenantId) params.set('tenantId', filter.tenantId);
      params.set('limit', '100');
      const res = await fetchJson<{ sales: Sale[] }>(`/api/admin/sales?${params.toString()}`);
      setData(res.sales);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load sales');
    } finally {
      setLoading(false);
    }
  }, [filter]);

  useEffect(() => {
    load();
  }, [load]);

  const totals = useMemo(
    () => data.reduce((acc, s) => ({ total: acc.total + s.total, profit: acc.profit + s.profit }), { total: 0, profit: 0 }),
    [data],
  );

  const fmt = (n: number) => new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format(n);

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-2xl font-semibold tracking-tight text-base-900">Sales</h2>
            <p className="text-sm text-base-500">Sales across all tenant shops.</p>
          </div>
        </div>

        {error && (
          <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">
            {error}
          </div>
        )}

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-4">
          <div className="card p-4">
            <p className="text-xs font-medium text-base-500">Total sales</p>
            <p className="text-lg font-semibold text-base-900">{fmt(totals.total)}</p>
          </div>
          <div className="card p-4">
            <p className="text-xs font-medium text-base-500">Total profit</p>
            <p className="text-lg font-semibold text-base-900">{fmt(totals.profit)}</p>
          </div>
          <div className="card p-4">
            <p className="text-xs font-medium text-base-500">Transactions</p>
            <p className="text-lg font-semibold text-base-900">{data.length}</p>
          </div>
          <div className="card p-4">
            <p className="text-xs font-medium text-base-500">Avg. transaction</p>
            <p className="text-lg font-semibold text-base-900">{data.length ? fmt(totals.total / data.length) : '--'}</p>
          </div>
        </div>

        <div className="card p-5">
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3 mb-4">
            <div className="flex flex-col gap-2">
              <label className="label">From</label>
              <input
                type="date"
                value={filter.from}
                onChange={(e) => setFilter({ ...filter, from: e.target.value })}
                className="input"
              />
            </div>
            <div className="flex flex-col gap-2">
              <label className="label">To</label>
              <input
                type="date"
                value={filter.to}
                onChange={(e) => setFilter({ ...filter, to: e.target.value })}
                className="input"
              />
            </div>
            <div className="flex flex-col gap-2">
              <label className="label">Tenant</label>
              <input
                value={filter.tenantId}
                onChange={(e) => setFilter({ ...filter, tenantId: e.target.value })}
                placeholder="tenant ID"
                className="input"
              />
            </div>
          </div>
        </div>

        <DataTable
          columns={[
            { key: 'createdAt', label: 'Date', sortable: true },
            { key: 'tenant.shopName', label: 'Shop' },
            { key: 'total', label: 'Total', sortable: true, align: 'right' },
            { key: 'profit', label: 'Profit', sortable: true, align: 'right' },
            { key: 'paymentMethod', label: 'Payment method' },
            { key: 'staff', label: 'Staff' },
          ]}
          data={data}
          rowKey={(r) => r.id}
          renderCell={(row, key) => {
            if (key === 'createdAt') {
              return <span className="text-base-900">{new Date(row.createdAt).toLocaleDateString()}</span>;
            }
            if (key === 'tenant.shopName') {
              return <span className="text-base-900">{row.tenant?.shopName ?? row.tenantId}</span>;
            }
            if (key === 'total' || key === 'profit') {
              return <span className="font-mono tabular-nums text-base-900">{fmt(row[key as keyof Sale] as number)}</span>;
            }
            const v = row[key as keyof Sale];
            return <span className="text-base-900">{v == null ? '—' : String(v)}</span>;
          }}
          emptyMessage="No sales"
        />
      </div>
    </ShellLayout>
  );
}
