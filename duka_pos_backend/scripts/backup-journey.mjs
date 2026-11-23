import { createHash, randomUUID } from 'node:crypto';
import { addStagingAuthTestHeader } from './staging-auth-headers.mjs';
import { issueAndClaimStagingVoucher } from './staging-voucher-journey.mjs';

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
const email = `ci-backup-${suffix}@example.com`;
const password = '123456';
const shopName = `CI Backup ${suffix}`;
const ownerName = 'CI Owner';
const link = await request('/api/auth/link', {
  method: 'POST',
  body: JSON.stringify({ email, password, shopName, ownerName }),
});
if (!link.ok) throw new Error(`auth/link returned ${link.status}`);
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
if (!verified.ok) throw new Error(`auth/verify returned ${verified.status}`);
const session = await verified.json();
if (session.voucher_redeemed !== false) {
  throw new Error('email verification must not auto-issue or redeem a voucher');
}
const headers = {
  authorization: `Bearer ${session.access_token}`,
  'x-tenant-id': session.tenant_id,
};
await issueAndClaimStagingVoucher({ baseUrl, email, tenantHeaders: headers, request });

const workspaceKey = `backup-${suffix}`;
const snapshotHash = createHash('sha256')
  .update(`backup-journey:${suffix}`)
  .digest('hex');

for (const [kind, ciphertext] of [
  ['device_bound', `device-ciphertext-${suffix}`],
  ['portable', `portable-ciphertext-${suffix}`],
]) {
  const uploaded = await request('/api/backups/full', {
    method: 'POST',
    headers,
    body: JSON.stringify({
      workspaceKey,
      kind,
      payload: ciphertext,
      snapshotHash: kind === 'device_bound' ? snapshotHash : undefined,
    }),
  });
  if (uploaded.status !== 201) {
    throw new Error(`${kind} upload returned ${uploaded.status}: ${JSON.stringify(await uploaded.json())}`);
  }
  if (kind === 'device_bound') {
    const retried = await request('/api/backups/full', {
      method: 'POST',
      headers,
      body: JSON.stringify({
        workspaceKey,
        kind,
        payload: `retry-${ciphertext}`,
        snapshotHash,
      }),
    });
    if (retried.status !== 200) {
      throw new Error(`idempotent ${kind} retry returned ${retried.status}`);
    }
  }
}

for (const [kind, expected] of [
  ['device_bound', `device-ciphertext-${suffix}`],
  ['portable', `portable-ciphertext-${suffix}`],
]) {
  const response = await request(`/api/backups/full?workspaceKey=${encodeURIComponent(workspaceKey)}&kind=${kind}`, { headers });
  if (response.status !== 200) throw new Error(`${kind} restore returned ${response.status}`);
  const body = await response.json();
  if (body.kind !== kind || body.payload !== expected) {
    throw new Error(`${kind} restore selected the wrong backup object`);
  }
}

console.log(`Backup kind-selection journey passed for tenant ${session.tenant_id}`);
