// Access boundaries for the verify flow.
//
// These three endpoints are the only ones in the service that authenticate by
// content rather than by token, because the first of them has to work for an
// account that does not exist yet. That makes them the most interesting
// surface in the API, and the questions worth answering are the ones a unit
// test of the code logic cannot: is the route reachable at all before a token
// exists, does a bad body get rejected at the door, is the server honest when
// it has no realm configured, and does an app session stop where it should.

import { beforeAll, describe, expect, it } from 'vitest';
import type { Express } from 'express';
import { issueAppSession } from '../lib/app_session';

let app: Express;

beforeAll(async () => {
  process.env.NODE_ENV = 'test';
  process.env.OIDC_ISSUER_URL = 'https://id.example.test/realms/duka';
  process.env.OIDC_AUDIENCE = 'duka-api';
  process.env.DATABASE_URL = 'postgresql://localhost:5432/duka_pos_test';
  const module = await import('../index');
  app = module.default;
});

const SECRET = 'test-app-session-secret-of-at-least-32-bytes';

function appSession(overrides: Partial<Parameters<typeof issueAppSession>[0]> = {}): string {
  return issueAppSession({
    subject: 'kc-user-1',
    email: 'owner@example.com',
    secret: SECRET,
    ...overrides,
  }).token;
}

async function http() {
  const supertest = await import('supertest');
  return supertest.default(app);
}

describe('the verify flow is reachable before any token exists', () => {
  it('answers /auth/link rather than 401-ing it', async () => {
    // The whole point: this endpoint runs before the shop has a token, so a
    // 401 here would mean the route was mounted behind the auth layer and
    // onboarding could never start.
    const request = await http();
    const response = await request.post('/api/auth/link').send({
      email: 'owner@example.com',
      pin: '1234',
      shopName: 'Amina Duka',
      ownerName: 'Amina',
    });
    expect(response.status).not.toBe(401);
  });

  it('says verification is not configured instead of half-creating an account', async () => {
    // No realm credentials and no EmailJS keys in this environment. The honest
    // answer is 503 — anything else would either pretend a code was sent or
    // mutate the identity server with defaults.
    const request = await http();
    const response = await request.post('/api/auth/link').send({
      email: 'owner@example.com',
      pin: '1234',
      shopName: 'Amina Duka',
      ownerName: 'Amina',
    });
    expect(response.status).toBe(503);
    expect(response.body.code).toBe('VERIFICATION_NOT_CONFIGURED');
  });

  it('rejects a body that is not a 4-digit PIN before it reaches any of that', async () => {
    const request = await http();
    const response = await request.post('/api/auth/link').send({
      email: 'owner@example.com',
      pin: '12',
      shopName: 'Amina Duka',
      ownerName: 'Amina',
    });
    expect(response.status).toBe(400);
    expect(response.body.error).toBe('Invalid request');
  });

  it('rejects a body that is not an email address', async () => {
    const request = await http();
    const response = await request.post('/api/auth/link').send({
      email: 'not-an-email',
      pin: '1234',
      shopName: 'Amina Duka',
      ownerName: 'Amina',
    });
    expect(response.status).toBe(400);
  });

  it('rejects a verification code that is not six digits', async () => {
    const request = await http();
    const response = await request.post('/api/auth/verify').send({
      email: 'owner@example.com',
      pin: '1234',
      code: '12345',
    });
    expect(response.status).toBe(400);
  });

  it('does not require a token to ask for a new session either', async () => {
    const request = await http();
    const response = await request.post('/api/auth/refresh').send({ refreshToken: 'x'.repeat(40) });
    // 503 (unconfigured) proves it got past the auth layer; 401 would mean
    // refresh is behind a token, which would make it useless.
    expect(response.status).toBe(503);
  });
});

describe('app sessions stop where the till has no business', () => {
  it('may not initiate a payment', async () => {
    process.env.APP_SESSION_SECRET = SECRET;
    const request = await http();
    const response = await request
      .post('/api/payments/initiate')
      .set('Authorization', `Bearer ${appSession()}`)
      .send({});
    expect(response.status).toBe(403);
    expect(response.body.code).toBe('APP_SESSION_NOT_ALLOWED');
  });

  it('may not file a tax invoice', async () => {
    const request = await http();
    const response = await request
      .post('/api/etims/receipts')
      .set('Authorization', `Bearer ${appSession()}`)
      .send({});
    expect(response.status).toBe(403);
    expect(response.body.code).toBe('APP_SESSION_NOT_ALLOWED');
  });

  it('may not touch platform administration', async () => {
    // `/api/system` never reaches `authMiddleware`: it has its own verifier,
    // which accepts only tokens minted by the identity server itself. So an
    // app session is refused at the door, before any tenant exists.
    const request = await http();
    const response = await request
      .get('/api/system/access')
      .set('Authorization', `Bearer ${appSession()}`);
    expect(response.status).toBe(401);
  });

  it('reaches the till’s own routes', async () => {
    const request = await http();
    const response = await request
      .get('/api/tenant/shops')
      .set('Authorization', `Bearer ${appSession()}`);
    // This suite has no database, so the response is a 500 from the data layer
    // — which is the proof that matters: the request got past authentication
    // rather than being refused at the door.
    expect(response.status).toBe(500);
  });

  it('is not accepted at all when the server has no session secret', async () => {
    // Rotation-by-removal: delete the secret and every outstanding session
    // stops verifying, so they fall through to the identity server instead.
    delete process.env.APP_SESSION_SECRET;
    const request = await http();
    const response = await request
      .get('/api/tenant/shops')
      .set('Authorization', `Bearer ${appSession()}`)
      .send();
    expect(response.status).toBe(401);
  });

  it('is not accepted when it has expired', async () => {
    process.env.APP_SESSION_SECRET = SECRET;
    const request = await http();
    const response = await request
      .get('/api/tenant/shops')
      .set('Authorization', `Bearer ${appSession({ now: new Date(Date.now() - 30 * 60 * 60 * 1000) })}`);
    expect(response.status).toBe(401);
  });

  it('is not accepted when signed with the wrong secret', async () => {
    const request = await http();
    const forged = appSession({ secret: 'an-attackers-guess-of-the-secret' });
    const response = await request
      .get('/api/tenant/shops')
      .set('Authorization', `Bearer ${forged}`);
    expect(response.status).toBe(401);
  });
});
