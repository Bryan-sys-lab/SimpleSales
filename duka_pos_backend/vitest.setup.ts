/**
 * Vitest setup for real integration tests.
 *
 * No mocks - tests hit the live backend via supertest against a real
 * Keycloak + PostgreSQL + backend stack.
 */
import { execSync } from 'child_process';

// Ensure test env vars are set
process.env.NODE_ENV = 'test';
process.env.OIDC_ISSUER_URL = process.env.OIDC_ISSUER_URL || 'https://id.example.test/realms/duka';
process.env.OIDC_AUDIENCE = process.env.OIDC_AUDIENCE || 'duka-api';
process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgresql://localhost:5432/duka_pos_test';
process.env.PAYHERO_AUTH_TOKEN = process.env.PAYHERO_AUTH_TOKEN || 'test-payhero-token';
process.env.SYSTEM_ADMIN_SUBJECTS = process.env.SYSTEM_ADMIN_SUBJECTS || 'admin-subject';
process.env.BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:3000/api';
process.env.KEYCLOAK_URL = process.env.KEYCLOAK_URL || 'http://localhost:8080';
process.env.KEYCLOAK_ADMIN = process.env.KEYCLOAK_ADMIN || 'admin';
process.env.KEYCLOAK_ADMIN_PASSWORD = process.env.KEYCLOAK_ADMIN_PASSWORD || 'admin';
process.env.REALM_NAME = process.env.REALM_NAME || 'duka';
process.env.CLIENT_ID = process.env.CLIENT_ID || 'duka-app';
process.env.TEST_USER = process.env.TEST_USER || 'test-user';
process.env.TEST_USER_PASSWORD = process.env.TEST_USER_PASSWORD || 'test-password';

export {};
