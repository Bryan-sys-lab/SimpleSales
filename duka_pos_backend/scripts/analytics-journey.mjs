import { randomUUID } from 'node:crypto';
import { addStagingAuthTestHeader } from './staging-auth-headers.mjs';

const baseUrl = (process.env.BASE_URL || 'http://localhost:3100').replace(/\/$/, '');

async function request(path, options = {}) {
  const headers = addStagingAuthTestHeader(baseUrl, path, {
    'content-type': 'application/json',
    ...(options.headers || {}),
  });
  return fetch(`${baseUrl}${path}`, {
    ...options,
    signal: AbortSignal.timeout(10_000),
    headers,
  });
}

const suffix = randomUUID().slice(0, 8);
const email = `ci-analytics-${suffix}@example.com`;
const password = '123456';
const shopName = `CI Analytics ${suffix}`;
const ownerName = 'CI Owner';
const link = await request('/api/auth/link', {
  method: 'POST',
  body: JSON.stringify({ email, password, shopName, ownerName }),
});
if (link.status !== 200) throw new Error(`auth/link returned ${link.status}`);
const challenge = await link.json();
if (!/^\d{6}$/.test(challenge.debug_code || '')) {
  throw new Error('auth/link did not return a test code; enable test-only verification debug codes');
}
if ('debug_first_voucher_code' in challenge) {
  throw new Error('auth/link must not generate a voucher before an administrator issues one');
}

const verified = await request('/api/auth/verify', {
  method: 'POST',
  body: JSON.stringify({
    email,
    password,
    code: challenge.debug_code,
    shopName,
    ownerName,
  }),
});
if (verified.status !== 200) throw new Error(`auth/verify returned ${verified.status}`);
const session = await verified.json();
if (session.voucher_redeemed !== false) {
  throw new Error('email verification must not auto-issue or redeem a voucher');
}
const headers = {
  authorization: `Bearer ${session.access_token}`,
  'x-tenant-id': session.tenant_id,
};
const productResponse = await request('/api/products/sync', {
  method: 'POST',
  headers,
  body: JSON.stringify({ products: [{
    id: 1,
    syncKey: `ci-till-${suffix}:1`,
    name: `CI Product ${suffix}`,
    category: 'Test',
    costPrice: 6,
    sellPrice: 10,
    stockQty: 10,
    openingStockQty: 10,
    reorderLevel: 1,
    bottleMl: 750,
    unit: 'each',
    mlPerKg: 0,
    active: true,
  }] }),
});
if (productResponse.status !== 200) throw new Error(`products/sync returned ${productResponse.status}`);
const productBody = await productResponse.json();
const productId = productBody.synced?.[0]?.remoteId;
if (typeof productId !== 'string' || productId.length === 0) throw new Error('product sync did not return an id');

const retryProductResponse = await request('/api/products/sync', {
  method: 'POST',
  headers,
  body: JSON.stringify({ products: [{
    id: 1,
    syncKey: `ci-till-${suffix}:1`,
    name: `CI Product ${suffix}`,
    category: 'Test',
    costPrice: 6,
    sellPrice: 10,
    stockQty: 10,
    openingStockQty: 10,
    reorderLevel: 1,
    bottleMl: 750,
    unit: 'each',
    mlPerKg: 0,
    active: true,
  }] }),
});
if (retryProductResponse.status !== 200) throw new Error(`retry products/sync returned ${retryProductResponse.status}`);
const retryProductBody = await retryProductResponse.json();
if (retryProductBody.synced?.[0]?.remoteId !== productId) {
  throw new Error('retried product sync created a second catalogue row');
}

const createdAt = new Date();
const saleResponse = await request('/api/sales/sync', {
  method: 'POST',
  headers,
  body: JSON.stringify({ sales: [{
    localId: 1,
    deviceId: `ci-till-${suffix}`,
    staffName: 'CI Owner',
    paymentMethod: 'cash',
    total: 1000,
    profit: 400,
    amountTendered: 1000,
    changeGiven: 0,
    createdAt: createdAt.toISOString(),
    items: [{ productId, productName: `CI Product ${suffix}`, qty: 1, unitPrice: 1000, unitCost: 600, portion: 'full', portionMl: 0 }],
  }] }),
});
if (saleResponse.status !== 200) throw new Error(`sales/sync returned ${saleResponse.status}`);
const saleBody = await saleResponse.json();
if (saleBody.synced?.[0]?.localId !== 1) {
  throw new Error('sales/sync did not confirm the expected sale');
}

const from = new Date(createdAt.getTime() - 60 * 60 * 1000).toISOString();
const to = new Date(createdAt.getTime() + 60 * 60 * 1000).toISOString();
const reportResponse = await request(`/api/reports/products?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}&productId=${encodeURIComponent(productId)}`, { headers });
if (reportResponse.status !== 200) throw new Error(`product report returned ${reportResponse.status}`);
const report = await reportResponse.json();
if (report.daily?.length !== 1 || report.staff?.length !== 1 || report.payments?.length !== 1) {
  throw new Error('product drill-down did not include daily, staff, and payment aggregates');
}
if (report.daily[0].net_sales !== 1000 || report.daily[0].gross_profit !== 400) {
  throw new Error('product drill-down totals are incorrect');
}

const catalogueResponse = await request(`/api/reports/products?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`, { headers });
if (catalogueResponse.status !== 200) throw new Error(`catalogue report returned ${catalogueResponse.status}`);
const catalogue = await catalogueResponse.json();
if (catalogue.costCoverage?.totalRevenueMinor !== 1000 || catalogue.costCoverage?.coveredRevenueMinor !== 1000) {
  throw new Error('full product report cost coverage is incorrect');
}

console.log(`Authenticated product analytics journey passed for tenant ${session.tenant_id}`);
