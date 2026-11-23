const stagingHost = 'duka-pos-backend-staging.brianbmk332.workers.dev';

export async function issueAndClaimStagingVoucher({
  baseUrl,
  email,
  tenantHeaders,
  request,
  voucherType = 'access',
  durationMonths = 1,
  discountPercent = 0,
}) {
  const url = new URL(baseUrl);
  if (url.protocol !== 'https:' || url.hostname.toLowerCase() !== stagingHost) {
    throw new Error('Admin-issued voucher journeys are restricted to the configured staging Worker');
  }
  if (!email.toLowerCase().endsWith('@example.com')) {
    throw new Error('Admin-issued voucher journey recipients must use the reserved example.com domain');
  }

  const masterToken = process.env.STAGING_ADMIN_TEST_TOKEN;
  if (!masterToken) {
    throw new Error('STAGING_ADMIN_TEST_TOKEN is required to exercise administrator-issued voucher claiming');
  }

  const adminLogin = await fetch(`${url.origin}/api/admin/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      email: process.env.STAGING_ADMIN_EMAIL || 'brian@nerva.co.ke',
      masterToken,
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!adminLogin.ok) {
    throw new Error(`Staging super-admin login returned ${adminLogin.status}`);
  }
  const adminSession = await adminLogin.json();
  if (adminSession.role !== 'super_admin' || typeof adminSession.access_token !== 'string') {
    throw new Error('Staging super-admin login did not return an administrator session');
  }

  const issued = await fetch(`${url.origin}/api/admin/billing/vouchers`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${adminSession.access_token}`,
    },
    body: JSON.stringify({
      email,
      voucherType,
      durationMonths,
      discountPercent: voucherType === 'discount' ? discountPercent : 0,
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (issued.status !== 201) {
    throw new Error(`Administrator voucher issuance returned ${issued.status}`);
  }
  const issueResult = await issued.json();
  if (
    issueResult.voucher?.emailSent !== true ||
    issueResult.voucher?.voucherType !== voucherType ||
    issueResult.voucher?.durationMonths !== durationMonths ||
    issueResult.voucher?.discountPercent !== (voucherType === 'discount' ? discountPercent : 0)
  ) {
    throw new Error('Administrator voucher issuance did not confirm the requested voucher details and email delivery');
  }

  const available = await request('/api/tenant/subscription', {
    headers: tenantHeaders,
  });
  if (!available.ok) {
    throw new Error(`Tenant subscription voucher status returned ${available.status}`);
  }
  const availableResult = await available.json();
  if (
    availableResult.support?.availableVoucher?.voucherType !== voucherType ||
    availableResult.support?.availableVoucher?.durationMonths !== durationMonths ||
    availableResult.support?.availableVoucher?.discountPercent !==
      (voucherType === 'discount' ? discountPercent : 0)
  ) {
    throw new Error('The one-tap subscription response did not expose the assigned voucher details');
  }

  const claimed = await request('/api/auth/voucher/claim', {
    method: 'POST',
    headers: tenantHeaders,
  });
  if (claimed.status !== 200) {
    const error = await claimed.json().catch(() => ({}));
    throw new Error(`Claiming the administrator-issued voucher returned ${claimed.status} (${error.code ?? 'no error code'})`);
  }
  const claimResult = await claimed.json();
  if (voucherType === 'discount') {
    if (
      claimResult.status !== 'discount_voucher_applied' ||
      claimResult.voucher?.voucherType !== 'discount' ||
      claimResult.voucher?.durationMonths !== durationMonths ||
      claimResult.voucher?.discountPercent !== discountPercent ||
      claimResult.entitlement?.allowed !== false ||
      claimResult.entitlement?.discountVoucherDurationMonths !== durationMonths ||
      claimResult.entitlement?.discountPercent < discountPercent ||
      claimResult.entitlement?.currentPeriodEnd !== null
    ) {
      throw new Error('The discount voucher did not remain pay-required and attached to its selected plan');
    }
  } else if (
    claimResult.status !== 'voucher_redeemed' ||
    claimResult.voucher?.durationMonths !== durationMonths ||
    claimResult.entitlement?.allowed !== true
  ) {
    throw new Error('The issued staging access voucher was not claimed for the signup account');
  }
}
