# Deployment environment

## Cloudflare Worker (backend)

Set these as secrets on the Worker (or via `wrangler secret put`):

- `DATABASE_URL` — Neon Postgres connection string (pooled or direct)
- `AUTH_JWT_SECRET` — HS256 signing secret, >=32 random bytes (base64)
- `AUTH_JWT_SECRET_PREVIOUS` — previous secret during rotation (optional)
- `EMAIL_VERIFICATION_SECRET` — HMAC key for verification codes
- `CLOUDFLARE_ACCOUNT_ID` — 0d995e8087844342ed0da43d9ccd9993
- `CLOUDFLARE_API_TOKEN` — token with Email Sending permission
- `CLOUDFLARE_EMAIL_FROM` — verified sender, e.g. security@nerva.co.ke
- `PUBLIC_API_URL` — public worker URL, e.g. https://duka-pos-backend.<account>.workers.dev
- `SYSTEM_ADMIN_SUBJECTS` — comma-separated User.id values granted system admin
- `APP_VERSION_NAME`, `APP_VERSION_CODE`, `APP_DOWNLOAD_URL`, `APP_UPDATE_REQUIRED`, `APP_RELEASE_NOTES`, `APP_RELEASE_REPOSITORY` — app update manifest

Optional integrations: `PAYHERO_AUTH_TOKEN`, `PAYHERO_ACCOUNT_ID`, `MPESA_CALLBACK_KEY`, `R2_*`, `TAX_*`, `RISITI_*`.

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