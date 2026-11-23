const RESOURCE_PERMISSIONS: Record<string, string> = {
  admins: 'keys:read',
  announcements: 'configuration:read',
  audit: 'audit:read',
  billing: 'configuration:read',
  churn: 'analytics:read',
  'commercial-ledger': 'commercial:read',
  diagnostics: 'diagnostics:read',
  expenses: 'analytics:read',
  exchanges: 'analytics:read',
  financials: 'analytics:read',
  'membership': 'membership:read',
  products: 'analytics:read',
  sales: 'analytics:read',
  sessions: 'sessions:read',
  support: 'support:read',
  'tax-compliance': 'analytics:read',
  'tax-rules': 'configuration:read',
  tasks: 'tasks:read',
  telemetry: 'sessions:read',
  tenants: 'tenants:read',
  users: 'users:read',
  'business-context': 'tenants:read',
  dashboard: 'analytics:read',
  laybys: 'analytics:read',
};

const ROUTES: Array<{ pattern: RegExp; resources: string[] }> = [
  { pattern: /^\/admin\/auth\/keys(?:\/|$)/, resources: ['admins'] },
  { pattern: /^\/admin\/announcement(?:\/|$)/, resources: ['announcements'] },
  { pattern: /^\/admin\/billing(?:\/|$)/, resources: ['billing', 'financials'] },
  { pattern: /^\/admin\/commercial(?:\/|$)/, resources: ['commercial-ledger', 'commercial-policy', 'commercial-quality'] },
  { pattern: /^\/admin\/diagnostics(?:\/|$)/, resources: ['diagnostics', 'dashboard'] },
  { pattern: /^\/admin\/membership(?:\/|$)|^\/tenant\/membership(?:\/|$)/, resources: ['membership'] },
  { pattern: /^\/admin\/org(?:\/|$)/, resources: ['tasks'] },
  { pattern: /^\/admin\/tax-(?:rules|entities)(?:\/|$)/, resources: ['tax-rules', 'tax-compliance'] },
  { pattern: /^\/admin\/tenants(?:\/|$)|^\/system\/tenants(?:\/|$)/, resources: ['tenants', 'business-context', 'dashboard'] },
  { pattern: /^\/admin\/users(?:\/|$)|^\/system\/users(?:\/|$)/, resources: ['users', 'tenants', 'dashboard'] },
  { pattern: /^\/admin\/sales(?:\/|$)|^\/sales(?:\/|$)|^\/reports(?:\/|$)/, resources: ['sales', 'financials', 'dashboard'] },
  { pattern: /^\/admin\/products(?:\/|$)|^\/products(?:\/|$)|^\/product-variants(?:\/|$)|^\/stock-movements(?:\/|$)|^\/reorder(?:\/|$)|^\/purchases(?:\/|$)|^\/shot-cups(?:\/|$)/, resources: ['products', 'sales', 'dashboard'] },
  { pattern: /^\/admin\/laybys(?:\/|$)|^\/laybys(?:\/|$)/, resources: ['laybys', 'sales', 'dashboard'] },
  { pattern: /^\/admin\/exchanges(?:\/|$)|^\/exchanges(?:\/|$)|^\/returns(?:\/|$)/, resources: ['exchanges', 'sales', 'dashboard'] },
  { pattern: /^\/admin\/expenses(?:\/|$)|^\/expenses(?:\/|$)|^\/cost-pools(?:\/|$)|^\/owner-transactions(?:\/|$)/, resources: ['expenses', 'financials', 'dashboard'] },
  { pattern: /^\/admin\/tax-compliance(?:\/|$)|^\/etims(?:\/|$)|^\/receipt-links(?:\/|$)/, resources: ['tax-compliance', 'tenants'] },
  { pattern: /^\/admin\/support(?:\/|$)|^\/telemetry\/support(?:\/|$)/, resources: ['support'] },
  { pattern: /^\/admin\/churn(?:\/|$)|^\/telemetry\/churn(?:\/|$)/, resources: ['churn', 'dashboard'] },
  { pattern: /^\/admin\/(?:audit|retention)(?:\/|$)/, resources: ['audit'] },
  { pattern: /^\/admin\/telemetry\/events(?:\/|$)|^\/telemetry\/events(?:\/|$)/, resources: ['telemetry', 'sessions', 'dashboard'] },
  { pattern: /^\/business-context(?:\/|$)|^\/tenant\/business-context(?:\/|$)/, resources: ['business-context', 'tenants'] },
  { pattern: /^\/profile(?:\/|$)/, resources: ['users', 'tenants'] },
  { pattern: /^\/evidence(?:\/|$)|^\/sale-evidence\/confirm$/, resources: ['sales'] },
  { pattern: /^\/tenant(?:\/|$)/, resources: ['tenants', 'users', 'dashboard'] },
  { pattern: /^\/payments?(?:\/|$)|^\/mpesa(?:\/|$)|^\/credit(?:\/|$)/, resources: ['billing', 'financials', 'sales', 'dashboard'] },
];

export type AdminLiveInvalidation = {
  resources: string[];
  requiredPermissions: string[];
};

export function adminLiveInvalidationFor(
  method: string,
  requestUrl: string,
): AdminLiveInvalidation | null {
  if (['GET', 'HEAD', 'OPTIONS'].includes(method.toUpperCase())) return null;

  const pathname = new URL(requestUrl, 'https://admin-live.internal').pathname
    .replace(/^\/api(?=\/)/, '')
    .replace(/\/+$/, '') || '/';
  if (
    pathname === '/admin/announcement' ||
    pathname === '/admin/diagnostics' ||
    pathname === '/telemetry/events'
  ) return null;
  const route = ROUTES.find((candidate) => candidate.pattern.test(pathname));
  if (!route) return null;

  const resources = new Set(route.resources);
  if (pathname.startsWith('/admin/')) resources.add('audit');
  const requiredPermissions = [...new Set(
    [...resources].map((resource) => RESOURCE_PERMISSIONS[resource]).filter(Boolean),
  )];
  if (requiredPermissions.length === 0) return null;
  return { resources: [...resources], requiredPermissions };
}
