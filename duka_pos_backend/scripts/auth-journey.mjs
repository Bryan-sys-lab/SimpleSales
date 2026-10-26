import { randomUUID } from 'node:crypto';

const baseUrl = (process.env.BASE_URL || 'http://localhost:3100').replace(/\/$/, '');
const code = process.env.AUTH_TEST_CODE;
if (!/^\d{6}$/.test(code || '')) {
  throw new Error('AUTH_TEST_CODE must be a six-digit non-production test value');
}

async function request(path, options = {}) {
  return fetch(`${baseUrl}${path}`, {
    ...options,
    signal: AbortSignal.timeout(10_000),
    headers: { 'content-type': 'application/json', ...(options.headers || {}) },
  });
}

const suffix = randomUUID().slice(0, 8);
const email = `ci-auth-${suffix}@example.com`;
const link = await request('/api/auth/link', {
  method: 'POST',
  body: JSON.stringify({
    email,
    pin: '1234',
    shopName: `CI Auth ${suffix}`,
    ownerName: 'CI Owner',
  }),
});
if (link.status !== 200) throw new Error(`auth/link returned ${link.status}`);

const secondLink = await request('/api/auth/link', {
  method: 'POST',
  body: JSON.stringify({
    email,
    pin: '1234',
    shopName: `CI Auth Other ${suffix}`,
    ownerName: 'CI Owner',
  }),
});
if (secondLink.status !== 200) {
  throw new Error(`second auth/link returned ${secondLink.status}`);
}

const verified = await request('/api/auth/verify', {
  method: 'POST',
  body: JSON.stringify({ email, pin: '1234', code }),
});
if (verified.status !== 200) throw new Error(`auth/verify returned ${verified.status}`);
const session = await verified.json();
if (typeof session.access_token !== 'string' || typeof session.tenant_id !== 'string') {
  throw new Error('auth/verify did not return a usable session');
}

const products = await request('/api/products', {
  headers: {
    authorization: `Bearer ${session.access_token}`,
    'x-tenant-id': session.tenant_id,
  },
});
if (products.status !== 200) {
  throw new Error(`opaque session could not access products: ${products.status}`);
}

const shops = await request('/api/tenant/shops', {
  headers: { authorization: `Bearer ${session.access_token}` },
});
if (shops.status !== 200) {
  throw new Error(`opaque session could not list shops: ${shops.status}`);
}
const shopBody = await shops.json();
if (!Array.isArray(shopBody.shops) || shopBody.shops.length < 2) {
  throw new Error('opaque session did not list both linked shops');
}
const portfolio = await request('/api/tenant/portfolio', {
  headers: { authorization: `Bearer ${session.access_token}` },
});
if (portfolio.status !== 200) {
  throw new Error(`opaque session could not load portfolio: ${portfolio.status}`);
}

console.log(`Authenticated email-code journey passed for tenant ${session.tenant_id}`);
