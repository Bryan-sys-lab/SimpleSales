'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

type QualityReport = {
  dictionaryVersion: string;
  qualityStates: string[];
  metricDefinitions: Array<{ key: string; formula: string; unit: string; source: string; exclusion: string; qualityState: string }>;
  sourceRowCount: number;
  eligibleRowCount: number;
  excludedRowCount: number;
  duplicateRowCount: number;
  currencies: string[];
  mixedCurrency: boolean;
  coverage: { complete: number; partial: number; unknown: number; completeRatio: number };
  qualityFlagCounts: Record<string, number>;
  freshness: { latestPeriodEndUtc: string | null; ageDays: number | null; status: string; thresholdDays: number };
  suppression: { cohortCount: number; suppressedCohortCount: number; publishableCohortCount: number };
  reproducibilityFingerprint: string;
  qualityNotes: string[];
};

export default function CommercialQualityPage() {
  const [report, setReport] = useState<QualityReport | null>(null);
  const [definitions, setDefinitions] = useState<Record<string, unknown>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetchJson<{ report: QualityReport; definitions: Record<string, unknown> }>('/api/admin/commercial/quality');
      setReport(response.report);
      setDefinitions(response.definitions);
      setError(null);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Failed to load data quality');
    } finally {
      setLoading(false);
    }
  }, []);
  useAdminLiveRefresh(load, ['commercial-quality']);
  useEffect(() => { void load(); }, [load]);

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-base-900">Data quality &amp; reconciliation</h1>
          <p className="text-sm text-base-500">Restricted pipeline health for definitions, coverage, freshness, suppression and reproducibility.</p>
        </div>
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          <strong>Internal quality view.</strong> This report contains counts and fingerprints only; it does not reveal contribution rows or contributor identity. Commercial collection remains disabled by policy.
        </div>
        {loading && <div className="card p-5 text-sm text-base-500" role="status">Loading data quality…</div>}
        {error && <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800" role="alert">{error}</div>}
        {report && !error && (
          <>
            <section className="card p-5" aria-label="Report period and freshness">
              <dl className="grid gap-3 text-sm sm:grid-cols-3">
                <div><dt className="font-medium text-base-700">Dictionary</dt><dd className="text-base-500">{report.dictionaryVersion}</dd></div>
                <div><dt className="font-medium text-base-700">Period</dt><dd className="text-base-500">{report.freshness.latestPeriodEndUtc ? `Through ${new Date(report.freshness.latestPeriodEndUtc).toLocaleString()}` : 'No eligible period'}</dd></div>
                <div><dt className="font-medium text-base-700">Last updated</dt><dd className="text-base-500">{new Date().toLocaleString()}</dd></div>
              </dl>
            </section>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <Metric label="Eligible rows" value={report.eligibleRowCount} detail={`Numerator ${report.eligibleRowCount} · denominator ${report.sourceRowCount}`} />
              <Metric label="Coverage" value={`${Math.round(report.coverage.completeRatio * 100)}%`} detail={`Numerator ${report.coverage.complete} · denominator ${report.sourceRowCount} · ${report.coverage.partial} partial · ${report.coverage.unknown} unknown`} />
              <Metric label="Freshness" value={report.freshness.status} detail={report.freshness.ageDays == null ? 'No eligible period' : `Numerator 0 · denominator ${report.freshness.thresholdDays} days · ${report.freshness.ageDays} days old`} />
              <Metric label="Suppressed cohorts" value={report.suppression.suppressedCohortCount} detail={`Numerator suppressed ${report.suppression.suppressedCohortCount} · denominator ${report.suppression.cohortCount} · ${report.suppression.publishableCohortCount} publishable`} />
            </div>
            <section className="card p-5" aria-label="Canonical quality states">
              <h2 className="text-sm font-semibold text-base-900">Canonical quality states</h2>
              <div className="mt-3 flex flex-wrap gap-2">
                {report.qualityStates.map((state) => <span key={state} className="rounded-full border border-base-200 px-3 py-1 text-xs text-base-700">{state}</span>)}
              </div>
            </section>
            <section className="card p-5" aria-label="Canonical metric definitions">
              <h2 className="text-sm font-semibold text-base-900">Canonical metrics</h2>
              <div className="mt-3 space-y-3">
                {report.metricDefinitions.map((metric) => (
                  <div key={metric.key} className="rounded-md border border-base-200 p-3">
                    <p className="text-sm font-medium text-base-900">{metric.key} <span className="font-normal text-base-500">· {metric.unit} · {metric.qualityState}</span></p>
                    <p className="mt-1 text-xs text-base-700">{metric.formula}</p>
                    <p className="mt-1 text-xs text-base-500">Source: {metric.source}. Exclusion: {metric.exclusion}</p>
                  </div>
                ))}
              </div>
            </section>
            <section className="card p-5" aria-label="Quality notes">
              <h2 className="text-sm font-semibold text-base-900">Quality notes</h2>
              {report.qualityNotes.length === 0 ? <p className="mt-2 text-sm text-emerald-700">No discrepancies detected in the evaluated input.</p> : <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-base-700">{report.qualityNotes.map((note) => <li key={note}>{note}</li>)}</ul>}
            </section>
            <section className="card p-5" aria-label="Definitions and reproducibility">
              <h2 className="text-sm font-semibold text-base-900">Definitions &amp; reproducibility</h2>
              <dl className="mt-3 grid gap-3 text-sm sm:grid-cols-2">
                {Object.entries(definitions).map(([key, value]) => <div key={key}><dt className="font-medium text-base-700">{key}</dt><dd className="text-base-500">{typeof value === 'object' ? JSON.stringify(value) : String(value)}</dd></div>)}
                <div className="sm:col-span-2"><dt className="font-medium text-base-700">Input fingerprint</dt><dd className="break-all font-mono text-xs text-base-500">{report.reproducibilityFingerprint}</dd></div>
              </dl>
            </section>
          </>
        )}
      </div>
    </ShellLayout>
  );
}

function Metric({ label, value, detail }: { label: string; value: string | number; detail: string }) {
  return <section className="card p-4"><p className="text-xs font-medium uppercase tracking-wide text-base-500">{label}</p><p className="mt-2 text-2xl font-semibold text-base-900">{value}</p><p className="mt-1 text-xs text-base-500">{detail}</p></section>;
}
