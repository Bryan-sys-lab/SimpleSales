'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { MetricCard } from '@/components/metric-card';
import { EmptyState } from '@/components/empty-state';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

type Financials = {
  revenue: number;
  expenses: number;
  net: number;
  activeCustomers: number;
  averageSubscription: number | null;
  revenueByTenant: { name: string; value: number }[];
  expensesByCategory: { name: string; value: number }[];
  expenseItems: { id: string; category: string; description: string; amount: number; date: string }[];
};

type SubscriptionRow = {
  status: string;
  tenantId: string;
  priceMinor?: number | null;
  tenant?: { shopName?: string | null } | null;
};

type ExpenseRow = {
  id: string;
  amount: number;
  category?: string | null;
  description?: string | null;
  date?: string | null;
};

const fmt = (n: number) => new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format(n / 100);

function BarChart({ title, data, color }: { title: string; data: { name: string; value: number }[]; color: string }) {
  const max = Math.max(...data.map((d) => d.value), 1);
  return (
    <div className="card p-5">
      <h2 className="text-sm font-semibold text-base-900 mb-4">{title}</h2>
      {data.length === 0 ? <EmptyState message="No data available" compact /> : <div className="space-y-3">
        {data.map((d) => (
          <div key={d.name}>
            <div className="flex items-center justify-between text-xs mb-1">
              <span className="text-base-600 truncate">{d.name}</span>
              <span className="font-mono tabular-nums text-base-900">{fmt(d.value)}</span>
            </div>
            <div className="h-2.5 rounded-full bg-base-100 overflow-hidden">
              <div className={`h-full rounded-full ${color}`} style={{ width: `${(d.value / max) * 100}%` }} />
            </div>
          </div>
        ))}
      </div>}
    </div>
  );
}

export default function FinancialsPage() {
  const [data, setData] = useState<Financials | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
        const [subsRes, expRes] = await Promise.all([
          fetchJson<{ subscriptions: SubscriptionRow[] }>('/api/admin/billing/subscriptions'),
          fetchJson<{ items: ExpenseRow[] }>('/api/admin/expenses'),
        ]);
        const active = (subsRes.subscriptions ?? []).filter((item) => item.status === 'active');
        const priced = active.filter((item) => typeof item.priceMinor === 'number');
        const revenue = priced.reduce((total, item) => total + item.priceMinor!, 0);
        const expenses = (expRes.items ?? []).reduce((total, item) => total + item.amount, 0);
        const byTenant = priced.map((item) => ({
          name: item.tenant?.shopName ?? item.tenantId,
          value: item.priceMinor!,
        }));
        const byCat: Record<string, number> = {};
        (expRes.items ?? []).forEach((item) => {
          const category = item.category ?? 'General';
          byCat[category] = (byCat[category] ?? 0) + item.amount;
        });
        const expensesByCategory = Object.entries(byCat).map(([name, value]) => ({ name, value }));
        const expenseItems = (expRes.items ?? []).map((item) => ({
          id: item.id,
          category: item.category ?? 'General',
          description: item.description ?? 'Expense',
          amount: item.amount,
          date: item.date ?? '',
        }));
        setData({
          revenue,
          expenses,
          net: revenue - expenses,
          activeCustomers: active.length,
          averageSubscription: priced.length ? Math.round(revenue / priced.length) : null,
          revenueByTenant: byTenant,
          expensesByCategory,
          expenseItems,
        });
        setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load financials');
    } finally {
      setLoading(false);
    }
  }, []);
  useAdminLiveRefresh(load, ['financials']);
  useEffect(() => { void load(); }, [load]);

  const margin = data && data.revenue > 0
    ? `${Math.round((data.net / data.revenue) * 100)}%`
    : '--';

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-base-900">Revenue & costs</h1>
          <p className="text-sm text-base-500">Current subscription values and expenses entered in the system.</p>
        </div>
        {error && <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        {loading && <p role="status" className="text-sm text-base-500">Loading financial records…</p>}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <MetricCard label="Active subscription value" value={data ? fmt(data.revenue) : '--'} caption="Configured active plans" />
          <MetricCard label="Total expenses" value={data ? fmt(data.expenses) : '--'} caption="App costs" />
          <MetricCard label="Net subscription value" value={data ? fmt(data.net) : '--'} caption="Subscription value less expenses" />
          <MetricCard label="Margin" value={margin} caption="Net / active subscription value" />
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <MetricCard label="Active shops" value={data ? data.activeCustomers : '--'} caption="Shops on an active subscription" />
          <MetricCard label="Average active subscription" value={data?.averageSubscription == null ? '--' : fmt(data.averageSubscription)} caption="Average of configured active plans" />
        </div>
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <BarChart title="Active subscription value by shop" data={data?.revenueByTenant ?? []} color="bg-accent-600" />
          <BarChart title="Expenses by category" data={data?.expensesByCategory ?? []} color="bg-red-500" />
        </div>
        <div className="card p-5">
          <h2 className="text-sm font-semibold text-base-900 mb-4">Expense ledger</h2>
          <DataTable
            caption="Expense ledger"
            columns={[
              { key: 'date', label: 'Date', sortable: true },
              { key: 'category', label: 'Category' },
              { key: 'description', label: 'Description' },
              { key: 'amount', label: 'Amount', sortable: true, align: 'right' },
            ]}
            data={data?.expenseItems ?? []}
            rowKey={(expense) => expense.id}
            renderCell={(expense, key) => {
              if (key === 'date') return <span>{expense.date ? new Date(expense.date).toLocaleDateString() : '—'}</span>;
              if (key === 'category') return <span className="badge badge-medium">{expense.category}</span>;
              if (key === 'description') return <span>{expense.description}</span>;
              if (key === 'amount') return <span>{fmt(expense.amount)}</span>;
              return null;
            }}
            emptyMessage={loading ? 'Loading expenses…' : 'No expenses'}
          />
        </div>
      </div>
    </ShellLayout>
  );
}
