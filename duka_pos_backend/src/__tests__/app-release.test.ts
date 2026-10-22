// The release manifest route.
//
// The property that matters is not LYING to a handset: a malformed manifest
// must read as "no release", never as a release with build 0. Build 0 is lower
// than every real build, so a handset would conclude it was already up to date
// and would never be prompted — a failure invisible everywhere except here.

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import express from 'express';
import request from 'supertest';

import appReleaseRoutes from '../routes/app-release';

/** An app mounting only the route under test. */
function app() {
  return express().use(appReleaseRoutes);
}

describe('app release manifest', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'release-'));
    process.env.APP_RELEASE_DIR = dir;
    process.env.APP_RELEASE_MANIFEST = 'current.json';
  });

  afterEach(async () => {
    delete process.env.APP_RELEASE_DIR;
    delete process.env.APP_RELEASE_MANIFEST;
    await rm(dir, { recursive: true, force: true });
  });

  it('serves a well-formed manifest', async () => {
    await writeFile(
      join(dir, 'current.json'),
      JSON.stringify({
        build: 7,
        version: '2.1.0',
        downloadUrl: 'https://example.com/app.apk',
        notes: 'Receipts print faster',
      }),
    );

    const response = await request(app()).get('/api/app/latest').expect(200);

    expect(response.body.build).toBe(7);
    expect(response.body.version).toBe('2.1.0');
    expect(response.body.downloadUrl).toBe('https://example.com/app.apk');
    expect(response.body.notes).toBe('Receipts print faster');
  });

  it('is cacheable, because a manifest changes only on release', async () => {
    await writeFile(
      join(dir, 'current.json'),
      JSON.stringify({
        build: 7,
        version: '2.1.0',
        downloadUrl: 'https://x/a.apk',
      }),
    );

    const response = await request(app()).get('/api/app/latest').expect(200);

    expect(response.headers['cache-control']).toContain('max-age');
  });

  it('answers 404 when nothing is published', async () => {
    await request(app()).get('/api/app/latest').expect(404);
  });

  it('refuses a manifest whose build is not a positive integer', async () => {
    // THE case: build 0 is lower than every real build, so a handset would
    // conclude it was up to date and would never be prompted.
    await writeFile(
      join(dir, 'current.json'),
      JSON.stringify({
        build: 0,
        version: '2.1.0',
        downloadUrl: 'https://x/a.apk',
      }),
    );

    await request(app()).get('/api/app/latest').expect(503);
  });

  it('refuses a manifest with no download URL', async () => {
    await writeFile(
      join(dir, 'current.json'),
      JSON.stringify({ build: 7, version: '2.1.0' }),
    );

    await request(app()).get('/api/app/latest').expect(503);
  });

  it('refuses a manifest that is not JSON at all', async () => {
    await writeFile(join(dir, 'current.json'), '<html>login page</html>');

    await request(app()).get('/api/app/latest').expect(503);
  });
});
