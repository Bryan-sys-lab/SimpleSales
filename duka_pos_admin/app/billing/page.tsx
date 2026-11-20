'use client';

import { FormEvent, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';

type Subscription = { tenantId: string; status: string; priceMinor: number | null; currency: string; billingInterval: string; currentPeriodEnd: string | null; tenant?: { id: string; shopName: string; profiles?: Array<{ id: string; name: string; email: string | null; user?: { email: string } | null }> } };
type Voucher = { id: string; codePrefix: string; tenantId: string | null; issuedToEmail: string | null; expiresAt: string | null; redeemedAt: string | null; revokedAt: string | null; pausedAt: string | null; deletedAt: string | null; autoIssued: boolean };
type Payment = { id: string; tenantId: string; reference: string; amountMinor: number; durationMonths: number; status: string; providerStatus: string | null; mpesaReceiptCode: string | null; createdAt: string; tenant?: { shopName: string; subscription?: { currency: string } | null } };

export default function BillingPage() {
  const [subscriptions, setSubscriptions] = useState<Subscription[]>([]);
  const [vouchers, setVouchers] = useState<Voucher[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [tenants, setTenants] = useState<{ id: string; shopName: string }[]>([]);
  const [tenantId, setTenantId] = useState('');
  const [price, setPrice] = useState('');
  const [end, setEnd] = useState('');
  const [voucherTarget, setVoucherTarget] = useState('');
  const [voucherEmail, setVoucherEmail] = useState('');
  const [duration, setDuration] = useState('1');
  const [newCode, setNewCode] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
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
    setTenants(t.tenants.map((x: any) => ({ id: x.id, shopName: x.shopName })));
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
    const response = await fetchJson<{ voucher: { code: string } }>('/api/admin/billing/vouchers', { method: 'POST', body: JSON.stringify({ tenantId: voucherTarget || undefined, email: voucherEmail || undefined, ...(duration === 'none' ? {} : { durationMonths: Number(duration) }) }) });
    setNewCode(response.voucher.code); setMessage('Copy this code now; it is not shown again.'); await load();
  }
  async function saveProvider(event: FormEvent) {
    event.preventDefault(); setMessage(null);
    await fetchJson('/api/admin/billing/provider', { method: 'PATCH', body: JSON.stringify({ channelType, shortCode, accountNumber: accountNumber || undefined }) });
    setMessage('PayHero collection destination saved.');
  }
  async function voucherAction(id: string, action: 'pause' | 'resume' | 'revoke' | 'delete') { await fetchJson(`/api/admin/billing/vouchers/${id}/${action}`, { method: 'POST' }); await load(); }

  return <ShellLayout><div className="space-y-6">
    <div><h2 className="text-2xl font-semibold tracking-tight text-base-900">Billing & access</h2><p className="text-sm text-base-500">Set negotiated monthly terms, activate shops, and issue time-limited vouchers.</p></div>
    {message && <div className="rounded-xl border border-accent-200 bg-accent-50 px-4 py-3 text-sm text-accent-800">{message}{newCode && <code className="ml-2 rounded bg-white px-2 py-1 font-semibold">{newCode}</code>}</div>}
    <div className="grid gap-4 lg:grid-cols-2">
      <form onSubmit={saveSubscription} className="card space-y-4 p-5"><h3 className="font-semibold">Shop subscription</h3><select className="input" required value={tenantId} onChange={e => setTenantId(e.target.value)}>
  <option value="">Select verified tenant…</option>
  {tenants.map((t) => <option key={t.id} value={t.id}>{t.shopName}</option>)}
</select><input className="input" required type="number" min="0" step="0.01" placeholder="Monthly price (KES)" value={price} onChange={e => setPrice(e.target.value)} /><input className="input" type="date" value={end} onChange={e => setEnd(e.target.value)} /><button className="button-primary" type="submit">Activate / update terms</button></form>
      <form onSubmit={createVoucher} className="card space-y-4 p-5"><h3 className="font-semibold">Generate voucher</h3><select className="input" value={voucherTarget} onChange={e => setVoucherTarget(e.target.value)}>
  <option value="">Choose a shop (optional if email is entered)</option>
  {tenants.map((t) => <option key={t.id} value={t.id}>{t.shopName}</option>)}
 </select><input className="input" type="email" placeholder="Recipient email (required without a shop)" value={voucherEmail} onChange={e => setVoucherEmail(e.target.value)} required={!voucherTarget} /><select className="input" value={duration} onChange={e => setDuration(e.target.value)}><option value="1">1 month</option><option value="3">3 months</option><option value="6">6 months</option><option value="12">1 year</option><option value="none">No expiry</option></select><button className="button-primary" type="submit">Generate one-time voucher</button><p className="text-xs text-base-500">Give the generated code to the issued user. The code is stored hashed and cannot be recovered later.</p></form>
      <form onSubmit={saveProvider} className="card space-y-4 p-5"><h3 className="font-semibold">PayHero destination</h3><select className="input" value={channelType} onChange={e => setChannelType(e.target.value)}><option value="till">Till</option><option value="paybill">Paybill</option><option value="bank">Bank</option></select><input className="input" required placeholder="Till / Paybill / bank short code" value={shortCode} onChange={e => setShortCode(e.target.value)} />{channelType === 'bank' && <input className="input" required placeholder="Bank account number" value={accountNumber} onChange={e => setAccountNumber(e.target.value)} />}<button className="button-primary" type="submit">Save PayHero destination</button><p className="text-xs text-base-500">The backend registers this destination with PayHero using its server-side credentials.</p></form>
    </div>
    <section className="card p-5"><h3 className="mb-4 font-semibold">Shop access</h3><div className="space-y-2">{subscriptions.map(s => <div key={s.tenantId} className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-base-200 px-3 py-3 text-sm"><span><b>{s.tenant?.shopName ?? s.tenantId}</b><span className="ml-2 text-base-500">{s.tenant?.profiles?.[0]?.name ?? 'Owner not linked'} · {s.tenant?.profiles?.[0]?.user?.email ?? s.tenant?.profiles?.[0]?.email ?? 'email unavailable'} · {s.status}</span></span><span>{s.priceMinor == null ? 'Price not set' : `${s.currency} ${(s.priceMinor / 100).toFixed(2)} / ${s.billingInterval}`} {s.currentPeriodEnd && `· ends ${new Date(s.currentPeriodEnd).toLocaleDateString()}`}</span></div>)}</div></section>
    <section className="card p-5"><h3 className="mb-4 font-semibold">Vouchers</h3><div className="space-y-2">{vouchers.map(v => <details key={v.id} className="rounded-lg border border-base-200 px-3 py-3 text-sm"><summary className="flex cursor-pointer list-none flex-wrap items-center justify-between gap-3"><span><code>{v.codePrefix}…</code>{v.autoIssued && <span className="ml-2 rounded bg-accent-50 px-1.5 py-0.5 text-accent-700">First month</span>}</span><span>{v.deletedAt ? 'Deleted' : v.revokedAt ? 'Revoked' : v.pausedAt ? 'Paused' : v.redeemedAt ? 'Redeemed' : `Expires ${v.expiresAt ? new Date(v.expiresAt).toLocaleDateString() : 'never'}`}</span></summary><div className="mt-3 grid gap-1 text-base-600"><span>Issued to: {v.issuedToEmail ?? 'Shop owner'}</span><span>Shop: {v.tenantId ?? 'Assigned on redemption'}</span><span>Validity: {v.expiresAt ? new Date(v.expiresAt).toLocaleDateString() : 'No expiry'}</span>{v.redeemedAt && <span>Redeemed: {new Date(v.redeemedAt).toLocaleString()}</span>}</div>{!v.deletedAt && !v.revokedAt && !v.redeemedAt && <div className="mt-3 flex flex-wrap gap-2"><button className="button-secondary" onClick={() => void voucherAction(v.id, v.pausedAt ? 'resume' : 'pause')}>{v.pausedAt ? 'Resume' : 'Pause'}</button><button className="button-secondary" onClick={() => void voucherAction(v.id, 'revoke')}>Revoke</button><button className="button-secondary" onClick={() => void voucherAction(v.id, 'delete')}>Delete</button></div>}</details>)}</div></section>
    <section className="card p-5"><h3 className="mb-4 font-semibold">Recent subscription payments</h3>{payments.length === 0 ? <p className="text-sm text-base-500">No checkout attempts yet.</p> : <div className="space-y-2">{payments.map(p => <details key={p.id} className="rounded-lg border border-base-200 px-3 py-3 text-sm"><summary className="flex cursor-pointer list-none flex-wrap justify-between gap-2"><span><b>{p.tenant?.shopName ?? p.tenantId}</b> · {p.tenant?.subscription?.currency ?? 'KES'} {(p.amountMinor / 100).toFixed(2)} · {p.status}</span><span className="text-base-500">{new Date(p.createdAt).toLocaleString()}</span></summary><div className="mt-3 grid gap-1 text-base-600"><span>Reference: {p.reference}</span><span>Term: {p.durationMonths} month(s)</span><span>Provider: {p.providerStatus ?? 'No provider update'}</span><span>M-Pesa receipt: {p.mpesaReceiptCode ?? 'Not recorded'}</span></div></details>)}</div>}</section>
  </div></ShellLayout>;
}
