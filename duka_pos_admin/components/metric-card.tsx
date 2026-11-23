'use client';

export interface MetricCardProps {
  label: string;
  value: React.ReactNode;
  trend?: { label: string; delta: number; positive?: boolean };
  caption?: string;
}

export function MetricCard({ label, value, trend, caption }: MetricCardProps) {
  return (
    <div className="card p-5 transition-transform duration-200 hover:-translate-y-0.5">
      <p className="text-xs font-medium uppercase tracking-wide text-base-500 mb-2">{label}</p>
      <div className="text-2xl font-semibold text-base-900 dark:text-electric-300 tracking-tight tabular-nums">{value}</div>
      {caption && <p className="text-xs text-base-400 mt-1">{caption}</p>}
      {trend && (
        <div className="mt-3 flex items-center gap-1.5">
          <span
            className={`text-xs font-medium rounded-md px-2 py-0.5 tabular-nums ${
              trend.positive !== false
                ? 'bg-sage-50 text-sage-800'
                : 'bg-coral-50 text-coral-800'
            }`}
          >
            {trend.delta >= 0 ? '+' : ''}{trend.delta}%
          </span>
          <span className="text-xs text-base-500">{trend.label}</span>
        </div>
      )}
    </div>
  );
}

export default MetricCard;
