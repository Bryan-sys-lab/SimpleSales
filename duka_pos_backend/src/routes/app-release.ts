// The release the server is currently serving to handsets.
//
// ## Why this is not part of the API
//
// It is read by the app BEFORE it has a token — a shop that has never signed in
// has no session, and an update prompt on first launch is exactly when a shop
// needs it most. Mounting this behind `authMiddleware` would make the update
// check fail for every user who is not yet signed in.
//
// ## Why the manifest is a file and not a database table
//
// The APK itself is a build artefact produced by CI, not by this service. A row
// in a table would have to be written by a deploy of the backend, which would
// mean an app release could not be published without a backend release — and
// would couple the two lifecycles for no benefit.
//
// The file is written by the release pipeline into a directory this route reads.
// Publishing an app version is then a matter of writing one JSON file, with no
// redeploy of anything.

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';

import express, { type Request, type Response } from 'express';

const router = express.Router();

/**
 * Where the release manifest lives.
 *
 * Read per REQUEST rather than captured at module scope, so the directory can
 * be pointed somewhere else without re-importing the module. A directory rather
 * than a single file, so more than one build can be staged and a bad one rolled
 * back without touching this code.
 */
function manifestPath(): string {
  const dir = process.env.APP_RELEASE_DIR || '/var/lib/daka/releases';
  const file = process.env.APP_RELEASE_MANIFEST || 'current.json';
  return join(dir, file);
}

interface ReleaseManifest {
  build: number;
  version: string;
  downloadUrl: string;
  notes?: string;
  required?: boolean;
  minimumBuild?: number;
}

/**
 * Reads and validates the manifest.
 *
 * Validation is deliberate rather than trusting the file: a malformed manifest
 * should read as "no release available", never as a release with `build: 0`.
 * A build of zero is lower than every real build, so a handset would conclude it
 * was already up to date and the prompt would silently never appear — the exact
 * failure a shop cannot diagnose.
 */
function readManifest(raw: string): ReleaseManifest | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof parsed !== 'object' || parsed === null) return null;
  const record = parsed as Record<string, unknown>;

  if (typeof record.build !== 'number' || !Number.isInteger(record.build) || record.build <= 0) {
    return null;
  }
  if (typeof record.version !== 'string' || record.version.trim() === '') return null;
  if (typeof record.downloadUrl !== 'string' || record.downloadUrl.trim() === '') return null;

  return {
    build: record.build,
    version: record.version.trim(),
    downloadUrl: record.downloadUrl.trim(),
    notes: typeof record.notes === 'string' ? record.notes.trim() : '',
    required: record.required === true,
    minimumBuild:
      typeof record.minimumBuild === 'number' ? record.minimumBuild : undefined,
  };
}

router.get('/api/app/latest', async (_request: Request, response: Response) => {
  const path = manifestPath();
  if (!existsSync(path)) {
    // No manifest at all. Answered as 404 rather than 200-with-nothing, so the
    // client can distinguish "nothing published yet" from "the endpoint broke".
    response.status(404).json({ error: 'no release published' });
    return;
  }

  let raw: string;
  try {
    raw = await readFile(path, 'utf8');
  } catch {
    // A read failure is a server-side fault and says so, rather than being
    // flattened into "no release" — the two need different attention.
    response.status(503).json({ error: 'release manifest unreadable' });
    return;
  }

  const manifest = readManifest(raw);
  if (manifest === null) {
    response.status(503).json({ error: 'release manifest malformed' });
    return;
  }

  // Long cache, because the manifest only changes when a release is published,
  // and a handset that caches it for an hour is a handset that asks less often.
  // `stale-while-revalidate` keeps a shop on a flaky connection working.
  response.setHeader('Cache-Control', 'public, max-age=300, stale-while-revalidate=600');
  response.json(manifest);
});


router.post('/api/app/release', async (request: Request, response: Response) => {
  const token = request.header('x-ci-token');
  if (!process.env.CI_TOKEN || token !== process.env.CI_TOKEN) {
    response.status(401).json({ error: 'unauthorized' });
    return;
  }

  const body = request.body as Record<string, unknown> | undefined;
  const build = body?.build;
  const version = body?.version;
  const downloadUrl = body?.downloadUrl;
  if (
    typeof build !== 'number' ||
    !Number.isInteger(build) ||
    build <= 0 ||
    typeof version !== 'string' ||
    version.trim() === '' ||
    typeof downloadUrl !== 'string' ||
    downloadUrl.trim() === ''
  ) {
    response.status(400).json({ error: 'invalid manifest' });
    return;
  }

  const manifest = {
    build,
    version: version.trim(),
    downloadUrl: downloadUrl.trim(),
    notes: typeof body?.notes === 'string' ? body.notes.trim() : '',
    required: body?.required === true,
    minimumBuild:
      typeof body?.minimumBuild === 'number' ? body.minimumBuild : undefined,
  };

  const path = manifestPath();
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, JSON.stringify(manifest, null, 2), 'utf8');

  response.json({ ok: true, build: manifest.build, version: manifest.version });
});

export default router;
