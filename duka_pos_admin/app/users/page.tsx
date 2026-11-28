'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout, useAdminAccess } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { useAdminLiveRefresh } from '@/components/websocket-provider';
import { showToast } from '@/lib/toast';

type ShopUser = {
  id: string;
  name: string;
  role: string;
  active: boolean;
  createdAt: string;
  user: { email: string } | null;
  tenant: { id: string; shopName: string };
};

type ShopDirectory = {
  tenantId: string;
  shopName: string;
  owner: ShopUser | null;
  profiles: ShopUser[];
  staffCount: number;
  activeCount: number;
  joinedAt: string;
};

export default function UsersPage() {
  const { can } = useAdminAccess();
  const canManageUsers = can('users:manage');
  const [users, setUsers] = useState<ShopUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [selectedTenantId, setSelectedTenantId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetchJson<{ users: ShopUser[] }>('/api/system/users');
      setUsers(res.users);
      setError('');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Failed to load users');
    } finally {
      setLoading(false);
    }
  }, []);
  useAdminLiveRefresh(load, ['users']);

  useEffect(() => {
    void load();
  }, [load]);

  const shops = useMemo(() => {
    const profilesByTenant = new Map<string, ShopUser[]>();
    for (const profile of users) {
      const profiles = profilesByTenant.get(profile.tenant.id) ?? [];
      profiles.push(profile);
      profilesByTenant.set(profile.tenant.id, profiles);
    }

    return [...profilesByTenant.entries()].map(([tenantId, profiles]): ShopDirectory => {
      const owner = profiles.find((profile) => profile.role === 'admin' && profile.user?.email) ?? null;
      return {
        tenantId,
        shopName: profiles[0].tenant.shopName,
        owner,
        profiles,
        staffCount: profiles.length - (owner ? 1 : 0),
        activeCount: profiles.filter((profile) => profile.active).length,
        joinedAt: owner?.createdAt ?? profiles[profiles.length - 1].createdAt,
      };
    }).sort((a, b) => a.shopName.localeCompare(b.shopName));
  }, [users]);

  const selectedShop = shops.find((shop) => shop.tenantId === selectedTenantId) ?? null;

  async function remove(profile: ShopUser, shop: ShopDirectory) {
    const removesLastProfile = shop.profiles.length === 1;
    const confirmation = removesLastProfile
      ? `Delete ${profile.name}'s profile? This is the last profile for ${shop.shopName}, so the shop will be archived and all sign-in access disabled. Sales, tax, and audit history will be retained.`
      : `Delete ${profile.name}'s profile? Only this profile's access will be removed; ${shop.shopName} and its other profiles will remain.`;
    if (!window.confirm(confirmation)) return;
    try {
      const result = await fetchJson<{ tenant_archived?: boolean }>(`/api/system/users/${encodeURIComponent(profile.id)}`, { method: 'DELETE' });
      if (result.tenant_archived) {
        showToast('success', `${shop.shopName} was archived. Its sales and compliance history has been retained.`);
      }
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not delete user');
    }
  }

  async function update(profile: ShopUser, changes: { active?: boolean; role?: string }) {
    try {
      await fetchJson(`/api/system/users/${encodeURIComponent(profile.id)}`, {
        method: 'PATCH',
        body: JSON.stringify(changes),
      });
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not update user');
    }
  }

  return (
    <ShellLayout>
      <div className="space-y-6">
        <header>
          <p className="text-sm font-semibold text-accent-800">Company directory</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">Shop users</h1>
          <p className="mt-1 text-sm text-base-600">
            Shops are listed once; tap a row to see the owner and staff together. Access controls remain per profile.
          </p>
        </header>
        {error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</p>}
        <DataTable
          caption="Shop user records"
          columns={[
            { key: 'owner', label: 'Owner / account' },
            { key: 'shopName', label: 'Shop', sortable: true },
            { key: 'staffCount', label: 'Staff', sortable: true },
            { key: 'activeCount', label: 'Active profiles', sortable: true },
            { key: 'joinedAt', label: 'Joined', sortable: true },
          ]}
          data={shops}
          rowKey={(shop) => shop.tenantId}
          onRowClick={(shop) => setSelectedTenantId((selected) => selected === shop.tenantId ? null : shop.tenantId)}
          renderCell={(shop, key) => {
            if (key === 'owner') {
              return (
                <span className="font-medium">
                  {shop.owner?.name ?? 'Owner not linked'}
                  <small className="block text-base-500">{shop.owner?.user?.email ?? 'No verified account linked'}</small>
                </span>
              );
            }
            if (key === 'shopName') return <span>{shop.shopName}</span>;
            if (key === 'staffCount') return <span>{shop.staffCount} staff</span>;
            if (key === 'activeCount') return <span>{shop.activeCount} / {shop.profiles.length}</span>;
            if (key === 'joinedAt') return <span>{new Date(shop.joinedAt).toLocaleDateString()}</span>;
            return null;
          }}
          emptyMessage={loading ? 'Loading shop users…' : 'No users'}
        />

        {selectedShop && (
          <section className="card space-y-4 p-5" aria-live="polite">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-accent-800">Shop account details</p>
                <h2 className="mt-1 text-lg font-semibold">{selectedShop.shopName}</h2>
                <p className="text-sm text-base-500">Owner and staff profiles are grouped under this shop.</p>
              </div>
              <button className="button-secondary min-h-10" onClick={() => setSelectedTenantId(null)}>Close details</button>
            </div>

            <ul className="divide-y divide-base-200 rounded-xl border border-base-200">
              {selectedShop.profiles.map((profile) => {
                const isOwner = profile.id === selectedShop.owner?.id;
                return (
                  <li key={profile.id} className="flex flex-wrap items-center justify-between gap-3 p-4">
                    <div className="min-w-0">
                      <p className="font-medium text-base-900">{profile.name}</p>
                      <p className="text-sm text-base-500">
                        {isOwner ? 'Owner account' : 'Staff'}{profile.user?.email ? ` · ${profile.user.email}` : ''}
                      </p>
                      <span className={`mt-2 inline-flex badge ${profile.active ? 'badge-none' : 'badge-high'}`}>
                        {profile.active ? 'Active' : 'Suspended'}
                      </span>
                    </div>
                    {canManageUsers && (
                      <div className="flex flex-wrap items-center gap-2">
                        <label className="sr-only" htmlFor={`role-${profile.id}`}>Role for {profile.name}</label>
                        <select
                          id={`role-${profile.id}`}
                          aria-label={`Role for ${profile.name}`}
                          className="input min-h-10 py-1 text-sm"
                          value={profile.role}
                          onChange={(event) => void update(profile, { role: event.target.value })}
                        >
                          <option value="admin">{isOwner ? 'Owner' : 'Admin staff'}</option>
                          <option value="manager">Manager</option>
                          <option value="cashier">Cashier</option>
                        </select>
                        <button
                          className="button-secondary min-h-10 text-xs"
                          onClick={() => void update(profile, { active: !profile.active })}
                        >
                          {profile.active ? 'Suspend access' : 'Restore access'}
                        </button>
                        <button
                          className="button-secondary min-h-10 text-xs text-red-700"
                          onClick={() => void remove(profile, selectedShop)}
                        >
                          Delete
                        </button>
                      </div>
                    )}
                  </li>
                );
              })}
            </ul>
          </section>
        )}
      </div>
    </ShellLayout>
  );
}
