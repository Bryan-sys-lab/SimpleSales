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

let app: Express;

beforeAll(async () => {
  process.env.NODE_ENV = 'test';
  process.env.OIDC_ISSUER_URL = 'https://id.example.test/realms/duka';
  process.env.OIDC_AUDIENCE = 'duka-api';
  process.env.DATABASE_URL = 'postgresql://localhost:5432/duka_pos_test';
  const module = await import('../index');
  app = module.default;
});

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
      pin: '123456',
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
      pin: '123456',
      shopName: 'Amina Duka',
      ownerName: 'Amina',
    });
    expect(response.status).toBe(503);
    expect(response.body.code).toBe('VERIFICATION_NOT_CONFIGURED');
  });

  it('rejects a body that is not a 6-digit PIN before it reaches any of that', async () => {
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

  it('refuses a four-digit admin PIN, because the admin PIN is six', async () => {
    // The owner's PIN is an ADMIN PIN: it is asked for in front of the things
    // it guards — deleting the account, changing the shop's settings — and a
    // four-digit admin PIN is a password somebody can guess while they wait
    // for the till to think.
    //
    // A STAFF PIN is still four digits. It is a different PIN, typed forty
    // times a day at a counter, and it never comes here.
    const request = await http();
    // Its OWN address: the link route is rate-limited per address, and this
    // is a test about the body, not about the limit. Sharing an address with
    // the cases above would make it the case that trips the limit.
    const response = await request.post('/api/auth/link').send({
      email: 'four-digits@example.com',
      pin: '1234',
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
      pin: '123456',
      shopName: 'Amina Duka',
      ownerName: 'Amina',
    });
    expect(response.status).toBe(400);
  });

  it('rejects a verification code that is not six digits', async () => {
    const request = await http();
    const response = await request.post('/api/auth/verify').send({
      email: 'owner@example.com',
      pin: '123456',
      code: '12345',
    });
    expect(response.status).toBe(400);
  });

  it('has no refresh endpoint, because there is no session of ours to refresh', async () => {
    // The credential is Keycloak's, and Keycloak refreshes it. A refresh
    // endpoint here would be a second session with a second lifetime, and the
    // one thing this service must not have is a credential of its own.
    //
    // The route is not there, so the request is REFUSED: it falls through the
    // auth router to the token middleware, which has no token to give it.
    // What matters is that it is not ANSWERED — no 200, and no 503 pretending
    // the server is merely unconfigured.
    const request = await http();
    const response = await request.post('/api/auth/refresh').send({ refreshToken: 'x'.repeat(40) });
    expect([401, 404]).toContain(response.status);
    expect(response.body.access_token).toBeUndefined();
    expect(response.body.refresh_token).toBeUndefined();
  });
});
