import { NextResponse } from 'next/server';
import {
  getTokenCookie,
  removeTokenCookie,
  setTokenCookie,
  sha256Base64Url,
  OIDC_CONFIG,
} from '@/lib/auth';

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const code = searchParams.get('code');
  const error = searchParams.get('error');
  const state = searchParams.get('state');

  if (error || !code || !state) {
    return NextResponse.redirect(new URL('/login?error=missing_code', request.url));
  }

  // Validate state against the PKCE state stored in a cookie.
  const storedState = request.headers.get('cookie')?.match(
    new RegExp(`(?:^|; )duka_admin_pkce_state=([^;]+)`),
  )?.[1];
  if (!storedState || storedState !== state) {
    return NextResponse.redirect(new URL('/login?error=invalid_state', request.url));
  }

  // Exchange the authorization code for an access token.
  const storedVerifier = request.headers.get('cookie')?.match(
    new RegExp(`(?:^|; )duka_admin_pkce_verifier=([^;]+)`),
  )?.[1];
  if (!storedVerifier) {
    return NextResponse.redirect(new URL('/login?error=missing_verifier', request.url));
  }

  const tokenEndpoint = `${OIDC_CONFIG.issuer}/protocol/openid-connect/token`;
  const tokenResponse = await fetch(tokenEndpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: OIDC_CONFIG.clientId,
      code,
      redirect_uri: `${new URL(request.url).origin}/login/callback`,
      code_verifier: storedVerifier,
    }).toString(),
  });

  if (!tokenResponse.ok) {
    return NextResponse.redirect(new URL('/login?error=token_exchange_failed', request.url));
  }

  const tokenData = await tokenResponse.json();
  const accessToken = tokenData.access_token as string;
  const expiresIn = (tokenData.expires_in as number) ?? 3600;

  const returnTo = '/dashboard';
  const response = NextResponse.redirect(new URL(returnTo, request.url));
  setTokenCookie(response, accessToken, expiresIn);
  removeTokenCookie(response); // clear PKCE verifier/state cookies by replacing them
  response.cookies.delete('duka_admin_pkce_verifier');
  response.cookies.delete('duka_admin_pkce_state');

  return response;
}
