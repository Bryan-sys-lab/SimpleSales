'use client';

import { useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';
import { EmptyState } from '@/components/empty-state';

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
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">Expenses settings</h2>
          <p className="text-sm text-base-500">Track app costs and operational expenses. All changes are audit-logged.</p>
        </div>
        {error && <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        {message && <div className="rounded-xl border border-accent-200 bg-accent-50 px-4 py-3 text-sm text-accent-800">{message}</div>}
        <form onSubmit={add} className="card space-y-4 p-5 max-w-2xl">
          <h3 className="font-semibold">Add expense</h3>
          <input className="input" required placeholder="Category" value={category} onChange={(e) => setCategory(e.target.value)} />
          <input className="input" required placeholder="Description" value={description} onChange={(e) => setDescription(e.target.value)} />
          <input className="input" required type="number" min="0" step="0.01" placeholder="Amount (KES)" value={amount} onChange={(e) => setAmount(e.target.value)} />
          <button className="button-primary" type="submit" disabled={saving}>{saving ? 'Saving…' : 'Add expense'}</button>
        </form>
        <div className="card p-5">
          <h3 className="text-sm font-semibold text-base-900 mb-4">Expense ledger</h3>
          <div className="overflow-x-auto">
            <table className="table">
              <thead>
                <tr>
                  <th>Category</th>
                  <th>Description</th>
                  <th className="text-right">Amount</th>
                  <th>Date</th>
                </tr>
              </thead>
              <tbody>
                {items.map((e) => (
                  <tr key={e.id}>
                    <td><span className="badge badge-medium">{e.category}</span></td>
                    <td className="text-base-900">{e.description}</td>
                    <td className="text-right font-mono tabular-nums">{fmt(e.amount)}</td>
                    <td className="text-sm text-base-500">{new Date(e.date).toLocaleDateString()}</td>
                  </tr>
                ))}
                {items.length === 0 && !loading && <tr><td colSpan={4}><EmptyState message="No expenses" compact /></td></tr>}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </ShellLayout>
  );
}
