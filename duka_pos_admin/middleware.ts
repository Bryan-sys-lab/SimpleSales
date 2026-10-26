import { NextResponse, NextRequest } from 'next/server';
import { getTokenExpiry } from '@/lib/auth';

const PROTECTED_PREFIXES = [
  '/dashboard',
  '/tenants',
  '/sales',
  '/audit',
  '/sessions',
  '/churn',
  '/support',
  '/commercial-policy',
  '/commercial-ledger',
  '/commercial-quality',
];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Login, callback, and static assets are always accessible.
  if (pathname === '/login' || pathname.startsWith('/login/callback') || pathname.startsWith('/_next')) {
    return NextResponse.next();
  }

  // Protected routes require a valid, unexpired token cookie.
  if (PROTECTED_PREFIXES.some((p) => pathname.startsWith(p))) {
    const token = request.cookies.get('duka_admin_token')?.value;
    if (!token) {
      const url = new URL('/login', request.url);
      url.searchParams.set('returnTo', pathname);
      return NextResponse.redirect(url);
    }
    const expiry = getTokenExpiry(token);
    if (expiry && expiry.getTime() <= Date.now()) {
      const response = NextResponse.redirect(new URL('/login?error=expired', request.url));
      response.cookies.delete('duka_admin_token');
      return response;
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/dashboard/:path*', '/tenants/:path*', '/sales/:path*', '/audit/:path*', '/sessions/:path*', '/churn/:path*', '/support/:path*', '/commercial-policy/:path*', '/commercial-ledger/:path*', '/commercial-quality/:path*'],
};
