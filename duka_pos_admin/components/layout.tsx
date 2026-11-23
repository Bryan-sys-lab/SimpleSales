'use client';

import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { removeToken } from '@/lib/auth';
import { BrandLockup } from './brand';
import { Nav, ICONS } from './nav';
import { ThemeToggle } from './theme-toggle';

const NAV_ITEMS: import('./nav').NavItem[] = [
  { href: '/dashboard', label: 'Dashboard', icon: 'dashboard' },
  { href: '/churn', label: 'Churn', icon: 'churn' },
  { href: '/sales', label: 'Sales', icon: 'sales' },
  { href: '/sessions', label: 'Sessions', icon: 'sessions' },
  { href: '/tenants', label: 'Tenants', icon: 'tenants' },
  { href: '/users', label: 'Shop users', icon: 'sessions' },
  { href: '/admins', label: 'Admin access', icon: 'audit' },
  { href: '/tasks', label: 'Team tasks', icon: 'support' },
  { href: '/products', label: 'Products (all shops)', icon: 'sales' },
  { href: '/billing', label: 'Billing & access', icon: 'billing' },
  { href: '/membership', label: 'Membership requests', icon: 'commercial-ledger' },
  { href: '/financials', label: 'Revenue & costs', icon: 'dashboard' },
  { href: '/expenses', label: 'Expenses settings', icon: 'commercial-quality' },
  { href: '/commercial-policy', label: 'Commercial policy', icon: 'commercial-policy' },
  { href: '/commercial-ledger', label: 'Contribution ledger', icon: 'commercial-ledger' },
  { href: '/commercial-quality', label: 'Data quality', icon: 'commercial-quality' },
  { href: '/support', label: 'Support', icon: 'support' },
  { href: '/audit', label: 'Audit log', icon: 'audit' },
  { href: '/diagnostics', label: 'Device diagnostics', icon: 'diagnostics' },
  { href: '/announcements', label: 'Announcements', icon: 'support' },
];

const MOBILE_PRIMARY = ['/dashboard', '/tenants', '/admins', '/tasks'];
const NAV_SCOPE: Record<string, string> = {
  '/dashboard':'analytics:read','/churn':'analytics:read','/sales':'analytics:read','/sessions':'sessions:read',
  '/tenants':'tenants:read','/users':'users:read','/admins':'keys:read','/tasks':'tasks:read','/products':'analytics:read',
  '/billing':'configuration:read','/financials':'analytics:read','/expenses':'analytics:read',
  '/membership':'membership:read',
  '/commercial-policy':'commercial:read','/commercial-ledger':'commercial:read','/commercial-quality':'commercial:read',
  '/support':'support:read','/audit':'audit:read','/diagnostics':'diagnostics:read','/announcements':'configuration:read',
};
type AdminAccess = { email: string; role: string; department: string; permissions: string[]; canRecruit: boolean; canMintKeys: boolean; canAssignTasks: boolean };
export function useAdminAccess() {
  const [access, setAccess] = useState<AdminAccess | null>(null);
  useEffect(() => {
    let active = true;
    fetch('/api/admin/auth/session', { credentials: 'same-origin', cache: 'no-store' })
      .then(response => response.ok ? response.json() as Promise<AdminAccess> : Promise.reject(new Error('Access unavailable')))
      .then(info => { if (active) setAccess(info); })
      .catch(() => undefined);
    return () => { active = false; };
  }, []);
  const can = (permission: string) => access?.role === 'super_admin' || Boolean(access?.permissions.includes(permission));
  return { access, can };
}

export function ShellLayout({ children }: { children: React.ReactNode }) {
  const [moreOpen, setMoreOpen] = useState(false);
  const [access, setAccess] = useState<AdminAccess | null>(null);
  const pathname = usePathname();
  const router = useRouter();

  useEffect(() => {
    let active = true;
    fetch('/api/admin/auth/session', { credentials: 'same-origin', cache: 'no-store' }).then(async response => {
      if (!response.ok) throw new Error('Session expired');
      const info = await response.json() as AdminAccess;
      if (active) setAccess(info);
    }).catch(() => { if (active) router.replace('/login'); });
    return () => { active = false; };
  }, [router]);

  useEffect(() => {
    if (!access) return;
    const refreshInterval = 30 * 60 * 1000;
    let lastRefreshAt = Date.now();
    let refreshing = false;

    const refreshSession = async () => {
      if (document.visibilityState !== 'visible' || refreshing) return;
      refreshing = true;
      try {
        const response = await fetch('/api/admin/auth/refresh', {
          method: 'POST',
          credentials: 'same-origin',
          cache: 'no-store',
        });
        if (response.status === 401) {
          router.replace('/login');
          return;
        }
        if (!response.ok) throw new Error(`Session refresh failed (${response.status})`);
        lastRefreshAt = Date.now();
      } catch (cause) {
        console.error('Could not refresh the active admin session:', cause);
      } finally {
        refreshing = false;
      }
    };

    const interval = window.setInterval(() => {
      if (Date.now() - lastRefreshAt >= refreshInterval) void refreshSession();
    }, 60 * 1000);
    const refreshOnReturn = () => {
      if (
        document.visibilityState === 'visible' &&
        Date.now() - lastRefreshAt >= refreshInterval
      ) {
        void refreshSession();
      }
    };
    document.addEventListener('visibilitychange', refreshOnReturn);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener('visibilitychange', refreshOnReturn);
    };
  }, [access, router]);

  const can = (permission: string) => access?.role === 'super_admin' || Boolean(access?.permissions.includes(permission));
  const visibleItems = access ? NAV_ITEMS.filter(item => access.role === 'super_admin' || can(NAV_SCOPE[item.href])) : [];

  const handleSignOut = async () => {
    await removeToken();
    router.push('/login');
  };

  useEffect(() => {
    setMoreOpen(false);
  }, [pathname]);

  useEffect(() => {
    if (!moreOpen) return;
    const closeOnEscape = (event: KeyboardEvent) => { if (event.key === 'Escape') setMoreOpen(false); };
    window.addEventListener('keydown', closeOnEscape);
    return () => window.removeEventListener('keydown', closeOnEscape);
  }, [moreOpen]);

  const primaryItems = visibleItems.filter((i) => MOBILE_PRIMARY.includes(i.href));
  const moreItems = visibleItems.filter((i) => !MOBILE_PRIMARY.includes(i.href));

  useEffect(() => {
    if (!access || !pathname || access.role === 'super_admin') return;
    const required = NAV_SCOPE[pathname] ?? (pathname.startsWith('/tenants/') ? 'tenants:read' : undefined);
    if (required && !access.permissions.includes(required)) {
      const fallback = NAV_ITEMS.find((item) => access.permissions.includes(NAV_SCOPE[item.href]));
      router.replace(fallback?.href ?? '/login');
    }
  }, [access, pathname, router]);

  return (
    <div className="min-h-screen bg-base-50 text-base-900 dark:bg-base-950 dark:text-base-100">
      {/* Top bar */}
      <header className="sticky top-0 z-40 bg-white/80 backdrop-blur-xl border-b border-base-200 dark:bg-base-900/80 dark:border-base-700">
        <div className="flex items-center justify-between h-14 px-4 md:px-6 gap-4">
          <BrandLockup compact className="shrink-0" />
          {/* Desktop horizontal nav (scrollable) */}
          <nav className="hidden md:flex items-center gap-0.5 flex-1 min-w-0 overflow-x-auto scrollbar-thin">
            <Nav items={visibleItems} pathname={pathname} horizontal />
          </nav>
          <ThemeToggle />
          <button
            onClick={handleSignOut}
            className="shrink-0 rounded-md px-3 py-1.5 text-sm text-base-600 hover:bg-base-100 focus:outline-none focus:ring-2 focus:ring-base-900 dark:text-base-300 dark:hover:bg-base-800 dark:focus:ring-electric-400"
            aria-label="Sign out"
          >
            Sign out
          </button>
        </div>
      </header>

      {/* Mobile bottom bar */}
      <nav className="md:hidden fixed bottom-0 inset-x-0 z-40 bg-white/90 backdrop-blur-xl border-t border-base-200 safe-bottom dark:bg-base-900/90 dark:border-base-700">
        <ul className="flex items-stretch justify-around">
          {primaryItems.map((item) => {
            const active = pathname === item.href;
            const mobileLabel: Record<string, string> = { '/dashboard': 'Home', '/tenants': 'Shops', '/admins': 'Admins', '/tasks': 'Tasks' };
            return (
              <li key={item.href} className="flex-1">
                <a
                  href={item.href}
                  className={`flex flex-col items-center justify-center py-2 text-[10px] font-medium ${active ? 'text-accent-700' : 'text-base-500'}`}
                >
                  <span className="mb-0.5 w-5 h-5">{ICONS[item.icon]}</span>
                  {mobileLabel[item.href] ?? item.label.split(' ')[0]}
                </a>
              </li>
            );
          })}
          {moreItems.length > 0 && <li className="flex-1">
            <button
              onClick={() => setMoreOpen(true)}
              aria-haspopup="dialog"
              aria-expanded={moreOpen}
              className="w-full flex flex-col items-center justify-center py-2 text-[11px] font-medium text-base-500"
            >
              More
            </button>
          </li>}
        </ul>
      </nav>

      {/* More sheet */}
      {moreOpen && (
        <div className="md:hidden fixed inset-0 z-50">
          <button className="absolute inset-0 bg-base-900/40" onClick={() => setMoreOpen(false)} aria-label="Close navigation" />
          <div role="dialog" aria-modal="true" aria-labelledby="more-navigation-title" className="absolute bottom-0 inset-x-0 bg-white rounded-t-2xl p-4 pb-8 max-h-[80vh] overflow-y-auto dark:bg-base-900">
            <div className="flex items-center justify-between mb-3">
              <h3 id="more-navigation-title" className="font-semibold">More sections</h3>
              <button onClick={() => setMoreOpen(false)} className="min-h-11 min-w-11 rounded-md text-base-600 hover:bg-base-100 dark:text-base-300 dark:hover:bg-base-800" aria-label="Close navigation">✕</button>
            </div>
            <Nav items={moreItems} pathname={pathname} />
          </div>
        </div>
      )}

      <main className="p-4 md:p-6 lg:p-8 pb-20 md:pb-8">
        {children}
      </main>
    </div>
  );
}

export default ShellLayout;
