# Deployment environment

## Cloudflare Worker (backend)

The backend uses Cloudflare D1 for relational data. `wrangler.jsonc` binds the
production and staging databases as `DB`; apply versioned SQL migrations with
Wrangler, not `prisma migrate deploy`. Cloudflare R2 remains the object store
for profile photos and encrypted backups.

Set these as Worker secrets (or via `wrangler secret put`):

- `AUTH_JWT_SECRET` — HS256 signing secret, >=32 random bytes (base64)
- `AUTH_JWT_SECRET_PREVIOUS` — previous secret during rotation (optional)
- `EMAIL_VERIFICATION_SECRET` — HMAC key for verification codes
- `PUBLIC_API_URL` — public worker URL, e.g. https://duka-pos-backend.<account>.workers.dev
- `SYSTEM_ADMIN_SUBJECTS` — comma-separated User.id values granted system admin
- `APP_VERSION_NAME`, `APP_VERSION_CODE`, `APP_DOWNLOAD_URL`, `APP_UPDATE_REQUIRED`, `APP_RELEASE_NOTES`, `APP_RELEASE_REPOSITORY` — app update manifest

Verification email uses the configured Cloudflare `EMAIL` binding. The REST
email API credentials are only needed if the binding is removed. Optional
integrations: `PAYHERO_AUTH_TOKEN`, `PAYHERO_ACCOUNT_ID`, `MPESA_CALLBACK_KEY`,
`R2_*`, `TAX_*`, `RISITI_*`.

The central PayHero integration must not enable merchant channel registration
or STK collection until PayHero confirms in writing that merchant-owned
destinations registered under the SimpleSales account settle to those
merchants, and confirms the callback/status evidence used to verify amount.
The deployment config forwards these non-secret gates to the container:
`PAYHERO_CHANNEL_SETTLEMENT_CONFIRMED` and
`PAYHERO_AMOUNT_VERIFICATION_CONFIRMED`. Both default to `false`. Do not set
either to `true` without the corresponding PayHero confirmation. The
system-admin-only `GET /api/system/payhero/configuration` endpoint reports
whether credentials/account identity and the gates are configured; it never
returns credential values.

The production Worker binds `BACKUP_BUCKET` to `duka-pos-backups` and
`PROFILE_IMAGE_BUCKET` to `duka-pos-profile-photos`. The app's Cloudflare
backup flow encrypts a snapshot of every local workspace table on-device,
uploads only ciphertext to the backup bucket, and keeps tenant/workspace
metadata in D1. Manual backups are available in Settings; the opt-in automatic
sync also retries cloud backups while the app is open. These are currently
device-bound backups: the AES key stays in that installation's OS keystore, so
the R2 copy cannot be decrypted after reinstalling the app or moving to a
replacement device. The separate `.duka` export remains an encrypted
inventory-only local file.

Profile-photo and sale-evidence existence checks and deletions use the
`PROFILE_IMAGE_BUCKET` binding in production. Their direct-upload/download
URLs remain signed with the configured `R2_*` S3-compatible credentials.

### Safe local deployment (Windows)

From `duka_pos_backend`, run `.\scripts\deploy-cloudflare.ps1`. The script runs
the backend test suite and build and verifies the staging D1 schema. It refuses
to proceed while Prisma `$transaction` call sites remain: the D1 adapter does
not make those operations atomic. The default run is preflight-only and never
changes production. Production promotion additionally requires an HTTPS
`STAGING_BASE_URL` whose hostname contains `staging`, passes live smoke and
authenticated staging journeys, and must be requested explicitly with
`.\scripts\deploy-cloudflare.ps1 -PromoteProduction`.

The authenticated staging journeys create test accounts and need the isolated
staging Worker configured for test verification. In staging only,
`VERIFICATION_DEBUG_CODES=true` enables returning the challenge and first
voucher to the auth test, and the response is gated by the
`STAGING_AUTH_TEST_SECRET` request header. The GitHub Actions workflow creates
a fresh random value for each run and writes it to the staging Worker; do not
store a persistent copy as a GitHub Actions secret. Never enable test-only
verification responses in production.

Staging encrypted-backup journeys use the isolated
`duka-pos-backups-staging` R2 bucket through the `BACKUP_BUCKET` binding.

On `cloudflare` pushes, the promotion job waits for backend tests and local D1
migration/schema checks, deploys to staging, and runs its live journeys before
production migration or deployment. It can also be started manually on that
branch. A missing staging auth-test secret or any failed journey stops the job
before production. Configure the public staging origin as the GitHub
repository variable `STAGING_BASE_URL`.

The backend GitHub Actions deployment uses only these Cloudflare settings:

- Repository secret `CLOUDFLARE_API_TOKEN`: the backend deployment token used
  for remote D1 migrations, staging Worker secrets, and Worker deployments.
  Scope it to the target account with D1 Write and Workers Scripts Write (or
  Workers Editor) permissions. Add Workers Routes Write only if the deployment
  changes routes or custom domains.
- Repository variable `CLOUDFLARE_ACCOUNT_ID`: the Cloudflare account ID; this
  is an identifier, not a secret.
- Repository variable `STAGING_BASE_URL`: the staging Worker origin used by
  the promotion checks.

`CLOUDFLARE_ADMIN_API_TOKEN` is a separate credential used only by the Admin
Worker workflow. Do not use it as the backend deployment token.

Each successful backend promotion uses `package.json`'s semantic version as
`BACKEND_VERSION_NAME`, GitHub Actions' monotonically increasing run number as
`BACKEND_VERSION_CODE`, and the pushed commit's short SHA as
`BACKEND_COMMIT_SHA`. The backend version is shown by `/health` and in the
Cloudflare deployment message; app update fields (`APP_VERSION_*`) remain
independent.

Authenticate Wrangler once with `wrangler login`; this uses the browser-based
OAuth flow and keeps deployment credentials out of scripts, command history,
and environment files. Do not pass an API token on a command line or store one
in this repository. The account token previously pasted into chat should be
revoked and must not be used by the deploy script.

The deployment script checks only `AUTH_JWT_SECRET` and
`EMAIL_VERIFICATION_SECRET` by name. Configure secret values in Cloudflare's
Worker Secrets UI; the script never changes them.

## GitHub Actions (app release)

Set these repository secrets:

- `BACKEND_URL` — deployed worker URL + `/api`, e.g. https://duka-pos-backend.<account>.workers.dev/api
- `SENTRY_DSN` (optional)

The release workflow injects `BACKEND_URL` via `--dart-define=BACKEND_URL=...`.

## Verification

After deploy, run:

```
curl -s https://<worker>/health
curl -s -X POST https://<worker>/api/auth/link -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"123456","shopName":"Shop","ownerName":"Owner"}'
```
EOF