import { defineConfig } from 'vitest/config';

// The tests run against the TS sources, which vitest transforms itself.
//
// They USED to run against the compiled `dist` — until the compiled output
// could not `require` vitest (a CommonJS module importing an ESM-only API),
// and every suite refused to load. The sources are the same tests the app
// ships; the build step adds nothing a test run needs.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/__tests__/**/*.test.ts'],
    exclude: ['**/node_modules/**', '**/dist/**', '**/src/__tests__/*.integration.test.ts'],
    globals: true,
  },
});
