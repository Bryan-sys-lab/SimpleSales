'use client';

import { usePathname, useRouter } from 'next/navigation';
import Link from 'next/link';
import { useCallback, useEffect, useRef, useState } from 'react';
import { removeToken } from '@/lib/auth';
import { BrandLockup } from './brand';
import { Nav, ICONS } from './nav';
import { ThemeToggle } from './theme-toggle';
import { showToast } from '@/lib/toast';

const NAV_ITEMS: import('./nav').NavItem[] = [
  { href: '/dashboard', label: 'Dashboard', icon: 'dashboard' },
  { href: '/churn', label: 'Churn', icon: 'churn' },
  { href: '/sales', label: 'Sales', icon: 'sales' },
  { href: '/sessions', label: 'Sessions', icon: 'sessions' },
  { href: '/telemetry', label: 'App telemetry', icon: 'sessions' },
  { href: '/diagnostics', label: 'Device diagnostics', icon: 'diagnostics' },
  { href: '/tenants', label: 'Tenants', icon: 'tenants' },
  { href: '/users', label: 'Shop users', icon: 'sessions' },
  { href: '/admins', label: 'Admin accounts & keys', icon: 'audit' },
  { href: '/tasks', label: 'Team tasks', icon: 'support' },
  { href: '/products', label: 'Products (all shops)', icon: 'sales' },
  { href: '/laybys', label: 'Lay-bys', icon: 'laybys' },
  { href: '/exchanges', label: 'Exchanges', icon: 'exchanges' },
  { href: '/billing', label: 'Billing & access', icon: 'billing' },
  { href: '/membership', label: 'Membership requests', icon: 'commercial-ledger' },
  { href: '/financials', label: 'Revenue & costs', icon: 'dashboard' },
  { href: '/expenses', label: 'Expenses settings', icon: 'commercial-quality' },
  { href: '/tax-rules', label: 'Tax rule registry', icon: 'tax-rules' },
  { href: '/tax-compliance', label: 'Tax compliance', icon: 'tax-compliance' },
  { href: '/commercial-policy', label: 'Commercial policy', icon: 'commercial-policy' },
  { href: '/data-intelligence', label: 'Data Intelligence', icon: 'commercial-quality' },
  { href: '/commercial-ledger', label: 'Contribution ledger', icon: 'commercial-ledger' },
  { href: '/commercial-quality', label: 'Data quality', icon: 'commercial-quality' },
  { href: '/support', label: 'Support', icon: 'support' },
  { href: '/audit', label: 'Audit log', icon: 'audit' },
  { href: '/announcements', label: 'Announcements', icon: 'support' },
];

const NAV_GROUPS: { label: string; hrefs: string[] }[] = [
  { label: 'Overview', hrefs: ['/dashboard', '/churn', '/sales'] },
  { label: 'Shops', hrefs: ['/tenants', '/users', '/products'] },
  { label: 'Operations', hrefs: ['/laybys', '/exchanges', '/sessions', '/telemetry', '/diagnostics'] },
  { label: 'People & access', hrefs: ['/admins', '/tasks', '/billing', '/membership'] },
  { label: 'Finance & tax', hrefs: ['/financials', '/expenses', '/tax-rules', '/tax-compliance'] },
  { label: 'Commercial insights', hrefs: ['/commercial-policy', '/data-intelligence', '/commercial-ledger', '/commercial-quality'] },
  { label: 'Support & governance', hrefs: ['/support', '/announcements', '/audit'] },
];

const MOBILE_PRIMARY = ['/dashboard', '/tenants', '/admins', '/tasks'];
const NAV_SCOPE: Record<string, string> = {
  '/dashboard':'analytics:read','/churn':'analytics:read','/sales':'analytics:read','/sessions':'sessions:read','/telemetry':'sessions:read',
  '/tenants':'tenants:read','/users':'users:read','/admins':'keys:read','/tasks':'tasks:read','/products':'analytics:read',
  '/laybys':'analytics:read','/exchanges':'analytics:read','/tax-compliance':'analytics:read','/tax-rules':'configuration:read',
  '/billing':'configuration:read','/financials':'analytics:read','/expenses':'analytics:read',
  '/membership':'membership:read',
  '/commercial-policy':'commercial:read','/commercial-ledger':'commercial:read','/commercial-quality':'commercial:read',
  '/data-intelligence':'commercial:read',
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
  const moreButtonRef = useRef<HTMLButtonElement>(null);
  const moreDialogRef = useRef<HTMLDialogElement>(null);
  const closeMoreNavigation = useCallback(() => {
    const dialog = moreDialogRef.current;
    if (dialog?.open) dialog.close();
    setMoreOpen(false);
  }, []);

  useEffect(() => {
    let active = true;
    fetch('/api/admin/auth/session', { credentials: 'same-origin', cache: 'no-store' }).then(async response => {
      if (!response.ok) throw new Error('Session expired');
      const info = await response.json() as AdminAccess;
      if (active) setAccess(info);
    }).catch(() => {
      if (active) {
        showToast('error', 'Your administrator session has expired. Please sign in again.');
        router.replace('/login');
      }
    });
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
          showToast('error', 'Your administrator session has expired. Please sign in again.');
          router.replace('/login');
          return;
        }
        if (!response.ok) throw new Error(`Session refresh failed (${response.status})`);
        lastRefreshAt = Date.now();
      } catch (cause) {
        console.error('Could not refresh the active admin session:', cause);
        showToast('error', 'Your administrator session could not be refreshed.');
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
    closeMoreNavigation();
  }, [closeMoreNavigation, pathname]);

  useEffect(() => {
    const dialog = moreDialogRef.current;
    if (!dialog) return;
    if (moreOpen && !dialog.open) dialog.showModal();
    else if (!moreOpen && dialog.open) dialog.close();
  }, [moreOpen]);

  useEffect(() => {
    if (!moreOpen) return;
    const closeOnWideScreen = () => {
      if (window.matchMedia('(min-width: 1024px)').matches) closeMoreNavigation();
    };
    window.addEventListener('resize', closeOnWideScreen);
    return () => window.removeEventListener('resize', closeOnWideScreen);
  }, [closeMoreNavigation, moreOpen]);

  const primaryItems = visibleItems.filter((i) => MOBILE_PRIMARY.includes(i.href));
  const moreItems = visibleItems.filter((i) => !MOBILE_PRIMARY.includes(i.href));
  const navigationGroups = NAV_GROUPS.map((group) => ({
    ...group,
    items: visibleItems.filter((item) => group.hrefs.includes(item.href)),
  })).filter((group) => group.items.length > 0);
  const moreIsActive = moreItems.some((item) => pathname === item.href || pathname.startsWith(`${item.href}/`));

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
      <a href="#main-content" className="skip-link">Skip to main content</a>
      <header className="safe-top sticky top-0 z-40 border-b border-base-200 bg-white/90 backdrop-blur-xl dark:border-base-700 dark:bg-base-900/90">
        <div className="flex min-h-16 items-center gap-2 px-3 sm:gap-3 sm:px-4 md:px-6 lg:pl-72">
          <Link href="/dashboard" aria-label="SimplerAnalytics home" className="shrink-0 rounded-md">
            <BrandLockup compact />
          </Link>
          <div className="ml-auto flex items-center gap-1 sm:gap-2">
            <ThemeToggle />
          <button
            onClick={handleSignOut}
            className="min-h-11 shrink-0 rounded-md px-2 text-sm font-medium text-base-700 hover:bg-base-100 focus:outline-none focus:ring-2 focus:ring-base-900 sm:px-3 dark:text-base-200 dark:hover:bg-base-800 dark:focus:ring-electric-400"
          >
            Sign out
          </button>
          </div>
        </div>
      </header>

      <aside className="fixed inset-y-16 left-0 z-30 hidden w-64 border-r border-base-200 bg-white dark:border-base-700 dark:bg-base-900 lg:flex lg:flex-col">
        <nav aria-label="Primary navigation" className="scrollbar-thin flex-1 space-y-5 overflow-y-auto p-4">
          {navigationGroups.map((group) => (
            <section key={group.label}>
              <h2 className="mb-2 px-3 text-xs font-semibold uppercase tracking-wide text-base-500">{group.label}</h2>
              <Nav items={group.items} pathname={pathname} />
            </section>
          ))}
        </nav>
      </aside>

      <nav aria-label="Primary navigation" className="safe-bottom fixed inset-x-0 bottom-0 z-40 border-t border-base-200 bg-white/95 backdrop-blur-xl dark:border-base-700 dark:bg-base-900/95 lg:hidden">
        <ul className="flex items-stretch justify-around">
          {primaryItems.map((item) => {
            const active = pathname === item.href;
            const mobileLabel: Record<string, string> = { '/dashboard': 'Home', '/tenants': 'Shops', '/admins': 'Admin keys', '/tasks': 'Tasks' };
            return (
              <li key={item.href} className="flex-1">
                <Link
                  href={item.href}
                  aria-current={active ? 'page' : undefined}
                  className={`flex min-h-16 flex-col items-center justify-center gap-1 border-t-2 px-1 text-xs font-medium ${active ? 'border-accent-700 bg-accent-50 text-accent-800 dark:bg-base-800 dark:text-electric-300' : 'border-transparent text-base-600 dark:text-base-300'}`}
                >
                  <span className="h-5 w-5" aria-hidden="true">{ICONS[item.icon]}</span>
                  {mobileLabel[item.href] ?? item.label.split(' ')[0]}
                </Link>
              </li>
            );
          })}
          {moreItems.length > 0 && <li className="flex-1">
            <button
              ref={moreButtonRef}
              type="button"
              onClick={() => setMoreOpen(true)}
              aria-haspopup="dialog"
              aria-controls="more-navigation"
              aria-expanded={moreOpen}
              className={`flex min-h-16 w-full flex-col items-center justify-center gap-1 border-t-2 px-1 text-xs font-medium ${moreIsActive ? 'border-accent-700 bg-accent-50 text-accent-800 dark:bg-base-800 dark:text-electric-300' : 'border-transparent text-base-600 dark:text-base-300'}`}
            >
              <span className="h-5 w-5" aria-hidden="true">•••</span>
              More
            </button>
          </li>}
        </ul>
      </nav>

      <dialog
        ref={moreDialogRef}
        id="more-navigation"
        aria-labelledby="more-navigation-title"
        className="mobile-navigation-dialog fixed inset-0 m-0 h-dvh max-h-none w-full max-w-none border-0 bg-transparent p-0 text-base-900 backdrop:bg-base-950/50 dark:text-base-100 lg:hidden"
        onClose={() => setMoreOpen(false)}
        onCancel={(event) => {
          event.preventDefault();
          closeMoreNavigation();
        }}
        onKeyDownCapture={(event) => {
          if (event.key === 'Escape') {
            event.preventDefault();
            closeMoreNavigation();
          }
        }}
        onClick={(event) => {
          if (event.target === event.currentTarget) closeMoreNavigation();
        }}
      >
        <div className="absolute inset-x-0 bottom-0 max-h-[85dvh] overflow-y-auto rounded-t-2xl bg-white p-4 pb-[calc(1rem+env(safe-area-inset-bottom))] shadow-2xl dark:bg-base-900">
          <div className="mb-3 flex items-center justify-between">
            <h2 id="more-navigation-title" className="text-lg font-semibold">More sections</h2>
            <button autoFocus type="button" onClick={closeMoreNavigation} className="min-h-11 min-w-11 rounded-md text-base-700 hover:bg-base-100 dark:text-base-200 dark:hover:bg-base-800">
              Close
            </button>
          </div>
          <nav aria-label="All sections" className="space-y-5">
            {navigationGroups.map((group) => {
              const items = group.items.filter((item) => !MOBILE_PRIMARY.includes(item.href));
              return items.length > 0 ? (
                <section key={group.label}>
                  <h3 className="mb-2 px-3 text-xs font-semibold uppercase tracking-wide text-base-500">{group.label}</h3>
                  <Nav items={items} pathname={pathname} />
                </section>
              ) : null;
            })}
          </nav>
        </div>
      </dialog>

      <main id="main-content" tabIndex={-1} className="mx-auto w-full max-w-[1600px] px-4 pb-24 pt-5 md:px-6 md:pb-24 md:pt-7 lg:ml-64 lg:w-[calc(100%-16rem)] lg:px-8 lg:pb-8">
        {children}
      </main>
    </div>
  );
}

export default ShellLayout;
