import Image from 'next/image';

export function EmptyState({ message, compact = false }: { message: string; compact?: boolean }) {
  return (
    <div className={`flex flex-col items-center justify-center text-center ${compact ? 'gap-2 py-4' : 'gap-3 py-8'}`} role="status">
      <Image
        src="/SimplerAnalytics%20Green%20Monogram%20Logo.png"
        alt=""
        width={compact ? 144 : 192}
        height={compact ? 72 : 96}
        className={compact ? 'h-12 w-24 object-contain' : 'h-16 w-32 object-contain'}
      />
      <p className="text-sm text-base-500">{message}</p>
    </div>
  );
}
