import { randomUUID } from 'node:crypto';

const baseUrl = (process.env.BASE_URL || 'http://localhost:3100').replace(/\/$/, '');
const concurrency = Math.max(1, Number(process.env.CONCURRENCY || 50));
const requests = Math.max(concurrency, Number(process.env.REQUESTS || concurrency * 4));

const headers = { 'content-type': 'application/json' };
const protectedPaths = [
  '/api/products',
  '/api/reports/sales?limit=1',
  '/api/reports/products',
  '/api/tenant/portfolio',
];

// CI supplies AUTH_TEST_CODE so the load check exercises authenticated
// database/report paths. Local callers can omit it and retain the cheap health
// probe when no test database or auth flow is available.
if (/^\d{6}$/.test(process.env.AUTH_TEST_CODE || '')) {
  const suffix = randomUUID().slice(0, 8);
  const email = `ci-load-${suffix}@example.com`;
  const link = await fetch(`${baseUrl}/api/auth/link`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      email,
      pin: '1234',
      shopName: `CI Load ${suffix}`,
      ownerName: 'CI Load Owner',
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!link.ok) throw new Error(`load auth/link returned ${link.status}`);
  const verify = await fetch(`${baseUrl}/api/auth/verify`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      email,
      pin: '1234',
      code: process.env.AUTH_TEST_CODE,
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!verify.ok) throw new Error(`load auth/verify returned ${verify.status}`);
  const session = await verify.json();
  if (typeof session.access_token !== 'string') {
    throw new Error('load auth/verify returned no access token');
  }
  headers.authorization = `Bearer ${session.access_token}`;
}

const latencies = [];
let next = 0;
let failures = 0;
let rateLimited = 0;
const statusCounts = new Map();
const authenticated = Boolean(headers.authorization);
async function worker() {
  while (true) {
    const index = next++;
    if (index >= requests) return;
    const started = performance.now();
    try {
      const path = authenticated
        ? protectedPaths[index % protectedPaths.length]
        : '/health';
      const response = await fetch(`${baseUrl}${path}`, {
        headers,
        signal: AbortSignal.timeout(10_000),
      });
      latencies.push(performance.now() - started);
      statusCounts.set(response.status, (statusCounts.get(response.status) || 0) + 1);
      // A 429 here is the configured abuse guard doing its job under the
      // intentionally bursty load. It is reported separately from transport
      // or server failures so the test does not call healthy rate limiting a
      // broken API.
      if (response.status === 429) rateLimited++;
      else if (!response.ok) failures++;
    } catch (_) {
      failures++;
    }
  }
}

await Promise.all(Array.from({ length: concurrency }, worker));
latencies.sort((a, b) => a - b);
const percentile = (p) => latencies[Math.min(latencies.length - 1, Math.floor(latencies.length * p))] || 0;
console.log(JSON.stringify({
  baseUrl,
  requests,
  concurrency,
  authenticated,
  failures,
  rateLimited,
  statuses: Object.fromEntries(statusCounts),
  p50Ms: Math.round(percentile(.5)),
  p95Ms: Math.round(percentile(.95)),
  maxMs: Math.round(latencies.at(-1) || 0),
}, null, 2));
if (failures > 0) process.exitCode = 1;
