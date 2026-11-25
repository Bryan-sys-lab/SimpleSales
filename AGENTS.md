# Agent guide

## Repository map and source of truth

- The backend Worker is in [`duka_pos_backend/`](./duka_pos_backend/). Its
  deployed entry point and bindings are defined by
  [`wrangler.jsonc`](./duka_pos_backend/wrangler.jsonc).
- The nested
  [`duka_pos_backend/cloudflare/`](./duka_pos_backend/cloudflare/) package has
  a separate container Worker configuration. Do not use it to build or deploy
  the API Worker unless the task specifically concerns that container.
- On the `cloudflare` branch, `duka_pos_app/` has no tracked source files.
  The Flutter CI and release workflows are present, but app changes require the
  branch or checkout that contains the app source.
- For backend behavior and deployment, prefer the current code, Wrangler
  configuration, CI workflow, and
  [`ENVIRONMENT.md`](./duka_pos_backend/ENVIRONMENT.md) over old setup or
  hosting examples in the backend README.

## Before changing files

- Check `git status --short --branch`; preserve and work around user changes.
- Keep changes focused. Do not stage `.wrangler/`, `.dev.vars`, `.env*`, build
  outputs, or generated secrets.
- Use the backend's pinned dependencies and lockfile. It requires Node.js 26
  or newer; install with `npm ci`, not an ad-hoc dependency upgrade.
- Do not copy tokens or secret values into source, command arguments, logs,
  documentation, or commits.

## Backend development

From `duka_pos_backend/`:

```powershell
npm ci
npx prisma generate
npm run dev
```

`npm run dev` runs the Express development entry point and needs its local
environment/database configured. For Worker-specific behavior and Cloudflare
bindings, use Wrangler in local mode:

```powershell
npx wrangler dev --local --config wrangler.jsonc
```

Use local bindings by default. A `--remote` D1/R2 operation or a deployed
staging test changes real Cloudflare resources; confirm the target and task
authorization first.

## Backend checks

Run the smallest relevant checks, then broaden as needed:

```powershell
npx prisma generate
npm run build
npm test
npm run lint
```

`npm test` runs the Vitest suite. To check D1 locally, apply the checked-in
Wrangler migrations to the local database and compare its schema:

```powershell
npx wrangler d1 migrations apply duka-pos-prod --local --config wrangler.jsonc
node scripts/check-d1-schema.mjs --local
```

The schema check requires exactly one target (`--local` or `--remote`) and
compares D1 tables, columns, and migration history against Prisma and the
versioned SQL migrations in `prisma/migrations-d1/`. Cloudflare D1 deployments
use Wrangler migrations; do not substitute `prisma migrate deploy`.

The live journey scripts are remote integration tests, not unit tests:

```powershell
npm run test:live
npm run test:live:auth
npm run test:live:admin-writes
npm run test:live:analytics
npm run test:live:backup
```

They must target the configured staging Worker and use the ephemeral
`STAGING_AUTH_TEST_SECRET` and `STAGING_ADMIN_TEST_TOKEN`. The scripts are
restricted to staging and write test data there. Never point them at production.
The auth journey tests voucher issuance/claiming; do not add a second email
send to its synthetic `@example.com` account in the admin-write journey. That
address can be suppressed after a bounce. Use a configured owned test inbox for
any additional live delivery test, or cover the behavior with a mocked email
transport.

## Cloudflare environments and deployment

- The default Wrangler environment is production: Worker `duka-pos-backend`,
  D1 `duka-pos-prod`, R2 `duka-pos-backups` and
  `duka-pos-profile-photos`.
- `--env staging` targets the isolated Worker `duka-pos-backend-staging`, D1
  `duka-pos-staging`, and R2 `duka-pos-backups-staging` and
  `duka-pos-profile-photos-staging`.
- D1 and R2 bindings must be listed in each Wrangler environment; do not
  assume top-level bindings are inherited by staging.
- `wrangler secret put` deploys a new Worker version immediately. Keep
  secrets out of shell history and output, and do not change production
  secrets during ordinary development.

The authoritative backend release process is
[`ci-backend.yml`](./.github/workflows/ci-backend.yml):

1. A push to `cloudflare` that changes backend files runs build/type-check,
   Prisma validation, dependency audits, and tests.
2. CI applies and checks local D1 migrations.
3. The deployment job applies staging migrations, sets run-scoped auth test
   credentials, deploys to staging, and runs the live journeys.
4. Only after those checks pass does it validate and migrate production D1,
   then deploy the production Worker.

**A successful push to `cloudflare` can promote to production.** Do not push
or dispatch this workflow unless production promotion is intended. A pull
request validates but does not run the production promotion job.

For manual backend work, [`deploy-cloudflare.ps1`](./duka_pos_backend/scripts/deploy-cloudflare.ps1)
without `-PromoteProduction` performs preflight checks and does not change
production. Promotion requires that switch and a passing staging gate. Check
`/health` and `/ready` after a deployment. Do not deploy production directly
with Wrangler as a shortcut around CI.

## App CI and release

The Flutter workflow [`ci.yml`](./.github/workflows/ci.yml) runs
`flutter analyze --fatal-infos`, `flutter test --reporter expanded`, and a
debug APK build for app changes on `main`. The release workflow
[`release.yml`](./.github/workflows/release.yml) is tag-driven: a `v*` tag
must point to `main` and match the app's `pubspec.yaml` version. It builds a
signed APK and requires the configured signing secrets. Read that workflow
before changing release behavior.
