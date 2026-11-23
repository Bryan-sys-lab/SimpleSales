import { NextRequest, NextResponse } from 'next/server';
import { TOKEN_COOKIE } from '@/lib/auth';

export const dynamic = 'force-dynamic';
type Context = { params: Promise<{ path: string[] }> };
const methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'] as const;

function setSessionCookie(response: NextResponse, token: string, expiresIn: number) {
  response.cookies.set(TOKEN_COOKIE, token, {
    httpOnly: true,
    secure: true,
    sameSite: 'lax',
    path: '/',
    maxAge: Math.min(Math.max(expiresIn, 60), 30 * 24 * 60 * 60),
  });
}

async function proxy(request: NextRequest, context: Context) {
  const { path: segments } = await context.params;
  const path = segments.join('/');
  const isLogin = path === 'admin/auth/login' && request.method === 'POST';
  const isRefresh = path === 'admin/auth/refresh' && request.method === 'POST';
  const isLogout = path === 'admin/auth/logout' && request.method === 'POST';
  const isWsUrl = path === 'admin/auth/ws-url' && request.method === 'GET';
  if (!isLogin && !isLogout && !request.cookies.get(TOKEN_COOKIE)?.value) {
    return NextResponse.json({ error: 'Authentication required' }, { status: 401 });
  }
  if (!['GET', 'HEAD', 'OPTIONS'].includes(request.method)) {
    const origin = request.headers.get('origin');
    if (!origin || origin !== new URL(request.url).origin) return NextResponse.json({ error: 'Invalid request origin' }, { status: 403 });
  }
  if (isLogout) {
    const response = NextResponse.json({ ok: true });
    response.cookies.set(TOKEN_COOKIE, '', { httpOnly: true, secure: true, sameSite: 'lax', path: '/', maxAge: 0 });
    return response;
  }

  const base = process.env.ADMIN_BACKEND_URL;
  if (!base) return NextResponse.json({ error: 'Admin backend is not configured' }, { status: 503 });
  if (isWsUrl) {
    try {
      const backend = new URL(base);
      if (backend.protocol !== 'https:' && backend.hostname !== 'localhost') throw new Error('HTTPS required');
      return NextResponse.json({ url: backend.origin }, { headers: { 'cache-control': 'no-store' } });
    } catch {
      return NextResponse.json({ error: 'Admin backend URL is invalid' }, { status: 503 });
    }
  }
  const token = request.cookies.get(TOKEN_COOKIE)?.value;
  const headers = new Headers();
  const contentType = request.headers.get('content-type');
  if (contentType) headers.set('content-type', contentType);
  if (token) headers.set('authorization', `Bearer ${token}`);
  const incomingUrl = new URL(request.url);
  const target = `${base.replace(/\/$/, '')}/api/${path}${incomingUrl.search}`;
  let upstream: Response;
  try {
    upstream = await fetch(target, {
      method: request.method,
      headers,
      body: ['GET', 'HEAD'].includes(request.method) ? undefined : await request.arrayBuffer(),
      cache: 'no-store',
    });
  } catch {
    return NextResponse.json({ error: 'Admin backend is unavailable' }, { status: 502 });
  }
  const body = await upstream.arrayBuffer();
  let response = new NextResponse(body, {
    status: upstream.status,
    headers: { 'content-type': upstream.headers.get('content-type') ?? 'application/json', 'cache-control': 'no-store' },
  });
  if ((upstream.status === 401 || (isRefresh && upstream.status === 403)) && token) {
    response.cookies.set(TOKEN_COOKIE, '', { httpOnly: true, secure: true, sameSite: 'lax', path: '/', maxAge: 0 });
  }
  if (isRefresh && upstream.status === 403) {
    response = NextResponse.json({ error: 'Administrator access is no longer active' }, { status: 401 });
    response.cookies.set(TOKEN_COOKIE, '', { httpOnly: true, secure: true, sameSite: 'lax', path: '/', maxAge: 0 });
    return response;
  }
  if (isLogin && upstream.ok) {
    try {
      const payload = JSON.parse(new TextDecoder().decode(body)) as { access_token?: string; expires_in?: number; email?: string; role?: string };
      if (!payload.access_token) return NextResponse.json({ error: 'Login response did not include a session' }, { status: 502 });
      response = NextResponse.json({ email: payload.email, role: payload.role }, { status: upstream.status });
      response.headers.set('cache-control', 'no-store');
      setSessionCookie(response, payload.access_token, payload.expires_in ?? 3600);
      return response;
    } catch {
      return NextResponse.json({ error: 'Invalid login response' }, { status: 502 });
    }
  }
  if (isRefresh && upstream.ok) {
    try {
      const payload = JSON.parse(new TextDecoder().decode(body)) as { access_token?: string; expires_in?: number };
      if (!payload.access_token) return NextResponse.json({ error: 'Session refresh did not include a token' }, { status: 502 });
      response = NextResponse.json({ ok: true }, { status: upstream.status });
      response.headers.set('cache-control', 'no-store');
      setSessionCookie(response, payload.access_token, payload.expires_in ?? 3600);
      return response;
    } catch {
      return NextResponse.json({ error: 'Invalid session refresh response' }, { status: 502 });
    }
  }
  return response;
}

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
export const HEAD = proxy;
