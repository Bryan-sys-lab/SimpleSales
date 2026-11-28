'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout, useAdminAccess } from '@/components/layout';
import { EmptyState } from '@/components/empty-state';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

type Subscription = { tenantId: string; status: string; priceMinor: number | null; discountPercent: number; currency: string; billingInterval: string; currentPeriodEnd: string | null; tenant?: { id: string; shopName: string; profiles?: Array<{ id: string; name: string; email: string | null; user?: { email: string } | null }> } };
type Voucher = { id: string; codePrefix: string; tenantId: string | null; issuedToEmail: string | null; voucherType: 'access' | 'discount'; durationMonths: number; discountPercent: number; expiresAt: string | null; redeemedAt: string | null; revokedAt: string | null; pausedAt: string | null; deletedAt: string | null; autoIssued: boolean };
type Payment = { id: string; tenantId: string; reference: string; amountMinor: number; durationMonths: number; status: string; providerStatus: string | null; mpesaReceiptCode: string | null; createdAt: string; tenant?: { shopName: string; subscription?: { currency: string } | null } };

function getVoucherStatus(voucher: Voucher): string {
  if (voucher.deletedAt) return 'Deleted';
  if (voucher.revokedAt) return 'Revoked';
  if (voucher.pausedAt) return 'Paused';
  if (voucher.redeemedAt) return 'Redeemed';
  return 'Ready to claim';
}

function getBillingStatusClass(status: string): string {
  const normalized = status.toLowerCase();
  if (['active', 'ready to claim', 'redeemed', 'paid', 'succeeded', 'success', 'settled', 'accepted', 'completed'].includes(normalized)) return 'badge-none';
  if (['paused', 'pending', 'processing'].includes(normalized)) return 'badge-medium';
  if (['deleted', 'revoked', 'cancelled', 'failed', 'declined', 'expired', 'rejected'].includes(normalized)) return 'badge-high';
  return 'badge-low';
}

function getErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'The request could not be completed.';
}

export default function BillingPage() {
  const { access, can } = useAdminAccess();
  const canManageBilling = can('billing:manage');
  const canReadProvider = can('configuration:read');
  const canManageProvider = can('configuration:manage');
  const [subscriptions, setSubscriptions] = useState<Subscription[]>([]);
  const [vouchers, setVouchers] = useState<Voucher[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [tenants, setTenants] = useState<{ id: string; shopName: string }[]>([]);
  const [tenantId, setTenantId] = useState('');
  const [price, setPrice] = useState('');
  const [billingInterval, setBillingInterval] = useState('monthly');
  const [discountPercent, setDiscountPercent] = useState('0');
  const [end, setEnd] = useState('');
  const [voucherTarget, setVoucherTarget] = useState('');
  const [voucherEmail, setVoucherEmail] = useState('');
  const [voucherType, setVoucherType] = useState<'access' | 'discount'>('access');
  const [voucherDiscountPercent, setVoucherDiscountPercent] = useState('10');
  const [duration, setDuration] = useState('1');
  const [newCode, setNewCode] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [channelType, setChannelType] = useState('till');
  const [shortCode, setShortCode] = useState('');
  const [accountNumber, setAccountNumber] = useState('');

  const load = useCallback(async () => {
    const providerRequest = canReadProvider
      ? fetchJson<{ provider: { channelType?: string; shortCode?: string; accountNumber?: string } }>('/api/admin/billing/provider')
      : Promise.resolve(null);
    const [s, v, t, pay, provider] = await Promise.all([
      fetchJson<{ subscriptions: Subscription[] }>('/api/admin/billing/subscriptions'),
      fetchJson<{ vouchers: Voucher[] }>('/api/admin/billing/vouchers'),
      fetchJson<{ tenants: { id: string; shopName: string }[] }>('/api/admin/billing/shop-options'),
      fetchJson<{ payments: Payment[] }>('/api/admin/billing/payments?limit=50'),
      providerRequest,
    ]);
    setSubscriptions(s.subscriptions); setVouchers(v.vouchers);
    setPayments(pay.payments);
    setTenants(t.tenants);
    if (provider) {
      setChannelType(provider.provider.channelType ?? 'till');
      setShortCode(provider.provider.shortCode ?? '');
      setAccountNumber(provider.provider.accountNumber ?? '');
    }
  }, [canReadProvider]);
  useAdminLiveRefresh(load, ['billing', 'financials']);
  useEffect(() => {
    if (!access) return;
    void load().catch(cause => setError(getErrorMessage(cause)));
  }, [access, load]);

  async function saveSubscription(event: FormEvent) {
    event.preventDefault(); setMessage(null); setError(null);
    try {
      await fetchJson(`/api/admin/billing/subscriptions/${encodeURIComponent(tenantId)}`, { method: 'PATCH', body: JSON.stringify({ status: 'active', priceMinor: Math.round(Number(price) * 100), discountPercent: Number(discountPercent), currency: 'KES', billingInterval, currentPeriodEnd: end ? new Date(end).toISOString() : null }) });
      setMessage('Subscription terms saved.');
      await load();
    } catch (cause) {
      setError(getErrorMessage(cause));
    }
  }
  async function createVoucher(event: FormEvent) {
    event.preventDefault(); setMessage(null); setError(null); setNewCode(null);
    try {
      const response = await fetchJson<{ voucher: { code: string } }>('/api/admin/billing/vouchers', { method: 'POST', body: JSON.stringify({ tenantId: voucherTarget || undefined, email: voucherEmail || undefined, voucherType, durationMonths: Number(duration), discountPercent: voucherType === 'discount' ? Number(voucherDiscountPercent) : 0 }) });
      setNewCode(response.voucher.code);
      setMessage(`${voucherType === 'discount' ? 'Discount voucher' : 'Access voucher'} emailed. Copy the code as a backup; it is shown only once.`);
      await load();
    } catch (cause) {
      setError(getErrorMessage(cause));
    }
  }
  async function saveProvider(event: FormEvent) {
    event.preventDefault(); setMessage(null); setError(null);
    try {
      await fetchJson('/api/admin/billing/provider', { method: 'PATCH', body: JSON.stringify({ channelType, shortCode, accountNumber: accountNumber || undefined }) });
      setMessage('PayHero collection destination saved.');
    } catch (cause) {
      setError(getErrorMessage(cause));
    }
  }
  async function voucherAction(id: string, action: 'pause' | 'resume' | 'revoke' | 'delete') {
    if ((action === 'revoke' || action === 'delete') && !window.confirm(`Are you sure you want to ${action} this voucher?`)) return;
    setMessage(null);
    setError(null);
    try {
      await fetchJson(`/api/admin/billing/vouchers/${id}/${action}`, { method: 'POST' });
      setMessage(`Voucher ${action === 'resume' ? 'resumed' : `${action}d`}.`);
      await load();
    } catch (cause) {
      setError(getErrorMessage(cause));
    }
  }

  return (
    <ShellLayout>
      <div className="space-y-6">
        <header className="space-y-1">
          <p className="text-sm font-semibold text-accent-800">Finance &amp; access</p>
          <h1 className="text-2xl font-semibold tracking-tight text-base-900">Billing &amp; access</h1>
          <p className="max-w-3xl text-base text-base-600">Set shop prices and discounts, activate tenants, and issue access or price-discount vouchers for 1, 3, 6, or 12-month plans.</p>
        </header>
        {message && <div role="status" aria-live="polite" className="rounded-xl border border-accent-200 bg-accent-50 px-4 py-3 text-sm text-accent-800">{message}{newCode && <code className="ml-2 rounded bg-white px-2 py-1 font-semibold">{newCode}</code>}</div>}
        {error && <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800" role="alert">{error}</div>}
        <div className="grid gap-4 xl:grid-cols-2">
          {canManageBilling && <>
            <form onSubmit={saveSubscription} className="card space-y-4 p-4 sm:p-5">
              <div>
                <h2 className="font-semibold">Shop subscription</h2>
                <p className="mt-1 text-sm text-base-600">Choose a verified shop to set its price and access period.</p>
              </div>
              <div>
                <label className="label" htmlFor="subscription-tenant">Shop</label>
                <select id="subscription-tenant" name="tenantId" className="input" required value={tenantId} onChange={e => {
                  const selectedTenantId = e.target.value;
                  const existing = subscriptions.find(subscription => subscription.tenantId === selectedTenantId);
                  setTenantId(selectedTenantId);
                  setPrice(existing?.priceMinor == null ? '' : (existing.priceMinor / 100).toFixed(2));
                  setBillingInterval(existing?.billingInterval ?? 'monthly');
                  setDiscountPercent(String(existing?.discountPercent ?? 0));
                  setEnd(existing?.currentPeriodEnd?.slice(0, 10) ?? '');
                }}>
                  <option value="">Select verified tenant…</option>
                  {tenants.map((t) => <option key={t.id} value={t.id}>{t.shopName}</option>)}
                </select>
              </div>
              <label className="block space-y-1 text-sm">
                <span>Price per billing period (KES)</span>
                <input className="input" name="price" required type="number" min="0" step="0.01" value={price} onChange={e => setPrice(e.target.value)} />
              </label>
              <label className="block space-y-1 text-sm">
                <span>Billing period</span>
                <select className="input" name="billingInterval" value={billingInterval} onChange={e => setBillingInterval(e.target.value)}>
                  <option value="monthly">Monthly</option><option value="quarterly">Quarterly (3 months)</option><option value="semiannual">Semiannual (6 months)</option><option value="annual">Annual (12 months)</option>
                </select>
              </label>
              <label className="block space-y-1 text-sm">
                <span>Discount on the set price (%)</span>
                <input className="input" name="discountPercent" required type="number" min="0" max="99" step="1" value={discountPercent} onChange={e => setDiscountPercent(e.target.value)} />
              </label>
              <label className="block space-y-1 text-sm">
                <span>Current period end (optional)</span>
                <input className="input" name="currentPeriodEnd" type="date" value={end} onChange={e => setEnd(e.target.value)} />
              </label>
              <button className="button-primary w-full sm:w-auto" type="submit">Activate / update terms</button>
            </form>
            <form onSubmit={createVoucher} className="card space-y-4 p-4 sm:p-5">
              <div>
                <h2 className="font-semibold">Generate voucher</h2>
                <p className="mt-1 text-sm text-base-600">Issue a one-time claim code for access or a checkout discount.</p>
              </div>
              <label className="block space-y-1 text-sm">
                <span>Shop (optional if you enter an email)</span>
                <select className="input" name="voucherTenantId" value={voucherTarget} onChange={e => setVoucherTarget(e.target.value)}>
                  <option value="">Choose a shop</option>
                  {tenants.map((t) => <option key={t.id} value={t.id}>{t.shopName}</option>)}
                </select>
              </label>
              <label className="block space-y-1 text-sm">
                <span>Recipient email {voucherTarget ? '(optional)' : ''}</span>
                <input className="input" name="voucherEmail" type="email" autoComplete="email" value={voucherEmail} onChange={e => setVoucherEmail(e.target.value)} required={!voucherTarget} />
                <span className="block text-xs text-base-500">If left blank for a selected shop, the code is emailed to its owner.</span>
              </label>
              <label className="block space-y-1 text-sm">
                <span>Voucher type</span>
                <select className="input" name="voucherType" value={voucherType} onChange={e => setVoucherType(e.target.value === 'discount' ? 'discount' : 'access')}>
                  <option value="access">Access voucher</option><option value="discount">Discount voucher</option>
                </select>
              </label>
              {voucherType === 'discount' && <label className="block space-y-1 text-sm">
                <span>Discount off the set price (%)</span>
                <input className="input" name="voucherDiscountPercent" required type="number" min="1" max="99" step="1" value={voucherDiscountPercent} onChange={e => setVoucherDiscountPercent(e.target.value)} />
              </label>}
              <label className="block space-y-1 text-sm">
                <span>Plan duration</span>
                <select className="input" name="durationMonths" value={duration} onChange={e => setDuration(e.target.value)}>
                  <option value="1">1 month</option><option value="3">3 months</option><option value="6">6 months</option><option value="12">12 months</option>
                </select>
              </label>
              <button className="button-primary w-full sm:w-auto" type="submit">Generate and email voucher</button>
              <p className="text-sm text-base-600">{voucherType === 'discount' ? 'This code applies once to the selected plan at checkout and does not grant free access. If the shop already has a negotiated discount, the larger discount is used.' : 'This code grants the selected access term when claimed. It is stored hashed and cannot be recovered later.'}</p>
            </form>
          </>}
          {!canManageBilling && <section className="card p-5 text-sm text-base-600" role="status">Your account can view billing records but cannot change subscription terms or manage vouchers.</section>}
          {canManageProvider && <form onSubmit={saveProvider} className="card space-y-4 p-4 sm:p-5">
            <div>
              <h2 className="font-semibold">PayHero destination</h2>
              <p className="mt-1 text-sm text-base-600">Choose where payment collections should be sent.</p>
            </div>
            <label className="block space-y-1 text-sm">
              <span>Destination type</span>
              <select className="input" name="channelType" value={channelType} onChange={e => setChannelType(e.target.value)}>
                <option value="till">Till</option><option value="paybill">Paybill</option><option value="bank">Bank</option>
              </select>
            </label>
            <label className="block space-y-1 text-sm">
              <span>{channelType === 'bank' ? 'Bank short code' : 'Till / Paybill short code'}</span>
              <input className="input" name="shortCode" required value={shortCode} onChange={e => setShortCode(e.target.value)} />
            </label>
            {channelType === 'bank' && <label className="block space-y-1 text-sm">
              <span>Bank account number</span>
              <input className="input" name="accountNumber" required value={accountNumber} onChange={e => setAccountNumber(e.target.value)} />
            </label>}
            <button className="button-primary w-full sm:w-auto" type="submit">Save PayHero destination</button>
            <p className="text-sm text-base-600">The backend registers this destination with PayHero using its server-side credentials.</p>
          </form>}
        </div>
        <section className="card p-4 sm:p-5">
          <h2 className="mb-4 font-semibold">Shop access</h2>
          {subscriptions.length === 0 ? <EmptyState message="No shop access records" compact /> : <ul className="space-y-2">
            {subscriptions.map(s => <li key={s.tenantId} className="grid gap-2 rounded-xl border border-base-200 p-4 text-sm lg:grid-cols-[minmax(0,1fr)_auto] lg:items-center">
              <div className="min-w-0">
                <p className="font-semibold text-base-900">{s.tenant?.shopName ?? s.tenantId}</p>
                <p className="mt-1 text-base-600">{s.tenant?.profiles?.[0]?.name ?? 'Owner not linked'} · {s.tenant?.profiles?.[0]?.user?.email ?? s.tenant?.profiles?.[0]?.email ?? 'email unavailable'}</p>
              </div>
              <div className="flex flex-wrap items-center gap-2 text-sm">
                <span className={`badge ${getBillingStatusClass(s.status)}`}>{s.status}</span>
                <span>{s.priceMinor == null ? 'Price not set' : `${s.currency} ${(s.priceMinor / 100).toFixed(2)} / ${s.billingInterval} · ${s.discountPercent ?? 0}% discount`}</span>
                {s.currentPeriodEnd && <span className="text-base-600">Ends {new Date(s.currentPeriodEnd).toLocaleDateString()}</span>}
              </div>
            </li>)}
          </ul>}
        </section>
        <section className="card p-4 sm:p-5">
          <h2 className="mb-4 font-semibold">Vouchers</h2>
          {vouchers.length === 0 ? <EmptyState message="No vouchers have been generated" compact /> : <div className="space-y-2">
            {vouchers.map(v => <details key={v.id} className="group rounded-xl border border-base-200 p-4 text-sm">
              <summary className="flex min-h-11 cursor-pointer list-none flex-wrap items-center justify-between gap-3">
                <span className="flex min-w-0 flex-wrap items-center gap-2"><code>{v.codePrefix}…</code>{v.autoIssued && <span className="rounded bg-accent-50 px-1.5 py-0.5 text-accent-700">Legacy auto-issued</span>}</span>
                <span className="ml-auto flex items-center gap-3"><span className={`badge ${getBillingStatusClass(getVoucherStatus(v))}`}>{getVoucherStatus(v)}</span><svg className="h-4 w-4 text-base-500 transition-transform group-open:rotate-180" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m6 9 6 6 6-6" /></svg></span>
              </summary>
              <div className="mt-3 grid gap-2 border-t border-base-200 pt-3 text-base-600 sm:grid-cols-2">
                <span>Issued to: {v.issuedToEmail ?? 'Shop owner'}</span><span>Shop: {v.tenantId ?? 'Assigned on redemption'}</span>
                <span>Type: {v.voucherType === 'discount' ? `${v.discountPercent}% checkout discount` : 'Access'}</span><span>Plan term: {v.durationMonths} month(s)</span>
                <span>Claim deadline: {v.expiresAt ? new Date(v.expiresAt).toLocaleDateString() : 'None'}</span>{v.redeemedAt && <span>Redeemed: {new Date(v.redeemedAt).toLocaleString()}</span>}
              </div>
              {canManageBilling && !v.deletedAt && !v.revokedAt && !v.redeemedAt && <div className="mt-3 flex flex-wrap gap-2">
                <button type="button" className="button-secondary" onClick={() => void voucherAction(v.id, v.pausedAt ? 'resume' : 'pause')}>{v.pausedAt ? 'Resume' : 'Pause'}</button>
                <button type="button" className="button-secondary" onClick={() => void voucherAction(v.id, 'revoke')}>Revoke</button>
                <button type="button" className="button-secondary text-coral-800" onClick={() => void voucherAction(v.id, 'delete')}>Delete</button>
              </div>}
            </details>)}
          </div>}
        </section>
        <section className="card p-4 sm:p-5">
          <h2 className="mb-4 font-semibold">Recent subscription payments</h2>
          {payments.length === 0 ? <EmptyState message="No checkout attempts yet" compact /> : <div className="space-y-2">
            {payments.map(p => <details key={p.id} className="group rounded-xl border border-base-200 p-4 text-sm">
              <summary className="flex min-h-11 cursor-pointer list-none flex-wrap items-center justify-between gap-2">
                <span className="min-w-0"><b>{p.tenant?.shopName ?? p.tenantId}</b> · {p.tenant?.subscription?.currency ?? 'KES'} {(p.amountMinor / 100).toFixed(2)} <span className={`badge ${getBillingStatusClass(p.status)}`}>{p.status}</span></span>
                <span className="flex items-center gap-3 text-base-600">{new Date(p.createdAt).toLocaleString()}<svg className="h-4 w-4 text-base-500 transition-transform group-open:rotate-180" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m6 9 6 6 6-6" /></svg></span>
              </summary>
              <div className="mt-3 grid gap-2 border-t border-base-200 pt-3 text-base-600 sm:grid-cols-2">
                <span>Reference: {p.reference}</span><span>Term: {p.durationMonths} month(s)</span>
                <span>Provider: {p.providerStatus ?? 'No provider update'}</span><span>M-Pesa receipt: {p.mpesaReceiptCode ?? 'Not recorded'}</span>
              </div>
            </details>)}
          </div>}
        </section>
      </div>
    </ShellLayout>
  );
}
