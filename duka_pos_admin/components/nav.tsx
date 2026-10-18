'use client';

import Link from 'next/link';

export type NavItem = {
  href: string;
  label: string;
  icon: 'dashboard' | 'churn' | 'sales' | 'sessions' | 'tenants' | 'support' | 'audit';
};

const ICONS: Record<string, React.ReactNode> = {
  dashboard: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="3" width="7" height="7" rx="1" ry="1"/>
      <rect x="14" y="3" width="7" height="7" rx="1" ry="1"/>
      <rect x="14" y="14" width="7" height="7" rx="1" ry="1"/>
      <rect x="3" y="14" width="7" height="7" rx="1" ry="1"/>
    </svg>
  ),
  churn: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/>
    </svg>
  ),
  sales: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <line x1="12" y1="1" x2="12" y2="23"/>
      <path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>
    </svg>
  ),
  sessions: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="7" width="20" height="14" rx="2" ry="2"/>
      <line x1="16" y1="21" x2="16" y2="21"/>
      <line x1="12" y1="11" x2="12" y2="11"/>
      <line x1="8" y1="11" x2="8" y2="11"/>
    </svg>
  ),
  tenants: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
      <circle cx="9" cy="7" r="4"/>
      <path d="M23 21v-2a4 4 0 0 0-3-3.87"/>
      <path d="M16 3.13a4 4 0 0 1 0 7.75"/>
    </svg>
  ),
  support: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 10c0 6-8 12-8 12s-8-6-8-12"/>
      <line x1="12" y1="20" x2="12" y2="20"/>
    </svg>
  ),
  audit: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="10"/>
      <line x1="12" y1="8" x2="12" y2="12"/>
      <line x1="12" y1="16" x2="12.01" y2="16"/>
    </svg>
  ),
};

export function Nav({ items, pathname }: { items: NavItem[]; pathname: string }) {
  return (
    <ul className="space-y-0.5">
      {items.map((item) => {
        const active = pathname === item.href || (item.href !== '/' && pathname.startsWith(item.href + '/'));
        const Icon = ICONS[item.icon];
        return (
          <li key={item.href}>
            <Link
              href={item.href}
              className={`flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors active:scale-95 ${
                active
                  ? 'bg-accent-50 text-accent-700 border-r-2 border-accent-600'
                  : 'text-base-600 hover:bg-base-100 hover:text-base-900'
              }`}
              aria-current={active ? 'page' : undefined}
            >
              <span className="shrink-0">{Icon}</span>
              {item.label}
            </Link>
          </li>
        );
      })}
    </ul>
  );
}
