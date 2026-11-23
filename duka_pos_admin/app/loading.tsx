import Image from 'next/image';

export default function Loading() {
  return (
    <main className="flex min-h-[60vh] items-center justify-center" role="status" aria-label="Loading">
      <Image
        src="/SimplerAnalytics%20Green%20Monogram%20Logo.png"
        alt="SimplerAnalytics"
        width={240}
        height={120}
        priority
        className="h-auto w-60"
      />
    </main>
  );
}
