'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { FormEvent, Suspense, useState } from 'react';
import { BrandLockup, BrandLoader } from '@/components/brand';

function LoginContent() {
  const search = useSearchParams();
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [masterToken, setMasterToken] = useState('');
  const [phone, setPhone] = useState('');
  const [key, setKey] = useState('');
  const [departmentLogin, setDepartmentLogin] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true); setError('');
    try {
      const response = await fetch('/api/admin/auth/login', {
        method: 'POST', credentials: 'same-origin',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(departmentLogin ? { email, phone, key } : { email, masterToken }),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? 'Sign in failed');
      const requested = search.get('returnTo') ?? '/dashboard';
      router.replace(requested.startsWith('/') && !requested.startsWith('//') ? requested : '/dashboard');
      router.refresh();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Sign in failed');
    } finally { setBusy(false); }
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-base-50 px-4 py-10 dark:bg-base-950">
      <div className="w-full max-w-md">
        <div className="mb-7 text-center">
          <BrandLockup stacked className="mb-5" priority />
          <h1 className="text-2xl font-semibold tracking-tight text-base-900 dark:text-base-100">Sign in to SimplerAnalytics</h1>
          <p className="mt-1 text-sm text-base-600 dark:text-base-300">Sign in with your administrator credentials.</p>
        </div>
        <form onSubmit={submit} className="card space-y-5 p-6" autoComplete="off">
          <div>
            <label className="label" htmlFor="email">Work email</label>
            <input id="email" name="admin-login-email" className="input" type="email" autoComplete="off" autoCapitalize="none" spellCheck={false} inputMode="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
          </div>
          {departmentLogin ? <>
            <div>
              <label className="label" htmlFor="phone">Phone</label>
              <input id="phone" className="input" type="tel" autoComplete="tel" required value={phone} onChange={(e) => setPhone(e.target.value)} />
            </div>
            <div>
              <label className="label" htmlFor="key">Administrator key</label>
              <input id="key" className="input" type="password" autoComplete="current-password" required value={key} onChange={(e) => setKey(e.target.value)} />
            </div>
          </> : <div>
            <label className="label" htmlFor="master-token">System access token</label>
            <input id="master-token" className="input" type="password" autoComplete="current-password" required value={masterToken} onChange={(e) => setMasterToken(e.target.value)} />
          </div>}
          {error && <p className="rounded-lg border border-coral-200 bg-coral-50 px-3 py-2 text-sm text-coral-900" role="alert">{error}</p>}
          <button className="btn btn-accent min-h-11 w-full" type="submit" disabled={busy}>{busy ? 'Signing in…' : 'Sign in securely'}</button>
          <button type="button" className="w-full py-2 text-sm font-medium text-accent-800 underline-offset-4 hover:underline dark:text-electric-300" onClick={() => { setDepartmentLogin((v) => !v); setError(''); }}>
            {departmentLogin ? 'Use system administrator token' : 'Sign in with a department key'}
          </button>
        </form>
        <p className="mt-4 text-center text-xs text-base-500 dark:text-base-400">Access is logged. Your session renews while the dashboard is open.</p>
      </div>
    </main>
  );
}

export default function LoginPage() {
  return <Suspense fallback={
    <BrandLoader className="min-h-screen bg-base-50 px-4" />
  }><LoginContent /></Suspense>;
}
