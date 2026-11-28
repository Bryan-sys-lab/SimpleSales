'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { TaxEntityAdmin, TaxRuleAdmin } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

const inputClass = 'input';

function statusClass(status: string): string {
  if (status === 'active' || status === 'approved') return 'bg-sage-50 text-sage-800';
  if (status === 'conflicted') return 'bg-coral-50 text-coral-800';
  return 'bg-electric-50 text-electric-800';
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
  useAdminLiveRefresh(load, ['tax-rules']);

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
          <h1 className="text-2xl font-semibold tracking-tight text-base-900">Tax rule registry</h1>
          <p className="text-sm text-base-500">Review source-backed, effective-dated rules before they reach a till.</p>
        </div>

        {error && <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        {message && <div role="status" className="rounded-md border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800">{message}</div>}

        <section className="rounded-xl border border-base-200 bg-white p-5 shadow-sm">
          <h2 className="text-lg font-semibold text-base-900">Add rule for review</h2>
          <p className="mt-1 text-sm text-base-500">A source URL and review approval are required before the app can use it.</p>
          <form className="mt-4 grid gap-4 md:grid-cols-2" onSubmit={createRule}>
            <label className="text-sm text-base-700" htmlFor="tax-entity">Tax entity
              <select id="tax-entity" name="taxEntityId" className={inputClass} value={entityId} onChange={(e) => setEntityId(e.target.value)} required>
                <option value="">Select entity</option>
                {entities.map((entity) => <option key={entity.id} value={entity.id}>{entity.display_label} ({entity.id})</option>)}
              </select>
            </label>
            <label className="text-sm text-base-700" htmlFor="tax-type">Tax type
              <select id="tax-type" name="taxType" className={inputClass} value={taxType} onChange={(e) => setTaxType(e.target.value)}>
                {['vat', 'tot', 'income_tax', 'etims', 'withholding', 'excise', 'payroll'].map((value) => <option key={value}>{value}</option>)}
              </select>
            </label>
            <label className="text-sm text-base-700" htmlFor="tax-scope">Scope
              <input id="tax-scope" name="scope" className={inputClass} value={scope} onChange={(e) => setScope(e.target.value)} required />
            </label>
            <label className="text-sm text-base-700" htmlFor="tax-base">Tax base
              <select id="tax-base" name="taxBase" className={inputClass} value={taxBase} onChange={(e) => setTaxBase(e.target.value)}>
                {['gross_sales', 'taxable_supply', 'net_profit', 'fixed_amount', 'none'].map((value) => <option key={value}>{value}</option>)}
              </select>
            </label>
            <label className="text-sm text-base-700" htmlFor="tax-rate">Rate (basis points)
              <input id="tax-rate" name="rateBasisPoints" className={inputClass} type="number" min="0" step="1" value={rateBasisPoints} onChange={(e) => setRateBasisPoints(e.target.value)} placeholder="1600 = 16%" />
            </label>
            <label className="text-sm text-base-700" htmlFor="tax-threshold">Threshold (minor units)
              <input id="tax-threshold" name="thresholdMinor" className={inputClass} type="number" min="0" step="1" value={thresholdMinor} onChange={(e) => setThresholdMinor(e.target.value)} />
            </label>
            <label className="text-sm text-base-700" htmlFor="filing-frequency">Filing frequency
              <select id="filing-frequency" name="filingFrequency" className={inputClass} value={filingFrequency} onChange={(e) => setFilingFrequency(e.target.value)}>
                {['none', 'monthly', 'quarterly', 'annual'].map((value) => <option key={value}>{value}</option>)}
              </select>
            </label>
            <label className="text-sm text-base-700" htmlFor="filing-due-day">Due day (optional)
              <input id="filing-due-day" name="filingDueDay" className={inputClass} type="number" min="1" max="31" step="1" value={filingDueDay} onChange={(e) => setFilingDueDay(e.target.value)} />
            </label>
            <label className="text-sm text-base-700" htmlFor="effective-from">Effective from
              <input id="effective-from" name="effectiveFrom" className={inputClass} type="datetime-local" value={effectiveFrom} onChange={(e) => setEffectiveFrom(e.target.value)} required />
            </label>
            <label className="text-sm text-base-700" htmlFor="source-url">Source URL
              <input id="source-url" name="sourceUrl" className={inputClass} type="url" value={sourceUrl} onChange={(e) => setSourceUrl(e.target.value)} required placeholder="https://www.kra.go.ke/..." />
            </label>
            <label className="text-sm text-base-700 md:col-span-2" htmlFor="source-reference">Source reference / review note
              <input id="source-reference" name="sourceReference" className={inputClass} value={sourceReference} onChange={(e) => setSourceReference(e.target.value)} placeholder="Official page, notice or legislation reference" />
            </label>
            <div className="md:col-span-2">
              <button className="btn btn-primary" type="submit" disabled={saving || !entityId}>{saving ? 'Saving…' : 'Save for review'}</button>
            </div>
          </form>
        </section>

        <section className="rounded-xl border border-base-200 bg-white shadow-sm">
          <div className="border-b border-base-200 px-5 py-4">
            <h2 className="font-semibold text-base-900">Configured rules</h2>
          </div>
          <div className="p-4 sm:p-5">
            <DataTable
              caption="Configured tax rules"
              columns={[
                { key: 'entity', label: 'Entity' },
                { key: 'rule', label: 'Rule' },
                { key: 'effective', label: 'Effective', sortable: true },
                { key: 'source', label: 'Source' },
                { key: 'status', label: 'Status' },
                { key: 'action', label: 'Action' },
              ]}
              data={rules}
              rowKey={(rule) => rule.id}
              renderCell={(rule, key) => {
                if (key === 'entity') return <span>{rule.tax_entity?.display_label ?? rule.tax_entity_id}</span>;
                if (key === 'rule') return <span><strong className="block font-medium">{rule.tax_type} · {rule.scope}</strong><span className="text-xs text-base-600">{rule.tax_base}{rule.rate_basis_points == null ? '' : ` · ${rule.rate_basis_points / 100}%`}</span></span>;
                if (key === 'effective') return <span>{new Date(rule.effective_from).toLocaleDateString()}</span>;
                if (key === 'source') return <a className="break-all text-accent-700 underline-offset-2 hover:underline dark:text-electric-300" href={rule.source_url} target="_blank" rel="noreferrer">{rule.source_reference || rule.source_url}</a>;
                if (key === 'status') return <span className={`badge ${statusClass(rule.status)}`}>{rule.status.replaceAll('_', ' ')}</span>;
                if (key === 'action') return rule.status === 'needs_review' || rule.status === 'draft'
                  ? <button type="button" className="button-secondary min-h-11" onClick={() => void approveRule(rule.id)}>Approve</button>
                  : <span className="text-sm text-base-600">Approved by {rule.approved_by ?? '—'}</span>;
                return null;
              }}
              emptyMessage={loading ? 'Loading tax rules…' : 'No rules configured.'}
            />
          </div>
        </section>
      </div>
    </ShellLayout>
  );
}
