'use client';

export interface MetricCardProps {
  label: string;
  value: React.ReactNode;
  trend?: { label: string; delta: number; positive?: boolean };
  caption?: string;
}

export function MetricCard({
  label,
  value,
  trend,
  caption,
}: MetricCardProps) {
  return (
    <div className="card p-5">
      <p className="text-sm font-medium text-base-500 mb-1">{label}</p>
      <div className="text-2xl font-semibold text-base-900 tracking-tight">{value}</div>
      {caption && <p className="text-xs text-base-400 mt-1">{caption}</p>}
      {trend && (
        <div className="mt-3 flex items-center gap-1.5">
          <span
            className={`text-xs font-medium rounded-md px-2 py-0.5 ${
              trend.positive !== false
                ? 'bg-emerald-50 text-emerald-700'
                : 'bg-red-50 text-red-700'
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
