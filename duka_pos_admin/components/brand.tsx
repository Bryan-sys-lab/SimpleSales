import Image from 'next/image';

type BrandMarkProps = {
  width: number;
  className?: string;
  priority?: boolean;
};

export function BrandMark({
  width,
  className = '',
  priority = false,
}: BrandMarkProps) {
  return (
    <Image
      src="/simpler-analytics-mark.webp"
      alt=""
      width={570}
      height={257}
      sizes={`${width}px`}
      priority={priority}
      style={{ width, height: 'auto' }}
      className={`shrink-0 object-contain ${className}`}
    />
  );
}

export function BrandName({
  animated = false,
  className = '',
}: {
  animated?: boolean;
  className?: string;
}) {
  return (
    <span
      className={`inline-flex whitespace-nowrap font-semibold tracking-tight ${
        animated ? 'brand-loading-name' : ''
      } ${className}`}
    >
      <span className="text-base-900 dark:text-base-100">Simpler</span>
      <span className="text-electric-700 dark:text-electric-300">Analytics</span>
    </span>
  );
}

export function BrandLockup({
  className = '',
  compact = false,
  stacked = false,
  animatedName = false,
  priority = false,
}: {
  className?: string;
  compact?: boolean;
  stacked?: boolean;
  animatedName?: boolean;
  priority?: boolean;
}) {
  return (
    <div
      className={`flex ${
        stacked
          ? 'flex-col items-center justify-center gap-1'
          : 'flex-row items-center gap-1'
      } ${className}`}
    >
      <BrandMark
        width={compact ? 48 : 112}
        priority={priority}
      />
      <BrandName
        animated={animatedName}
        className={compact ? 'text-xs' : 'text-xl'}
      />
    </div>
  );
}

export function BrandLoader({ className = '' }: { className?: string }) {
  return (
    <div
      className={`flex flex-col items-center justify-center gap-2 ${className}`}
      role="status"
      aria-label="Loading SimplerAnalytics"
    >
      <BrandMark width={140} />
      <BrandName animated className="text-lg" />
      <span className="sr-only">Loading</span>
    </div>
  );
}
