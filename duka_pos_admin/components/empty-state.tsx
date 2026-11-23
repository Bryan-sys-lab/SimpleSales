import { BrandMark } from './brand';

export function EmptyState({ message, compact = false }: { message: string; compact?: boolean }) {
  return (
    <div className={`flex flex-col items-center justify-center text-center ${compact ? 'gap-2 py-4' : 'gap-3 py-8'}`} role="status">
      <BrandMark
        width={compact ? 96 : 128}
      />
      <p className="text-sm text-base-500">{message}</p>
    </div>
  );
}
