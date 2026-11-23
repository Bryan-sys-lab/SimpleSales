# Admin authentication and operations setup

## Required environment

Configure the **backend Worker** with a private `SYSTEM_ADMIN_TOKEN` secret and `AUTH_JWT_SECRET`. Set `SYSTEM_ADMIN_EMAIL=brian@nerva.co.ke` and `ADMIN_APP_ORIGIN=https://simpleranalytics.nerva.co.ke` as backend Worker variables. Configure the admin Worker with server-only `ADMIN_BACKEND_URL` pointing at the backend origin.

For production, generate a high-entropy token locally and place it in a temporary,
access-restricted JSON file with the `SYSTEM_ADMIN_TOKEN` property. From the
backend project directory, pass that file to the guarded promotion script:

```powershell
.\scripts\deploy-cloudflare.ps1 -PromoteProduction -SystemAdminTokenFile <path-to-protected-json>
```

The script uploads the token with the final backend deployment, after staging
journeys, production migration, and schema checks pass. This avoids the immediate
deployment that `wrangler secret put` would otherwise trigger. Do not put the
token in the admin Worker, a `NEXT_PUBLIC_` variable, source control, or a browser
setting. The super-admin email is fixed by `SYSTEM_ADMIN_EMAIL`; the first
administrator signs in with that email and the backend secret.

Department credentials are minted from **Admin access**. A key is shown once, is bound to its invited email and phone, and expires after its configured lifetime. Revoke lost keys from the access roster. Delegated managers can only invite into their department, choose lower roles, and grant permissions and capabilities they already hold.

## Database and deployment

Apply backend Prisma migrations before enabling the new admin screens, then deploy the backend and admin Workers. `SYSTEM_ADMIN_TOKEN` and `AUTH_JWT_SECRET` are Worker secrets and must be set separately in each environment. Keep `ADMIN_BACKEND_URL` on HTTPS outside local development.

The admin session is an HttpOnly, Secure, SameSite cookie with a one-hour lifetime. Browser requests use the same-origin admin proxy; the proxy forwards the bearer token server-side. Session activity replays contain event names, sanitized routes, time, and a tenant-scoped device hash, while crash reports show their bounded diagnostic trail. User-entered telemetry details are not uploaded.
