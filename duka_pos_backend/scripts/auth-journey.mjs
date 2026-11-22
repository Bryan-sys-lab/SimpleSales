import { pbkdf2Sync, randomBytes, randomUUID } from 'node:crypto';

const baseUrl = (process.env.BASE_URL || 'http://localhost:3100').replace(/\/$/, '');
const stagingAuthTestSecret = process.env.STAGING_AUTH_TEST_SECRET;
const isStaging = new URL(baseUrl).hostname.toLowerCase() === 'duka-pos-backend-staging.brianbmk332.workers.dev';
if (isStaging && !stagingAuthTestSecret) {
  throw new Error('STAGING_AUTH_TEST_SECRET is required for the staging auth journey');
}
const fallbackCode = process.env.AUTH_TEST_CODE;
if (fallbackCode && !/^\d{6}$/.test(fallbackCode)) {
  throw new Error('AUTH_TEST_CODE must be a six-digit non-production test value');
}

async function request(path, options = {}) {
  const headers = { 'content-type': 'application/json', ...(options.headers || {}) };
  if (isStaging && path === '/api/auth/link') {
    headers['x-staging-auth-test-secret'] = stagingAuthTestSecret;
  }
  return fetch(`${baseUrl}${path}`, {
    ...options,
    signal: AbortSignal.timeout(10_000),
    headers,
  });
}

const suffix = randomUUID().slice(0, 8);
const email = `ci-auth-${suffix}@example.com`;
const link = await request('/api/auth/link', {
  method: 'POST',
  body: JSON.stringify({
    email,
    password: '123456',
    shopName: `CI Auth ${suffix}`,
    ownerName: 'CI Owner',
  }),
});
if (link.status !== 200) throw new Error(`auth/link returned ${link.status}`);
const challenge = await link.json();
const verificationCode = challenge.debug_code || fallbackCode;
if (!/^\d{6}$/.test(verificationCode || '')) {
  throw new Error('No verification code was available; configure the test inbox or test-only debug codes');
}
const voucherCode = challenge.debug_first_voucher_code;
if (typeof voucherCode !== 'string' || !voucherCode.startsWith('SS-')) {
  throw new Error('auth/link did not return the first-registration voucher in the test environment');
}

const verified = await request('/api/auth/verify', {
  method: 'POST',
  body: JSON.stringify({
    email,
    password: '123456',
    code: verificationCode,
    voucherCode,
    shopName: `CI Auth ${suffix}`,
    ownerName: 'CI Owner',
  }),
});
if (verified.status !== 200) throw new Error(`auth/verify returned ${verified.status}`);
const session = await verified.json();
if (typeof session.access_token !== 'string' || typeof session.tenant_id !== 'string') {
  throw new Error('auth/verify did not return a usable session');
}
if (session.voucher_redeemed !== true) {
  throw new Error('auth/verify did not redeem the first-registration voucher');
}

const tenantHeaders = {
  authorization: `Bearer ${session.access_token}`,
  'x-tenant-id': session.tenant_id,
};
const products = await request('/api/products', {
  headers: tenantHeaders,
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
if (!Array.isArray(shopBody.shops) || shopBody.shops.length !== 1) {
  throw new Error('newly verified account should have exactly one linked shop');
}
const portfolio = await request('/api/tenant/portfolio', {
  headers: { authorization: `Bearer ${session.access_token}` },
});
if (portfolio.status !== 200) {
  throw new Error(`opaque session could not load portfolio: ${portfolio.status}`);
}

const staffPin = '2468';
const salt = randomBytes(16);
const iterations = 100_000;
const pinHash = pbkdf2Sync(staffPin, salt, iterations, 32, 'sha256');
const username = `ci-${suffix}`;
const staffSync = await request('/api/tenant/staff/sync', {
  method: 'POST',
  headers: tenantHeaders,
  body: JSON.stringify({
    staff: [{
      localId: 1,
      name: `CI Staff ${suffix}`,
      username,
      role: 'cashier',
      active: true,
      pinHash: `pbkdf2$${iterations}$${salt.toString('base64url')}$${pinHash.toString('base64url')}`,
    }],
  }),
});
if (staffSync.status !== 200) {
  throw new Error(`tenant/staff/sync returned ${staffSync.status}`);
}
const staffRows = await staffSync.json();
if (!Array.isArray(staffRows.synced) || typeof staffRows.synced[0]?.remoteId !== 'string') {
  throw new Error('tenant/staff/sync did not return a remote staff identity');
}

const staffLogin = await request('/api/tenant/staff/authenticate', {
  method: 'POST',
  headers: { 'x-tenant-id': session.tenant_id },
  body: JSON.stringify({ username, pin: staffPin }),
});
if (staffLogin.status !== 200) {
  throw new Error(`tenant/staff/authenticate returned ${staffLogin.status}`);
}
const staffSession = await staffLogin.json();
if (staffSession.staff_id !== staffRows.synced[0].remoteId || typeof staffSession.session_token !== 'string') {
  throw new Error('staff login did not return the synced staff session');
}

console.log(`Email verification, first-month voucher, staff sync, and staff login passed for tenant ${session.tenant_id}`);
