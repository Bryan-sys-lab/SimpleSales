import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // Explicit, because the defaults changed between vitest majors and this
    // project has a `dist/` directory full of compiled copies of its own tests.
    // vitest 5 stopped excluding it, so every test ran twice: once from source
    // and once from the stale compiled JS, and the compiled copies failed on
    // their own relative imports.
    include: ['src/**/*.test.ts'],
    exclude: ['node_modules/**', 'dist/**'],

    environment: 'node',
    globals: false,
    // The integration tests import `src/index.ts`, which builds an Express app
    // and opens a Prisma client at module load. Neither has a network or a
    // database available in CI, so the suite asserts on the wiring and the pure
    // arithmetic rather than on live calls.
    env: {
      NODE_ENV: 'test',
      DATABASE_URL:
        process.env.DATABASE_URL ?? 'postgresql://localhost:5432/duka_pos_test',
      OIDC_ISSUER_URL:
        process.env.OIDC_ISSUER_URL ?? 'https://id.example.test/realms/duka',
      OIDC_AUDIENCE: process.env.OIDC_AUDIENCE ?? 'duka-api',
    },
  },
});