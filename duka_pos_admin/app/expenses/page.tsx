'use client';

import { useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

type ExpenseItem = { id: string; category: string; description: string; amount: number; date: string };

export default function ExpensesPage() {
  const [items, setItems] = useState<ExpenseItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [category, setCategory] = useState('');
  const [description, setDescription] = useState('');
  const [amount, setAmount] = useState('');
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchJson<{ items: ExpenseItem[] }>('/api/admin/expenses');
      setItems(res.items);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load expenses');
    } finally {
      setLoading(false);
    }
  };

  useAdminLiveRefresh(load, ['expenses']);
  useEffect(() => { load(); }, []);

  const add = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setMessage(null);
    try {
      await fetchJson('/api/admin/expenses', {
        method: 'POST',
        body: JSON.stringify({ category, description, amount: Math.round(Number(amount) * 100) }),
      });
      setMessage('Expense added.');
      setCategory(''); setDescription(''); setAmount('');
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to add expense');
    } finally {
      setSaving(false);
    }
  };

  const fmt = (n: number) => new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format(n / 100);

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-base-900">Expenses settings</h1>
          <p className="text-sm text-base-500">Track app costs and operational expenses. All changes are audit-logged.</p>
        </div>
        {error && <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        {message && <div role="status" className="rounded-xl border border-accent-200 bg-accent-50 px-4 py-3 text-sm text-accent-800">{message}</div>}
        <form aria-labelledby="expense-form-heading" onSubmit={add} className="card max-w-2xl space-y-4 p-4 sm:p-5">
          <h2 id="expense-form-heading" className="text-lg font-semibold">Add expense</h2>
          <div>
            <label className="label" htmlFor="expense-category">Category</label>
            <input id="expense-category" name="category" className="input" required value={category} onChange={(e) => setCategory(e.target.value)} />
          </div>
          <div>
            <label className="label" htmlFor="expense-description">Description</label>
            <input id="expense-description" name="description" className="input" required value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>
          <div>
            <label className="label" htmlFor="expense-amount">Amount (KES)</label>
            <input id="expense-amount" name="amount" className="input" required type="number" min="0" step="0.01" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </div>
          <button className="button-primary" type="submit" disabled={saving}>{saving ? 'Saving…' : 'Add expense'}</button>
        </form>
        <div className="card p-5">
          <h2 className="mb-4 text-lg font-semibold text-base-900">Expense ledger</h2>
          <DataTable
            caption="Expense ledger"
            columns={[
              { key: 'category', label: 'Category' },
              { key: 'description', label: 'Description' },
              { key: 'amount', label: 'Amount', sortable: true, align: 'right' },
              { key: 'date', label: 'Date', sortable: true },
            ]}
            data={items}
            rowKey={(expense) => expense.id}
            renderCell={(expense, key) => {
              if (key === 'category') return <span className="badge badge-medium">{expense.category}</span>;
              if (key === 'description') return <span>{expense.description}</span>;
              if (key === 'amount') return <span>{fmt(expense.amount)}</span>;
              if (key === 'date') return <span>{new Date(expense.date).toLocaleDateString()}</span>;
              return null;
            }}
            emptyMessage={loading ? 'Loading expenses…' : 'No expenses'}
          />
        </div>
      </div>
    </ShellLayout>
  );
}
