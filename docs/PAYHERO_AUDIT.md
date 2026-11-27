# SimpleSales PayHero Integration Forensic Audit

**Audit date:** 2026-11-27  
**Readiness:** **Not production ready**  
**Scope:** Current app/backend working trees, checked-in Cloudflare configuration and D1 migrations, available PayHero API documentation, tests, and read-only Cloudflare deployment/secret metadata.

## Scope and safety

Secret values were not read, copied, logged, or changed. No PayHero production API call, channel registration, customer payment, production deployment, or migration was performed during this evidence collection. Cloudflare checks were read-only: secret-name listing, deployment history, and D1 migration status. The production PayHero credential's functionality and account identity therefore remain unverified.

The source working trees contain earlier, uncommitted PayHero changes. The deployment metadata does not prove that the latest deployed Worker is exactly the source currently in the working tree; this is called out below.

## Remediation follow-up

The user subsequently approved remediation and confirmed one central SimpleSales PayHero account with each merchant's channel isolated to its authenticated tenant. This follow-up supersedes conflicting historical findings and test counts below.

| Finding | Current status |
|---|---|
| PH-01 provider settlement evidence | **Fail-closed, unresolved externally.** Provider references are correlated and success settlement remains disabled until PayHero confirms merchant settlement and authoritative amount verification. |
| PH-02 staging credentials | **Unresolved.** No staging credentials were added or tested. |
| PH-03 account identity | **Implemented, not live-verified.** A read-only wallet/account check compares the provider account ID to configured `PAYHERO_ACCOUNT_ID`; production credential pairing was not called. |
| PH-04 channel registration | **Hardened in code.** Paginated lookup, durable registration reservation/fingerprint and tenant association are covered by mocks; live provider behavior remains untested. |
| PH-05 callback authentication | **Mitigated, unresolved externally.** Callback data is not treated as proof; the backend independently queries PayHero. No signature contract has been verified. |
| PH-06 pending-payment reconciliation | **Unresolved.** There is no bounded scheduled stale-payment reconciliation process. |
| PH-07 amount integrity | **Fail-closed.** Collection and settlement require both confirmation flags, which remain `false`; no amount is inferred from undocumented response fields. |
| PH-08 channel management UX | **Implemented in code.** Settings reads and removes server-configured channels and preserves owner-only management; live API behavior remains untested. |
| PH-09 deployment provenance | **Unresolved.** No deployment was performed; the serving revision and duplicate Wrangler configuration remain unverified. |
| PH-10 offline M-Pesa | **Partially mitigated.** Offline payments remain explicitly unverified and are excluded from verified sales aggregates; operator reconciliation is still needed. |
| PH-11 polling errors | **Addressed in code.** Review, expired-session, access-denied and unavailable-status outcomes are distinct and covered by focused tests. |

No production secret values were accessed or changed. No production payment, channel registration, migration or deployment was performed. The new D1 migration was validated only against an in-memory SQLite database.

## Executive assessment

The active PayHero path is the Cloudflare Worker/D1 backend. The Flutter app sends channel and payment requests to that backend and contains no PayHero credential. Payment initiation stores a pending payment, and successful sales are finalized only after a provider status lookup reports `SUCCESS`; an HTTP success from the STK initiation endpoint alone does not finalize a sale.

Tenant isolation is enforced in code: channel setup/removal is admin-only, channel IDs are selected from the authenticated tenant's record, and payment status lookups are scoped to the authenticated tenant. The callback body does not directly set payment success; the handler independently queries PayHero.

However, production readiness cannot be established because:

1. The PayHero settlement/amount contract has not been confirmed. Both collection and successful settlement remain disabled by default.
2. Staging PayHero credentials and a safe test account are unavailable, so provider behavior cannot be validated outside production.
3. Account identity code exists, but the configured production credential/account pairing has not been functionally verified.
4. PayHero callback authentication and retry guarantees remain undocumented/unverified.
5. There is no bounded server-side pending-payment reconciliation job.
6. The serving Worker source revision and deployment configuration remain ambiguous.

## A. Architecture map

```text
Flutter Settings (admin)
  -> BackendService.registerMpesaChannel
  -> POST /api/tenant/mpesa/channel
  -> PayHero GET payment_channels, then POST payment_channels if no match
  -> persist PayHero channel ID/details on the authenticated Tenant

Flutter Sell screen
  -> BackendService.initiatePayment
  -> POST /api/payments/initiate
  -> create QUEUED Payment using authenticated tenant and server-side product prices
  -> PayHero POST /api/v2/payments (STK Push)
  -> persist PENDING and checkout request ID
  -> Flutter polls GET /api/payments/status; backend queries PayHero
     OR PayHero calls POST /webhooks/payhero-callback; backend queries PayHero
  -> D1 batch finalizes sale, sale items, stock and payment after provider SUCCESS

Separate payment paths:
  - Dynamic QR uses Safaricom directly and is reconciled by the separately
    keyed M-Pesa C2B confirmation webhook, not by the PayHero callback.
  - Subscription payments use the same PayHero client with a platform
    subscription destination and SUBS references.
  - Offline M-Pesa sales are local and explicitly unverified.
```

The old Supabase Edge Functions and Supabase migrations have been removed from the backend working tree. No active backend source or Flutter runtime reference to those functions remains.

## B. Integration inventory

### Backend and deployment

- [`../duka_pos_backend/src/services/payhero.ts`](../duka_pos_backend/src/services/payhero.ts): Basic Authorization header, Kenyan phone normalization, channel lookup/registration, STK Push, and status query.
- [`../duka_pos_backend/src/routes/tenant.ts`](../duka_pos_backend/src/routes/tenant.ts): `POST/GET/DELETE /api/tenant/mpesa/channel`; subscription payment initiation/status; stores tenant channel configuration.
- [`../duka_pos_backend/src/routes/payment.ts`](../duka_pos_backend/src/routes/payment.ts): `POST /api/payments/initiate`, `POST /api/payments/qr`, `GET /api/payments/status`.
- [`../duka_pos_backend/src/routes/payhero-callback.ts`](../duka_pos_backend/src/routes/payhero-callback.ts): public PayHero callback, provider status lookup, and D1 sale settlement.
- [`../duka_pos_backend/src/routes/mpesa.ts`](../duka_pos_backend/src/routes/mpesa.ts): separate Safaricom C2B validation/confirmation callbacks, including Dynamic QR matching. This is not the PayHero callback.
- [`../duka_pos_backend/src/services/safaricom_qr.ts`](../duka_pos_backend/src/services/safaricom_qr.ts): separate Safaricom Dynamic QR request.
- [`../duka_pos_backend/src/index.ts`](../duka_pos_backend/src/index.ts): mounts payment routes and public callback; global JSON limit and rate limiting.
- [`../duka_pos_backend/src/worker.ts`](../duka_pos_backend/src/worker.ts): D1-backed Worker entry point; five-minute scheduled handler only performs a database warm ping.
- [`../duka_pos_backend/prisma/schema.prisma`](../duka_pos_backend/prisma/schema.prisma): Tenant PayHero channel fields, Payment and SubscriptionPayment models.
- [`../duka_pos_backend/prisma/migrations-d1/20261127000000_payhero_hardening/migration.sql`](../duka_pos_backend/prisma/migrations-d1/20261127000000_payhero_hardening/migration.sql): channel metadata and unique payment operation ID migration.
- [`../duka_pos_backend/wrangler.jsonc`](../duka_pos_backend/wrangler.jsonc): intended API Worker entry point, production/staging D1 and R2 bindings, observability and cron configuration.
- [`../duka_pos_backend/cloudflare/wrangler.jsonc`](../duka_pos_backend/cloudflare/wrangler.jsonc) and [`../duka_pos_backend/cloudflare/worker.ts`](../duka_pos_backend/cloudflare/worker.ts): separate container-based Worker configuration/entry point. It has the same Worker name as the API config; repository guidance says not to use it to deploy the API.

### Flutter

- [`../../SimpleSales-app/duka_pos_app/lib/screens/settings_screen.dart`](../../SimpleSales-app/duka_pos_app/lib/screens/settings_screen.dart): admin setup dialog for Till, Paybill and Bank, local display/settings and enable/disable behavior.
- [`../../SimpleSales-app/duka_pos_app/lib/screens/sell_screen.dart`](../../SimpleSales-app/duka_pos_app/lib/screens/sell_screen.dart): STK/QR checkout, status polling, sale recording and explicitly unverified offline M-Pesa path.
- [`../../SimpleSales-app/duka_pos_app/lib/services/backend_service.dart`](../../SimpleSales-app/duka_pos_app/lib/services/backend_service.dart): backend API calls; no PayHero token/password use.
- [`../../SimpleSales-app/duka_pos_app/test/screens/settings_screen_test.dart`](../../SimpleSales-app/duka_pos_app/test/screens/settings_screen_test.dart): setup guide and settings UI tests.
- [`../../SimpleSales-app/duka_pos_app/test/offline_payment_test.dart`](../../SimpleSales-app/duka_pos_app/test/offline_payment_test.dart): local offline M-Pesa marked unverified and reconciliation list behavior.
- [`../../SimpleSales-app/duka_pos_app/test/backend_service_test.dart`](../../SimpleSales-app/duka_pos_app/test/backend_service_test.dart): payment types/phone validation and general backend-service tests; it does not exercise PayHero network calls.
- [`../../SimpleSales-app/duka_pos_app/test/widget_test.dart`](../../SimpleSales-app/duka_pos_app/test/widget_test.dart): app root/router/theme smoke test only, not a payment test.

## C. Secrets and deployment report

### PayHero authentication

The PayHero documentation reviewed specifies a Basic Authorization token in the `Authorization` header. The backend reads the provider-issued `PAYHERO_AUTH_TOKEN`, removes an optional existing `Basic ` prefix, then sends `Authorization: Basic <token>`. It does **not** separately read a username/password or construct the token from those fields.

- Production secret-name listing showed `PAYHERO_AUTH_TOKEN`, `PAYHERO_ACCOUNT_ID`, and `PUBLIC_API_URL`. Values were not accessed.
- Staging secret-name listing showed `PUBLIC_API_URL` but not `PAYHERO_AUTH_TOKEN` or `PAYHERO_ACCOUNT_ID`.
- The source uses the PayHero API base URL `https://backend.payhero.co.ke/api/v2`; there is no `PAYHERO_BASE_URL` override in the active implementation.
- `PAYHERO_USERNAME` and `PAYHERO_PASSWORD` are not referenced in the active app/backend. There is no separate password secret in the current implementation.
- `MPESA_CALLBACK_KEY` is used by the distinct Safaricom C2B callback path. It does not authenticate the PayHero callback.
- The app sends channel details only; PayHero credentials remain backend-side in source.
- The checked-in `.env.example` documents the provider-issued Basic token, account-ID placeholder and fail-closed confirmation flags; `ENVIRONMENT.md` lists the server-side secret names.

The backend now has a read-only account verification check that queries the documented service-wallet endpoint and compares its `account_id` with `PAYHERO_ACCOUNT_ID`; an owner-restricted system endpoint reports configuration and verification booleans without returning token material. This code path is covered with mocked responses only. It has not been called using the production credential, so secret existence is not proof the configured values work together.

### Cloudflare deployment

- Production Worker: `duka-pos-backend`. The latest deployment reported 100% traffic on version `eca3ce70-f6cb-46e8-9800-b7c105ccfb09`, created 2026-11-26 22:22 UTC, with no build message/source SHA.
- Staging Worker: latest deployment reported 100% traffic on version `18836993-530d-4c27-8b64-021463b51e96`, created 2026-11-26 22:20 UTC, with no build message/source SHA.
- The most recent identifiable build message before those deployments was `Backend 2.0.0+96 (aaa97ba)` in both environments. It is not possible from the current deployment metadata to assert that the later versions contain that exact source.
- The original audit's remote migration listing reported no migrations to apply before this remediation. No remote migration listing or apply was performed during remediation; the new local migration remains unapplied remotely.
- The top-level Worker config binds production D1 `duka-pos-prod` and separate staging D1 `duka-pos-staging`. Logging/tracing/issue observability is enabled in the checked-in config.
- The backend CI and promotion script use the top-level `wrangler.jsonc`. A nested container config also declares the name `duka-pos-backend` and has a manual deploy script; that name collision creates an avoidable deployment hazard if the nested config is used.
- `PUBLIC_API_URL` exists as a secret name, and production startup requires HTTPS. Its value was not read, so the exact configured callback URL was not confirmed.

## D. End-to-end flow assessment

| Flow | Evidence-based behavior | Assessment |
|---|---|---|
| Configure channel | Admin-only backend route calls PayHero lookup/register, then stores channel ID/type/short code/account number on the authenticated tenant. | Functional code path; live registration and provider response behavior not tested. |
| Select channel for POS payment | Client does not submit a channel ID. Backend loads the channel from `req.user.tenantId` and sends that ID to PayHero. | Tenant selection is server-side; cross-tenant channel substitution is not apparent in source. |
| Initiate STK | Backend calculates cart prices from tenant products, persists a payment, sends integer KES amount and normalized Kenyan phone, then stores `PENDING` and checkout ID. | HTTP initiation response does not itself mark a sale successful. |
| Confirm STK | Status endpoint and callback independently query PayHero; provider `SUCCESS` leads to a D1 batch that updates payment, sale, items and stock. | Correct high-level lifecycle, but provider response correlation/amount validation is insufficient (finding PH-01). |
| Callback | Public and rate-limited; callback status text is not trusted directly. It extracts a reference and queries PayHero. | Better than trusting callback payload, but sender authentication/signature support remains unverified (PH-05). |
| Dynamic QR | Direct Safaricom QR generation; its separate C2B confirmation route checks `MPESA_CALLBACK_KEY`, matches reference/tenant and checks amount before finalization. | Distinct provider path; do not treat it as a PayHero integration test. |
| Offline M-Pesa | Local sale is written with `paymentVerified: false`, stock is decremented locally, and UI says no STK prompt was sent. | Explicitly unverified and visible to the operator; requires reconciliation (PH-10). |
| Recovery | Flutter polls every three seconds for up to 90 seconds; backend limits PayHero status refreshes to once per 10 seconds. Callback can also settle. | No scheduled payment reconciliation exists; missed callback plus no later poll can leave payment pending (PH-06). |

## E. Findings register

### PH-01 — High: provider settlement response is not strictly correlated

- **Affected:** `queryTransactionStatus`, `handlePayheroCallback`, `/payments/status` in [`payhero.ts`](../duka_pos_backend/src/services/payhero.ts), [`payhero-callback.ts`](../duka_pos_backend/src/routes/payhero-callback.ts), and [`payment.ts`](../duka_pos_backend/src/routes/payment.ts).
- **Evidence/behavior:** A mismatching response reference is rejected only if a reference is present as a string. Missing `success` is allowed; settlement checks `status === 'SUCCESS'` and `success !== false`. Amount, provider, channel/destination and transaction reference are not all compared to the stored payment. The D1 callback test supplies a status response with `status: 'SUCCESS'` but no `success` field and accepts it.
- **Expected:** Require the documented success indicator and exact returned reference before settlement; compare transaction amount and other available immutable payment fields. If the status API does not expose amount, confirm the supported reconciliation method with PayHero instead of inventing a field.
- **Risk:** An incomplete or mismatched provider response can finalize a sale and decrement stock without sufficient transaction correlation.
- **Correction:** Validate provider response shape strictly and persist provider receipt/reference data where documented; add negative tests for missing/mismatched reference, missing/false success, wrong amount and wrong provider.

### PH-02 — Medium: staging lacks PayHero credentials

- **Affected:** staging Worker secrets and [`payhero.ts`](../duka_pos_backend/src/services/payhero.ts).
- **Evidence/behavior:** Read-only secret-name listing found `PUBLIC_API_URL` in staging but no `PAYHERO_AUTH_TOKEN` or `PAYHERO_ACCOUNT_ID`. The client throws when either required PayHero value is missing.
- **Expected:** Use separate staging/sandbox credentials and account ID, verify the channel and status flows there, and never reuse production secrets for staging.
- **Risk:** The real integration cannot be safely validated before production; configuration errors may only appear against production.
- **Correction:** Configure the staging account securely and add a deployment preflight that checks required PayHero secret names without exposing values.

### PH-03 — Medium: intended PayHero account identity is not verified

- **Affected:** `registerPaymentChannel` and owner setup in [`payhero.ts`](../duka_pos_backend/src/services/payhero.ts) and [`tenant.ts`](../duka_pos_backend/src/routes/tenant.ts).
- **Evidence/behavior:** One global Basic token and numeric `PAYHERO_ACCOUNT_ID` are used for registrations. There is no explicit API identity/profile verification or owner-visible account confirmation. The channel list check only finds an active matching channel; it does not establish identity if the list is empty.
- **Expected:** Verify that the configured API key and account ID belong to the intended PayHero account using a documented provider mechanism before enabling merchant collections.
- **Risk:** A mismatched account ID/token can cause registration failures or channel association with the wrong PayHero account; the app cannot prove whose account it is using.
- **Correction:** Confirm whether SimpleSales intentionally uses one platform PayHero account or one account per merchant. Implement only a documented identity check and make the verified account explicit to the owner.

### PH-04 — Medium: channel registration is not reliably idempotent

- **Affected:** `registerPaymentChannel` in [`payhero.ts`](../duka_pos_backend/src/services/payhero.ts).
- **Evidence/behavior:** Registration performs one active-channel list request followed by a create request. The documented list response is paginated, but code ignores pagination. Concurrent setup requests can both see no match and create duplicates. The create response is accepted based on a positive `id` alone; returned account, channel type, shortcode and active status are not validated.
- **Expected:** Resolve all pages or use a provider-supported exact lookup, prevent concurrent duplicate registration, and validate the returned channel identity/status before persisting it.
- **Risk:** Duplicate or inactive/wrong channels may be stored and selected for customer payments.
- **Correction:** Add provider-contract-backed pagination and idempotency/locking and verify the full provider response before updating the tenant.

### PH-05 — Medium: PayHero callback sender authentication is unverified

- **Affected:** `/webhooks/payhero-callback` in [`index.ts`](../duka_pos_backend/src/index.ts) and `handlePayheroCallback` in [`payhero-callback.ts`](../duka_pos_backend/src/routes/payhero-callback.ts).
- **Evidence/behavior:** The route is public and rate-limited to 30 requests/minute. No signature or shared-key verification is implemented for this route. The handler mitigates forged status claims by querying PayHero by reference before settlement. The PayHero documentation bundle reviewed did not establish a callback signature contract.
- **Expected:** Confirm PayHero's documented callback-authentication/retry contract. Do not invent a signature. Continue treating callbacks as notifications unless provider authentication is documented and verified.
- **Risk:** Anyone who knows a reference can trigger provider lookups, consume rate limit/provider quota, or cause processing load. Current code does not directly accept a forged `SUCCESS` body as proof of payment.
- **Correction:** Obtain the provider's callback security contract; test forged, duplicate and out-of-order callback requests. Restrict lookup work and keep provider status verification authoritative.

### PH-06 — Medium: no server-side pending-payment reconciliation job

- **Affected:** Worker scheduled handler in [`worker.ts`](../duka_pos_backend/src/worker.ts), payment status route in [`payment.ts`](../duka_pos_backend/src/routes/payment.ts).
- **Evidence/behavior:** The five-minute cron only performs a database warm ping. Payment reconciliation occurs through callback handling or an authenticated status poll. No payment queue or scheduled PayHero reconciliation was found.
- **Expected:** Pending/ambiguous payments should have a bounded, observable server-side recovery path when callbacks or the client are absent.
- **Risk:** A missed callback and closed/expired client can leave a payment in `QUEUED`/`PENDING` without a later status refresh.
- **Correction:** Add a bounded reconciliation process for stale pending references, with rate limits, idempotent settlement, alerting and no duplicate STK initiation.

### PH-07 — Medium: provider amount rounding is not reconciled with sale amount

- **Affected:** `initiateStkPush` and `createPaymentDraft` in [`payhero.ts`](../duka_pos_backend/src/services/payhero.ts) and [`payment.ts`](../duka_pos_backend/src/routes/payment.ts); the separate Dynamic QR flow in [`safaricom_qr.ts`](../duka_pos_backend/src/services/safaricom_qr.ts) and [`mpesa.ts`](../duka_pos_backend/src/routes/mpesa.ts).
- **Evidence/behavior:** The product schema accepts finite decimal prices. The backend stores the cart-derived amount but rounds the amount sent to both provider flows. PayHero STK settlement does not compare the provider amount with the stored amount/cart total. Safaricom QR confirmation instead requires the callback amount to match the unrounded stored amount within 0.01.
- **Expected:** Define one canonical payable amount and ensure the provider charge, payment record and sale total agree.
- **Risk:** For fractional totals, the STK customer charge can differ from the ledger sale total, while a Dynamic QR callback can fail to settle against the unrounded amount.
- **Correction:** Confirm each provider's amount/currency rules and product pricing policy; reject or explicitly normalize unsupported fractions before creating a payment, then test boundary values.

### PH-08 — Low: Flutter does not use channel retrieval/removal routes

- **Affected:** `SettingsScreen` and `BackendService` in [`settings_screen.dart`](../../SimpleSales-app/duka_pos_app/lib/screens/settings_screen.dart) and [`backend_service.dart`](../../SimpleSales-app/duka_pos_app/lib/services/backend_service.dart); backend `GET/DELETE /tenant/mpesa/channel` in [`tenant.ts`](../duka_pos_backend/src/routes/tenant.ts).
- **Evidence/behavior:** Flutter calls the registration endpoint and persists channel details locally. No Flutter call to the backend GET or DELETE channel route was found. Disabling M-Pesa sets the enable flag false; it does not invoke channel removal. There is no distinct enabled-state edit/remove control.
- **Expected:** Clearly expose whether the account is configured, allow authorized retrieval/update/removal, and distinguish local disable from provider channel deletion.
- **Risk:** Local display can diverge from backend configuration; a user may believe a channel was removed when it is only disabled locally/backend-side.
- **Correction:** Wire the existing GET/DELETE routes or remove them if not intended; define the exact semantics for disabling versus removing a PayHero channel.

### PH-09 — Medium: deployment provenance/configuration is ambiguous

- **Affected:** [`wrangler.jsonc`](../duka_pos_backend/wrangler.jsonc), [`cloudflare/wrangler.jsonc`](../duka_pos_backend/cloudflare/wrangler.jsonc), CI and deployment scripts.
- **Evidence/behavior:** The latest production/staging deployments have no source/build message. The last identifiable message is `2.0.0+96 (aaa97ba)`, earlier than the current deployment IDs. Two checked-in Wrangler configs use the name `duka-pos-backend`; one is the D1 API Worker and the nested one is a container Worker with a manual deploy script. CI/deploy documentation uses the top-level API config.
- **Expected:** Every serving Worker version should map to an immutable source commit and one unambiguous deployment configuration.
- **Risk:** Operators cannot prove which code/config is serving; using the nested config could target the same Worker name.
- **Correction:** Reconcile the current serving version to source, give the container Worker a distinct name if it remains deployable, and require build metadata in each deployment.

### PH-10 — Low: offline M-Pesa is an unverified local sale

- **Affected:** `_recordUnverifiedMpesa` in [`sell_screen.dart`](../../SimpleSales-app/duka_pos_app/lib/screens/sell_screen.dart).
- **Evidence/behavior:** When the backend is unavailable, the app records a local M-Pesa sale, decrements local stock, sets `paymentVerified: false`, and tells the operator no STK prompt was sent and the sale requires reconciliation. Tests cover this behavior.
- **Expected:** The unverified state must remain visible and reconcilable; it must never be treated as provider-confirmed revenue/payment.
- **Risk:** An operator can record a sale without a payment prompt or evidence that funds arrived; outstanding unverified rows affect local sales/stock until reconciled.
- **Correction:** Preserve the explicit unverified state, provide a durable reconciliation workflow, and ensure reports distinguish confirmed from unconfirmed sales.

### PH-11 — Low: polling hides permanent session/API errors as timeout

- **Affected:** `BackendService.pollPaymentStatus` in [`backend_service.dart`](../../SimpleSales-app/duka_pos_app/lib/services/backend_service.dart).
- **Evidence/behavior:** Polling catches all errors and retries every three seconds until timeout, without distinguishing transient network errors from authorization/session failures.
- **Expected:** Preserve the warning not to charge again while surfacing session expiration and permanent API failures distinctly.
- **Risk:** A paid transaction may be reported to the operator only as a generic timeout; recovery is less clear.
- **Correction:** Classify retryable transport errors versus authentication/permanent errors and direct the operator to status reconciliation without suggesting a duplicate charge.

## F. Test report and matrix

### Executed in the remediation follow-up

| Check | Result |
|---|---|
| Backend TypeScript build, ESLint, Prisma validation and client generation | Passed |
| Backend Vitest suite | 62 files, 344 tests passed |
| Flutter focused analytics, backend-service and Settings tests | 83 tests passed |
| Flutter analysis for changed payment/settings files | Passed, no issues |
| D1 migration sequence | All 15 migrations applied to in-memory SQLite; expected PayHero columns verified |
| Wrangler staging deploy dry-run | Passed; packaged only, no upload |
| Wrangler environment type generation | Passed |
| Production/staging D1 and secret metadata | Not rechecked during remediation; no remote migration or secret operation performed |

The PayHero service tests mock `fetch`; callback/D1 tests mock provider status and D1 batch operations. These tests do not prove the configured production credential works or exercise PayHero itself. The in-memory SQLite migration check is not a D1 remote migration test.

### Required matrix

| Scenario | Status | Evidence / reason |
|---|---|---|
| Basic header construction | Mock-tested | Tests assert `Authorization: Basic <token>`; not a valid provider credential test. |
| Valid/invalid production credentials | **Not tested** | Values were intentionally not read; staging credentials were not configured. |
| Owner/account identity verification | Mock-tested, not live-verified | Wallet/account response mismatch is rejected; no production API call was made. |
| Till/Paybill/Bank registration contract | Mock-tested | Per-type fields, response identity and bank account requirements are covered; live provider behavior is not tested. |
| Duplicate channel registration | Mock-tested | Pagination, exact reuse, ambiguous duplicates and durable reservation logic are covered; live concurrency is not tested. |
| Cross-tenant/unauthorized channel access | Code reviewed; no live adversarial test | Channel writes use authenticated tenant and admin role; provider destination is selected server-side. |
| STK initiation success/failure | Mock-tested only | Provider-generated reference and Basic auth are covered; no live request or production transaction was run. |
| Phone formatting | Unit-tested | Kenyan local and international forms covered. |
| Forged callback | Mock-tested | A forged success notification while PayHero remains queued does not settle a payment. |
| Duplicate/out-of-order callbacks | Partial | Atomic D1 claim/concurrent callback behavior is tested; provider retry behavior is not live-verified. |
| Missing/mismatched status fields and amount | Fail-closed, provider contract unresolved | Mismatched provider references are rejected; successful settlement is disabled pending authoritative amount confirmation. |
| Delayed callback / lost callback reconciliation | **Not implemented** | No scheduled payment reconciliation job. |
| D1 settlement/idempotency | Mock-tested | Atomic batch and concurrent claim behavior tested; not a remote production failure-injection test. |
| Offline POS | Local behavior tested | Offline M-Pesa remains unverified and excluded from verified sales aggregates; no provider payment is sent. |
| Session expiration during poll | Mock-tested | Expired session, access denial, review-needed and unavailable status remain distinct. |
| Production callback URL, real channel or payment | **Not tested** | No production payment or channel registration was performed. |

The attached `widget_test.dart` is a root app/router/theme smoke test. It does not cover PayHero, channel persistence, payment status or backend calls.

## G. Remaining remediation plan

Code remediation has been performed under the user's subsequent approval. Remaining work is ordered by production dependency:

1. **Confirm PayHero settlement and amount guarantees.** Keep `PAYHERO_CHANNEL_SETTLEMENT_CONFIRMED` and `PAYHERO_AMOUNT_VERIFICATION_CONFIRMED` false until PayHero confirms merchant-channel settlement under the central account and supplies an authoritative way to verify charged amount.
2. **Provision isolated staging credentials.** Use a non-production PayHero account and verify secret bindings without printing values. Run safe read-only account verification and mock-free staging checks.
3. **Resolve callback guarantees.** Obtain PayHero's documented callback authentication and retry contract. Keep the callback as a notification unless the provider documents and verifies sender authentication.
4. **Add bounded pending-payment recovery.** Reconcile stale pending references without re-initiating charges; alert on unresolved payments and preserve idempotent settlement.
5. **Verify channel ownership and production account pairing.** Use the owner-facing read-only account check only after confirming the configured credential is the intended central account; no real channel registration is needed for this check.
6. **Prove deployment provenance.** Identify the currently serving Worker version/config and resolve the duplicate Worker name/config risk before deployment.
7. **Run controlled staging verification.** Exercise registration, retrieval, removal, payment initiation, callback and reconciliation using only provider-approved test channels and transactions. Do not use customer payments.

## Final readiness assessment

**Not production ready.** The code now enforces tenant-scoped channel selection, durable channel registration state, provider-reference correlation, guarded settlement, owner-facing account verification and distinct Flutter payment outcomes. The integration intentionally fails closed while PayHero's central-account merchant settlement and authoritative amount-verification guarantees are unconfirmed. Staging credentials, callback authentication/retry guarantees, scheduled recovery and deployed-source provenance also remain unresolved. No production credential values were read or changed, and no real payment, channel registration, migration or deployment was performed.
