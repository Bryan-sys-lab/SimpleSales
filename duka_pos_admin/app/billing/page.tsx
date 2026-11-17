'use client';

import { FormEvent, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';

type Subscription = { tenantId: string; status: string; priceMinor: number | null; currency: string; billingInterval: string; currentPeriodEnd: string | null; tenant?: { shopName: string } };
type Voucher = { id: string; codePrefix: string; tenantId: string | null; issuedToEmail: string | null; expiresAt: string | null; redeemedAt: string | null; revokedAt: string | null };

export default function BillingPage() {
  const [subscriptions, setSubscriptions] = useState<Subscription[]>([]);
  const [vouchers, setVouchers] = useState<Voucher[]>([]);
  const [tenantId, setTenantId] = useState('');
  const [price, setPrice] = useState('');
  const [end, setEnd] = useState('');
  const [voucherTarget, setVoucherTarget] = useState('');
  const [duration, setDuration] = useState('1');
  const [newCode, setNewCode] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [channelType, setChannelType] = useState('till');
  const [shortCode, setShortCode] = useState('');
  const [accountNumber, setAccountNumber] = useState('');

  const load = async () => {
    const [s, v, p] = await Promise.all([
      fetchJson<{ subscriptions: Subscription[] }>('/api/admin/billing/subscriptions'),
      fetchJson<{ vouchers: Voucher[] }>('/api/admin/billing/vouchers'),
      fetchJson<{ provider: { channelType?: string; shortCode?: string; accountNumber?: string } }>('/api/admin/billing/provider'),
    ]);
    setSubscriptions(s.subscriptions); setVouchers(v.vouchers);
    setChannelType(p.provider.channelType ?? 'till'); setShortCode(p.provider.shortCode ?? ''); setAccountNumber(p.provider.accountNumber ?? '');
  };
  useEffect(() => { void load(); }, []);

  async function saveSubscription(event: FormEvent) {
    event.preventDefault(); setMessage(null);
    await fetchJson(`/api/admin/billing/subscriptions/${encodeURIComponent(tenantId)}`, { method: 'PATCH', body: JSON.stringify({ status: 'active', priceMinor: Math.round(Number(price) * 100), currency: 'KES', billingInterval: 'monthly', currentPeriodEnd: end ? new Date(end).toISOString() : null }) });
    setMessage('Subscription terms saved.'); await load();
  }
  async function createVoucher(event: FormEvent) {
    event.preventDefault(); setMessage(null); setNewCode(null);
    const response = await fetchJson<{ voucher: { code: string } }>('/api/admin/billing/vouchers', { method: 'POST', body: JSON.stringify({ tenantId: voucherTarget || undefined, durationMonths: Number(duration) }) });
    setNewCode(response.voucher.code); setMessage('Copy this code now; it is not shown again.'); await load();
  }
  async function saveProvider(event: FormEvent) {
    event.preventDefault(); setMessage(null);
    await fetchJson('/api/admin/billing/provider', { method: 'PATCH', body: JSON.stringify({ channelType, shortCode, accountNumber: accountNumber || undefined }) });
    setMessage('PayHero collection destination saved.');
  }
  async function revoke(id: string) { await fetchJson(`/api/admin/billing/vouchers/${id}/revoke`, { method: 'POST' }); await load(); }

  return <ShellLayout><div className="space-y-6">
    <div><h2 className="text-2xl font-semibold tracking-tight text-base-900">Billing & access</h2><p className="text-sm text-base-500">Set negotiated monthly terms, activate shops, and issue time-limited vouchers.</p></div>
    {message && <div className="rounded-xl border border-accent-200 bg-accent-50 px-4 py-3 text-sm text-accent-800">{message}{newCode && <code className="ml-2 rounded bg-white px-2 py-1 font-semibold">{newCode}</code>}</div>}
    <div className="grid gap-4 lg:grid-cols-2">
      <form onSubmit={saveSubscription} className="card space-y-4 p-5"><h3 className="font-semibold">Shop subscription</h3><input className="input" required placeholder="Tenant ID" value={tenantId} onChange={e => setTenantId(e.target.value)} /><input className="input" required type="number" min="0" step="0.01" placeholder="Monthly price (KES)" value={price} onChange={e => setPrice(e.target.value)} /><input className="input" type="date" value={end} onChange={e => setEnd(e.target.value)} /><button className="button-primary" type="submit">Activate / update terms</button></form>
      <form onSubmit={createVoucher} className="card space-y-4 p-5"><h3 className="font-semibold">Generate voucher</h3><input className="input" placeholder="Tenant ID (optional)" value={voucherTarget} onChange={e => setVoucherTarget(e.target.value)} /><input className="input" required type="number" min="1" max="36" placeholder="Duration in months" value={duration} onChange={e => setDuration(e.target.value)} /><button className="button-primary" type="submit">Generate one-time voucher</button><p className="text-xs text-base-500">Give the generated code to the issued user. The code is stored hashed and cannot be recovered later.</p></form>
      <form onSubmit={saveProvider} className="card space-y-4 p-5"><h3 className="font-semibold">PayHero destination</h3><select className="input" value={channelType} onChange={e => setChannelType(e.target.value)}><option value="till">Till</option><option value="paybill">Paybill</option><option value="bank">Bank</option></select><input className="input" required placeholder="Till / Paybill / bank short code" value={shortCode} onChange={e => setShortCode(e.target.value)} />{channelType === 'bank' && <input className="input" required placeholder="Bank account number" value={accountNumber} onChange={e => setAccountNumber(e.target.value)} />}<button className="button-primary" type="submit">Save PayHero destination</button><p className="text-xs text-base-500">The backend registers this destination with PayHero using its server-side credentials.</p></form>
    </div>
    <section className="card p-5"><h3 className="mb-4 font-semibold">Shop access</h3><div className="space-y-2">{subscriptions.map(s => <div key={s.tenantId} className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-base-200 px-3 py-3 text-sm"><span><b>{s.tenant?.shopName ?? s.tenantId}</b><span className="ml-2 text-base-500">{s.status}</span></span><span>{s.priceMinor == null ? 'Price not set' : `${s.currency} ${(s.priceMinor / 100).toFixed(2)} / ${s.billingInterval}`} {s.currentPeriodEnd && `· ends ${new Date(s.currentPeriodEnd).toLocaleDateString()}`}</span></div>)}</div></section>
    <section className="card p-5"><h3 className="mb-4 font-semibold">Vouchers</h3><div className="space-y-2">{vouchers.map(v => <div key={v.id} className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-base-200 px-3 py-3 text-sm"><span><code>{v.codePrefix}…</code>{v.tenantId && <span className="ml-2 text-base-500">{v.tenantId}</span>}</span><span>{v.redeemedAt ? 'Redeemed' : v.revokedAt ? 'Revoked' : `Expires ${v.expiresAt ? new Date(v.expiresAt).toLocaleDateString() : 'never'}`}</span>{!v.redeemedAt && !v.revokedAt && <button className="button-secondary" onClick={() => void revoke(v.id)}>Revoke</button>}</div>)}</div></section>
  </div></ShellLayout>;
}
