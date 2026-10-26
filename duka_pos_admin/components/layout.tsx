'use client';

import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { removeToken } from '@/lib/auth';
import { Nav } from './nav';

const NAV_ITEMS: import('./nav').NavItem[] = [
  { href: '/dashboard', label: 'Dashboard', icon: 'dashboard' },
  { href: '/churn', label: 'Churn', icon: 'churn' },
  { href: '/sales', label: 'Sales', icon: 'sales' },
  { href: '/laybys', label: 'Lay-bys', icon: 'laybys' },
  { href: '/exchanges', label: 'Exchanges', icon: 'exchanges' },
  { href: '/sessions', label: 'Sessions', icon: 'sessions' },
  { href: '/tenants', label: 'Tenants', icon: 'tenants' },
  { href: '/tax-rules', label: 'Tax rules', icon: 'tax-rules' },
  { href: '/tax-compliance', label: 'Tax compliance', icon: 'tax-compliance' },
  { href: '/commercial-policy', label: 'Commercial policy', icon: 'commercial-policy' },
  { href: '/commercial-ledger', label: 'Contribution ledger', icon: 'commercial-ledger' },
  { href: '/commercial-quality', label: 'Data quality', icon: 'commercial-quality' },
  { href: '/support', label: 'Support', icon: 'support' },
  { href: '/audit', label: 'Audit log', icon: 'audit' },
];

export function ShellLayout({ children }: { children: React.ReactNode }) {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const pathname = usePathname();
  const router = useRouter();

  const handleSignOut = () => {
    removeToken();
    router.push('/login');
  };

  useEffect(() => {
    setSidebarOpen(false);
  }, [pathname]);

  return (
    <div className="flex h-screen bg-base-50 text-base-900">
      <aside
        className={`sidebar transform transition-transform duration-300 ${sidebarOpen ? 'translate-x-0' : '-translate-x-full'} md:relative md:translate-x-0`}
        aria-label="Main navigation"
      >
        <div className="flex h-full flex-col">
          <div className="flex items-center gap-2 h-12 px-5 bg-base-100 border-b border-base-200 shrink-0">
            <span className="rounded-lg bg-accent-600 p-1">
              <svg className="w-5 h-5 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <rect width="18" height="18" x="3" y="3" rx="2" ry="2"/>
                <line x1="3" y1="9" x2="21" y2="9"/>
                <line x1="9" y1="21" x2="9" y2="9"/>
              </svg>
            </span>
            <span className="font-semibold tracking-tight">Duka Admin</span>
          </div>
          <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-1">
            <Nav items={NAV_ITEMS} pathname={pathname} />
          </nav>
          <div className="px-3 py-4 border-t border-base-200 shrink-0">
            <button
              onClick={handleSignOut}
              className="btn btn-ghost w-full text-left"
              aria-label="Sign out"
            >
              Sign out
            </button>
          </div>
        </div>
      </aside>

      {sidebarOpen && (
        <div
          className="fixed inset-0 z-20 bg-base-900/60 backdrop-blur-sm md:hidden"
          aria-hidden="true"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      <div className="flex flex-col flex-1 relative md:pl-64">
        <header className="topbar px-6 h-16 flex items-center justify-between shrink-0">
          <div className="flex items-center gap-3">
            <button
              onClick={() => setSidebarOpen((o) => !o)}
              className="rounded-md p-2 text-base-600 hover:bg-base-200 focus:outline-none focus:ring-2 focus:ring-base-900 md:hidden"
              aria-label="Open navigation"
            >
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <line x1="4" y1="6" x2="20" y2="6"/>
                <line x1="4" y1="12" x2="20" y2="12"/>
                <line x1="4" y1="18" x2="20" y2="18"/>
              </svg>
            </button>
            <h1 className="text-lg font-semibold tracking-tight">Dashboard</h1>
          </div>
          <div className="flex items-center gap-3">
            <span className="hidden md:block text-sm text-base-600">System Administrator</span>
            <button
              onClick={handleSignOut}
              className="hidden md:flex items-center gap-2 rounded-md px-3 py-1.5 text-sm text-base-600 hover:bg-base-200 focus:outline-none focus:ring-2 focus:ring-base-900"
              aria-label="Sign out"
            >
              <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/>
                <polyline points="16 17 21 12 16 7"/>
                <line x1="21" y1="21" x2="9" y2="21"/>
              </svg>
              Sign out
            </button>
          </div>
        </header>
        <main className="flex-1 overflow-y-auto p-6 md:p-8">{children}</main>
      </div>
    </div>
  );
}

export default ShellLayout;
