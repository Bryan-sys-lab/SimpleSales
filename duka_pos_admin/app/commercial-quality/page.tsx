'use client';

import { useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';

type QualityReport = {
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

  useEffect(() => {
    let cancelled = false;
    void fetchJson<{ report: QualityReport; definitions: Record<string, unknown> }>('/api/admin/commercial/quality')
      .then((response) => {
        if (!cancelled) {
          setReport(response.report);
          setDefinitions(response.definitions);
          setLoading(false);
        }
      })
      .catch((cause) => {
        if (!cancelled) {
          setError(cause instanceof Error ? cause.message : 'Failed to load data quality');
          setLoading(false);
        }
      });
    return () => { cancelled = true; };
  }, []);

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">Data quality &amp; reconciliation</h2>
          <p className="text-sm text-base-500">Restricted pipeline health for definitions, coverage, freshness, suppression and reproducibility.</p>
        </div>
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          <strong>Internal quality view.</strong> This report contains counts and fingerprints only; it does not reveal contribution rows or contributor identity. Commercial collection remains disabled by policy.
        </div>
        {loading && <div className="card p-5 text-sm text-base-500" role="status">Loading data quality…</div>}
        {error && <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800" role="alert">{error}</div>}
        {report && !error && (
          <>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <Metric label="Eligible rows" value={report.eligibleRowCount} detail={`${report.excludedRowCount} excluded`} />
              <Metric label="Coverage" value={`${Math.round(report.coverage.completeRatio * 100)}%`} detail={`${report.coverage.partial} partial · ${report.coverage.unknown} unknown`} />
              <Metric label="Freshness" value={report.freshness.status} detail={report.freshness.ageDays == null ? 'No eligible period' : `${report.freshness.ageDays} days old`} />
              <Metric label="Suppressed cohorts" value={report.suppression.suppressedCohortCount} detail={`${report.suppression.publishableCohortCount} publishable`} />
            </div>
            <section className="card p-5" aria-label="Quality notes">
              <h3 className="text-sm font-semibold text-base-900">Quality notes</h3>
              {report.qualityNotes.length === 0 ? <p className="mt-2 text-sm text-emerald-700">No discrepancies detected in the evaluated input.</p> : <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-base-700">{report.qualityNotes.map((note) => <li key={note}>{note}</li>)}</ul>}
            </section>
            <section className="card p-5" aria-label="Definitions and reproducibility">
              <h3 className="text-sm font-semibold text-base-900">Definitions &amp; reproducibility</h3>
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
