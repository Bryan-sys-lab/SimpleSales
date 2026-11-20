'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { FormEvent, Suspense, useState } from 'react';

function LoginContent() {
  const search = useSearchParams();
  const router = useRouter();
  const [email, setEmail] = useState('brian@nerva.co.ke');
  const [masterToken, setMasterToken] = useState('');
  const [phone, setPhone] = useState('');
  const [key, setKey] = useState('');
  const [departmentLogin, setDepartmentLogin] = useState(false);
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
    <main className="flex min-h-screen items-center justify-center bg-base-50 px-4 py-10">
      <div className="w-full max-w-md">
        <div className="mb-7">
          <span className="mb-4 inline-flex rounded-xl bg-accent-700 p-2.5 text-white shadow-sm" aria-hidden="true">D</span>
          <h1 className="text-2xl font-semibold tracking-tight text-base-900">Duka platform admin</h1>
          <p className="mt-1 text-sm text-base-600">Sign in with your administrator credentials.</p>
        </div>
        <form onSubmit={submit} className="card space-y-5 p-6">
          <div>
            <label className="label" htmlFor="email">Work email</label>
            <input id="email" className="input" type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} />
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
          {error && <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800" role="alert">{error}</p>}
          <button className="btn btn-accent min-h-11 w-full" type="submit" disabled={busy}>{busy ? 'Signing in…' : 'Sign in securely'}</button>
          <button type="button" className="w-full py-2 text-sm font-medium text-accent-800 underline-offset-4 hover:underline" onClick={() => { setDepartmentLogin((v) => !v); setError(''); }}>
            {departmentLogin ? 'Use system administrator token' : 'Sign in with a department key'}
          </button>
        </form>
        <p className="mt-4 text-center text-xs text-base-500">Access is logged. Sessions expire after one hour.</p>
      </div>
    </main>
  );
}

export default function LoginPage() {
  return <Suspense fallback={<div className="min-h-screen bg-base-50" />}><LoginContent /></Suspense>;
}
