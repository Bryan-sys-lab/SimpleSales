const stagingHost = 'duka-pos-backend-staging.brianbmk332.workers.dev';

export function addStagingAuthTestHeader(baseUrl, path, headers) {
  if (new URL(baseUrl).hostname.toLowerCase() !== stagingHost || path !== '/api/auth/link') {
    return headers;
  }
  const secret = process.env.STAGING_AUTH_TEST_SECRET;
  if (!secret) {
    throw new Error('STAGING_AUTH_TEST_SECRET is required for the staging auth journey');
  }
  return { ...headers, 'x-staging-auth-test-secret': secret };
}
