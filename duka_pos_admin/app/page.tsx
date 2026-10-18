'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { getToken, getTokenExpiry } from '@/lib/auth';

export default function RootPage() {
  const router = useRouter();

  useEffect(() => {
    const token = getToken();
    if (!token) {
      router.push('/login');
      return;
    }
    const expiry = getTokenExpiry(token);
    if (expiry && expiry.getTime() <= Date.now()) {
      router.push('/login');
      return;
    }
    router.push('/dashboard');
  }, [router]);

  return null;
}
