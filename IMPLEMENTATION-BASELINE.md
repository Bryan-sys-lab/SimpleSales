# Duka POS v84 Data Intelligence Patches 13–18 — Baseline

Baseline captured 2026-11-19 before Patch 13 implementation. The original v84 archive is read-only; its SHA-256 (`59d6107f2697237c5dc146e112df352ff387a9e2660f7a74995c244191ba5a01`) matches the supplied package manifest.

## Authoritative worktrees and existing edits

| Surface | Worktree | Branch / HEAD | Existing state |
|---|---|---|---|
| Flutter app | `/home/bstudio/Projects/Pos` | `app` / `2b75845` | Existing uncommitted sales, diagnostics, telemetry, theme, backend and Wrangler edits; patch bundle untracked. Preserve and reconcile relevant changes. |
| Backend | `/home/bstudio/Projects/Pos/.kilo/worktrees/duka-backend` | `cloudflare` / `5212d64` | Existing uncommitted admin auth/permissions, diagnostics, audit, telemetry, schema, migration, org and WebSocket changes. Preserve. |
| Admin | `/home/bstudio/Projects/Pos/.kilo/worktrees/duka-admin` | `admin` / `0b4dcd9` | Existing uncommitted auth/session/diagnostics, admin management, task, style and communication-plan changes. Preserve. |

These branches have divergent histories and represent different repository snapshots. Do not merge entire branches: that would replace unrelated app/backend files. Reconcile only relevant changes by file and behavior. A separate backend-analytics worktree has a release-manifest commit and a dirty email-sender test; neither is relevant to patches 13–18, so it was not merged.

Cross-worktree reconciliation review (2026-11-19): the app worktree's event ID, quoted-secret scrub pattern, event deduplication, aggregate counters and admin broadcast behaviors are already present in the authoritative cloudflare backend's in-progress diagnostics implementation and schema/migration. Tenant settings audit and profile-email output are also already present there. No code cherry-pick is needed for those overlaps. Keep the cloudflare auth middleware and existing `admin`/`cloudflare` worktree changes intact. Remaining independent differences are formatting and an app-branch-only verified-account directory; no Patch 13–18 backend dependency requires that route. The app/admin/backend diagnostics path is therefore reconciled by existing behavior, not by a broad merge.

## Architecture map

- **App:** Flutter/Dart, offline-first, four profiles on one canonical schema, encrypted workspace SQLite. Database migrations are registered in `duka_pos_app/lib/data/local/database/schema_version.dart`; Patch 13 advances schema to version 90. Keep optional intelligence fields non-blocking and keep the contribution queue separate from owner backup (`OwnerBusinessSyncService`).
- **Backend:** TypeScript, Express 5 on Cloudflare Workers, Prisma/PostgreSQL (Neon). Existing commercial primitives live in `duka_pos_backend/src/lib/commercial_{controls,ledger,normalizer,policy,quality}.ts`, with migrations `20261026110000_commercial_contribution_ledger` and `20261026120000_commercial_ledger_lineage`. Existing admin API routes cover policy, ledger, aggregate preview, quality, withdrawal and manual retention. Worker cron currently performs a database warm ping; there is no aggregation/retention job or partner delivery service.
- **Admin:** Existing Next.js 14 App Router application in `duka_pos_admin`, including live commercial pages `/commercial-policy`, `/commercial-ledger`, `/commercial-quality`; they use authenticated backend APIs and existing admin shell. The authoritative admin worktree also contains in-progress auth, diagnostics, audit, admins, and tasks surfaces. New intelligence screens must extend this app and use backend read APIs, not static production samples.
- **Governance/auth:** Existing commercial policy is draft and collection is hard-coded disabled. Current broad commercial permissions need a data-steward/analyst/partner-manager split. App authentication remains tenant/profile scoped; device diagnostics must not become an alternate contribution route.

## Patch map and gaps

| Patch | Existing primitive | Missing work |
|---|---|---|
| 13 Business context / KeSIC | Shared profile and product storage | Context capture, canonical reference data, KeSIC mapping and optional/non-blocking UI. |
| 14 Product identity / supply chain | Product and receipt records | Item kind, GPC/GTIN and normalized manufacturer/brand identity; purchase-order and PO-line linkage to receipts. |
| 18 Quality / metrics | Partial normalization and quality helpers | Dictionary-backed states, deterministic metric definitions, denominator/coverage/freshness and open-service handling. |
| 15 Governance / consent | Draft disabled policy; generic commercial wording in v1.2 Privacy Policy and Terms (effective 2026-10-25) | Versioned notice, granular default-off scope grants and evidence, withdrawal lifecycle, purpose map and legal gates. No ODPC registration evidence, DPIA or partner agreements found in the checked repositories. |
| 16 Pipeline / admin integration | Restricted contribution ledger, admin policy/ledger/quality APIs and pages | Mobile queue/service, allowlisted idempotent ingest, server grant checks, tenancy isolation, aggregation/suppression jobs, full datasets/lineage/coverage/overview views and steward role enforcement. |
| 17 Data products | No partner delivery service | Fixed NGO/manufacturer/supplier report schemas, partner scoping, delivery audit and disclosure controls. |

Existing contribution policy thresholds (5 contributors / 10 transactions) are weaker than Patch 17 requirements (at least 10 distinct contributors / 100 underlying transactions) and do not provide the required differencing protections. Tighten before any partner release. Live contribution must remain disabled until the legal/privacy gate is documented and approved.

## Baseline checks

- Flutter SDK: `/home/bstudio/.local/share/flutter/bin/flutter`, version 3.47.5 / Dart 3.13.4. `flutter analyze --no-pub` completed with two existing info-level lints in `lib/main.dart:320` and `lib/services/telemetry_service.dart:321`.
- Backend `cloudflare`: 32 test files / 195 tests passed; Prisma schema validation passed. TypeScript build completed with no reported diagnostics (npm printed only its normal `npm run` header).
- Admin `admin`: `npm run build` passed, including the existing commercial pages and admin/task routes. No test script is defined in its package manifest.
- Flutter full suite was interrupted after 1,149 passed and 10 failed because the run had exceeded 19 minutes; interruption caused an additional Flutter runner shutdown error. Failures observed include compact-screen setup overflows in `shop_profile_picker.dart` and profile/setup forms, plus profile-picker expectations that do not match rendered labels. This is a diagnostic, incomplete baseline; do not treat it as a clean full-suite result.
- Environment has Node 18.20.8 while the backend package declares Node >=26; Node 20.20.2 is also installed. Record/resolve compatibility in CI/deploy checks rather than changing runtime assumptions silently.

## Required implementation order

Follow the supplied order: **13 → 14 → 18 → 15 → 16 → 17**. Complete and report each patch independently, including migrations, tests, security review and acceptance evidence; stop after each completed patch for the user's approval before proceeding. Do not enable live collection before the legal gate. The communication-channel plan remains proposal-only until approved.

## Patch 13 implementation update (in progress; catalog reconciliation remains)

- Added workspace-local `business_context` table in additive schema v90 and fresh-install schema, independent from `shop_profile` and consent. Context stores the current four-value POS profile, selected KeSIC code/scheme/version, optional secondary codes, operator roles, sales channels, owner-selected county and broad settlement band, field-level provenance and confirmation timestamps.
- Added owner-only Business details entry beside POS profile controls in the existing Settings → shops/profile area. Merchant flow omits staff/outlet counts, business age, registration status and inferred sales mode per user direction; all retained details are optional. It never enables contribution or telemetry.
- Included the table in the existing owner-controlled full workspace backup manifest; this is separate from commercial contribution.
- KeSIC search now has an offline, versioned index transcribed from the detailed table in the KeSIC 2020 first edition (published 2021). The two official PDFs (the standard and the correspondence tables) assign the code `016190` to both crop-support and animal-support descriptions. It is excluded from verified choices; owner-entered `016190` and all uncached codes stay pending. No `016290` code is invented. The remaining index contains 1,169 distinct six-digit codes. The official portal reports 1,172 subclass-2 entries, while the PDF summary reports 1,180; the portal host is currently failing TLS negotiation from this environment, so parity with the portal and the PDF summary remains unresolved. No classification is inferred from the POS profile.
- Added full-backup disclosure in English and Swahili. Added backup round-trip and foreign-workspace restore rejection tests. Updating the POS profile atomically updates business context provenance; saving context derives its POS profile from the active shop record.
- `flutter analyze` passed on all touched Patch 13 files. The focused editor and model/database test files passed together (12 tests): phone-width render, KeSIC search and selection, four POS profiles, atomic profile mapping, backup round-trip, foreign-workspace restore rejection, migration, validation and pending/declined states. Android debug build could not proceed because the environment has not accepted NDK 28.2.13676358's SDK license; web build is unavailable because this app is not configured for web.
- Patch 13 remains open pending verified KeSIC catalogue parity/current version and reconciliation of the official source's conflicting `016190` entries. Live data contribution remains disabled. Do not start Patch 14 until Patch 13 acceptance is demonstrated.

### Patch 13 cross-tree verification checkpoint (2026-11-19)

- App focused verification: Flutter analyze reports no issues across 10 changed files. Focused model/editor/owner-sync tests pass (13 tests). The widget smoke test covers phone-width rendering and KeSIC search/selection; persistence, backup round-trip, migration and restore isolation are covered by model/database tests. An expanded UI save-tap tail hung in Flutter's test harness and was removed from the widget test; it was not counted as passing evidence.
- Backend: added the tenant-owned `business_context` record, strict owner-only upsert/read routes, server-derived tenant and POS profile values, profile-change propagation, and Prisma migration. The KeSIC code set is generated from the app's versioned offline reference. API tests cover tenant scoping, owner-only access, selected-code validation, preservation of unknown pending codes and rejection of extra fields. Prisma validation and TypeScript build pass; all 33 backend test files / 200 tests pass.
- Admin: tenant list links to a mobile-first business-context detail view. Its API is tenant-id scoped, requires the existing `tenants:read` permission and writes an audit event for each detail read. It shows operational details and provenance only; commercial contribution views remain on separate APIs. Admin production build passes. The UI state-marker check found loading, empty, error, disabled, focus, selected, submitting and success markers in the project; no live admin URL was available for visual smoke verification.
- App: the separate `business_context` sync call is included in the owner-controlled sync report and remains separate from the commercial contribution path. Its inclusion in the separately disclosed encrypted workspace backup remains unchanged. The editor and the English/Swahili automatic-sync disclosure explain that details sync to the operational shop record and do not enable commercial sharing.
- Latest primary-source check: KLMIS describes KeSIC as the Kenya-specific adaptation of ISIC Rev. 4 and its indexed official portal reports 1,172 subclass-2 entries. Direct TLS access to the portal still fails in this environment. The offline first-edition list contains 1,169 distinct verified codes after excluding ambiguous `016190`; exact code-by-code portal parity remains unverified and the offline list is not claimed as complete/current. Sources: [KLMIS classifications](https://www.labourmarket.go.ke/classifications/), [KeSIC portal](https://kesic.labourmarket.go.ke/).
- User accepted the versioned offline-catalogue limitation by instructing “advance to 14” (2026-11-19). Patch 13 is closed with the limitation retained: the local list is explicitly versioned, ambiguous `016190` remains pending, and exact portal parity is not claimed. Proceed to Patch 14.

## Patch 14 implementation update (in progress)

- App schema advances to v91 additively. Products receive stable UUIDs, item-kind, GPC/unit version+status, GTIN, local SKU/brand label, pack conversion and provenance; old products stay `unknown`/unmapped. The inventory editor captures item kind, GPC code/version/status, UNECE unit code/version/status and pack quantity/unit, and the owner has a review queue for unresolved mappings. Only check-digit-valid supplier GTINs sync; internal shop/restricted-circulation barcodes stay local. Current verified reference versions are GS1 GPC 2026-05 and UNECE Rec.20 Revision 17 (2021); neither is represented as a complete in-app code browser.
- Service and fee products remain ordinary sale lines but do not participate in stock checks, stock decrements or stock movements. Sale snapshots are untouched.
- Receipt headers and items carry nullable local PO references; receipt sync resolves stable PO and PO-line UUIDs. Posting allocates against one remaining PO line, so partial receipts cannot inflate all same-product order lines.
- Backend persists product identity fields with tenant scoping, validates GTIN check digits and mapping prerequisites, and validates receipt order UUID formats. Admin product coverage shows item-kind/GPC/unit status counts without expanding the coverage response with free-text product names.
- The shop-profile selector is now a horizontal rail on both phone and wide layouts. Rail height/card width respond to text scale and each option exposes selected/button semantics.
- Focused Flutter analyze passed for the changed model, DB, repositories, inventory editor and picker before the latest unit-editor additions. The first combined migration run found old repair fixtures without a products table; the v91 migration now guards absent tables and indexes. Subsequent targeted test run is in progress. Backend validation tests (37) and TypeScript build passed after the current schema/route changes; Prisma validation/generation passed. Admin production build passed.
- The full app suite previously reported five overflow failures in the shop-profile picker at compact widths before the horizontal rail adjustment; the focused picker suite is being rerun. The earlier migration failure set was fixed and the migration suite rerun is in progress. Do not close Patch 14 until focused picker/migration/product/receipt/sale checks finish and all three worktrees are rechecked.

## Patch 18 implementation update (2026-11-23)

- Added a versioned canonical metric and quality-state module to the backend:
  `duka_pos_backend/src/lib/canonical_metrics.ts`. It defines all required
  Patch 18 states and deterministic definitions for sales, payments,
  receivables, unit volumes, stock coverage/stockout, procurement, profile
  completeness and sales-record completeness.
- Added independently calculated metric-fixture coverage for reconciliation,
  missing/unknown stock observations, PO fill linkage and service
  not-applicable semantics.
- The existing backend quality report now exposes its data-dictionary version,
  canonical quality states and metric definitions. Numerator/denominator,
  period, freshness and suppression metadata are carried through the existing
  restricted `/api/admin/commercial/quality` API.
- Tightened disclosure guardrails from 5/10 to the Patch 17 minimum 10
  independent contributors and 100 underlying transactions.
- The existing Admin `/commercial-quality` page now renders backend-supplied
  definitions, quality states, period/freshness and explicit
  numerator/denominator details. It contains no static production fixture.
- Added merchant-only business-profile completeness to the existing optional
  Business details editor. Prefer-not-to-say and not-sure states do not block
  POS operations or imply commercial consent.
- Open services and fees remain ordinary `good|service|fee` catalogue/sale-line
  records. Existing inventory and stockout tests confirm service/fee products
  do not enter stockout calculations.
- Sequential execution instruction updated in
  `DUKA_POS_V84_NEW_PATCHES_13_TO_18/AGENT-WORK-ORDER.md`: after a patch passes
  all affected-branch verification gates, implementation advances
  automatically to the next patch; it stops on any failed or blocked gate.
- Verification: app business-context/product/receipt suite passed 34 tests;
  app analysis passed with no issues. Backend canonical/quality/control suite
  passed 13 tests; backend build and Prisma validation passed. Admin production
  build passed. No Flutter app build was run.

## Patch 15 implementation update (2026-11-23)

- Implemented the consent lifecycle on the mobile app: owner-only Settings
  entry, six explicit granular scopes, default-off collection disclosure,
  affirmative grant evidence, SHA-256 notice digest, app/schema/dictionary
  versions, authority evidence and withdrawal.
- Added app schema v92 with `commercial_consent_grants` and
  `commercial_contribution_queue`. Withdrawal marks active local grants
  withdrawn and deletes unsent queued commercial batches in the same
  transaction. The queue is separate from owner backup and checkout.
- Backend gained a tenant-authenticated commercial consent route. It validates
  scope allowlists, notice evidence, schema/dictionary versions and owner or
  authorized-representative authority. Withdrawal marks grants withdrawn and
  changes processing state to purge queued unsubmitted work.
- Prisma/PostgreSQL and D1 migrations add `commercial_consent_grants`.
  Prisma schema generation and validation pass.
- Admin commercial-policy now obtains real backend consent status counts and
  displays scope allowlists plus controller/processor, ODPC, DPIA,
  cross-border and partner-contract release gates. It never enables collection.
- Production commercial contribution remains disabled. No counsel, ODPC,
  DPIA or partner-contract approval was claimed.
- Verification: app consent/migration suite passed 15 tests; app analysis passed
  with no issues. Backend consent/policy/business-context suite passed 11
  tests; Prisma generation/validation and backend build passed. Admin production
  build passed. D1 migration SQL executed successfully in isolated SQLite and
  required consent columns were verified.
- Limitation: Wrangler local D1 runtime returned repeatable `write EOF` errors
  for both existing and isolated persistence state. Live Wrangler D1
  application remains blocked and was not claimed as pass.

## Patch 16 implementation update (2026-11-23)

- Added a separate mobile `CommercialContributionService` and kept it outside
  `OwnerBusinessSyncService.ownerBusinessDomains`. It calculates monthly
  coarse aggregates from confirmed local sales, applies active scopes, and
  queues only schema-pinned minimized batches with deterministic UUIDs.
- Mobile withdrawal deletes unsent queued batches in the consent transaction.
  Offline and unavailable-backend behavior does not affect checkout or owner
  backup synchronization.
- Backend gained authenticated
  `POST /api/tenant/commercial-contributions/batches`. It derives the tenant
  from the verified profile, requires an active owner grant, validates every
  scope, rejects unknown nested fields and foreign tenant fields, reconciles
  gross/discount/refund/tax/net values, canonicalizes payload hashes, and
  returns idempotent duplicate delivery behavior.
- Added tenant-scoped idempotency to `CommercialContribution` and PostgreSQL/D1
  migrations for `tenant_id` plus a unique tenant/batch key. Production
  ingestion remains hard-disabled until the Patch 15 legal gate is approved.
- Existing Admin Panel gained a backend-fed Data Intelligence overview and
  dataset-snapshot view. It reads `/api/admin/commercial/data-intelligence/*`
  and displays actual counts, reporting period, freshness, coverage, warnings
  and suppressed/no-data states. No mobile database or static fixture is used.
- Backend Admin overview and datasets are restricted by the existing admin
  authentication/permission boundary. The partner and merchant isolation
  primitives remain server-side and no partner route exposes ledger rows.
- Verification: app dedicated queue/business-context/product suite passed 19
  tests; app analysis passed with no issues. Backend ingest/consent/quality
  suite passed 13 tests; Prisma validation and backend build passed. Admin
  production build passed. D1-compatible tenant/batch SQL executed in isolated
  SQLite and required tenant columns/uniqueness were verified. Live Wrangler
  D1 still has the Patch 15 environment `write EOF` limitation.
