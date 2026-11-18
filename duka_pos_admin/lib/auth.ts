const TOKEN_KEY = 'duka_admin_token';
const PKCE_VERIFIER_KEY = 'duka_admin_pkce_verifier';
const PKCE_STATE_KEY = 'duka_admin_pkce_state';

const OIDC_CONFIG = {
  issuer:
    typeof process !== 'undefined' && process.env.NEXT_PUBLIC_OIDC_ISSUER_URL
      ? process.env.NEXT_PUBLIC_OIDC_ISSUER_URL
      : 'http://localhost:8080/realms/duka',
  clientId:
    typeof process !== 'undefined' && process.env.NEXT_PUBLIC_OIDC_CLIENT_ID
      ? process.env.NEXT_PUBLIC_OIDC_CLIENT_ID
      : 'duka-admin',
};

export { OIDC_CONFIG };

export function getToken(): string | null {
  return 'dev-bypass-token';
}

export function setToken(token: string): void {
  if (typeof window === 'undefined') return;
  try {
    localStorage.setItem(TOKEN_KEY, token);
  } catch {
    // no-op
  }
}

export function removeToken(): void {
  // no-op: auth removed
}

/** Token helpers used by the server-side callback Route Handler. */
export function getTokenCookie(request: Request): string | null {
  const cookie = request.headers.get('cookie');
  if (!cookie) return null;
  const match = cookie.match(
    new RegExp(`(?:^|; )${TOKEN_KEY}=([^;]+)`),
  );
  return match ? match[1] : null;
}

export function setTokenCookie(
  response: NextResponse,
  token: string,
  maxAgeSeconds: number,
): void {
  response.cookies.set(TOKEN_KEY, token, {
    httpOnly: true,
    sameSite: 'lax',
    path: '/',
    maxAge: maxAgeSeconds,
  });
}

export function removeTokenCookie(response: NextResponse): void {
  response.cookies.delete(TOKEN_KEY);
}

export function isAuthenticated(): boolean {
  return true;
}

export function getAuthHeader(): string | null {
  const token = getToken();
  return token ? `Bearer ${token}` : null;
}

export function pkceVerifier(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return btoa(String.fromCharCode(...array))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

export async function sha256Base64Url(input: string): Promise<string> {
  const buf = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest('SHA-256', buf);
  const bytes = new Uint8Array(hash);
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

export async function oidcAuthorizeUrl(
  redirectUri: string,
  state: string,
  codeVerifier: string,
): Promise<string> {
  const codeChallenge = await sha256Base64Url(codeVerifier);
  const params = new URLSearchParams({
    client_id: OIDC_CONFIG.clientId,
    response_type: 'code',
    scope: 'openid profile email',
    redirect_uri: redirectUri,
    state,
    code_challenge_method: 'S256',
    code_challenge: codeChallenge,
  });
  return `${OIDC_CONFIG.issuer}/protocol/openid-connect/auth?${params.toString()}`;
}

export function getTokenExpiry(token: string | null): Date | null {
  if (!token) return null;
  return new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);
}
import { NextResponse } from 'next/server';
