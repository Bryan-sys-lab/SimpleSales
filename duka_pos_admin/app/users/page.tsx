'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout, useAdminAccess } from '@/components/layout';
import { DataTable } from '@/components/data-table';

type ShopUser = { id: string; name: string; role: string; active: boolean; createdAt: string; user: { email: string } | null; tenant: { id: string; shopName: string } };
export default function UsersPage() {
  const { can } = useAdminAccess(); const canManageUsers = can('users:manage');
  const [users, setUsers] = useState<ShopUser[]>([]); const [loading, setLoading] = useState(true); const [error, setError] = useState('');
  const load = useCallback(async () => { setLoading(true); try { const res = await fetchJson<{ users: ShopUser[] }>('/api/system/users'); setUsers(res.users); setError(''); } catch (cause) { setError(cause instanceof Error ? cause.message : 'Failed to load users'); } finally { setLoading(false); } }, []);
  useEffect(() => { void load(); }, [load]);
  async function update(user: ShopUser, update: { active?: boolean; role?: string }) {
    try { await fetchJson(`/api/system/users/${encodeURIComponent(user.id)}`, { method: 'PATCH', body: JSON.stringify(update) }); await load(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not update user'); }
  }
  return <ShellLayout><main className="space-y-6 pb-24">
    <header><p className="text-sm font-semibold text-accent-800">Company directory</p><h1 className="mt-1 text-2xl font-semibold tracking-tight">Shop users</h1><p className="mt-1 text-sm text-base-600">Manage profile access across shops. Changes are recorded in the audit log.</p></header>
    {error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</p>}
    <DataTable columns={[{key:'name',label:'Person'},{key:'tenant',label:'Shop'},{key:'role',label:'Role'},{key:'active',label:'Access'},...(canManageUsers?[{key:'actions',label:'Controls'}]:[]),{key:'createdAt',label:'Joined'}]} data={users} rowKey={u=>u.id} renderCell={(user,key)=>{
      if(key==='name') return <span className="font-medium">{user.name}<small className="block text-base-500">{user.user?.email ?? 'No email linked'}</small></span>;
      if(key==='tenant') return <span>{user.tenant?.shopName ?? '—'}</span>;
      if(key==='role') return canManageUsers?<select aria-label={`Role for ${user.name}`} className="input min-h-10 py-1 text-sm" value={user.role} onChange={e=>void update(user,{role:e.target.value})}><option value="admin">Owner</option><option value="manager">Manager</option><option value="cashier">Cashier</option></select>:<span className="capitalize">{user.role}</span>;
      if(key==='active') return <span className={`badge ${user.active?'badge-none':'badge-high'}`}>{user.active?'Active':'Suspended'}</span>;
      if(key==='createdAt') return <span>{new Date(user.createdAt).toLocaleDateString()}</span>;
      if(key==='actions') return canManageUsers&&<button className="button-secondary min-h-10 text-xs" onClick={e=>{e.stopPropagation(); void update(user,{active:!user.active});}}>{user.active?'Suspend access':'Restore access'}</button>;
      return null;
    }} emptyMessage={loading?'Loading shop users…':'No users'} />
  </main></ShellLayout>;
}
