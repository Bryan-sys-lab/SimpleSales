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

async function initRealm(token) {
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
}

console.log(`Waiting for Keycloak at ${baseUrl}...`);
let ready = false;
for (let attempt = 1; attempt <= 60; attempt += 1) {
  try {
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
const passwordCandidates = [adminPassword, 'admin', 'admin_local_dev'];
let tokenResult;
let tokenError = null;
for (let attempt = 1; attempt <= 15; attempt += 1) {
  for (const pwd of passwordCandidates) {
    form.set('password', pwd);
    tokenResult = await request('/realms/master/protocol/openid-connect/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: form,
    });
    if (tokenResult.response.ok && typeof tokenResult.data?.access_token === 'string') {
      tokenError = null;
      break;
    }
  }
  if (!tokenError) break;
  tokenError = `status ${tokenResult.response.status}`;
  await sleep(5000);
}
if (tokenError) {
  throw new Error(`Could not obtain Keycloak admin token after retries: ${tokenError}`);
}
const token = tokenResult.data.access_token;

// Retry the entire realm provisioning flow: Keycloak's admin API may not be
// fully provisioned yet even after the server reports ready, so a 401 on
// realm creation means we need to wait and try again.
let initError = null;
for (let attempt = 1; attempt <= 15; attempt += 1) {
  try {
    await initRealm(token);
    initError = null;
    break;
  } catch (err) {
    initError = err;
    await sleep(5000);
  }
}
if (initError) throw initError;

console.log('Keycloak initialization complete');
