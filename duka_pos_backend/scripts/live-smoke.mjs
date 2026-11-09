const baseUrl = (process.env.BASE_URL || 'http://localhost:3100').replace(/\/$/, '');

const checks = [
  ['/health', 200],
  ['/ready', 200],
  ['/api/products', 401],
  ['/api/backups/full', 401],
  ['/api/profile/photo/upload-url', 401],
  ['/does-not-exist', 404],
];

for (const [path, expected] of checks) {
  let response;
  try {
    response = await fetch(`${baseUrl}${path}`, { signal: AbortSignal.timeout(10_000) });
  } catch (error) {
    throw new Error(`Live smoke could not reach ${baseUrl}: ${error.message}`);
  }
  console.log(`${path}: ${response.status} (expected ${expected})`);
  if (response.status !== expected) {
    throw new Error(`${path} returned ${response.status}; expected ${expected}`);
  }
}

console.log(`Live smoke passed against ${baseUrl}`);
