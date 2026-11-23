import { randomUUID } from 'node:crypto';

const baseUrl = (process.env.BASE_URL || '').replace(/\/$/, '');
const stagingHost = 'duka-pos-backend-staging.brianbmk332.workers.dev';
if (new URL(baseUrl).protocol !== 'https:' || new URL(baseUrl).hostname.toLowerCase() !== stagingHost) {
  throw new Error('Admin write journeys are restricted to the configured staging Worker');
}

const masterToken = process.env.STAGING_ADMIN_TEST_TOKEN;
if (!masterToken) {
  throw new Error('STAGING_ADMIN_TEST_TOKEN is required to exercise staging admin writes');
}

async function request(path, options = {}) {
  const headers = {
    'content-type': 'application/json',
    authorization: `Bearer ${adminToken}`,
    ...(options.headers || {}),
  };
  return fetch(`${baseUrl}${path}`, {
    ...options,
    signal: AbortSignal.timeout(10_000),
    headers,
  });
}

const login = await fetch(`${baseUrl}/api/admin/auth/login`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({
    email: process.env.STAGING_ADMIN_EMAIL || 'brian@nerva.co.ke',
    masterToken,
  }),
  signal: AbortSignal.timeout(10_000),
});
if (!login.ok) throw new Error(`Staging super-admin login returned ${login.status}`);
const session = await login.json();
if (session.role !== 'super_admin' || typeof session.access_token !== 'string') {
  throw new Error('Staging super-admin login did not return an administrator session');
}
const adminToken = session.access_token;

const wsTicket = await request('/api/admin/auth/ws-ticket', { method: 'POST' });
if (!wsTicket.ok) throw new Error(`Admin WebSocket ticket issue returned ${wsTicket.status}`);
const wsTicketBody = await wsTicket.json();
if (typeof wsTicketBody.ticket !== 'string' || wsTicketBody.expiresIn !== 30) {
  throw new Error('Admin WebSocket ticket did not have the expected short lifetime');
}

const usersResponse = await request('/api/admin/users');
if (!usersResponse.ok) throw new Error(`Admin user list returned ${usersResponse.status}`);
const users = (await usersResponse.json()).users;
const testUser = users.find((user) =>
  user.profiles?.some((profile) =>
    profile.tenant?.shopName?.startsWith('CI Auth '),
  ),
);
const testProfile = testUser?.profiles?.find((profile) =>
  profile.tenant?.shopName?.startsWith('CI Auth '),
);
if (!testUser?.email || !testProfile?.tenant?.id) {
  throw new Error('The auth staging journey did not leave a test tenant for admin write checks');
}
const tenantId = testProfile.tenant.id;
const suffix = randomUUID().slice(0, 8);

const keyEmail = `ci-admin-${suffix}@example.com`;
const keyPhone = `+2547${randomUUID().replace(/\D/g, '').slice(0, 8)}`;
const mintedKey = await request('/api/admin/auth/keys/mint', {
  method: 'POST',
  body: JSON.stringify({
    email: keyEmail,
    phone: keyPhone,
    department: 'staging-ci',
    role: 'worker',
    permissions: ['tasks:read', 'tasks:manage'],
    expiresInDays: 7,
  }),
});
if (mintedKey.status !== 201) {
  throw new Error(`Admin key mint returned ${mintedKey.status}`);
}
const mintedKeyBody = await mintedKey.json();
if (typeof mintedKeyBody.id !== 'string' || typeof mintedKeyBody.key !== 'string') {
  throw new Error('Admin key mint did not return its one-time staging credentials');
}
const adminKeyId = mintedKeyBody.id;
const departmentLogin = await request('/api/admin/auth/login', {
  method: 'POST',
  body: JSON.stringify({
    email: keyEmail,
    phone: keyPhone,
    key: mintedKeyBody.key,
  }),
});
if (
  !departmentLogin.ok ||
  (await departmentLogin.json()).role !== 'department_admin'
) {
  throw new Error('The minted staging administrator could not log in');
}
const updatedKey = await request(`/api/admin/auth/keys/${encodeURIComponent(adminKeyId)}`, {
  method: 'PATCH',
  body: JSON.stringify({
    role: 'manager',
    permissions: ['tasks:read', 'tasks:manage'],
    expiresInDays: 7,
  }),
});
if (!updatedKey.ok || (await updatedKey.json()).key?.role !== 'manager') {
  throw new Error(`Admin key update returned ${updatedKey.status}`);
}

const createdTask = await request('/api/admin/org/tasks', {
  method: 'POST',
  body: JSON.stringify({
    title: `CI staging task ${suffix}`,
    description: 'Temporary staging-only administrator task.',
    assigneeKeyId: adminKeyId,
  }),
});
if (createdTask.status !== 201) {
  throw new Error(`Admin task creation returned ${createdTask.status}`);
}
const taskId = (await createdTask.json()).task?.id;
if (typeof taskId !== 'string') throw new Error('Admin task creation returned no task ID');
for (const status of ['in_progress', 'done']) {
  const taskUpdate = await request(`/api/admin/org/tasks/${encodeURIComponent(taskId)}`, {
    method: 'PATCH',
    body: JSON.stringify({ status }),
  });
  if (!taskUpdate.ok || (await taskUpdate.json()).task?.status !== status) {
    throw new Error(`Admin task status update to ${status} returned ${taskUpdate.status}`);
  }
}
const revokedKey = await request(`/api/admin/auth/keys/${encodeURIComponent(adminKeyId)}/revoke`, {
  method: 'POST',
});
if (!revokedKey.ok || !(await revokedKey.json()).key?.revokedAt) {
  throw new Error(`Admin key revocation returned ${revokedKey.status}`);
}
const revokedLogin = await request('/api/admin/auth/login', {
  method: 'POST',
  body: JSON.stringify({
    email: keyEmail,
    phone: keyPhone,
    key: mintedKeyBody.key,
  }),
});
if (revokedLogin.status !== 401) {
  throw new Error(`Revoked staging administrator login should return 401, got ${revokedLogin.status}`);
}

const subscription = await request(`/api/admin/billing/subscriptions/${encodeURIComponent(tenantId)}`, {
  method: 'PATCH',
  body: JSON.stringify({
    status: 'pending',
    priceMinor: 10_000,
    discountPercent: 10,
    currency: 'KES',
    billingInterval: 'monthly',
    currentPeriodEnd: null,
    graceUntil: null,
  }),
});
if (!subscription.ok) throw new Error(`Admin subscription update returned ${subscription.status}`);
const subscriptionBody = await subscription.json();
if (
  subscriptionBody.subscription?.status !== 'pending' ||
  subscriptionBody.subscription?.priceMinor !== 10_000
) {
  throw new Error('Admin subscription update did not persist the staging terms');
}

const issued = await request('/api/admin/billing/vouchers', {
  method: 'POST',
  body: JSON.stringify({
    tenantId,
    email: testUser.email,
    voucherType: 'access',
    durationMonths: 1,
  }),
});
if (issued.status !== 201) throw new Error(`Admin voucher issue returned ${issued.status}`);
const issuedBody = await issued.json();
const voucherId = issuedBody.voucher?.id;
if (issuedBody.voucher?.emailSent !== true || typeof voucherId !== 'string') {
  throw new Error('Admin voucher issue did not confirm delivery and return its staging ID');
}
for (const action of ['pause', 'resume', 'revoke', 'delete']) {
  const actionResponse = await request(`/api/admin/billing/vouchers/${encodeURIComponent(voucherId)}/${action}`, {
    method: 'POST',
  });
  if (!actionResponse.ok) {
    throw new Error(`Admin voucher ${action} returned ${actionResponse.status}`);
  }
}

const providerValidation = await request('/api/admin/billing/provider', {
  method: 'PATCH',
  body: JSON.stringify({ channelType: 'till', shortCode: 'not-a-real-channel' }),
});
if (providerValidation.status !== 400) {
  throw new Error(`Invalid provider configuration should be rejected before external registration; got ${providerValidation.status}`);
}

const retention = await request('/api/admin/retention/run', {
  method: 'POST',
  body: JSON.stringify({ olderThanDays: 365, dryRun: 1 }),
});
if (!retention.ok) throw new Error(`Admin telemetry retention dry-run returned ${retention.status}`);

const commercialRetention = await request('/api/admin/commercial/retention/run', {
  method: 'POST',
  body: JSON.stringify({ olderThanDays: 365, dryRun: true }),
});
if (!commercialRetention.ok) {
  throw new Error(`Admin commercial retention dry-run returned ${commercialRetention.status}`);
}
if ((await commercialRetention.json()).dryRun !== true) {
  throw new Error('Commercial retention endpoint did not honor dryRun');
}

const audit = await request('/api/admin/audit', {
  method: 'POST',
  body: JSON.stringify({
    action: `ci_admin_write_${suffix}`,
    targetType: 'ci_test',
    targetId: suffix,
    tenantId,
  }),
});
if (audit.status !== 201) throw new Error(`Admin audit write returned ${audit.status}`);

const expense = await request('/api/admin/expenses', {
  method: 'POST',
  body: JSON.stringify({
    category: 'CI staging test',
    description: `Automated admin write check ${suffix}`,
    amount: 1,
  }),
});
if (expense.status !== 201 || typeof (await expense.json()).id !== 'string') {
  throw new Error(`Admin expense write returned ${expense.status} or no staging record ID`);
}

const withdrawal = await request(`/api/admin/commercial/ledger/ci-missing-${suffix}/withdraw`, {
  method: 'POST',
  body: JSON.stringify({ reason: 'CI route verification; no contribution exists' }),
});
if (withdrawal.status !== 404) {
  throw new Error(`Commercial withdrawal should safely reject a missing test record; got ${withdrawal.status}`);
}

const announcementRead = await request('/api/admin/announcement');
if (!announcementRead.ok) throw new Error(`Admin announcement read returned ${announcementRead.status}`);
const previousAnnouncement = (await announcementRead.json()).announcement;
if (!previousAnnouncement) {
  const announcement = await request('/api/admin/announcement', {
    method: 'POST',
    body: JSON.stringify({
      title: `CI staging write check ${suffix}`,
      body: 'Temporary staging-only announcement used by the automated admin write journey.',
      active: false,
    }),
  });
  if (announcement.status !== 201) {
    throw new Error(`Admin announcement write returned ${announcement.status}`);
  }
  const cleared = await request('/api/admin/announcement', { method: 'DELETE' });
  if (cleared.status !== 204) throw new Error(`Admin announcement clear returned ${cleared.status}`);
}

const taxEntitiesResponse = await request('/api/admin/tax-entities');
if (!taxEntitiesResponse.ok) {
  throw new Error(`Admin tax entity list returned ${taxEntitiesResponse.status}`);
}
const taxEntity = (await taxEntitiesResponse.json()).entities?.[0];
const taxRule = await request('/api/admin/tax-rules', {
  method: 'POST',
  body: JSON.stringify({
    taxEntityId: taxEntity?.id ?? `ci-missing-${suffix}`,
    taxType: 'payroll',
    scope: `ci-${suffix}`,
    jurisdiction: 'KE',
    taxBase: 'none',
    filingFrequency: 'none',
    effectiveFrom: '2099-01-01T00:00:00.000Z',
    sourceUrl: 'https://example.com/ci-admin-write-journey',
    sourceReference: `CI ${suffix}`,
  }),
});
if (taxEntity) {
  if (taxRule.status !== 201) {
    throw new Error(`Admin tax rule create returned ${taxRule.status}`);
  }
  const taxRuleId = (await taxRule.json()).rule?.id;
  if (typeof taxRuleId !== 'string') throw new Error('Admin tax rule create returned no ID');
  const approval = await request(`/api/admin/tax-rules/${encodeURIComponent(taxRuleId)}/approve`, {
    method: 'POST',
    body: JSON.stringify({ approvalNote: `Staging CI ${suffix}` }),
  });
  if (!approval.ok) throw new Error(`Admin tax rule approval returned ${approval.status}`);
  if ((await approval.json()).rule?.status !== 'approved') {
    throw new Error('The future-dated staging tax rule was not approved');
  }
} else if (taxRule.status !== 404) {
  throw new Error(`Admin tax rule create should reject the missing staging entity; got ${taxRule.status}`);
}

console.log(`Staging admin key/task, subscription, voucher, retention, audit, expense, announcement, and tax-rule writes passed for tenant ${tenantId}`);
