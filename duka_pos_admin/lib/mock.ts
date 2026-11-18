// Lightweight mock backend for the admin panel so it runs standalone.
// Returns canned data for /api/admin/* endpoints when the real backend is unavailable.

const tenants = [
  { id: 't1', shopName: 'Mama Njeri Kiosk', admin: 'Njeri W.', _count: { profiles: 3, sales: 124 }, settings: { mpesa: true, etims: false, payhero: true } },
  { id: 't2', shopName: 'Otieno General Store', admin: 'Otieno O.', _count: { profiles: 5, sales: 312 }, settings: { mpesa: true, etims: true, payhero: true } },
  { id: 't3', shopName: 'Aisha Cosmetics', admin: 'Aisha M.', _count: { profiles: 2, sales: 89 }, settings: { mpesa: false, etims: false, payhero: false } },
];

let subscriptions: any[] = [
  { tenantId: 't1', status: 'active', priceMinor: 250000, currency: 'KES', billingInterval: 'monthly', currentPeriodEnd: new Date(Date.now() + 20 * 86400000).toISOString(), tenant: tenants[0] },
  { tenantId: 't2', status: 'trial', priceMinor: null, currency: 'KES', billingInterval: 'monthly', currentPeriodEnd: null, tenant: tenants[1] },
];

let auditLogs: any[] = [];
let expenses: any[] = [
  { id: 'e1', category: 'Hosting', description: 'Cloudflare Workers + Pages', amount: 420000, date: new Date().toISOString() },
  { id: 'e2', category: 'Database', description: 'Neon Postgres', amount: 210000, date: new Date().toISOString() },
];
let vouchers: any[] = [
  { id: 'v1', codePrefix: 'DUKA-', tenantId: 't1', issuedToEmail: 'njeri@example.com', expiresAt: new Date(Date.now() + 30 * 86400000).toISOString(), redeemedAt: null, revokedAt: null, pausedAt: null, deletedAt: null, autoIssued: true },
];

let provider = { channelType: 'till', shortCode: '123456', accountNumber: '' };
let announcement: any = null;

function code() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = 'DUKA-';
  for (let i = 0; i < 10; i++) out += chars[Math.floor(Math.random() * chars.length)];
  return out;
}

export function mockFor(path: string, method: string, body?: any): any {
  const p = path.split('?')[0];

  if (p === '/api/admin/tenants') {
    return { tenants };
  }
  if (p === '/api/admin/dashboard') {
    return { tenants: tenants.length, activeUsers: 10, sales: { total: 1845000, count: 525, profit: 312000 }, churnByRisk: { none: 2, low: 1, medium: 0, high: 0 } };
  }
  if (p === '/api/admin/churn') {
    return { snapshots: tenants.map((t, i) => ({ tenant: t, tenantId: t.id, computedAt: new Date(Date.now() - i * 86400000).toISOString(), streakDays: i * 3, daysSinceLastActive: i * 2, totalSessions: 12 - i * 3, risk: i === 0 ? 'none' : i === 1 ? 'low' : 'medium', score: 0.1 + i * 0.2, dropReason: i === 0 ? 'Active' : i === 1 ? 'No sales in 7 days' : 'Low session count + no restock' })) };
  }
  if (p === '/api/admin/sales') {
    return { sales: [] };
  }
  if (p === '/api/admin/sessions') {
    return { sessions: [] };
  }
  if (p === '/api/admin/support-tickets') {
    return { tickets: [] };
  }
  if (p === '/api/admin/laybys') {
    return { laybys: [] };
  }
  if (p === '/api/admin/exchanges') {
    return { exchanges: [] };
  }
  if (p === '/api/admin/audit') {
    return { logs: auditLogs };
  }
  if (p === '/api/admin/diagnostics') {
    return { diagnostics: [] };
  }
  if (p === '/api/admin/tax-rules') {
    return { rules: [] };
  }
  if (p === '/api/admin/tax-entities') {
    return { entities: [] };
  }
  if (p === '/api/admin/tax-compliance') {
    return { vat_returns: [], tot_returns: [] };
  }
  if (p === '/api/admin/commercial/policy') {
    return { policy: { policyId: 'cp-1', version: '1.0', status: 'draft', collectionEnabled: false, purpose: 'Aggregate commercial insights.', disclosure: 'No PII.', allowlist: ['categoryFamily', 'transactionCount'], prohibited: ['tenantId', 'email'] } };
  }
  if (p === '/api/admin/commercial/ledger') {
    return { policy: { collectionEnabled: false }, contributions: [] };
  }
  if (p === '/api/admin/commercial/aggregate-preview') {
    return { aggregates: [] };
  }
  if (p === '/api/admin/commercial/quality') {
    return { report: { sourceRowCount: 0, eligibleRowCount: 0, excludedRowCount: 0, duplicateRowCount: 0, currencies: [], mixedCurrency: false, coverage: { complete: 0, partial: 0, unknown: 0, completeRatio: 1 }, qualityFlagCounts: {}, freshness: { latestPeriodEndUtc: null, ageDays: null, status: 'n/a', thresholdDays: 30 }, suppression: { cohortCount: 0, suppressedCohortCount: 0, publishableCohortCount: 0 }, reproducibilityFingerprint: 'mock', qualityNotes: [] }, definitions: {} };
  }

  // billing
  if (p === '/api/admin/billing/subscriptions') {
    return { subscriptions };
  }
  if (p.startsWith('/api/admin/billing/subscriptions/')) {
    if (method === 'PATCH' && body) {
      const tid = decodeURIComponent(p.split('/').pop() || '');
      const idx = subscriptions.findIndex((s) => s.tenantId === tid);
      const t = tenants.find((x) => x.id === tid);
      const updated = { tenantId: tid, status: body.status ?? 'active', priceMinor: body.priceMinor ?? null, currency: body.currency ?? 'KES', billingInterval: body.billingInterval ?? 'monthly', currentPeriodEnd: body.currentPeriodEnd ?? null, tenant: t };
      if (idx >= 0) subscriptions[idx] = updated; else subscriptions.push(updated);
      return { ok: true };
    }
    return { ok: true };
  }
  if (p === '/api/admin/billing/vouchers') {
    if (method === 'POST') {
      const v = { id: 'v' + (vouchers.length + 1), codePrefix: code(), tenantId: body?.tenantId ?? null, issuedToEmail: null, expiresAt: body?.durationMonths ? new Date(Date.now() + body.durationMonths * 30 * 86400000).toISOString() : null, redeemedAt: null, revokedAt: null, pausedAt: null, deletedAt: null, autoIssued: false };
      vouchers.push(v);
      return { voucher: { code: v.codePrefix + 'FULLCODE', ...v } };
    }
    return { vouchers };
  }
  const vMatch = p.match(/^\/api\/admin\/billing\/vouchers\/([^/]+)\/(pause|resume|revoke|delete)$/);
  if (vMatch) {
    const id = decodeURIComponent(vMatch[1]);
    const action = vMatch[2];
    const v = vouchers.find((x: any) => x.id === id);
    if (v) {
      if (action === 'pause') v.pausedAt = new Date().toISOString();
      if (action === 'resume') v.pausedAt = null;
      if (action === 'revoke') v.revokedAt = new Date().toISOString();
      if (action === 'delete') v.deletedAt = new Date().toISOString();
    }
    auditLogs.unshift({ adminId: 'admin', action: `${action}_access_voucher`, targetType: 'access_voucher', targetId: id, tenantId: v?.tenantId ?? null, at: new Date().toISOString() });
    return { ok: true };
  }
  if (p === '/api/admin/billing/provider') {
    if (method === 'PATCH' && body) {
      if (body.channelType) provider.channelType = body.channelType;
      if (body.shortCode) provider.shortCode = body.shortCode;
      if (body.accountNumber !== undefined) provider.accountNumber = body.accountNumber;
      return { ok: true };
    }
    return { provider };
  }

  // announcement
  if (p === '/api/admin/announcement') {
    if (method === 'GET') return { announcement };
    if (method === 'POST' && body) {
      announcement = { id: 'ann-' + Date.now(), title: body.title, body: body.body, active: body.active ?? true };
      return { id: announcement.id, title: announcement.title, body: announcement.body, active: announcement.active };
    }
    if (method === 'DELETE') { announcement = null; return { ok: true }; }
  }
  if (p === '/api/admin/products') {
    return { products: aggProducts, total: aggProducts.length };
  }
  if (p === '/api/admin/financials') {
    return financials;
  }
  if (p === '/api/system/analytics') {
    return { tenants: 3, activeUsers: 10, activeProducts: 42, salesCount: 525, totalSales: 1845000, totalProfit: 312000, byTenant: { t1: { salesCount: 124, totalSales: 720000, totalProfit: 120000, byPaymentMethod: { cash: 400000, mpesa: 320000 } }, t2: { salesCount: 312, totalSales: 885000, totalProfit: 140000, byPaymentMethod: { cash: 500000, mpesa: 385000 } }, t3: { salesCount: 89, totalSales: 240000, totalProfit: 52000, byPaymentMethod: { cash: 240000 } } } };
  }
  if (p === '/api/system/users') {
    return { users: [{ id: 'u1', name: 'Njeri W.', role: 'admin', createdAt: new Date().toISOString(), tenant: { id: 't1', shopName: 'Mama Njeri Kiosk' } }] };
  }
  if (p === '/api/system/access') {
    return { systemAdmin: true };
  }
  const tMatch = p.match(/^\/api\/admin\/tenants\/([^/]+)\/(deactivate|delete|activate)$/);
  if (tMatch) {
    const id = decodeURIComponent(tMatch[1]);
    const action = tMatch[2];
    auditLogs.unshift({ adminId: 'admin', action: `${action}_tenant`, targetType: 'tenant', targetId: id, tenantId: id, at: new Date().toISOString() });
    return { ok: true };
  }
  const uMatch = p.match(/^\/api\/admin\/users\/([^/]+)\/(deactivate|delete|activate)$/);
  if (uMatch) {
    const id = decodeURIComponent(uMatch[1]);
    const action = uMatch[2];
    auditLogs.unshift({ adminId: 'admin', action: `${action}_user`, targetType: 'user', targetId: id, tenantId: null, at: new Date().toISOString() });
    return { ok: true };
  }
  if (p === '/api/admin/audit' && method === 'POST' && body) {
    auditLogs.unshift({ adminId: body.adminId ?? 'admin', action: body.action, targetType: body.targetType, targetId: body.targetId, tenantId: body.tenantId ?? null, at: new Date().toISOString() });
    return { ok: true };
  }
  if (p === '/api/admin/expenses') {
    if (method === 'GET') return { items: expenses };
    if (method === 'POST' && body) {
      const item = { id: 'e' + (expenses.length + 1), category: body.category, description: body.description, amount: body.amount, date: new Date().toISOString() };
      expenses.push(item);
      auditLogs.unshift({ adminId: 'admin', action: 'add_expense', targetType: 'expense', targetId: item.id, tenantId: null, at: new Date().toISOString() });
      return { ok: true };
    }
  }
  if (p === '/api/admin/retention/run') {
    auditLogs.unshift({ adminId: 'admin', action: 'run_retention', targetType: 'retention', targetId: null, tenantId: null, at: new Date().toISOString() });
    return { ok: true, expired: 0 };
  }
  return null;
}

// aggregated products (mock)
const aggProducts = [
  { key: 'Coca-Cola 500ml', name: 'Coca-Cola 500ml', category: 'Beverages', shops: 3, minPrice: 6000, maxPrice: 7500, totalStock: 124 },
  { key: 'Unga 2kg', name: 'Unga 2kg', category: 'Groceries', shops: 2, minPrice: 18000, maxPrice: 19500, totalStock: 48 },
  { key: 'Blue Band 500g', name: 'Blue Band 500g', category: 'Groceries', shops: 4, minPrice: 22000, maxPrice: 25000, totalStock: 60 },
];

const financials = (() => {
  const activeSubs = subscriptions.filter((s: any) => s.status === 'active');
  const revenue = activeSubs.reduce((a: number, s: any) => a + (s.priceMinor ?? 0), 0);
  const revenueByTenant = activeSubs.map((s: any) => ({ name: s.tenant?.shopName ?? s.tenantId, value: s.priceMinor ?? 0 }));
  const expenses = 1230000;
  const expensesByCategory = [
    { name: 'Hosting', value: 420000 },
    { name: 'Database', value: 210000 },
    { name: 'SMS / comms', value: 180000 },
    { name: 'Payment gateway', value: 240000 },
    { name: 'Support', value: 180000 },
  ];
  const payments = [
    { method: 'M-Pesa', value: Math.round(revenue * 0.66) },
    { method: 'Voucher', value: Math.round(revenue * 0.2) },
    { method: 'Manual', value: Math.round(revenue * 0.14) },
  ];
  return {
    revenue,
    expenses,
    net: revenue - expenses,
    cac: 320000,
    ltv: 1850000,
    arpu: Math.round(revenue / Math.max(activeSubs.length, 1)),
    churnRate: 4.2,
    paybackMonths: 3.1,
    activeCustomers: activeSubs.length,
    newCustomers: 5,
    revenueByTenant,
    expensesByCategory,
    payments,
    expenseItems: [
      { id: 'e1', category: 'Hosting', description: 'Cloudflare Workers + Pages', amount: 420000, date: '2026-11-01' },
      { id: 'e2', category: 'Database', description: 'Neon Postgres', amount: 210000, date: '2026-11-01' },
      { id: 'e3', category: 'SMS / comms', description: "Africa's Talking", amount: 180000, date: '2026-11-05' },
      { id: 'e4', category: 'Payment gateway', description: 'PayHero fees', amount: 240000, date: '2026-11-10' },
      { id: 'e5', category: 'Support', description: 'Helpdesk tooling', amount: 180000, date: '2026-11-12' },
    ],
  };
})();
