import { NextRequest, NextResponse } from 'next/server';
import { TOKEN_COOKIE } from '@/lib/auth';

export const dynamic = 'force-dynamic';
type Context = { params: { path: string[] } };
const methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'] as const;

async function proxy(request: NextRequest, context: Context) {
  const path = context.params.path.join('/');
  const isLogin = path === 'admin/auth/login' && request.method === 'POST';
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
  if (upstream.status === 401 && token) {
    response.cookies.set(TOKEN_COOKIE, '', { httpOnly: true, secure: true, sameSite: 'lax', path: '/', maxAge: 0 });
  }
  if (isLogin && upstream.ok) {
    try {
      const payload = JSON.parse(new TextDecoder().decode(body)) as { access_token?: string; expires_in?: number; email?: string; role?: string };
      if (!payload.access_token) return NextResponse.json({ error: 'Login response did not include a session' }, { status: 502 });
      response = NextResponse.json({ email: payload.email, role: payload.role }, { status: upstream.status });
      response.headers.set('cache-control', 'no-store');
      response.cookies.set(TOKEN_COOKIE, payload.access_token, {
        httpOnly: true, secure: true, sameSite: 'lax', path: '/',
        maxAge: Math.min(Math.max(payload.expires_in ?? 3600, 60), 3600),
      });
      return response;
    } catch {
      return NextResponse.json({ error: 'Invalid login response' }, { status: 502 });
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
