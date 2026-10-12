// The dashboard shell, served from the API.
//
// It is served by the API rather than by a static host for one reason: the
// page's only backend is this service, and a separate origin would mean a
// CORS negotiation, a second deployment to keep in step, and a second place
// for an operator to wonder which version they are looking at. `/admin` here
// and `/api/system/*` beside it are one origin by construction.
//
// The HTML is read from disk at boot and served from memory. Reading it per
// request would mean a filesystem hit on every dashboard load; inlining it
// into the bundle would mean the file an operator sees stop being the file in
// the repository.

import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Router, Request, Response } from 'express';

const router = Router();

// `dashboard.ts` compiles to `dist/routes/dashboard.js`, and `npm run build`
// copies `src/public` to `dist/public`, so `dist/public` is where the assets
// live in a deployment. `__dirname` is available because this package compiles
// to CommonJS, and using it rather than a path relative to the working
// directory means the dashboard can be started from anywhere.
//
// `src/public` is the fallback, so a `tsx watch src/index.ts` developer
// session serves the same page without a build step.
const builtPublicDir = join(__dirname, '..', 'public');
const sourcePublicDir = join(__dirname, '..', '..', 'src', 'public');

/**
 * Reads one asset, preferring the built copy and falling back to the source.
 *
 * The fallback exists so the flow "edit the HTML, reload the browser" works in
 * development — the one flow a dashboard without a build step is supposed to
 * have. A deployment always has the built copy.
 */
function readAsset(name: string): Promise<string> {
  return readFile(join(builtPublicDir, name), 'utf8').catch(() =>
    readFile(join(sourcePublicDir, name), 'utf8'),
  );
}

/** Cache-control headers for the static assets. */
function asset(response: Response) {
  // No-cache, not no-store: the page is small, and an operator who has a
  // cached copy from before a deployment is an operator reading last week's
  // numbers and believing them.
  response.setHeader('Cache-Control', 'no-cache, must-revalidate');
  return response;
}

/**
 * Each asset read once, memoised.
 *
 * The only failure mode is a missing file, which is a deployment error: the
 * operator is told the dashboard is unavailable rather than being served a
 * blank page that looks like a platform outage.
 */
const files: Record<string, Promise<string>> = {
  'dashboard.html': readAsset('dashboard.html'),
  'dashboard.css': readAsset('dashboard.css'),
  'dashboard.js': readAsset('dashboard.js'),
};

const TYPES: Record<string, string> = {
  'dashboard.html': 'text/html; charset=utf-8',
  'dashboard.css': 'text/css; charset=utf-8',
  'dashboard.js': 'text/javascript; charset=utf-8',
};

router.get('/', (_req: Request, res: Response) => {
  files['dashboard.html']
    .then((html) => {
      asset(res).setHeader('Content-Type', TYPES['dashboard.html']);
      res.status(200).send(html);
    })
    .catch((error: unknown) => {
      res.status(500).json({
        error: 'The dashboard is not available in this deployment',
        code: 'DASHBOARD_UNAVAILABLE',
        detail: error instanceof Error ? error.message : 'unknown',
      });
    });
});

router.get('/:asset', (req: Request, res: Response) => {
  const name = (req.params.asset ?? '').replace(/[^a-zA-Z0-9._-]/g, '');
  const promise = files[name];
  if (!promise) {
    res.status(404).json({ error: 'No such asset', code: 'ASSET_NOT_FOUND' });
    return;
  }
  promise
    .then((body) => {
      asset(res).setHeader('Content-Type', TYPES[name]);
      res.status(200).send(body);
    })
    .catch(() => {
      res.status(500).json({ error: 'The dashboard is not available in this deployment', code: 'DASHBOARD_UNAVAILABLE' });
    });
});

export default router;
