import { randomUUID } from 'node:crypto';

const baseUrl = (process.env.BASE_URL || 'http://localhost:3100').replace(/\/$/, '');
const code = process.env.AUTH_TEST_CODE;
if (!/^\d{6}$/.test(code || '')) throw new Error('AUTH_TEST_CODE must be a six-digit test value');

async function request(path, options = {}) {
  return fetch(`${baseUrl}${path}`, {
    ...options,
    signal: AbortSignal.timeout(10_000),
    headers: { 'content-type': 'application/json', ...(options.headers || {}) },
  });
}

const suffix = randomUUID().slice(0, 8);
const email = `ci-backup-${suffix}@example.com`;
const link = await request('/api/auth/link', {
  method: 'POST',
  body: JSON.stringify({ email, pin: '1234', shopName: `CI Backup ${suffix}`, ownerName: 'CI Owner' }),
});
if (!link.ok) throw new Error(`auth/link returned ${link.status}`);
const verified = await request('/api/auth/verify', {
  method: 'POST',
  body: JSON.stringify({ email, pin: '1234', code }),
});
if (!verified.ok) throw new Error(`auth/verify returned ${verified.status}`);
const session = await verified.json();
const headers = {
  authorization: `Bearer ${session.access_token}`,
  'x-tenant-id': session.tenant_id,
};
const workspaceKey = `backup-${suffix}`;

for (const [kind, ciphertext] of [
  ['device_bound', `device-ciphertext-${suffix}`],
  ['portable', `portable-ciphertext-${suffix}`],
]) {
  const uploaded = await request('/api/backups/full', {
    method: 'POST',
    headers,
    body: JSON.stringify({ workspaceKey, kind, payload: ciphertext }),
  });
  if (uploaded.status !== 201) throw new Error(`${kind} upload returned ${uploaded.status}`);
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
