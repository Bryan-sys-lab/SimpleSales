'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout, useAdminAccess } from '@/components/layout';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

type MembershipOffer = {
  id: string;
  revision: number;
  status: string;
  amountMinor: number;
  currency: string;
  termMonths: number | null;
  paymentArrangement: string;
  renewalTerms: string;
  includedFeatures: string[];
  additionalConditions: string | null;
  expiresAt: string | null;
};

type MembershipMessage = {
  id: string;
  senderType: string;
  body: string;
  createdAt: string;
};

type MembershipRequest = {
  id: string;
  status: string;
  features: string[];
  requirements: string;
  createdAt: string;
  tenant: { id: string; shopName: string };
  offers: MembershipOffer[];
  messages: MembershipMessage[];
  agreement: { reference: string; acceptedAt: string; snapshot: Record<string, unknown> } | null;
};

function formatPrice(amountMinor: number, currency = 'KES') {
  return `${currency} ${(amountMinor / 100).toFixed(2)}`;
}

function statusBadgeClass(status: string) {
  switch (status.toLowerCase()) {
    case 'accepted':
    case 'active':
    case 'completed':
      return 'badge-none';
    case 'offered':
    case 'offer_ready':
      return 'badge-medium';
    case 'closed':
    case 'declined':
    case 'expired':
    case 'rejected':
      return 'badge-high';
    default:
      return 'badge-low';
  }
}

export default function MembershipPage() {
  const { can } = useAdminAccess();
  const canManage = can('membership:manage');
  const [requests, setRequests] = useState<MembershipRequest[]>([]);
  const [selectedId, setSelectedId] = useState('');
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [amount, setAmount] = useState('');
  const [termMonths, setTermMonths] = useState('');
  const [paymentArrangement, setPaymentArrangement] = useState('');
  const [renewalTerms, setRenewalTerms] = useState('');
  const [includedFeatures, setIncludedFeatures] = useState('');
  const [additionalConditions, setAdditionalConditions] = useState('');
  const [expiresAt, setExpiresAt] = useState('');
  const [message, setMessage] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const response = await fetchJson<{ requests: MembershipRequest[] }>(
        '/api/admin/membership/requests?limit=100',
      );
      setRequests(response.requests);
      setSelectedId((current) =>
        response.requests.some((request) => request.id === current)
          ? current
          : response.requests[0]?.id ?? '',
      );
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load membership requests.');
    } finally {
      setLoading(false);
    }
  }, []);
  useAdminLiveRefresh(load, ['membership']);

  useEffect(() => { void load(); }, [load]);

  const selected = requests.find((request) => request.id === selectedId) ?? null;

  async function createOffer(event: FormEvent) {
    event.preventDefault();
    if (!selected) return;
    setBusy(true);
    setError('');
    try {
      await fetchJson(`/api/admin/membership/requests/${encodeURIComponent(selected.id)}/offers`, {
        method: 'POST',
        body: JSON.stringify({
          amountMinor: Math.round(Number(amount) * 100),
          currency: 'KES',
          termMonths: termMonths ? Number(termMonths) : null,
          paymentArrangement,
          renewalTerms,
          includedFeatures: includedFeatures.trim()
            ? includedFeatures.split(/\r?\n|,/).map((item) => item.trim()).filter(Boolean)
            : undefined,
          additionalConditions: additionalConditions.trim() || null,
          expiresAt: expiresAt ? new Date(expiresAt).toISOString() : null,
        }),
      });
      setAmount('');
      setTermMonths('');
      setPaymentArrangement('');
      setRenewalTerms('');
      setIncludedFeatures('');
      setAdditionalConditions('');
      setExpiresAt('');
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not send this offer.');
    } finally {
      setBusy(false);
    }
  }

  async function sendMessage(event: FormEvent) {
    event.preventDefault();
    if (!selected || !message.trim()) return;
    setBusy(true);
    setError('');
    try {
      await fetchJson(`/api/admin/membership/requests/${encodeURIComponent(selected.id)}/messages`, {
        method: 'POST',
        body: JSON.stringify({ body: message.trim() }),
      });
      setMessage('');
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not send this message.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <ShellLayout>
      <main className="mx-auto max-w-6xl space-y-6 pb-24">
        <header>
          <p className="text-sm font-semibold text-accent-800">Customer plans</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">Membership requests</h1>
          <p className="mt-1 max-w-2xl text-sm text-base-600">
            Review each request, discuss changes and send a clear offer. Accepted agreements remain fixed.
          </p>
        </header>

        {error && <p role="alert" className="rounded-lg border border-coral-200 bg-coral-50 p-3 text-sm text-coral-900">{error}</p>}
        <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)]">
          <section className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-semibold">Requests</h2>
              <button className="button-secondary min-h-10" onClick={() => void load()} disabled={loading}>Refresh</button>
            </div>
            {loading ? <p className="text-sm text-base-500">Loading requests…</p> : requests.length === 0 ? (
              <div className="rounded-xl border border-base-200 bg-white p-5 text-sm text-base-600">No membership requests yet.</div>
            ) : requests.map((request) => (
              <button
                type="button"
                key={request.id}
                onClick={() => setSelectedId(request.id)}
                className={`w-full rounded-xl border p-4 text-left ${selectedId === request.id ? 'border-electric-500 bg-electric-50' : 'border-base-200 bg-white'}`}
              >
                <span className="flex items-center justify-between gap-3">
                  <strong className="truncate">{request.tenant.shopName}</strong>
                  <span className={`badge ${statusBadgeClass(request.status)}`}>{request.status.replaceAll('_', ' ')}</span>
                </span>
                <span className="mt-2 block text-sm text-base-600 line-clamp-2">
                  {request.features.join(', ') || request.requirements || 'No details provided'}
                </span>
                <span className="mt-2 block text-xs text-base-500">
                  {new Date(request.createdAt).toLocaleString()}
                </span>
              </button>
            ))}
          </section>

          <section className="space-y-4">
            {!selected ? <div className="rounded-xl border border-base-200 bg-white p-5 text-sm text-base-600">Select a request to review its details.</div> : (
              <>
                <article className="card space-y-3 p-4 sm:p-6">
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wide text-accent-800">{selected.tenant.shopName}</p>
                    <h2 className="mt-1 text-lg font-semibold">Requested membership</h2>
                  </div>
                  {selected.features.length > 0 && <p className="text-sm"><strong>Features:</strong> {selected.features.join(', ')}</p>}
                  {selected.requirements && <p className="whitespace-pre-wrap text-sm"><strong>Requirements:</strong> {selected.requirements}</p>}
                  {selected.agreement && (
                    <div className="rounded-lg border border-sage-200 bg-sage-50 p-3 text-sm">
                      Accepted agreement {selected.agreement.reference}. Its recorded terms should not be edited.
                    </div>
                  )}
                  {selected.offers.map((offer) => (
                    <div key={offer.id} className={`rounded-lg border p-3 text-sm ${offer.status === 'offered' ? 'border-coral-200 bg-coral-50/40' : 'border-base-200'}`}>
                      <div className="flex justify-between gap-3">
                        <strong>Offer {offer.revision}</strong>
                        <span className={`badge ${statusBadgeClass(offer.status)}`}>{offer.status}</span>
                      </div>
                      <p className="mt-1">{formatPrice(offer.amountMinor, offer.currency)}{offer.termMonths ? ` · ${offer.termMonths} months` : ' · As agreed'}</p>
                      <p className="mt-1 text-base-600">Payment: {offer.paymentArrangement} · Renewal: {offer.renewalTerms}</p>
                      {offer.includedFeatures.length > 0 && <p className="mt-1 text-base-600">Includes: {offer.includedFeatures.join(', ')}</p>}
                      {offer.additionalConditions && <p className="mt-1 text-base-600">{offer.additionalConditions}</p>}
                      {offer.expiresAt && <p className="mt-1 text-xs text-base-500">Expires {new Date(offer.expiresAt).toLocaleString()}</p>}
                    </div>
                  ))}
                </article>

                <article className="card p-4 sm:p-6">
                  <h2 className="text-lg font-semibold">Conversation</h2>
                  <div className="mt-3 space-y-2">
                    {selected.messages.length === 0 ? <p className="text-sm text-base-500">No messages yet.</p> : selected.messages.map((item) => (
                      <div key={item.id} className="rounded-lg bg-base-50 p-3 text-sm">
                        <p className="font-medium">{item.senderType === 'sales' ? 'Sales team' : 'Customer'}</p>
                        <p className="mt-1 whitespace-pre-wrap">{item.body}</p>
                        <p className="mt-1 text-xs text-base-500">{new Date(item.createdAt).toLocaleString()}</p>
                      </div>
                    ))}
                  </div>
                  {canManage && selected.status !== 'accepted' && selected.status !== 'closed' && (
                    <form className="mt-4 space-y-3" onSubmit={sendMessage}>
                      <label className="label" htmlFor="membership-message">Reply</label>
                      <textarea id="membership-message" className="input min-h-24" value={message} onChange={(event) => setMessage(event.target.value)} maxLength={2000} required />
                      <button className="button-secondary min-h-11" type="submit" disabled={busy}>{busy ? 'Sending…' : 'Send reply'}</button>
                    </form>
                  )}
                </article>

                {canManage && !selected.agreement && selected.status !== 'closed' && (
                  <form className="card space-y-4 p-4 sm:p-6" onSubmit={createOffer}>
                    <div>
                      <h2 className="text-lg font-semibold">Prepare an offer</h2>
                      <p className="mt-1 text-sm text-base-600">State the actual amount and terms. Leave the term empty when no fixed duration is agreed.</p>
                    </div>
                    <div className="grid gap-4 sm:grid-cols-2">
                      <div><label className="label" htmlFor="offer-amount">Price (KES)</label><input id="offer-amount" className="input" type="number" min="0.01" step="0.01" value={amount} onChange={(event) => setAmount(event.target.value)} required /></div>
                      <div><label className="label" htmlFor="offer-term">Term in months (optional)</label><input id="offer-term" className="input" type="number" min="1" max="120" value={termMonths} onChange={(event) => setTermMonths(event.target.value)} /></div>
                    </div>
                    <div><label className="label" htmlFor="offer-payment">Payment arrangement</label><textarea id="offer-payment" className="input min-h-20" maxLength={500} value={paymentArrangement} onChange={(event) => setPaymentArrangement(event.target.value)} required /></div>
                    <div><label className="label" htmlFor="offer-renewal">Renewal terms</label><textarea id="offer-renewal" className="input min-h-20" maxLength={500} value={renewalTerms} onChange={(event) => setRenewalTerms(event.target.value)} required /></div>
                    <div><label className="label" htmlFor="offer-features">Included features (one per line; defaults to requested features)</label><textarea id="offer-features" className="input min-h-24" maxLength={4000} value={includedFeatures} onChange={(event) => setIncludedFeatures(event.target.value)} /></div>
                    <div><label className="label" htmlFor="offer-conditions">Additional conditions (optional)</label><textarea id="offer-conditions" className="input min-h-20" maxLength={2000} value={additionalConditions} onChange={(event) => setAdditionalConditions(event.target.value)} /></div>
                    <div><label className="label" htmlFor="offer-expiry">Offer expiry (optional)</label><input id="offer-expiry" className="input" type="datetime-local" value={expiresAt} onChange={(event) => setExpiresAt(event.target.value)} /></div>
                    <button className="btn btn-accent min-h-11" type="submit" disabled={busy}>{busy ? 'Saving…' : 'Send offer'}</button>
                  </form>
                )}
              </>
            )}
          </section>
        </div>
      </main>
    </ShellLayout>
  );
}
