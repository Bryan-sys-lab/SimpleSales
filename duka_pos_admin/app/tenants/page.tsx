'use client';

import { SyntheticEvent, useCallback, useEffect, useRef, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { Tenant } from '@/lib/types';
import { ShellLayout, useAdminAccess } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import Link from 'next/link';
import { showToast } from '@/lib/toast';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

export default function TenantsPage() {
  const { can } = useAdminAccess(); const canManageTenants = can('tenants:manage');
  const [data, setData] = useState<Tenant[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tenantToDelete, setTenantToDelete] = useState<Tenant | null>(null);
  const [deletingTenantId, setDeletingTenantId] = useState<string | null>(null);
  const deleteDialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    if (tenantToDelete && !deleteDialogRef.current?.open) {
      deleteDialogRef.current?.showModal();
    }
  }, [tenantToDelete]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchJson<{ tenants: Tenant[] }>('/api/admin/tenants');
      setData(res.tenants.map((tenant) => ({
        ...tenant,
        activeProfiles: tenant._count?.profiles ?? 0,
        salesCount: tenant._count?.sales ?? 0,
      })));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load tenants');
    } finally {
      setLoading(false);
    }
  }, []);
  useAdminLiveRefresh(load, ['tenants', 'business-context']);

  useEffect(() => { load(); }, [load]);

  const act = async (id: string, setting: 'mpesaEnabled' | 'etimsEnabled', value: boolean) => {
    try {
      await fetchJson(`/api/system/tenants/${encodeURIComponent(id)}/settings`, { method: 'PATCH', body: JSON.stringify({ [setting]: value }) });
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Action failed');
    }
  };

  const deleteTenant = async (tenant: Tenant) => {
    setDeletingTenantId(tenant.id);
    setError(null);
    try {
      await fetchJson(`/api/system/tenants/${encodeURIComponent(tenant.id)}`, { method: 'DELETE' });
      showToast('success', `${tenant.shopName} was archived. Its sales and compliance history has been retained.`);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not archive tenant');
    } finally {
      setDeletingTenantId(null);
    }
  };

  const handleDeleteDialogClose = (event: SyntheticEvent<HTMLDialogElement>) => {
    const dialog = event.currentTarget;
    const shouldDelete = dialog.returnValue === 'delete';
    const tenant = tenantToDelete;
    dialog.returnValue = '';
    setTenantToDelete(null);
    if (shouldDelete && tenant) void deleteTenant(tenant);
  };

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-base-900">Tenants</h1>
          <p className="text-sm text-base-500">Tenant directory with profile and sale counts. Actions are audit-logged.</p>
        </div>

        {error && (
          <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">
            {error}
          </div>
        )}

        <DataTable
          caption="Tenant directory"
          columns={[
            { key: 'shopName', label: 'Shop name' },
            { key: 'admin', label: 'Admin' },
            { key: 'activeProfiles', label: 'Active profiles', sortable: true, align: 'right' },
            { key: 'salesCount', label: 'Sales count', sortable: true, align: 'right' },
            { key: 'mpesaEnabled', label: 'M-Pesa' },
            { key: 'etimsEnabled', label: 'eTIMS' },
            { key: 'businessContext', label: 'Business details' },
            ...(canManageTenants ? [{ key: 'actions', label: 'Controls' }] : []),
          ]}
          data={data}
          rowKey={(t) => t.id}
          renderCell={(row, key) => {
            if (key === 'shopName') return <span className="text-base-900">{row.shopName}</span>;
            if (key === 'admin') return <span className="text-base-900">{row.admin ?? '—'}</span>;
            if (key === 'activeProfiles') return <span className="font-mono tabular-nums text-base-900">{row.activeProfiles ?? 0}</span>;
            if (key === 'salesCount') return <span className="font-mono tabular-nums text-base-900">{row.salesCount ?? 0}</span>;
            if (key === 'mpesaEnabled') return <span className={`badge ${(row as any).mpesaEnabled ? 'badge-none' : 'badge-high'}`}>{(row as any).mpesaEnabled ? 'On' : 'Off'}</span>;
            if (key === 'etimsEnabled') return <span className={`badge ${(row as any).etimsEnabled ? 'badge-none' : 'badge-high'}`}>{(row as any).etimsEnabled ? 'On' : 'Off'}</span>;
            if (key === 'businessContext') return <Link className="button-secondary inline-flex min-h-11 items-center" href={`/tenants/${encodeURIComponent(row.id)}/business-context`} onClick={(e) => e.stopPropagation()}>View details</Link>;
            if (key === 'actions') {
              return (
                <div className="flex flex-wrap gap-1">
                  <button className="button-secondary min-h-10 text-xs" onClick={(e) => { e.stopPropagation(); void act(row.id, 'mpesaEnabled', !(row as any).mpesaEnabled); }}>{(row as any).mpesaEnabled ? 'Turn M-Pesa off' : 'Turn M-Pesa on'}</button>
                  <button className="button-secondary min-h-10 text-xs" onClick={(e) => { e.stopPropagation(); void act(row.id, 'etimsEnabled', !(row as any).etimsEnabled); }}>{(row as any).etimsEnabled ? 'Turn eTIMS off' : 'Turn eTIMS on'}</button>
                  <button
                    className="button-secondary min-h-10 text-xs text-red-700"
                    aria-label={`Archive ${row.shopName} tenant`}
                    disabled={deletingTenantId === row.id}
                    onClick={(e) => { e.stopPropagation(); setTenantToDelete(row); }}
                  >
                    {deletingTenantId === row.id ? 'Archiving…' : 'Archive tenant'}
                  </button>
                </div>
              );
            }
            const value = row[key as keyof Tenant];
            return <span className="text-base-900">{typeof value === 'object' ? '—' : value ?? '—'}</span>;
          }}
          emptyMessage={loading ? 'Loading tenants…' : 'No tenants'}
        />
      </div>
      <dialog
        ref={deleteDialogRef}
        className="tenant-delete-dialog w-[calc(100%-2rem)] max-w-lg rounded-2xl border border-base-200 bg-white p-0 text-base-900 shadow-2xl backdrop:bg-base-950/60"
        aria-labelledby="tenant-delete-title"
        aria-describedby="tenant-delete-description"
        onClose={handleDeleteDialogClose}
      >
        {tenantToDelete && (
          <div className="space-y-4 p-5 sm:p-6">
            <div>
              <p className="text-sm font-semibold text-red-700">Remove tenant access</p>
              <h1 id="tenant-delete-title" className="mt-1 text-xl font-semibold">Archive {tenantToDelete.shopName}?</h1>
            </div>
            <p id="tenant-delete-description" className="text-sm leading-6 text-base-600">
              This archives the shop and disables all of its user profiles. Sales, payment, tax, and audit history are retained for compliance. A login account is removed only if it has no profile in another shop.
            </p>
            <p className="rounded-lg bg-base-50 p-3 text-sm text-base-700">
              {tenantToDelete.activeProfiles ?? 0} active profiles will lose access. {tenantToDelete.salesCount ?? 0} sales records will remain in the system.
            </p>
            <form method="dialog" className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <button type="submit" value="cancel" autoFocus className="button-secondary min-h-11">Cancel</button>
              <button type="submit" value="delete" className="button-secondary min-h-11 border-red-300 text-red-700">
                Archive tenant
              </button>
            </form>
          </div>
        )}
      </dialog>
    </ShellLayout>
  );
}
