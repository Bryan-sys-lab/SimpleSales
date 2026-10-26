'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { TaxEntityAdmin, TaxRuleAdmin } from '@/lib/types';
import { ShellLayout } from '@/components/layout';

const inputClass = 'w-full rounded-md border border-base-300 bg-white px-3 py-2 text-sm text-base-900 shadow-sm focus:border-accent-600 focus:outline-none focus:ring-2 focus:ring-accent-100';

function statusClass(status: string): string {
  if (status === 'active' || status === 'approved') return 'bg-emerald-50 text-emerald-700';
  if (status === 'conflicted') return 'bg-red-50 text-red-700';
  return 'bg-amber-50 text-amber-700';
}

export default function TaxRulesPage() {
  const [rules, setRules] = useState<TaxRuleAdmin[]>([]);
  const [entities, setEntities] = useState<TaxEntityAdmin[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [entityId, setEntityId] = useState('');
  const [taxType, setTaxType] = useState('vat');
  const [scope, setScope] = useState('general');
  const [rateBasisPoints, setRateBasisPoints] = useState('');
  const [taxBase, setTaxBase] = useState('taxable_supply');
  const [filingFrequency, setFilingFrequency] = useState('none');
  const [filingDueDay, setFilingDueDay] = useState('');
  const [thresholdMinor, setThresholdMinor] = useState('');
  const [effectiveFrom, setEffectiveFrom] = useState(() => new Date().toISOString().slice(0, 16));
  const [sourceUrl, setSourceUrl] = useState('');
  const [sourceReference, setSourceReference] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [ruleResponse, entityResponse] = await Promise.all([
        fetchJson<{ rules: TaxRuleAdmin[] }>('/api/admin/tax-rules?limit=200'),
        fetchJson<{ entities: TaxEntityAdmin[] }>('/api/admin/tax-entities'),
      ]);
      setRules(ruleResponse.rules);
      setEntities(entityResponse.entities);
      setEntityId((current) => current || entityResponse.entities[0]?.id || '');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load tax rules');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function createRule(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await fetchJson('/api/admin/tax-rules', {
        method: 'POST',
        body: JSON.stringify({
          taxEntityId: entityId,
          taxType,
          scope,
          jurisdiction: 'KE',
          rateBasisPoints: rateBasisPoints ? Number(rateBasisPoints) : null,
          taxBase,
          filingFrequency,
          filingDueDay: filingDueDay ? Number(filingDueDay) : null,
          thresholdMinor: thresholdMinor ? Number(thresholdMinor) : null,
          effectiveFrom: new Date(effectiveFrom).toISOString(),
          sourceUrl,
          sourceReference: sourceReference || null,
        }),
      });
      setMessage('Rule saved for review. It is not active until approved.');
      setSourceUrl('');
      setSourceReference('');
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save tax rule');
    } finally {
      setSaving(false);
    }
  }

  async function approveRule(id: string) {
    setError(null);
    setMessage(null);
    try {
      await fetchJson(`/api/admin/tax-rules/${id}/approve`, {
        method: 'POST',
        body: JSON.stringify({}),
      });
      setMessage('Rule approved and available to linked shops from its effective date.');
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to approve tax rule');
    }
  }

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">Tax rule registry</h2>
          <p className="text-sm text-base-500">Review source-backed, effective-dated rules before they reach a till.</p>
        </div>

        {error && <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        {message && <div role="status" className="rounded-md border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800">{message}</div>}

        <section className="rounded-xl border border-base-200 bg-white p-5 shadow-sm">
          <h3 className="text-base font-semibold text-base-900">Add rule for review</h3>
          <p className="mt-1 text-sm text-base-500">A source URL and review approval are required before the app can use it.</p>
          <form className="mt-4 grid gap-4 md:grid-cols-2" onSubmit={createRule}>
            <label className="text-sm text-base-700">Tax entity
              <select className={inputClass} value={entityId} onChange={(e) => setEntityId(e.target.value)} required>
                <option value="">Select entity</option>
                {entities.map((entity) => <option key={entity.id} value={entity.id}>{entity.display_label} ({entity.id})</option>)}
              </select>
            </label>
            <label className="text-sm text-base-700">Tax type
              <select className={inputClass} value={taxType} onChange={(e) => setTaxType(e.target.value)}>
                {['vat', 'tot', 'income_tax', 'etims', 'withholding', 'excise', 'payroll'].map((value) => <option key={value}>{value}</option>)}
              </select>
            </label>
            <label className="text-sm text-base-700">Scope
              <input className={inputClass} value={scope} onChange={(e) => setScope(e.target.value)} required />
            </label>
            <label className="text-sm text-base-700">Tax base
              <select className={inputClass} value={taxBase} onChange={(e) => setTaxBase(e.target.value)}>
                {['gross_sales', 'taxable_supply', 'net_profit', 'fixed_amount', 'none'].map((value) => <option key={value}>{value}</option>)}
              </select>
            </label>
            <label className="text-sm text-base-700">Rate (basis points)
              <input className={inputClass} type="number" min="0" step="1" value={rateBasisPoints} onChange={(e) => setRateBasisPoints(e.target.value)} placeholder="1600 = 16%" />
            </label>
            <label className="text-sm text-base-700">Threshold (minor units)
              <input className={inputClass} type="number" min="0" step="1" value={thresholdMinor} onChange={(e) => setThresholdMinor(e.target.value)} />
            </label>
            <label className="text-sm text-base-700">Filing frequency
              <select className={inputClass} value={filingFrequency} onChange={(e) => setFilingFrequency(e.target.value)}>
                {['none', 'monthly', 'quarterly', 'annual'].map((value) => <option key={value}>{value}</option>)}
              </select>
            </label>
            <label className="text-sm text-base-700">Due day (optional)
              <input className={inputClass} type="number" min="1" max="31" step="1" value={filingDueDay} onChange={(e) => setFilingDueDay(e.target.value)} />
            </label>
            <label className="text-sm text-base-700">Effective from
              <input className={inputClass} type="datetime-local" value={effectiveFrom} onChange={(e) => setEffectiveFrom(e.target.value)} required />
            </label>
            <label className="text-sm text-base-700">Source URL
              <input className={inputClass} type="url" value={sourceUrl} onChange={(e) => setSourceUrl(e.target.value)} required placeholder="https://www.kra.go.ke/..." />
            </label>
            <label className="text-sm text-base-700 md:col-span-2">Source reference / review note
              <input className={inputClass} value={sourceReference} onChange={(e) => setSourceReference(e.target.value)} placeholder="Official page, notice or legislation reference" />
            </label>
            <div className="md:col-span-2">
              <button className="btn btn-primary" type="submit" disabled={saving || !entityId}>{saving ? 'Saving…' : 'Save for review'}</button>
            </div>
          </form>
        </section>

        <section className="rounded-xl border border-base-200 bg-white shadow-sm">
          <div className="border-b border-base-200 px-5 py-4">
            <h3 className="font-semibold text-base-900">Configured rules</h3>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full text-left text-sm">
              <thead className="bg-base-50 text-xs uppercase tracking-wide text-base-500">
                <tr><th className="px-5 py-3">Entity</th><th className="px-5 py-3">Rule</th><th className="px-5 py-3">Effective</th><th className="px-5 py-3">Source</th><th className="px-5 py-3">Status</th><th className="px-5 py-3">Action</th></tr>
              </thead>
              <tbody className="divide-y divide-base-100">
                {rules.map((rule) => (
                  <tr key={rule.id}>
                    <td className="px-5 py-4 text-base-900">{rule.tax_entity?.display_label ?? rule.tax_entity_id}</td>
                    <td className="px-5 py-4"><div className="font-medium text-base-900">{rule.tax_type} · {rule.scope}</div><div className="text-xs text-base-500">{rule.tax_base}{rule.rate_basis_points == null ? '' : ` · ${rule.rate_basis_points / 100}%`}</div></td>
                    <td className="px-5 py-4 text-base-600">{new Date(rule.effective_from).toLocaleDateString()}</td>
                    <td className="max-w-xs px-5 py-4"><a className="truncate text-accent-700 hover:underline" href={rule.source_url} target="_blank" rel="noreferrer">{rule.source_reference || rule.source_url}</a></td>
                    <td className="px-5 py-4"><span className={`rounded-full px-2 py-1 text-xs font-medium ${statusClass(rule.status)}`}>{rule.status}</span></td>
                    <td className="px-5 py-4">{rule.status === 'needs_review' || rule.status === 'draft' ? <button className="btn btn-secondary text-xs" onClick={() => void approveRule(rule.id)}>Approve</button> : <span className="text-xs text-base-500">{rule.approved_by ?? '—'}</span>}</td>
                  </tr>
                ))}
                {!loading && rules.length === 0 && <tr><td className="px-5 py-8 text-center text-base-500" colSpan={6}>No rules configured.</td></tr>}
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </ShellLayout>
  );
}
