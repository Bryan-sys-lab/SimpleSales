const baseUrl = process.env.KEYCLOAK_URL || 'http://keycloak:8080';
const admin = process.env.KEYCLOAK_ADMIN || 'admin';
const adminPassword = process.env.KEYCLOAK_ADMIN_PASSWORD || 'admin';
const realm = process.env.REALM_NAME || 'duka';
const clientId = process.env.CLIENT_ID || 'duka-app';
const testUser = process.env.TEST_USER || 'test-user';
const testPassword = process.env.TEST_USER_PASSWORD || 'test-password';
const testEmail = process.env.TEST_USER_EMAIL || 'test-user@example.com';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function request(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, options);
  const body = await response.text();
  let data = null;
  try {
    data = body ? JSON.parse(body) : null;
  } catch {
    data = body;
  }
  return { response, data };
}

async function createIfMissing(path, token, payload, label) {
  const { response, data } = await request(path, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  if (response.ok || response.status === 409) {
    console.log(`${label}: ${response.status === 409 ? 'already exists' : 'created'}`);
    return;
  }
  throw new Error(`${label} failed (${response.status}): ${JSON.stringify(data)}`);
}

console.log(`Waiting for Keycloak at ${baseUrl}...`);
let ready = false;
for (let attempt = 1; attempt <= 60; attempt += 1) {
  try {
    // Keycloak 24's dev distribution does not expose /health/ready unless
    // health endpoints are explicitly enabled. The public master realm is
    // available only after the server and its database are ready.
    const { response } = await request('/realms/master');
    if (response.ok) {
      ready = true;
      break;
    }
  } catch {
    // Keycloak is still starting.
  }
  await sleep(5000);
}
if (!ready) throw new Error('Keycloak did not become ready within 5 minutes');

const form = new URLSearchParams({
  grant_type: 'password',
  client_id: 'admin-cli',
  username: admin,
  password: adminPassword,
});
const tokenResult = await request('/realms/master/protocol/openid-connect/token', {
  method: 'POST',
  headers: { 'content-type': 'application/x-www-form-urlencoded' },
  body: form,
});
if (!tokenResult.response.ok || typeof tokenResult.data?.access_token !== 'string') {
  throw new Error(`Could not obtain Keycloak admin token: ${tokenResult.response.status}`);
}
const token = tokenResult.data.access_token;

await createIfMissing('/admin/realms', token, {
  enabled: true,
  realm,
  displayName: 'Duka POS',
}, `realm ${realm}`);

await createIfMissing(`/admin/realms/${encodeURIComponent(realm)}/clients`, token, {
  clientId,
  enabled: true,
  publicClient: true,
  protocol: 'openid-connect',
  standardFlowEnabled: true,
  implicitFlowEnabled: false,
  directAccessGrantsEnabled: true,
  serviceAccountsEnabled: false,
  redirectUris: ['http://localhost:*'],
  webOrigins: ['*'],
}, `client ${clientId}`);

await createIfMissing(`/admin/realms/${encodeURIComponent(realm)}/users`, token, {
  username: testUser,
  email: testEmail,
  enabled: true,
  emailVerified: true,
  firstName: 'Test',
  lastName: 'User',
  credentials: [{ type: 'password', value: testPassword, temporary: false }],
}, `user ${testUser}`);

console.log('Keycloak initialization complete');
