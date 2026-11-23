'use client';

import { FormEvent, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';
import { EmptyState } from '@/components/empty-state';

type Subscription = { tenantId: string; status: string; priceMinor: number | null; discountPercent: number; currency: string; billingInterval: string; currentPeriodEnd: string | null; tenant?: { id: string; shopName: string; profiles?: Array<{ id: string; name: string; email: string | null; user?: { email: string } | null }> } };
type Voucher = { id: string; codePrefix: string; tenantId: string | null; issuedToEmail: string | null; voucherType: 'access' | 'discount'; durationMonths: number; discountPercent: number; expiresAt: string | null; redeemedAt: string | null; revokedAt: string | null; pausedAt: string | null; deletedAt: string | null; autoIssued: boolean };
type Payment = { id: string; tenantId: string; reference: string; amountMinor: number; durationMonths: number; status: string; providerStatus: string | null; mpesaReceiptCode: string | null; createdAt: string; tenant?: { shopName: string; subscription?: { currency: string } | null } };

function getErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'The request could not be completed.';
}

export default function BillingPage() {
  const [subscriptions, setSubscriptions] = useState<Subscription[]>([]);
  const [vouchers, setVouchers] = useState<Voucher[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [tenants, setTenants] = useState<{ id: string; shopName: string }[]>([]);
  const [tenantId, setTenantId] = useState('');
  const [price, setPrice] = useState('');
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

  const load = async () => {
    const [s, v, p, t, pay] = await Promise.all([
      fetchJson<{ subscriptions: Subscription[] }>('/api/admin/billing/subscriptions'),
      fetchJson<{ vouchers: Voucher[] }>('/api/admin/billing/vouchers'),
      fetchJson<{ provider: { channelType?: string; shortCode?: string; accountNumber?: string } }>('/api/admin/billing/provider'),
      fetchJson<{ tenants: { id: string; shopName: string }[] }>('/api/admin/tenants'),
      fetchJson<{ payments: Payment[] }>('/api/admin/billing/payments?limit=50'),
    ]);
    setSubscriptions(s.subscriptions); setVouchers(v.vouchers);
    setPayments(pay.payments);
    setTenants(t.tenants);
    setChannelType(p.provider.channelType ?? 'till'); setShortCode(p.provider.shortCode ?? ''); setAccountNumber(p.provider.accountNumber ?? '');
  };
  useEffect(() => { void load().catch(cause => setError(getErrorMessage(cause))); }, []);

  async function saveSubscription(event: FormEvent) {
    event.preventDefault(); setMessage(null); setError(null);
    try {
      await fetchJson(`/api/admin/billing/subscriptions/${encodeURIComponent(tenantId)}`, { method: 'PATCH', body: JSON.stringify({ status: 'active', priceMinor: Math.round(Number(price) * 100), discountPercent: Number(discountPercent), currency: 'KES', billingInterval: 'monthly', currentPeriodEnd: end ? new Date(end).toISOString() : null }) });
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
    setError(null);
    try {
      await fetchJson(`/api/admin/billing/vouchers/${id}/${action}`, { method: 'POST' });
      await load();
    } catch (cause) {
      setError(getErrorMessage(cause));
    }
  }

  return <ShellLayout><div className="space-y-6">
    <div><h2 className="text-2xl font-semibold tracking-tight text-base-900">Billing & access</h2><p className="text-sm text-base-500">Set shop prices and discounts, activate tenants, and issue access or price-discount vouchers for 1, 3, 6, or 12-month plans.</p></div>
    {message && <div className="rounded-xl border border-accent-200 bg-accent-50 px-4 py-3 text-sm text-accent-800">{message}{newCode && <code className="ml-2 rounded bg-white px-2 py-1 font-semibold">{newCode}</code>}</div>}
    {error && <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800" role="alert">{error}</div>}
    <div className="grid gap-4 lg:grid-cols-2">
      <form onSubmit={saveSubscription} className="card space-y-4 p-5"><h3 className="font-semibold">Shop subscription</h3><select className="input" required value={tenantId} onChange={e => {
        const selectedTenantId = e.target.value;
        const existing = subscriptions.find(subscription => subscription.tenantId === selectedTenantId);
        setTenantId(selectedTenantId);
        setPrice(existing?.priceMinor == null ? '' : (existing.priceMinor / 100).toFixed(2));
        setDiscountPercent(String(existing?.discountPercent ?? 0));
        setEnd(existing?.currentPeriodEnd?.slice(0, 10) ?? '');
      }}>
  <option value="">Select verified tenant…</option>
  {tenants.map((t) => <option key={t.id} value={t.id}>{t.shopName}</option>)}
</select><input className="input" required type="number" min="0" step="0.01" placeholder="Monthly price (KES)" value={price} onChange={e => setPrice(e.target.value)} /><label className="block space-y-1 text-sm"><span>Discount on the set price (%)</span><input className="input" required type="number" min="0" max="99" step="1" value={discountPercent} onChange={e => setDiscountPercent(e.target.value)} /></label><input className="input" type="date" value={end} onChange={e => setEnd(e.target.value)} /><button className="button-primary" type="submit">Activate / update terms</button></form>
     <form onSubmit={createVoucher} className="card space-y-4 p-5"><h3 className="font-semibold">Generate voucher</h3><select className="input" value={voucherTarget} onChange={e => setVoucherTarget(e.target.value)}>
  <option value="">Choose a shop (optional if email is entered)</option>
  {tenants.map((t) => <option key={t.id} value={t.id}>{t.shopName}</option>)}
 </select><input className="input" type="email" placeholder="Recipient email (defaults to the selected shop owner)" value={voucherEmail} onChange={e => setVoucherEmail(e.target.value)} required={!voucherTarget} /><select className="input" value={voucherType} onChange={e => setVoucherType(e.target.value === 'discount' ? 'discount' : 'access')}><option value="access">Access voucher</option><option value="discount">Discount voucher</option></select>{voucherType === 'discount' && <label className="block space-y-1 text-sm"><span>Discount off the set price (%)</span><input className="input" required type="number" min="1" max="99" step="1" value={voucherDiscountPercent} onChange={e => setVoucherDiscountPercent(e.target.value)} /></label>}<select className="input" value={duration} onChange={e => setDuration(e.target.value)}><option value="1">1 month</option><option value="3">3 months</option><option value="6">6 months</option><option value="12">12 months</option></select><button className="button-primary" type="submit">Generate and email voucher</button><p className="text-xs text-base-500">{voucherType === 'discount' ? 'The no-expiry code applies once to the selected plan at checkout and does not grant free access. If the shop already has a negotiated discount, the larger discount is used.' : 'The no-expiry code grants the selected access term when claimed. The code is stored hashed and cannot be recovered later.'}</p></form>
      <form onSubmit={saveProvider} className="card space-y-4 p-5"><h3 className="font-semibold">PayHero destination</h3><select className="input" value={channelType} onChange={e => setChannelType(e.target.value)}><option value="till">Till</option><option value="paybill">Paybill</option><option value="bank">Bank</option></select><input className="input" required placeholder="Till / Paybill / bank short code" value={shortCode} onChange={e => setShortCode(e.target.value)} />{channelType === 'bank' && <input className="input" required placeholder="Bank account number" value={accountNumber} onChange={e => setAccountNumber(e.target.value)} />}<button className="button-primary" type="submit">Save PayHero destination</button><p className="text-xs text-base-500">The backend registers this destination with PayHero using its server-side credentials.</p></form>
    </div>
    <section className="card p-5"><h3 className="mb-4 font-semibold">Shop access</h3>{subscriptions.length === 0 ? <EmptyState message="No shop access records" compact /> : <div className="space-y-2">{subscriptions.map(s => <div key={s.tenantId} className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-base-200 px-3 py-3 text-sm"><span><b>{s.tenant?.shopName ?? s.tenantId}</b><span className="ml-2 text-base-500">{s.tenant?.profiles?.[0]?.name ?? 'Owner not linked'} · {s.tenant?.profiles?.[0]?.user?.email ?? s.tenant?.profiles?.[0]?.email ?? 'email unavailable'} · {s.status}</span></span><span>{s.priceMinor == null ? 'Price not set' : `${s.currency} ${(s.priceMinor / 100).toFixed(2)} / ${s.billingInterval}`} · {s.discountPercent ?? 0}% discount {s.currentPeriodEnd && `· ends ${new Date(s.currentPeriodEnd).toLocaleDateString()}`}</span></div>)}</div>}</section>
    <section className="card p-5"><h3 className="mb-4 font-semibold">Vouchers</h3>{vouchers.length === 0 ? <EmptyState message="No vouchers have been generated" compact /> : <div className="space-y-2">{vouchers.map(v => <details key={v.id} className="rounded-lg border border-base-200 px-3 py-3 text-sm"><summary className="flex cursor-pointer list-none flex-wrap items-center justify-between gap-3"><span><code>{v.codePrefix}…</code>{v.autoIssued && <span className="ml-2 rounded bg-accent-50 px-1.5 py-0.5 text-accent-700">Legacy auto-issued</span>}</span><span>{v.deletedAt ? 'Deleted' : v.revokedAt ? 'Revoked' : v.pausedAt ? 'Paused' : v.redeemedAt ? 'Redeemed' : 'Ready to claim'}</span></summary><div className="mt-3 grid gap-1 text-base-600"><span>Issued to: {v.issuedToEmail ?? 'Shop owner'}</span><span>Shop: {v.tenantId ?? 'Assigned on redemption'}</span><span>Type: {v.voucherType === 'discount' ? `${v.discountPercent}% checkout discount` : 'Access'}</span><span>Plan term: {v.durationMonths} month(s)</span><span>Claim deadline: {v.expiresAt ? new Date(v.expiresAt).toLocaleDateString() : 'None'}</span>{v.redeemedAt && <span>Redeemed: {new Date(v.redeemedAt).toLocaleString()}</span>}</div>{!v.deletedAt && !v.revokedAt && !v.redeemedAt && <div className="mt-3 flex flex-wrap gap-2"><button className="button-secondary" onClick={() => void voucherAction(v.id, v.pausedAt ? 'resume' : 'pause')}>{v.pausedAt ? 'Resume' : 'Pause'}</button><button className="button-secondary" onClick={() => void voucherAction(v.id, 'revoke')}>Revoke</button><button className="button-secondary" onClick={() => void voucherAction(v.id, 'delete')}>Delete</button></div>}</details>)}</div>}</section>
    <section className="card p-5"><h3 className="mb-4 font-semibold">Recent subscription payments</h3>{payments.length === 0 ? <EmptyState message="No checkout attempts yet" compact /> : <div className="space-y-2">{payments.map(p => <details key={p.id} className="rounded-lg border border-base-200 px-3 py-3 text-sm"><summary className="flex cursor-pointer list-none flex-wrap justify-between gap-2"><span><b>{p.tenant?.shopName ?? p.tenantId}</b> · {p.tenant?.subscription?.currency ?? 'KES'} {(p.amountMinor / 100).toFixed(2)} · {p.status}</span><span className="text-base-500">{new Date(p.createdAt).toLocaleString()}</span></summary><div className="mt-3 grid gap-1 text-base-600"><span>Reference: {p.reference}</span><span>Term: {p.durationMonths} month(s)</span><span>Provider: {p.providerStatus ?? 'No provider update'}</span><span>M-Pesa receipt: {p.mpesaReceiptCode ?? 'Not recorded'}</span></div></details>)}</div>}</section>
  </div></ShellLayout>;
}
