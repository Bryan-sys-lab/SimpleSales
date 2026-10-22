import { beforeAll, describe, expect, it } from 'vitest';
import type { Express } from 'express';

let app: Express;

beforeAll(async () => {
  process.env.NODE_ENV = 'test';
  process.env.OIDC_ISSUER_URL = 'https://id.example.test/realms/duka';
  process.env.OIDC_AUDIENCE = 'duka-api';
  process.env.DATABASE_URL = 'postgresql://localhost:5432/duka_pos_test';
  const module = await import('../index');
  app = module.default;
});

describe('HTTP safety boundaries', () => {
  it('returns a health response without authentication', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('ok');
    expect(response.headers['x-request-id']).toBeTruthy();
  });

  it('rejects protected routes without a bearer token', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/products');
    expect(response.status).toBe(401);
    expect(response.body.error).toBe('Request could not be completed');
    expect(response.body.requestId).toBeTruthy();
  });

  it('rejects platform administration without a bearer token', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/system/analytics');
    expect(response.status).toBe(401);
  });

  it('returns JSON for unknown paths', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/does-not-exist');
    expect(response.status).toBe(404);
    expect(response.body.error).toBe('Not found');
  });
});
