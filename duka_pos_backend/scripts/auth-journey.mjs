import { pbkdf2Sync, randomBytes, randomUUID } from 'node:crypto';
import process from 'node:process';
import { URL } from 'node:url';
import { addStagingAuthTestHeader, STAGING_WORKER_HOST } from './staging-auth-headers.mjs';
import { issueAndClaimStagingVoucher } from './staging-voucher-journey.mjs';

const baseUrl = (process.env.BASE_URL || 'http://localhost:3100').replace(/\/$/, '');
const target = new URL(baseUrl);
const localHosts = new Set(['localhost', '127.0.0.1', '::1']);
const isLocalTarget = localHosts.has(target.hostname.toLowerCase());
const isStagingTarget =
  target.protocol === 'https:' &&
  target.hostname.toLowerCase() === STAGING_WORKER_HOST;
if (!isLocalTarget && !isStagingTarget) {
  throw new Error('Auth journey tests may only target localhost or the configured staging Worker');
}
if (isStagingTarget) {
  const missing = ['STAGING_AUTH_TEST_SECRET', 'STAGING_ADMIN_TEST_TOKEN']
    .filter((name) => !process.env[name]);
  if (missing.length > 0) {
    throw new Error(`Staging auth journey requires: ${missing.join(', ')}`);
  }
}
const fallbackCode = process.env.AUTH_TEST_CODE;
if (fallbackCode && !/^\d{6}$/.test(fallbackCode)) {
  throw new Error('AUTH_TEST_CODE must be a six-digit non-production test value');
}

async function request(path, options = {}) {
  const headers = addStagingAuthTestHeader(baseUrl, path, {
    'content-type': 'application/json',
    ...(options.headers || {}),
  });
  try {
    return await globalThis.fetch(`${baseUrl}${path}`, {
      ...options,
      signal: globalThis.AbortSignal.timeout(30_000),
      headers,
    });
  } catch (error) {
    if (error instanceof Error && error.name === 'TimeoutError') {
      throw new Error(`Auth journey request ${path} timed out`, { cause: error });
    }
    throw error;
  }
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
const verifiedSession = await verified.json();
if (
  typeof verifiedSession.access_token !== 'string' ||
  typeof verifiedSession.tenant_id !== 'string'
) {
  throw new Error('auth/verify did not return a usable session');
}
if (verifiedSession.voucher_redeemed !== false) {
  throw new Error('email verification must not auto-issue or redeem a voucher');
}

const tenantId = verifiedSession.tenant_id;
const deviceTenantHeaders = {
  authorization: `Bearer ${verifiedSession.access_token}`,
  'x-tenant-id': tenantId,
};
await issueAndClaimStagingVoucher({
  baseUrl,
  email,
  tenantHeaders: deviceTenantHeaders,
  request,
});

const products = await request('/api/products', {
  headers: deviceTenantHeaders,
});
if (products.status !== 200) {
  throw new Error(`opaque session could not access products: ${products.status}`);
}

const shops = await request('/api/tenant/shops', {
  headers: deviceTenantHeaders,
});
if (shops.status !== 200) {
  throw new Error(`opaque session could not list shops: ${shops.status}`);
}
const shopBody = await shops.json();
if (!Array.isArray(shopBody.shops) || shopBody.shops.length !== 1) {
  throw new Error('newly verified account should have exactly one linked shop');
}
const restrictedPortfolio = await request('/api/tenant/portfolio', {
  headers: deviceTenantHeaders,
});
if (restrictedPortfolio.status === 403) {
  const body = await restrictedPortfolio.json().catch(() => ({}));
  if (body.code === 'DEVICE_TOKEN_NOT_ALLOWED') {
    throw new Error('device session should now have full app access, but portfolio was blocked');
  }
}

const ownerLogin = await request('/api/auth/login', {
  method: 'POST',
  body: JSON.stringify({ email, password: '123456' }),
});
if (ownerLogin.status !== 200) {
  throw new Error(`verified owner login returned ${ownerLogin.status}`);
}
const ownerSession = await ownerLogin.json();
if (
  typeof ownerSession.access_token !== 'string' ||
  !Array.isArray(ownerSession.tenants) ||
  !ownerSession.tenants.some((tenant) => tenant.id === tenantId)
) {
  throw new Error('owner login did not return access to the verified tenant');
}
const tenantHeaders = {
  authorization: `Bearer ${ownerSession.access_token}`,
  'x-tenant-id': tenantId,
};
const portfolio = await request('/api/tenant/portfolio', {
  headers: tenantHeaders,
});
if (portfolio.status !== 200) {
  const body = await portfolio.json().catch(() => ({}));
  throw new Error(`owner session could not load portfolio: ${portfolio.status} (${body.code ?? 'no error code'})`);
}

const staffPin = '246810';
const changedStaffPin = '135790';
const deviceId = `ci-device-${suffix}`;
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

const appStaffLoginBody = {
  username,
  pin: staffPin,
  device_id: deviceId,
};
const missingTenantLogin = await request('/api/tenant/staff/authenticate', {
  method: 'POST',
  body: JSON.stringify(appStaffLoginBody),
});
if (missingTenantLogin.status !== 401) {
  throw new Error(`staff login without the app's selected tenant returned ${missingTenantLogin.status}, expected 401`);
}

const invalidPinLogin = await request('/api/tenant/staff/authenticate', {
  method: 'POST',
  headers: { 'x-tenant-id': tenantId },
  body: JSON.stringify({ ...appStaffLoginBody, pin: '000000' }),
});
if (invalidPinLogin.status !== 401) {
  throw new Error(`one invalid staff PIN returned ${invalidPinLogin.status}, expected 401`);
}

const staffLogin = await request('/api/tenant/staff/authenticate', {
  method: 'POST',
  headers: { 'x-tenant-id': tenantId },
  body: JSON.stringify(appStaffLoginBody),
});
if (staffLogin.status !== 200) {
  throw new Error(`tenant/staff/authenticate returned ${staffLogin.status}`);
}
const staffSession = await staffLogin.json();
if (
  staffSession.staff_id !== staffRows.synced[0].remoteId ||
  typeof staffSession.session_token !== 'string' ||
  typeof staffSession.offline_lease !== 'string' ||
  staffSession.device_id !== deviceId ||
  !Number.isFinite(Date.parse(staffSession.offline_lease_expires_at))
) {
  throw new Error('staff login did not return the synced staff session');
}

const changePin = await request('/api/tenant/staff/self-pin', {
  method: 'POST',
  headers: {
    authorization: `Bearer ${staffSession.session_token}`,
    'x-tenant-id': tenantId,
  },
  body: JSON.stringify({ currentPin: staffPin, newPin: changedStaffPin }),
});
if (changePin.status !== 200) {
  throw new Error(`authenticated staff PIN change returned ${changePin.status}`);
}

const staleSessionPinChange = await request('/api/tenant/staff/self-pin', {
  method: 'POST',
  headers: {
    authorization: `Bearer ${staffSession.session_token}`,
    'x-tenant-id': tenantId,
  },
  body: JSON.stringify({ currentPin: changedStaffPin, newPin: '975310' }),
});
if (staleSessionPinChange.status !== 401) {
  throw new Error(`staff PIN change with a stale session returned ${staleSessionPinChange.status}, expected 401`);
}

const changedPinLogin = await request('/api/tenant/staff/authenticate', {
  method: 'POST',
  headers: { 'x-tenant-id': tenantId },
  body: JSON.stringify({ ...appStaffLoginBody, pin: changedStaffPin }),
});
if (changedPinLogin.status !== 200) {
  throw new Error(`staff login with the changed PIN returned ${changedPinLogin.status}`);
}
const changedPinSession = await changedPinLogin.json();
if (typeof changedPinSession.session_token !== 'string') {
  throw new Error('staff login with the changed PIN did not return a session');
}

const revokeDevice = await request(
  `/api/tenant/devices/${encodeURIComponent(deviceId)}/revoke`,
  { method: 'POST', headers: tenantHeaders },
);
if (revokeDevice.status !== 200) {
  throw new Error(`owner device revocation returned ${revokeDevice.status}`);
}

const revokedDeviceLogin = await request('/api/tenant/staff/authenticate', {
  method: 'POST',
  headers: { 'x-tenant-id': tenantId },
  body: JSON.stringify({ ...appStaffLoginBody, pin: changedStaffPin }),
});
if (revokedDeviceLogin.status !== 403) {
  throw new Error(`login from a revoked device returned ${revokedDeviceLogin.status}, expected 403`);
}
const revokedDeviceBody = await revokedDeviceLogin.json();
if (revokedDeviceBody.code !== 'DEVICE_REVOKED') {
  throw new Error('revoked device login did not return DEVICE_REVOKED');
}

const revokedSessionPinChange = await request('/api/tenant/staff/self-pin', {
  method: 'POST',
  headers: {
    authorization: `Bearer ${changedPinSession.session_token}`,
    'x-tenant-id': tenantId,
  },
  body: JSON.stringify({ currentPin: changedStaffPin, newPin: '975310' }),
});
if (revokedSessionPinChange.status !== 401) {
  throw new Error(`staff PIN change after device revocation returned ${revokedSessionPinChange.status}, expected 401`);
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
const discountTenantHeaders = {
  authorization: `Bearer ${discountSession.access_token}`,
  'x-tenant-id': discountSession.tenant_id,
};
const discountSubscription = await request('/api/tenant/subscription', {
  headers: discountTenantHeaders,
});
if (!discountSubscription.ok) {
  throw new Error(`discount tenant subscription returned ${discountSubscription.status}`);
}
const discountEntitlement = (await discountSubscription.json()).entitlement;
const voucherTermByInterval = {
  monthly: 1,
  quarterly: 3,
  semiannual: 6,
  annual: 12,
};
const discountDurationMonths = voucherTermByInterval[discountEntitlement?.billingInterval];
if (!discountDurationMonths) {
  throw new Error(`Unsupported discount-test billing interval: ${discountEntitlement?.billingInterval}`);
}
await issueAndClaimStagingVoucher({
  baseUrl,
  email: discountEmail,
  tenantHeaders: discountTenantHeaders,
  request,
  voucherType: 'discount',
  durationMonths: discountDurationMonths,
  discountPercent: 25,
});

globalThis.console.log(`Email verification, device-token restrictions, owner login, access and discount voucher journeys, app-shaped staff login, PIN change, session invalidation, and device revocation passed for tenant ${tenantId}`);
