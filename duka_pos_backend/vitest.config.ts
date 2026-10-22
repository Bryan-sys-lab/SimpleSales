import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: [
      'dist/__tests__/security.test.js',
      'dist/__tests__/manifest.test.js',
      'dist/__tests__/validation.test.js',
      'dist/__tests__/identity.test.js',
      'dist/__tests__/stock-adjust.test.js',
      'dist/__tests__/staff-authenticate.test.js',
      'dist/__tests__/etims.test.js',
      'dist/__tests__/portfolio.test.js',
      'dist/__tests__/auth.test.js',
      'dist/__tests__/products.test.js',
      'dist/__tests__/reports.test.js',
      'dist/__tests__/payments.test.js',
      'dist/__tests__/profile.test.js',
    ],
    exclude: [
      '**/node_modules/**',
      '**/src/**',
      '**/dist/__tests__/*.integration.test.js',
    ],
    globals: true,
  },
});
