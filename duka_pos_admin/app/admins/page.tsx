'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout, useAdminAccess } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { showToast } from '@/lib/toast';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

type AdminPackage = { id: string; name: string; department: string; permissions: string[] };
type AccessCatalog = {
  packages: AdminPackage[];
  permissions: string[];
  assignablePackageIds: string[];
  assignablePermissions: string[];
};
type AdminKeyRow = { id: string; email: string; phone: string; department: string; role: string; packages: string[]; permissions: string[]; canRecruit: boolean; canMintKeys: boolean; canAssignTasks: boolean; parentKeyId: string | null; parent?: { email: string; role: string } | null; createdBy: string; createdAt: string; expiresAt: string; revokedAt: string | null; usedAt: string | null };

function packagePermissions(packages: string[], catalog: AccessCatalog | null): string[] {
  return [...new Set(catalog?.packages
    .filter((item) => packages.includes(item.id))
    .flatMap((item) => item.permissions) ?? [])];
}

function permissionsWithoutPackages(permissions: string[], packages: string[], catalog: AccessCatalog | null): string[] {
  const packageScopes = new Set(packagePermissions(packages, catalog));
  return permissions.filter((permission) => !packageScopes.has(permission));
}

export default function AdminsPage() {
  const { can } = useAdminAccess();
  const canManageKeys = can('keys:manage');
  const [keys, setKeys] = useState<AdminKeyRow[]>([]);
  const [catalog, setCatalog] = useState<AccessCatalog | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [email, setEmail] = useState(''); const [phone, setPhone] = useState(''); const [department, setDepartment] = useState('Operations'); const [role, setRole] = useState('worker');
  const [selectedPackages, setSelectedPackages] = useState<string[]>(['operations']); const [additionalPermissions, setAdditionalPermissions] = useState<string[]>([]);
  const [canRecruit, setCanRecruit] = useState(false); const [canMintKeys, setCanMintKeys] = useState(false); const [canAssignTasks, setCanAssignTasks] = useState(false);
  const [issuedKey, setIssuedKey] = useState('');
  const [editingKey, setEditingKey] = useState<AdminKeyRow | null>(null);
  const [editExpiry, setEditExpiry] = useState<number | undefined>(undefined);
  const [editRole, setEditRole] = useState('worker'); const [editPackages, setEditPackages] = useState<string[]>([]); const [editAdditionalPermissions, setEditAdditionalPermissions] = useState<string[]>([]); const [editRecruit, setEditRecruit] = useState(false); const [editMint, setEditMint] = useState(false); const [editTasks, setEditTasks] = useState(false);
  const load = useCallback(async () => {
    try {
      const [result, accessCatalog] = await Promise.all([
        fetchJson<{ keys: AdminKeyRow[] }>('/api/admin/auth/keys'),
        fetchJson<AccessCatalog>('/api/admin/auth/access-catalog'),
      ]);
      setKeys(result.keys);
      setCatalog(accessCatalog);
    }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not load administrators'); }
  }, []);
  useAdminLiveRefresh(load, ['admins']);
  useEffect(() => { void load(); }, [load]);
  async function createKey(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError(''); setIssuedKey('');
    try {
      const result = await fetchJson<{ key: string }>('/api/admin/auth/keys/mint', { method: 'POST', body: JSON.stringify({ email, phone, department, role, packages: selectedPackages, permissions: additionalPermissions, canRecruit, canMintKeys, canAssignTasks, expiresInDays: 90 }) });
      setIssuedKey(result.key); setEmail(''); setPhone(''); await load();
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not create administrator key'); }
    finally { setBusy(false); }
  }
  async function removeKey(id: string) {
    if (!window.confirm('Delete this administrator key now?')) return;
    try { await fetchJson(`/api/admin/auth/keys/${encodeURIComponent(id)}`, { method: 'DELETE' }); await load(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not delete key'); }
  }

  async function revoke(id: string) {
    if (!window.confirm('Revoke this administrator key now?')) return;
    try { await fetchJson(`/api/admin/auth/keys/${encodeURIComponent(id)}/revoke`, { method: 'POST' }); await load(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not revoke key'); }
  }
  async function reactivate(id: string) {
    if (!window.confirm('Reactivate this administrator key now?')) return;
    try { await fetchJson(`/api/admin/auth/keys/${encodeURIComponent(id)}/reactivate`, { method: 'POST' }); await load(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not reactivate key'); }
  }
  async function copyIssuedKey() {
    try {
      await navigator.clipboard.writeText(issuedKey);
      showToast('success', 'Administrator key copied to clipboard.');
    } catch (cause) {
      showToast('error', cause instanceof Error ? cause.message : 'Could not copy the administrator key.');
    }
  }
  function beginEdit(row: AdminKeyRow) {
    setEditingKey(row); setEditRole(row.role); setEditPackages(row.packages ?? []);
    setEditAdditionalPermissions(permissionsWithoutPackages(row.permissions ?? [], row.packages ?? [], catalog));
    setEditRecruit(row.canRecruit); setEditMint(row.canMintKeys); setEditTasks(row.canAssignTasks);
    setEditExpiry(undefined);
  }
  async function saveAccess(event: FormEvent) {
    event.preventDefault(); if (!editingKey) return; setBusy(true); setError('');
    try {
      await fetchJson(`/api/admin/auth/keys/${encodeURIComponent(editingKey.id)}`, { method:'PATCH', body:JSON.stringify({ role:editRole, packages:editPackages, permissions:editAdditionalPermissions, canRecruit:editRecruit, canMintKeys:editMint, canAssignTasks:editTasks, ...(editExpiry?{expiresInDays:editExpiry}:{}) }) });
      setEditingKey(null); await load();
    } catch(cause) { setError(cause instanceof Error?cause.message:'Could not update access'); }
    finally { setBusy(false); }
  }
  const assignablePackages = catalog?.packages.filter((item) => catalog.assignablePackageIds.includes(item.id)) ?? [];
  const assignablePermissions = catalog?.permissions.filter((permission) => catalog.assignablePermissions.includes(permission)) ?? [];
  const packageDepartmentOptions = [...new Set(catalog?.packages.map((item) => item.department) ?? [])];
  const selectedPackageScopes = packagePermissions(selectedPackages, catalog);
  const editPackageScopes = packagePermissions(editPackages, catalog);

  return <ShellLayout><main className="mx-auto max-w-6xl space-y-6 pb-24">
    <header><p className="text-sm font-semibold text-accent-800">Company access</p><div className="mt-1 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between"><div><h1 className="text-2xl font-semibold tracking-tight">Admin accounts &amp; keys</h1><p className="mt-1 max-w-2xl text-sm text-base-600">Organize access by department. A department lead can only grant permissions they already hold.</p></div><nav className="flex flex-wrap gap-2" aria-label="Administrator sections">{canManageKeys&&<a className="button-secondary inline-flex min-h-11 items-center" href="#create-admin">Create admin</a>}<a className="button-secondary inline-flex min-h-11 items-center" href="#manage-keys">Manage keys</a></nav></div></header>
    {error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</p>}
    {issuedKey && <section className="rounded-xl border border-accent-200 bg-accent-50 p-4" aria-live="polite"><h2 className="font-semibold text-accent-900">Key created — copy it now</h2><p className="mt-1 text-sm text-accent-900">This key is only shown once. Copy it exactly; spaces are not part of the key.</p><input className="mt-3 block w-full rounded bg-white p-3 font-mono text-sm text-base-900" readOnly value={issuedKey} onFocus={(e) => e.target.select()} spellCheck={false} /><button className="button-secondary mt-3" onClick={() => void copyIssuedKey()}>Copy key</button></section>}
    {canManageKeys&&editingKey&&<section className="card border-l-4 border-l-accent-600 p-4 sm:p-6"><div className="flex items-start justify-between gap-3"><div><p className="text-xs font-semibold uppercase tracking-wide text-accent-800">Edit issued access</p><h2 className="mt-1 text-lg font-semibold">{editingKey.email}</h2><p className="text-sm text-base-600">{editingKey.department} · invited by {editingKey.parent?.email??editingKey.createdBy}</p></div><button className="button-secondary min-h-10" onClick={()=>setEditingKey(null)}>Cancel</button></div><form className="mt-4 space-y-5" onSubmit={saveAccess}>
      <div className="grid gap-4 sm:grid-cols-2"><div><label className="label" htmlFor="edit-role">Role</label><select id="edit-role" className="input" value={editRole} onChange={e=>setEditRole(e.target.value)}><option value="worker">Worker</option><option value="manager">Manager</option><option value="department_head">Department head</option><option value="executive">Executive</option></select></div><div><label className="label" htmlFor="expiry">Extend access (days from now)</label><select id="expiry" className="input" onChange={e=>setEditExpiry(Number(e.target.value))} defaultValue=""><option value="" disabled>Keep current expiry</option><option value="30">30 days</option><option value="90">90 days</option><option value="180">180 days</option><option value="365">365 days</option></select></div></div>
      <fieldset><legend className="label mb-2">Access packages</legend><p className="mb-2 text-xs text-base-500">A member can combine any packages available to you. Package permissions are included automatically.</p><div className="grid gap-2 sm:grid-cols-2">{assignablePackages.map(item=><label key={item.id} className="flex min-h-11 items-start gap-3 rounded-lg border border-base-200 px-3 py-2 text-sm"><input type="checkbox" checked={editPackages.includes(item.id)} onChange={e=>setEditPackages(v=>e.target.checked?[...v,item.id]:v.filter(x=>x!==item.id))}/><span><strong className="block">{item.name}</strong><span className="text-xs text-base-500">{item.permissions.length ? item.permissions.join(', ') : 'No preset scopes'}</span></span></label>)}</div></fieldset>
      <fieldset><legend className="label mb-2">Additional permissions</legend><div className="grid gap-2 sm:grid-cols-2">{assignablePermissions.map(scope=>{const included=editPackageScopes.includes(scope);return <label key={scope} className="flex min-h-11 items-center gap-3 rounded-lg border border-base-200 px-3 py-2 text-sm"><input type="checkbox" checked={included||editAdditionalPermissions.includes(scope)} disabled={included} onChange={e=>setEditAdditionalPermissions(v=>e.target.checked?[...v,scope]:v.filter(x=>x!==scope))}/><span><strong className="block">{scope}</strong><span className="text-xs text-base-500">{included?'Included by selected package':'Add this scope'}</span></span></label>})}</div></fieldset>
      <div className="flex flex-wrap gap-5"><label className="flex min-h-11 items-center gap-2 text-sm"><input type="checkbox" checked={editRecruit} onChange={e=>setEditRecruit(e.target.checked)}/>Can invite members</label><label className="flex min-h-11 items-center gap-2 text-sm"><input type="checkbox" checked={editMint} onChange={e=>setEditMint(e.target.checked)}/>Can mint keys</label><label className="flex min-h-11 items-center gap-2 text-sm"><input type="checkbox" checked={editTasks} onChange={e=>setEditTasks(e.target.checked)}/>Can assign tasks</label></div>
      <button type="submit" className="btn btn-accent min-h-11 w-full sm:w-auto" disabled={busy || editPackages.length === 0}>{busy?'Saving…':'Save access changes'}</button>
    </form></section>}
    {canManageKeys?<section id="create-admin" className="card scroll-mt-24 p-4 sm:p-6"><h2 className="text-lg font-semibold">Create admin key</h2><form className="mt-4 space-y-5" onSubmit={createKey}>
      <div className="grid gap-4 sm:grid-cols-2"><div><label className="label" htmlFor="admin-email">Email</label><input className="input" id="admin-email" type="email" autoComplete="email" required value={email} onChange={e => setEmail(e.target.value)} /></div><div><label className="label" htmlFor="admin-phone">Phone</label><input className="input" id="admin-phone" type="tel" autoComplete="tel" required value={phone} onChange={e => setPhone(e.target.value)} /></div><div><label className="label" htmlFor="department">Primary department</label><select id="department" className="input" value={department} onChange={e=>setDepartment(e.target.value)}>{packageDepartmentOptions.map(d=><option key={d} value={d}>{d}</option>)}</select></div><div><label className="label" htmlFor="role">Role</label><select id="role" className="input" value={role} onChange={e=>setRole(e.target.value)}><option value="worker">Worker</option><option value="manager">Manager</option><option value="department_head">Department head</option><option value="executive">Executive</option></select></div></div>
      <fieldset><legend className="label mb-2">Access packages</legend><p className="mb-2 text-xs text-base-500">Choose one or more packages. Their scopes are combined for this account.</p><div className="grid gap-2 sm:grid-cols-2">{assignablePackages.map(item=><label key={item.id} className="flex min-h-11 items-start gap-3 rounded-lg border border-base-200 px-3 py-2 text-sm"><input type="checkbox" checked={selectedPackages.includes(item.id)} onChange={e=>setSelectedPackages(v=>e.target.checked?[...v,item.id]:v.filter(x=>x!==item.id))}/><span><strong className="block">{item.name}</strong><span className="text-xs text-base-500">{item.permissions.length ? item.permissions.join(', ') : 'No preset scopes'}</span></span></label>)}</div></fieldset>
      <fieldset><legend className="label mb-2">Additional permissions</legend><p className="mb-2 text-xs text-base-500">Add scopes beyond the selected packages. Package scopes are included automatically.</p><div className="grid gap-2 sm:grid-cols-2">{assignablePermissions.map(scope=>{const included=selectedPackageScopes.includes(scope);return <label key={scope} className="flex min-h-11 items-center gap-3 rounded-lg border border-base-200 px-3 py-2 text-sm"><input type="checkbox" checked={included||additionalPermissions.includes(scope)} disabled={included} onChange={e=>setAdditionalPermissions(v=>e.target.checked?[...v,scope]:v.filter(x=>x!==scope))}/><span><strong className="block font-medium">{scope}</strong><span className="text-xs text-base-500">{included?'Included by selected package':'Add this scope'}</span></span></label>})}</div></fieldset>
      <div className="flex flex-wrap gap-5"><label className="flex min-h-11 items-center gap-2 text-sm"><input type="checkbox" checked={canRecruit} onChange={e => setCanRecruit(e.target.checked)} />Can invite team members</label><label className="flex min-h-11 items-center gap-2 text-sm"><input type="checkbox" checked={canMintKeys} onChange={e => setCanMintKeys(e.target.checked)} />Can mint department keys</label><label className="flex min-h-11 items-center gap-2 text-sm"><input type="checkbox" checked={canAssignTasks} onChange={e => setCanAssignTasks(e.target.checked)} />Can assign tasks to direct reports</label></div>
      <button type="submit" className="btn btn-accent min-h-11 w-full sm:w-auto" disabled={busy || !catalog || selectedPackages.length === 0}>{busy ? 'Creating…' : 'Create admin key'}</button>
    </form></section>:<p className="rounded-xl border border-base-200 bg-white p-4 text-sm text-base-600">You can view accounts in your reporting line. Your access does not include inviting or changing administrator permissions.</p>}
    <section id="manage-keys" className="scroll-mt-24 space-y-3"><div><h2 className="text-lg font-semibold">Manage administrator keys</h2><p className="text-sm text-base-600">Tap a card on mobile for role, inviter, packages, permissions, activity and expiry status.</p></div><DataTable columns={[{key:'email',label:'Account'},{key:'department',label:'Department'},{key:'packages',label:'Packages'},{key:'role',label:'Role'},{key:'permissions',label:'Permissions'},{key:'invitedBy',label:'Invited by'},{key:'status',label:'Status'},{key:'issuedAt',label:'Issued'},{key:'lastUsed',label:'Last used'},{key:'expiresAt',label:'Expires'},{key:'actions',label:'Controls'}]} data={keys} rowKey={row=>row.id} renderCell={(row,key)=>{
      if(key==='email') return <span className="font-medium">{row.email}<small className="block text-base-500">{row.phone}</small></span>;
      if(key==='packages') return <span>{row.packages?.map(id=>catalog?.packages.find(item=>item.id===id)?.name??id).join(', ')||'Custom'}</span>;
      if(key==='permissions') return <span>{row.permissions?.length ?? 0} scopes</span>;
      if(key==='role') return <span className="capitalize">{row.role.replace('_',' ')}</span>;
      if(key==='invitedBy') return <span>{row.parent?.email ?? (row.createdBy==='super-admin'?'System admin':row.createdBy)}</span>;
      if(key==='status') return <span className={`badge ${row.revokedAt?'badge-high':new Date(row.expiresAt)<=new Date()?'badge-medium':row.usedAt?'badge-none':'badge-low'}`}>{row.revokedAt?'Revoked':new Date(row.expiresAt)<=new Date()?'Expired':row.usedAt?'Active':'Invited'}</span>;
      if(key==='issuedAt') return <span>{new Date(row.createdAt).toLocaleDateString()}</span>;
      if(key==='lastUsed') return <span>{row.usedAt?new Date(row.usedAt).toLocaleString():'Never'}</span>;
      if(key==='canRecruit') return <span>{row.canRecruit ? 'Allowed' : 'No'}</span>;
      if(key==='expiresAt') return <span>{new Date(row.expiresAt).toLocaleDateString()}</span>;
      if(key==='actions') return <div className="flex flex-wrap justify-end gap-1">{canManageKeys&&!row.revokedAt&&<button className="button-secondary min-h-10 text-xs" onClick={e=>{e.stopPropagation();beginEdit(row);}}>Edit</button>}{canManageKeys&&!row.revokedAt&&<button className="button-secondary min-h-10 text-xs" onClick={e=>{e.stopPropagation(); void revoke(row.id);}}>Revoke</button>}{canManageKeys&&row.revokedAt&&<button className="button-secondary min-h-10 text-xs" onClick={e=>{e.stopPropagation(); void reactivate(row.id);}}>Reactivate</button>}{canManageKeys&&<button className="button-secondary min-h-10 text-xs text-red-700" onClick={e=>{e.stopPropagation(); void removeKey(row.id);}}>Delete</button>}{row.revokedAt&&<span className="badge badge-high">Revoked</span>}</div>;
      return <span>{String(row[key as keyof AdminKeyRow] ?? '—')}</span>;
    }} emptyMessage="No department administrators have been added." /></section>
  </main></ShellLayout>;
}
