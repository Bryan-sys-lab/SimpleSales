'use client';

export interface MetricCardProps {
  label: string;
  value: React.ReactNode;
  trend?: { label: string; delta: number; positive?: boolean };
  caption?: string;
}

export function MetricCard({ label, value, trend, caption }: MetricCardProps) {
  return (
    <div className="card min-w-0 p-4 sm:p-5">
      <p className="mb-2 text-sm font-medium text-base-600">{label}</p>
      <div className="break-words text-2xl font-semibold tracking-tight text-base-900 tabular-nums dark:text-electric-300">{value}</div>
      {caption && <p className="mt-1 text-sm text-base-600">{caption}</p>}
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
