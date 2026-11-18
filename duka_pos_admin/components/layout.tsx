'use client';

import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { removeToken } from '@/lib/auth';
import { Nav, ICONS } from './nav';
import { ThemeToggle } from './theme-toggle';

const NAV_ITEMS: import('./nav').NavItem[] = [
  { href: '/dashboard', label: 'Dashboard', icon: 'dashboard' },
  { href: '/churn', label: 'Churn', icon: 'churn' },
  { href: '/sales', label: 'Sales', icon: 'sales' },
  { href: '/sessions', label: 'Sessions', icon: 'sessions' },
  { href: '/tenants', label: 'Tenants', icon: 'tenants' },
  { href: '/users', label: 'Verified users', icon: 'sessions' },
  { href: '/products', label: 'Products (all shops)', icon: 'sales' },
  { href: '/billing', label: 'Billing & access', icon: 'billing' },
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

const MOBILE_PRIMARY = ['/dashboard', '/tenants', '/products', '/billing'];

export function ShellLayout({ children }: { children: React.ReactNode }) {
  const [moreOpen, setMoreOpen] = useState(false);
  const pathname = usePathname();
  const router = useRouter();

  const handleSignOut = () => {
    removeToken();
    router.push('/login');
  };

  useEffect(() => {
    setMoreOpen(false);
  }, [pathname]);

  const primaryItems = NAV_ITEMS.filter((i) => MOBILE_PRIMARY.includes(i.href));
  const moreItems = NAV_ITEMS.filter((i) => !MOBILE_PRIMARY.includes(i.href));

  return (
    <div className="min-h-screen bg-base-50 text-base-900">
      {/* Top bar */}
      <header className="sticky top-0 z-40 bg-white/80 backdrop-blur-xl border-b border-base-200">
        <div className="flex items-center justify-between h-14 px-4 md:px-6 gap-4">
          <div className="flex items-center gap-2 shrink-0">
            <span className="rounded-lg bg-accent-600 p-1">
              <svg className="w-5 h-5 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <rect width="18" height="18" x="3" y="3" rx="2" ry="2"/>
                <line x1="3" y1="9" x2="21" y2="9"/>
                <line x1="9" y1="21" x2="9" y2="9"/>
              </svg>
            </span>
            <span className="font-semibold tracking-tight text-base-900 hidden sm:inline">SimplerAnalytics</span>
          </div>
          {/* Desktop horizontal nav (scrollable) */}
          <nav className="hidden md:flex items-center gap-0.5 flex-1 min-w-0 overflow-x-auto scrollbar-thin">
            <Nav items={NAV_ITEMS} pathname={pathname} horizontal />
          </nav>
          <ThemeToggle />
          <button
            onClick={handleSignOut}
            className="shrink-0 rounded-md px-3 py-1.5 text-sm text-base-600 hover:bg-base-100 focus:outline-none focus:ring-2 focus:ring-base-900"
            aria-label="Sign out"
          >
            Sign out
          </button>
        </div>
      </header>

      {/* Mobile bottom bar */}
      <nav className="md:hidden fixed bottom-0 inset-x-0 z-40 bg-white/90 backdrop-blur-xl border-t border-base-200 safe-bottom">
        <ul className="flex items-stretch justify-around">
          {primaryItems.map((item) => {
            const active = pathname === item.href;
            return (
              <li key={item.href} className="flex-1">
                <a
                  href={item.href}
                  className={`flex flex-col items-center justify-center py-2 text-[10px] font-medium ${active ? 'text-accent-700' : 'text-base-500'}`}
                >
                  <span className="mb-0.5 w-5 h-5">{ICONS[item.icon]}</span>
                  {item.label.split(' ')[0]}
                </a>
              </li>
            );
          })}
          <li className="flex-1">
            <button
              onClick={() => setMoreOpen(true)}
              className="w-full flex flex-col items-center justify-center py-2 text-[11px] font-medium text-base-500"
            >
              More
            </button>
          </li>
        </ul>
      </nav>

      {/* More sheet */}
      {moreOpen && (
        <div className="md:hidden fixed inset-0 z-50">
          <div className="absolute inset-0 bg-base-900/40" onClick={() => setMoreOpen(false)} />
          <div className="absolute bottom-0 inset-x-0 bg-white rounded-t-2xl p-4 max-h-[70vh] overflow-y-auto">
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-semibold">More</h3>
              <button onClick={() => setMoreOpen(false)} className="text-base-500">✕</button>
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
