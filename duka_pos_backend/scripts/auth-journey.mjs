import { pbkdf2Sync, randomBytes, randomUUID } from 'node:crypto';
import { addStagingAuthTestHeader } from './staging-auth-headers.mjs';
import { issueAndClaimStagingVoucher } from './staging-voucher-journey.mjs';

const baseUrl = (process.env.BASE_URL || 'http://localhost:3100').replace(/\/$/, '');
const fallbackCode = process.env.AUTH_TEST_CODE;
if (fallbackCode && !/^\d{6}$/.test(fallbackCode)) {
  throw new Error('AUTH_TEST_CODE must be a six-digit non-production test value');
}

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
if ('debug_first_voucher_code' in challenge) {
  throw new Error('auth/link must not generate a voucher before an administrator issues one');
}

const verified = await request('/api/auth/verify', {
  method: 'POST',
  body: JSON.stringify({
    email,
    password: '123456',
    code: verificationCode,
    shopName: `CI Auth ${suffix}`,
    ownerName: 'CI Owner',
  }),
});
if (verified.status !== 200) throw new Error(`auth/verify returned ${verified.status}`);
const session = await verified.json();
if (typeof session.access_token !== 'string' || typeof session.tenant_id !== 'string') {
  throw new Error('auth/verify did not return a usable session');
}
if (session.voucher_redeemed !== false) {
  throw new Error('email verification must not auto-issue or redeem a voucher');
}

const tenantHeaders = {
  authorization: `Bearer ${session.access_token}`,
  'x-tenant-id': session.tenant_id,
};
await issueAndClaimStagingVoucher({ baseUrl, email, tenantHeaders, request });

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

const diagnostic = await request('/api/admin/diagnostics', {
  method: 'POST',
  headers: tenantHeaders,
  body: JSON.stringify({
    deviceId: `ci-device-${suffix}`,
    platform: 'android',
    osVersion: 'staging-test',
    appVersion: '2.0.0',
    buildNumber: 'ci',
    locale: 'en',
    manufacturer: 'CI',
    model: 'Staging test device',
    crashes: [],
  }),
});
if (diagnostic.status !== 201) {
  throw new Error(`tenant diagnostic upload returned ${diagnostic.status}`);
}

const discountSuffix = randomUUID().slice(0, 8);
const discountEmail = `ci-discount-${discountSuffix}@example.com`;
const discountShopName = `CI Discount ${discountSuffix}`;
const discountLink = await request('/api/auth/link', {
  method: 'POST',
  body: JSON.stringify({
    email: discountEmail,
    password: '123456',
    shopName: discountShopName,
    ownerName: 'CI Discount Owner',
  }),
});
if (discountLink.status !== 200) {
  throw new Error(`discount auth/link returned ${discountLink.status}`);
}
const discountChallenge = await discountLink.json();
const discountVerificationCode = discountChallenge.debug_code || fallbackCode;
if (!/^\d{6}$/.test(discountVerificationCode || '')) {
  throw new Error('No verification code was available for the reserved discount test account');
}
const discountVerified = await request('/api/auth/verify', {
  method: 'POST',
  body: JSON.stringify({
    email: discountEmail,
    password: '123456',
    code: discountVerificationCode,
    shopName: discountShopName,
    ownerName: 'CI Discount Owner',
  }),
});
if (discountVerified.status !== 200) {
  throw new Error(`discount auth/verify returned ${discountVerified.status}`);
}
const discountSession = await discountVerified.json();
if (
  typeof discountSession.access_token !== 'string' ||
  discountSession.voucher_redeemed !== false
) {
  throw new Error('The discount test account did not verify without auto-granting access');
}
await issueAndClaimStagingVoucher({
  baseUrl,
  email: discountEmail,
  tenantHeaders: {
    authorization: `Bearer ${discountSession.access_token}`,
    'x-tenant-id': discountSession.tenant_id,
  },
  request,
  voucherType: 'discount',
  durationMonths: 3,
  discountPercent: 25,
});

console.log(`Email verification, access and discount voucher journeys, staff sync, and staff login passed for tenant ${session.tenant_id}`);
