'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { AdminUser } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';

export default function UsersPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchJson<{ users: AdminUser[] }>('/api/admin/users');
      setUsers(res.users);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load users');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const act = async (id: string, action: 'deactivate' | 'delete' | 'activate') => {
    try {
      await fetchJson(`/api/admin/users/${encodeURIComponent(id)}/${action}`, { method: 'POST' });
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Action failed');
    }
  };

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">Verified users</h2>
          <p className="text-sm text-base-500">Every account appears here after email verification. Actions are audit-logged.</p>
        </div>
        {error && <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        <DataTable
          columns={[
            { key: 'email', label: 'Email' },
            { key: 'status', label: 'Verification' },
            { key: 'shop', label: 'Shop' },
            { key: 'createdAt', label: 'Created' },
            { key: 'actions', label: 'Actions' },
          ]}
          data={users}
          rowKey={(user) => user.id}
          renderCell={(user, key) => {
            if (key === 'email') return <span className="text-base-900">{user.email}</span>;
            if (key === 'status') return user.emailVerifiedAt
              ? <span className="badge badge-none">Verified</span>
              : <span className="badge badge-medium">Pending</span>;
            if (key === 'shop') return <span className="text-base-700">{user.profiles[0]?.tenant?.shopName ?? 'Shop setup pending'}</span>;
            if (key === 'createdAt') return <span className="text-base-500">{new Date(user.createdAt).toLocaleDateString()}</span>;
            if (key === 'actions') {
              return (
                <div className="flex gap-1">
                  <button className="button-secondary text-xs" onClick={() => act(user.id, 'deactivate')}>Deactivate</button>
                  <button className="button-secondary text-xs" onClick={() => act(user.id, 'delete')}>Delete</button>
                </div>
              );
            }
            return null;
          }}
          emptyMessage={loading ? 'Loading users…' : 'No users'}
        />
      </div>
    </ShellLayout>
  );
}
