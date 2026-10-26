'use client';

import { useSearchParams } from 'next/navigation';
import { Suspense, useCallback, useState } from 'react';
import { oidcAuthorizeUrl, pkceVerifier } from '@/lib/auth';

function LoginContent() {
  const searchParams = useSearchParams();
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const returnTo = searchParams.get('returnTo') || '/dashboard';

  const handleSignIn = useCallback(async () => {
    const verifier = pkceVerifier();
    const state = crypto.randomUUID?.() || Math.random().toString(36).slice(2);
    try {
      // Store PKCE data in httpOnly cookies so the server-side callback can read it.
      document.cookie = `duka_admin_pkce_verifier=${verifier}; path=/; max-age=600; SameSite=Lax`;
      document.cookie = `duka_admin_pkce_state=${state}; path=/; max-age=600; SameSite=Lax`;
      document.cookie = `duka_admin_return_to=${returnTo}; path=/; max-age=600; SameSite=Lax`;
    } catch {
      // no-op if cookies unavailable
    }
    const redirectUri = `${window.location.origin}/login/callback`;
    const url = await oidcAuthorizeUrl(redirectUri, state, verifier);
    window.location.href = url;
  }, [returnTo]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-base-50 px-4">
      <div className="w-full max-w-md">
        <div className="mb-8">
          <h1 className="text-2xl font-semibold tracking-tight text-base-900">Duka POS</h1>
          <p className="mt-1 text-sm text-base-500">Systems Admin — sign in</p>
        </div>
        <div className="card p-6">
          <div className="mb-6">
            <p className="text-sm text-base-600">
              Authenticate with the OIDC provider (Keycloak) to access the admin dashboard.
            </p>
          </div>
          <button
            onClick={handleSignIn}
            className="btn btn-accent w-full mb-3"
            aria-label="Sign in with Keycloak"
          >
            Sign in with Keycloak
          </button>
          {error && (
            <p className="mt-3 text-sm text-red-700" role="alert">
              {error}
            </p>
          )}
          <p className="mt-5 text-xs text-base-400 text-center">
            In production this initiates a PKCE authorization-code flow against{' '}
            <span className="font-medium">{process.env.NEXT_PUBLIC_OIDC_ISSUER_URL ?? 'http://localhost:8080/realms/duka'}</span>.
          </p>
        </div>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-base-50" />}>
      <LoginContent />
    </Suspense>
  );
}
