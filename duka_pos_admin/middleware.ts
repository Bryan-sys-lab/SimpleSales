import { NextResponse, NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  if (pathname === '/login' || pathname.startsWith('/login/')) return NextResponse.next();
  if (pathname.startsWith('/api/')) return NextResponse.next();
  if (!request.cookies.has('__Host-duka_admin_session')) {
    const login = new URL('/login', request.url);
    login.searchParams.set('returnTo', `${pathname}${search}`);
    return NextResponse.redirect(login);
  }
  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|manifest.webmanifest|icon.svg).*)'],
};
