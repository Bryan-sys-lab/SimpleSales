# Duka POS Backend - Custom TypeScript API

Production-ready TypeScript backend replacing Supabase with Express + Prisma + self-hosted OIDC.

## Why This Approach?

**Keycloak/OIDC for Authentication** instead of building from scratch because:
- ✓ Battle-tested security (JWT handling, session management, password hashing)
- ✓ Built-in OAuth providers (Google, Facebook)
- ✓ Multi-factor authentication
- ✓ Password reset, email verification
- ✓ Free tier: 7,000 active users/month
- ✓ Claims-based auth works perfectly with multi-tenant architecture

**Custom TypeScript Backend** vs Supabase:
- ✓ Full control over business logic
- ✓ Easier to debug and extend
- ✓ No vendor lock-in
- ✓ Can deploy anywhere (AWS, DigitalOcean, Railway)

## Quick Start

```bash
# Install dependencies
npm install

# Setup PostgreSQL database
createdb duka_pos

# Copy environment variables
cp .env.example .env

# Run Prisma migrations
npm run db:push

# Start development server
npm run dev
```

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Flutter App   │────▶│   Keycloak/OIDC  │────▶│  PostgreSQL DB  │
│                 │     │   (JWT Tokens)   │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                                                ▲
         │                                                │
         └────────────────────────────────────────────────┘
                     Express API (Protected)
                     - Tenant management
                     - Product sync
                     - Payment orchestration
```

## Self-hosted Keycloak/OIDC setup

1. Create the Keycloak realm and public mobile client described in `../KEYCLOAK_DEPLOYMENT.md`.
2. Use Authorization Code + PKCE for the Android/iOS client; do not embed a client secret in Flutter.
3. Add `.env` variables:
   ```env
   OIDC_ISSUER_URL=https://id.example.com/realms/duka
   OIDC_AUDIENCE=duka-api
   OIDC_JWKS_URI=https://id.example.com/realms/duka/protocol/openid-connect/certs
   PUBLIC_API_URL=https://api.example.com
   ```

4. Prepare the database:
```bash
npm run db:generate
npm run db:deploy
```

For an existing owner/staff deployment, take a verified backup and run `npm run db:deploy` after following the deployment baseline procedure for the existing database. The chain is additive and re-runnable: `20260929220000_reconcile_legacy_roles` maps the legacy `('owner','staff')` role vocabulary to `('admin','manager','cashier')` and adds every column, table and index the old schema is missing (`deletion_ledger`, the `profiles` OIDC columns, the portion prices and decimal stock). Do not run migrations as the container startup command; legacy databases must be baselined and migrated in a controlled deployment step first.

`npm run db:migrate:roles` is retained for runbooks that reference it, but it only reconciles the role column — prefer the full chain.

## Database Schema

Same as your existing Supabase schema:
- `tenants` - Multi-tenant shops
- `profiles` - Users with shop roles (admin/manager/cashier)
- `products` - Product catalog
- `sales` - Sales records
- `payments` - M-Pesa payment tracking

Prisma enforces tenant isolation in application code instead of PostgreSQL RLS.

Platform administration is separate from shop administration. Set `SYSTEM_ADMIN_SUBJECTS` for the small, audited set of Keycloak subjects allowed to use `/api/system/users`, `/api/system/analytics`, and cross-tenant backend configuration. Shop admins cannot grant this privilege.

## API Endpoints

### Tenant Management
- `POST /api/tenant/provision` - Register new shop
- `GET /api/tenant/settings` - Get tenant config
- `GET /api/tenant/shops` - List shops available to the authenticated OIDC owner
- `PATCH /api/tenant/settings` - Update settings (owner only)
- `POST /api/tenant/staff` - Add staff member (owner only)

### Products
- `POST /api/products/sync` - Bulk sync from app
- `GET /api/products` - List all products

### Tax reporting (Risiti by PesaStack; KRA activation pending)
- `POST /api/etims/device` - Reserved for an activated tax deployment (disabled by default)
- `POST /api/etims/receipts` - Submit a recorded sale through the server-side Risiti adapter when activated
- `POST /api/etims/upload` - Upload every outstanding receipt, oldest first (admin/manager)
- `GET /api/etims/status` - How much is outstanding, and whether the device is registered
- `GET /api/etims/z-report` - The end-of-day report for a business date
- `POST /api/etims/z-report` - File that report with KRA only after explicit activation (owner only)
- `GET /api/etims/receipts/:receiptNumber` - A receipt this shop filed
- `GET /api/etims/verify/:receiptNumber` - **Public.** What the QR code on a customer's receipt points at

The default posture is deliberately `TAX_REPORTING_ACTIVATED=false`: sales and VAT
reports continue locally, while no KRA credentials or Risiti API key are used by the
till. When enabled after merchant onboarding, the backend uses Risiti's Platform API
with a server-only `RISITI_API_KEY`, a tenant-scoped `risiti_merchant_id`, stable
external IDs, and idempotency keys. An asynchronous response is only an issued tax
receipt when Risiti reports `submission.terminal && submission.succeeded`; queued
responses remain pending.

### Platform system administration
- `GET /api/system/users` - Active users across all shops (system-admin allowlist only)
- `GET /api/system/analytics` - Cross-tenant aggregate analytics and per-tenant payment breakdowns
- `PATCH /api/system/tenants/:tenantId/settings` - Configure a tenant backend integration

### Payments
- `POST /api/payments/initiate` - Start M-Pesa payment
- `GET /api/payments/status?reference=xxx` - Check payment status

### Webhooks
- `POST /webhooks/payhero-callback` - PayHero callback (no auth)

## Flutter Integration

Replace `backend_service.dart` with:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BackendService {
  static final _dio = Dio(BaseOptions(
    baseUrl: 'https://your-api.com/api',
  ));
  
  static const _storage = FlutterSecureStorage();
  
  static Future<void> setAuthToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
    _dio.interceptors.clear();
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['Authorization'] = 'Bearer $token';
        return handler.next(options);
      }
    ));
  }
  
  // Everything else stays the same, just HTTP calls instead of Supabase SDK
}
```

## Deploy to Production

### Option 1: Railway.app (Easiest)
```bash
railway init
railway add postgresql
railway run -- npm run db:push
railway up
```

### Option 2: AWS
- Use AWS RDS for PostgreSQL
- Deploy to AWS App Runner or EC2
- Set environment variables in AWS console

### Option 3: DigitalOcean
- Use Managed PostgreSQL
- Deploy to App Platform

## eTIMS design notes

The following OSCU notes describe the retained KRA transport seam and are not an
activation claim. The live application path is gated off until the Risiti merchant
and KRA connection have been approved.

### What was implemented, and against what

The integration is written to KRA's **OSCU** (Online Sales Control Unit)
contract — the one KRA documents for a Trader Invoicing System that is always
online. The previous version of this service was written against an invented
REST shape and was wrong at the fundamentals; the corrections are listed below
because each of them would have failed on the first live call.

| | Was | Is |
|---|---|---|
| Base URL | `api.kra.go.ke/invoice/v1` | `etims-api.kra.go.ke/etims-api` (sandbox: `etims-api-sbx.kra.go.ke`) |
| Auth | none; signed with the device key only | bearer token from `/auth/get-token`, plus the device signature |
| Initialisation | `/init-device` | `/init-osdc-info` with `bhfId` + `dvcSrlNo` |
| Filing | `/save-invoice` | `/save-sales-trns` with `salesTrnsItems[]` / `prdtDet[]` |
| Tax | `taxRate: 16` | `taxTyCd: 'V'` |
| Code lists | never called | `/select-code-list` after registration |
| Receipt label | not sent | `rcptLabel` — `NS`/`NC`/`CS`/`CC`/`TS`/`TC`/`PS` |
| Reprint | a second identical sale | filed as `COPY` / `CS` |

**VSCU seam.** Everything KRA-specific is confined to `services/kra.ts`. The
endpoints are named constants and the transport is one `callEndpoint`, so moving
to VSCU — the bulk/offline variant, which is arguably the better fit for a till
that loses signal — is a change to that map rather than a rewrite. The
orchestration in `services/etims.ts` is written against the interface, not
against OSCU.

### Decisions worth knowing

**Money crosses the wire as integer minor units and is stored as `DECIMAL`.**
The till sends cents because that is what it stores and prints; this database
holds `DECIMAL(14,2)` because KRA and the PayHero webhook both speak major
units. The conversion happens once, in `services/etims.ts`, and `toMajor`
**throws** on a fractional minor unit rather than rounding it — a tax invoice out
by a hundred because something upstream sent a float is invisible in review and
fatal at audit. Amounts leaving for KRA are strings, because KRA's schema is
`Decimal`.

**Reprints are COPY receipts.** KRA requires one original receipt and that
reprints be watermarked "Copy". Filing a reprint as `NS` would be a second
claimed original sale, so `labelForSubmission` maps it to `COPY`/`CS` and the
till watermarks the paper to match.

**A receipt row is written before the network call, and never deleted on
failure.** A sale that exists only in the till's memory until KRA answers is a
sale that can be lost. A `pending` row is evidence the invoice is outstanding; a
missing row is indistinguishable from a sale that never happened.

**Refusals and transport failures are opposites.** A KRA refusal is terminal, is
recorded against the receipt with its reason, and stops the upload run — because
a refusal is usually a stale clock, an uninitialised device or a bad TIN, and
none of those improves for the next receipt. A network failure leaves the row
`pending` and is retried. The run stops rather than carrying on precisely so the
device's invoice sequence stays contiguous: KRA rejects a gap, so filing over one
would turn a temporary outage into a permanent compliance gap.

**The Z-report reports its own gaps.** `pending_count` counts receipts the shop
recorded but KRA has not accepted. A Z-report that agreed with itself while
disagreeing with the authority is worse than one that reports the discrepancy.

### What is NOT implemented, and what is NOT verified

**Nothing here has been exercised against KRA.** There are no sandbox
credentials available, so:

- the request *shape*, the endpoint names, the field names, the signing scheme
  and the failure taxonomy are taken from KRA's OSCU specification and the
  taxpayer portal documentation, and are implemented as written;
- the **payload field names beyond those cited above** — in particular the exact
  spelling of nested document keys — are inferred from KRA's published examples
  rather than transcribed from the specification PDF, which is not
  machine-readable;
- the transport has no retry, no backoff and no connection pooling.

`KRA_BASE_URL` must be set from the taxpayer's own KRA account, and
`KRA_USERNAME` / `KRA_PASSWORD` supplied, before eTIMS is enabled for a live
shop. **Run the sandbox flow end to end (`init-osdc-info` → `select-code-list` →
`save-sales-trns` → `report`) before trusting a single live invoice.**

Signing keys are stored per shop in `etims_devices` and are never returned by
any endpoint — not filtered out of a response, but never *selected*. `GET
/api/etims/status` runs on every settings visit from a mobile connection, and
those keys sign every invoice the shop will ever file.

## Security

- ✓ JWT verification via OIDC JWKS
- ✓ Tenant isolation enforced in application code
- ✓ SQL injection prevention via Prisma
- ✓ CORS configured
- ✓ Helmet.js for HTTP headers
- ✓ Runtime request validation and bounded JSON bodies
- ✓ Rate limits on API and PayHero webhook traffic
- ✓ PayHero secrets never exposed to client

### PostgreSQL RLS and mobile workspace isolation

Tenant isolation is currently enforced **in the application layer**: the
`x-tenant-id` header is validated against the caller's OIDC profile memberships
on every protected request, and every query is filtered by that tenant id.

`prisma/ENABLE_RLS.sql` is an **optional, manual** defence-in-depth script. It
is deliberately NOT part of `prisma/migrations/`, because the API does not yet
set a transaction-local tenant context and the platform system-admin endpoints
intentionally perform cross-tenant reads. Applying it today would return zero
rows for every tenant query. The file documents the required wiring (non-superuser
role, `set_config('app.tenant_id', tenantId, true)` inside the same transaction,
and a dedicated role or policy for system-admin reads) before it should be run.

SQLite has no native RLS. The mobile equivalent is file-level isolation: every
shop uses its own `duka_pos_<workspace>.db`; the original `duka_pos.db` remains
the legacy first-shop workspace. Workspace selection happens before any local
repository access.

SQLite has no native RLS. The mobile equivalent is file-level isolation: every
shop uses its own `duka_pos_<workspace>.db`; the original `duka_pos.db` remains
the legacy first-shop workspace. Workspace selection happens before any local
repository access.

The PayHero callback is not OIDC-protected because PayHero calls it. It re-checks transaction status with PayHero, accepts only references generated by this API, and finalizes a sale inside a database transaction. Add PayHero signature verification before launch if it is available for your account.

## Next Steps

1. Set up the Keycloak realm and get OIDC issuer/audience values
2. Provision PostgreSQL database
3. Update `.env` with your credentials
4. Run `npm run db:push` to create tables
5. Build Flutter with the Keycloak OIDC issuer and public client ID
6. Replace `backend_service.dart` with HTTP calls
7. Deploy backend

## Migration from Supabase

Your Flutter app already has the right architecture:
- Local SQLite is the source of truth
- Backend is optional (only for M-Pesa)
- Product sync happens on-demand

Just replace Supabase SDK calls with HTTP calls to this API.
