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

### Account creation without a password (the till's Verify flow)

The owner taps Verify on the till and never types a password: the app sends the
email and the 4-digit admin PIN it collected at shop setup, and this server
creates the account, emails a 6-digit code, and signs the till in once the code
comes back. Three pieces of configuration make that possible, and each of them
exists for a reason worth knowing:

- **A Keycloak admin client** (`KEYCLOAK_ADMIN_CLIENT_ID` /
  `KEYCLOAK_ADMIN_CLIENT_SECRET`). A confidential client in the realm with
  `realm-management`'s `manage-users` role. The admin credential belongs on the
  server and nowhere else — in an APK it is a published credential that lets
  anyone create an account for someone else's email.
  Set `KEYCLOAK_REALM` / `KEYCLOAK_BASE_URL` only if they cannot be derived
  from `OIDC_ISSUER_URL`.
- **A verification secret** (`EMAIL_VERIFICATION_SECRET`). Codes and PINs are
  stored as HMACs under a per-row salt, so a dumped table cannot be replayed.
  Generating one: `openssl rand -base64 48`.
- **EmailJS keys** (`EMAILJS_SERVICE_ID`, `EMAILJS_TEMPLATE_ID`,
  `EMAILJS_PUBLIC_KEY`, `EMAILJS_PRIVATE_KEY`). The private half never leaves
  this process; without the full set, `/auth/link` answers 503 rather than
  pretending a code was sent.
- **A session secret** (`APP_SESSION_SECRET`), which signs the till's session
  token. Optional: without it, verification still works and the till simply
  cannot hold a session of its own.

The account is created `enabled: false` with `emailVerified: false` and is only
switched on by `/auth/verify`, after a code sent to that address has been
presented. A guessed PIN therefore buys the caller a disabled row in the
identity server and nothing else. Enable Keycloak's brute-force detection on
the realm: the PIN is four digits, and the realm is the only place a wrong one
can be tried more than five times.

For local development without an EmailJS template, set
`VERIFICATION_DEBUG_CODES=true` outside production; `/auth/link` then returns
the code in a `debug_code` field. This is ignored by release builds and gated
on `NODE_ENV !== production`, and it is deliberately not available in one.

4. Prepare the database:
```bash
npm run db:generate
npm run db:deploy
```

For an existing owner/staff deployment, take a verified backup and run `npm run db:deploy` as normal. The chain is additive and re-runnable: `20260929220000_reconcile_legacy_roles` maps the legacy `('owner','staff')` role vocabulary to `('admin','manager','cashier')` and adds every column, table and index the old schema is missing (`deletion_ledger`, the `profiles` OIDC columns, the portion prices and decimal stock).

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

### Identity verification (the "Verify" button)
The only endpoints that authenticate by content rather than by token, because
the first one has to work for an account that does not exist yet. They are
rate-limited per address, and the Keycloak account they create stays **dark**
(disabled, unverified) until an emailed code is presented.

- `POST /api/auth/link` - `{ email, pin, shopName, ownerName }`. Creates the Keycloak account for the owner's email if there is not one, sends a 6-digit code to it, and answers where it was sent. It never says whether the address already had an account.
- `POST /api/auth/verify` - `{ email, pin, code }`. Consumes the code, enables and marks the account verified, adopts or creates the shop, and returns the shop's tenant id plus an app session for the till.
- `POST /api/auth/refresh` - `{ refreshToken }`. A rotated token pair; a token lifted off a phone works exactly once.

An **app session** is signed by this server, not by the identity server, and is accepted on `/api/tenant/*`, `/api/products/*` and `/api/reports/*` only. It cannot move money (`/api/payments/*`), file a tax invoice (`/api/etims/*`), or touch platform administration (`/api/system/*`). Set `APP_SESSION_SECRET` to enable it; deleting the secret is the revocation switch for every outstanding session.

### Platform administration
Mounted at `/api/system`, and the one surface that reads *every* shop — which
is the whole job of answering "is anything wrong anywhere?". The allowlist is
`SYSTEM_ADMIN_SUBJECTS`: OIDC subject ids, never email addresses. An app
session is refused here, and so is every tenant token, so a till cannot reach
platform administration even by accident.

- `GET /api/system/access` - Whether the caller is a platform operator.
- `GET /api/system/users?limit&offset` - Who is on the platform, paged, with the email's masked form.
- `GET /api/system/analytics?from&to` - Platform totals. Window-bounded (400 days, flagged when clamped).
- `GET /api/system/analytics/drilldown?from&to&tenant_id` - Per-day series, tender mix, staff leaderboard, per-shop breakdown. All of it from `src/lib/admin_analytics.ts`, which is pure and unit-tested, so the dashboard and the aggregates cannot disagree.
- `GET /api/system/observability` - Pending verification codes, codes burnt in the last 24h, and the recent attempts — a spike here is a shop whose email is failing before anyone notices.
- `GET|PATCH /api/system/tenants/:tenantId/settings` - One shop's settings, read and written.

### Operator dashboard (`/admin`)
A hand-built page served from this origin, so it cannot drift from the API it
reads: `npm run build` copies `src/public/` to `dist/public/`, and `/admin`
serves it from memory. No framework, no bundle, no separate deployment. It
holds no token — the operator pastes a bearer token into a form, and the page
keeps it in `sessionStorage` for the tab's lifetime only. The API's own error
message is shown verbatim, so an operator can tell an expired token from a
rate limit without calling anyone. `src/__tests__/dashboard.test.ts` asserts
the page links only assets that exist and calls only endpoints that exist.

### Live channel (`/live`)
A WebSocket for the till, replacing polling for the portfolio screen and other fast-changing data. It carries a **signal**, never the data:

- The till opens `wss://host/live` with its app session in the `Authorization` header.
- It may send `{"type":"ping"}` (answered with a pong) and `{"type":"read"}` (answered with a snapshot read by the same `readPortfolio` the HTTP endpoint uses, so the two can never disagree).
- A write — a product sync, a stock adjustment, a settings change — emits onto the channel's bus, and every stream holding that shop is told `{"type":"stale","reasons":["sales"],"at":"…"}`. The till answers a stale signal by reading, which is why the bus carries no payloads.

Scoping is per shop and read at connect time from the caller's own profiles, so one customer's till is never told about another's. A connection counts as alive only while it speaks: 30s heartbeat, 10-minute idle close. The reason vocabulary is closed (`products`, `stock`, `sales`, `settings`) so the phone never meets a reason it has no copy for. Two seams — the shop lookup and the snapshot read — are injectable, which is how the route test drives the channel with no database.

### Products
- `POST /api/products/sync` - Bulk sync from app
- `GET /api/products` - List all products

### eTIMS (KRA electronic tax invoicing)
- `POST /api/etims/device` - Register this shop's till with KRA and store its signing keys (owner only)
- `POST /api/etims/receipts` - Issue a tax receipt for one recorded sale
- `POST /api/etims/upload` - Upload every outstanding receipt, oldest first (admin/manager)
- `GET /api/etims/status` - How much is outstanding, and whether the device is registered
- `GET /api/etims/z-report` - The end-of-day report for a business date
- `POST /api/etims/z-report` - File that report with KRA (owner only)
- `GET /api/etims/receipts/:receiptNumber` - A receipt this shop filed
- `GET /api/etims/verify/:receiptNumber` - **Public.** What the QR code on a customer's receipt points at

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
- ✓ Keycloak admin credentials never exposed to the client: the API mints tokens instead of shipping them
- ✓ Verification codes and refresh tokens stored as HMACs, single-use, and bounded in lifetime
- ✓ App sessions limited to an allowlist of paths

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
