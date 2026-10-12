// The operator dashboard's HTTP surface.
//
// What is asserted here is what an operator would report as a bug:
//
//   1. `/admin` serves a page, and the page's own asset URLs resolve — a link
//      to a file that does not exist is a dashboard with no styling, which is
//      the first thing anyone notices.
//   2. The page never carries a token: no `Authorization` header is set from
//      the HTML, and no token is echoed into it. The HTML is static, so this
//      reads like a tautology until someone adds a `?token=` support shortcut.
//   3. `/api/system/*` is unreachable without a platform-operator token, and
//      with a tenant token — not just any valid OIDC token.

import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
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

describe('the dashboard shell', () => {
  it('serves the page at /admin', async () => {
    const request = await http();
    const response = await request.get('/admin');
    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toContain('text/html');
  });

  it('is a page with a title, a sign-in and no inline token', async () => {
    const request = await http();
    const response = await request.get('/admin');
    const html = String(response.text);
    expect(html).toContain('<title>SimpleSales operator</title>');
    expect(html).toContain('id="signin"');
    // The page is static HTML: it must not embed a token, a key or a DSN. A
    // `?token=` support shortcut here would put an operator's bearer token
    // into browser history and every access log in between. The form's own
    // label is allowed to say "Bearer token" — that is a prompt, not a value.
    for (const forbidden of [
      /eyJ[A-Za-z0-9_-]{10,}/, // a JWT, ever
      /AKIA[0-9A-Z]{16}/, // an AWS key
      /sk_[A-Za-z0-9]{16,}/, // a provider secret
      /service_[A-Za-z0-9]{16,}/, // an EmailJS service id
    ]) {
      expect(html).not.toMatch(forbidden);
    }
    // And it never sets the header itself: that is the script's job, at
    // request time, from a token that is never written to disk by this file.
    expect(html).not.toMatch(/headers\s*:/);
  });

  it('is no-cache, so an operator never reads last week’s numbers', async () => {
    const request = await http();
    const response = await request.get('/admin');
    // A cached copy of a page whose backend changed is a page lying.
    expect(response.headers['cache-control']).toContain('no-cache');
  });

  it('serves the stylesheet the page links to', async () => {
    const request = await http();
    const page = await request.get('/admin');
    const href = /href="([^"]+\.css)"/.exec(String(page.text))?.[1];
    expect(href).toBeTruthy();
    const response = await request.get(href!);
    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toContain('text/css');
    // A dashboard whose stylesheet is empty is a dashboard with no design.
    expect(String(response.text).length).toBeGreaterThan(500);
  });

  it('serves the script the page links to', async () => {
    const request = await http();
    const page = await request.get('/admin');
    const src = /src="([^"]+\.js)"/.exec(String(page.text))?.[1];
    expect(src).toBeTruthy();
    const response = await request.get(src!);
    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toContain('javascript');
    // The page is inert without its script, so a blank script is a broken
    // dashboard rather than a graceful degradation.
    expect(String(response.text).length).toBeGreaterThan(500);
  });

  it('never renders a listing', async () => {
    const request = await http();
    const response = await request.get('/admin/');
    // A listing would be an index of every file in the assets directory,
    // which is a map of the surface for anyone who adds a trailing slash.
    // The page's own <script src="/admin/dashboard.js"> is not a listing, so
    // the check is for what a listing actually looks like.
    expect(String(response.text ?? '')).not.toContain('Index of');
    expect(String(response.text ?? '')).not.toContain('Parent Directory');
  });

  it('renders no design notes as page text', async () => {
    // The preamble is an HTML comment, so a browser shows the heading and not
    // a paragraph of architecture notes above it. The doctype is the first
    // thing in the file, so a comment before it cannot put the browser into
    // quirks mode either.
    const request = await http();
    const response = await request.get('/admin');
    expect(String(response.text).trimStart().startsWith('<!DOCTYPE html>')).toBe(true);
    expect(String(response.text)).not.toContain('<body>//');
  });

  it('rejects an asset that does not exist, with a code', async () => {
    const request = await http();
    const response = await request.get('/admin/nope.css');
    expect(response.status).toBe(404);
    expect(response.body.code).toBe('ASSET_NOT_FOUND');
  });

  it('rejects a path that tries to escape the assets directory', async () => {
    const request = await http();
    const response = await request.get('/admin/..%2f..%2fpackage.json');
    // Sanitised to alphanumerics before any lookup, so it is a 404 rather
    // than a traversal that reads the repository.
    expect(response.status).toBe(404);
  });
});

describe('the page and its sources agree', () => {
  it('links only assets that exist on disk', async () => {
    // The one failure that survives every unit test: an HTML file edited to
    // point at a stylesheet that was renamed. Reading the repo, not the
    // running server, so this catches it before a deployment does.
    const dir = join(__dirname, '..', 'public');
    const html = await readFile(join(dir, 'dashboard.html'), 'utf8');
    const referenced = [
      ...html.matchAll(/(?:href|src)="\/([^"]+)"/g),
    ].map((match) => match[1]);
    expect(referenced.length).toBeGreaterThan(0);
    for (const asset of referenced) {
      const name = asset.split('/').pop()!;
      const present = await readFile(join(dir, name), 'utf8')
        .then(() => true)
        .catch(() => false);
      expect(present, `${asset} is referenced by the page but missing`).toBe(true);
    }
  });

  it('calls only endpoints that exist', async () => {
    // A page that calls an endpoint nobody routes is a page whose tables are
    // silently empty, which looks exactly like "the platform has no shops".
    const js = await readFile(join(__dirname, '..', 'public', 'dashboard.js'), 'utf8');
    const called = [...js.matchAll(/api\(\s*`([^`]+)`/g)].map((match) => match[1]);
    expect(called.length).toBeGreaterThan(0);
    const known = [
      '/api/system/analytics',
      '/api/system/analytics/drilldown',
      '/api/system/users',
      '/api/system/observability',
    ];
    for (const path of called) {
      // The template's query string is stripped before matching.
      const base = path.split('?')[0].replace('${query}', '').replace(/\/$/, '');
      expect(known, `${base} is not an endpoint this service routes`).toContain(base);
    }
  });
});

describe('platform administration is not reachable from the dashboard page', () => {
  it('refuses an unauthenticated system analytics read', async () => {
    const request = await http();
    const response = await request.get('/api/system/analytics');
    expect(response.status).toBe(401);
  });

  it('refuses a forged token, rather than trusting the page’s own origin', async () => {
    // A token this server did not issue is refused even though the request is
    // same-origin: the allowlist is the platform's, not the browser's.
    const request = await http();
    const response = await request
      .get('/api/system/analytics')
      .set('Authorization', 'Bearer not-a-real-token');
    expect(response.status).toBe(401);
  });

  it('refuses an app session, which is a till’s session and not an operator’s', async () => {
    const { createHmac, randomBytes } = await import('node:crypto');
    const secret = 'system-dashboard-test-secret-of-32-bytes-xxxxx';
    process.env.APP_SESSION_SECRET = secret;
    const b64 = (value: Buffer | string) =>
      Buffer.from(value as never)
        .toString('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/, '');
    const claims = {
      sub: 'kc-subject-1',
      email: 'owner@example.com',
      email_verified: true,
      token_use: 'app_session',
      iss: 'simplesales-app',
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 3600,
      jti: randomBytes(8).toString('hex'),
    };
    const body = `${b64(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))}.${b64(JSON.stringify(claims))}`;
    const token = `${body}.${createHmac('sha256', secret).update(body, 'utf8').digest('base64url')}`;

    const request = await http();
    const response = await request
      .get('/api/system/analytics')
      .set('Authorization', `Bearer ${token}`);
    expect(response.status).toBe(401);
    delete process.env.APP_SESSION_SECRET;
  });
});
