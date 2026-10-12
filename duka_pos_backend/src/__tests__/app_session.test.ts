import { describe, expect, it } from 'vitest';
import {
  APP_SESSION_ISSUER,
  APP_SESSION_TTL_MS,
  appSessionAllowedPrefixes,
  issueAppSession,
  isAppSessionAllowed,
  verifyAppSession,
} from '../lib/app_session';

const SECRET = 'a-secret-of-at-least-32-bytes-xxxxxxxxxx';
const OTHER_SECRET = 'a-different-secret-of-the-same-length';
const NOW = new Date('2026-10-10T12:00:00.000Z');

function issue(overrides: Partial<Parameters<typeof issueAppSession>[0]> = {}) {
  return issueAppSession({
    subject: 'kc-user-1',
    email: 'owner@example.com',
    secret: SECRET,
    now: NOW,
    ...overrides,
  });
}

describe('app session issuance', () => {
  it('carries the claims the middleware needs and nothing else', () => {
    const { claims } = issue();
    expect(claims.sub).toBe('kc-user-1');
    expect(claims.email).toBe('owner@example.com');
    expect(claims.email_verified).toBe(true);
    expect(claims.token_use).toBe('app_session');
    expect(claims.iss).toBe(APP_SESSION_ISSUER);
    expect(claims.exp - claims.iat).toBe(APP_SESSION_TTL_MS / 1000);
  });

  it('produces a three-part token signed with the secret', () => {
    expect(issue().token.split('.')).toHaveLength(3);
    // The same inputs with the same jti would collide, but the token must at
    // least differ from one signed with another secret.
    expect(verifyAppSession(issue().token, [OTHER_SECRET], NOW)).toBeNull();
  });
});

describe('app session verification', () => {
  it('accepts a token it issued', () => {
    const { token, claims } = issue();
    expect(verifyAppSession(token, [SECRET], NOW)).toEqual(claims);
  });

  it('accepts any of several secrets, so rotation does not log everyone out at once', () => {
    const { token } = issue();
    expect(verifyAppSession(token, [OTHER_SECRET, SECRET], NOW)).not.toBeNull();
  });

  it('refuses when no secret is configured rather than accepting anything', () => {
    const { token } = issue();
    expect(verifyAppSession(token, [], NOW)).toBeNull();
  });

  it('refuses an expired session', () => {
    const { token } = issue();
    expect(verifyAppSession(token, [SECRET], new Date(NOW.getTime() + APP_SESSION_TTL_MS + 1000))).toBeNull();
  });

  it('refuses a session from the future', () => {
    const { token } = issue();
    expect(verifyAppSession(token, [SECRET], new Date(NOW.getTime() - 10 * 60_000))).toBeNull();
  });

  it('refuses a token with the signature stripped off', () => {
    const { token } = issue();
    const [header, payload] = token.split('.');
    expect(verifyAppSession(`${header}.${payload}.`, [SECRET], NOW)).toBeNull();
  });

  it('refuses a payload edited after issue', () => {
    const { token } = issue();
    const [header, , signature] = token.split('.');
    const forged = Buffer.from(JSON.stringify({ sub: 'someone-else', email: ' attacker@example.com', email_verified: true, token_use: 'app_session', iat: claims_iat(NOW), exp: claims_iat(NOW) + 3600, jti: 'x', iss: APP_SESSION_ISSUER }))
      .toString('base64url');
    expect(verifyAppSession(`${header}.${forged}.${signature}`, [SECRET], NOW)).toBeNull();
  });

  it('refuses a token that is not one of ours by shape', () => {
    expect(verifyAppSession('not-a-token', [SECRET], NOW)).toBeNull();
    expect(verifyAppSession('a.b', [SECRET], NOW)).toBeNull();
  });

  it('refuses a token that claims an unverified email', () => {
    // Minted only by a verified link: a payload that says otherwise is a
    // forgery attempt, and every consumer treats the address as verified.
    const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
    const body = Buffer.from(
      JSON.stringify({
        sub: 'kc-user-1',
        email: 'owner@example.com',
        email_verified: false,
        token_use: 'app_session',
        iat: claims_iat(NOW),
        exp: claims_iat(NOW) + 3600,
        jti: 'x',
        iss: APP_SESSION_ISSUER,
      }),
    ).toString('base64url');
    const signing = `${header}.${body}`;
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { createHmac } = require('node:crypto') as typeof import('node:crypto');
    const signature = createHmac('sha256', SECRET).update(signing, 'utf8').digest('base64url');
    expect(verifyAppSession(`${signing}.${signature}`, [SECRET], NOW)).toBeNull();
  });
});

function claims_iat(date: Date): number {
  return Math.floor(date.getTime() / 1000);
}

describe('app session scope', () => {
  it('reaches what the till needs', () => {
    expect(isAppSessionAllowed('/tenant/settings')).toBe(true);
    expect(isAppSessionAllowed('/tenant/portfolio')).toBe(true);
    expect(isAppSessionAllowed('/products/sync')).toBe(true);
    expect(isAppSessionAllowed('/reports/sales')).toBe(true);
  });

  it('does not reach the surfaces that move money or speak to KRA', () => {
    for (const path of ['/payments/initiate', '/etims/receipts', '/system/tenants', '/auth/verify', '/staff/whatever']) {
      expect(isAppSessionAllowed(path)).toBe(false);
    }
  });

  it('the allowlist is a short, named list rather than a wildcard', () => {
    expect(appSessionAllowedPrefixes().every((prefix) => prefix.startsWith('/'))).toBe(true);
    expect(appSessionAllowedPrefixes().length).toBeLessThanOrEqual(4);
  });
});
