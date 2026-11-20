# Source Reference and Backend Boundary Report

## Source used

Original source archive: `duka_pos_app_source_v84.zip`

SHA-256 verified in the current runtime:

`59d6107f2697237c5dc146e112df352ff387a9e2660f7a74995c244191ba5a01`

Archive contains the Flutter mobile app and planning material. It does **not** include the separate Go backend or the separate admin-panel repository.

## Confirmed v84 source references

| File / section | What is confirmed | Patch use |
|---|---|---|
| `plan/SimpleSales_Codex_Commercial_Intelligence_Plan_v13.md` §§47–54 | Data purposes, consent, minimization, contribution schema, suppression, admin integration, partner products, contribution ledger and lineage | Main product/architecture source for all patches |
| `assets/SimpleSales_Privacy_Policy.pdf` | Existing public policy describes controller/processor roles, business/customer/supplier/staff records and optional commercial intelligence | Patch 15 must update/version it before new purposes/fields/recipients are collected |
| `lib/db/database_helper.dart`, `_createShopProfileTable()` | Shop profile is only four-value POS profile plus updated timestamp | Patch 13 adds business context separately |
| `lib/services/workspace_service.dart` | Workspace/tenant identity and shop display details exist | Keep identity in operational layer; no direct commercial export |
| `lib/data/local/repositories/inventory_repository.dart` | Product catalogue, stock tracking, unit, stock movement and supplier/receipt base | Patch 14 and 18 |
| `lib/data/local/repositories/sales_repository.dart` | Sale and sale-line records with sale-time totals, costs, tax and discount snapshots | Patch 18 metric definitions |
| `lib/db/database_helper.dart`, `_migrateReordering()` | Product-supplier link, POs and PO lines | Patch 14 procurement linkage |
| `lib/db/database_helper.dart`, `_createReceiptTables()` | Supplier, stock receipt, receipt item and cost history. Current schema receipt lacks PO ID and receipt item lacks PO line ID | Patch 14 must add reliable PO-to-receipt linkage before lead-time metrics |
| `lib/db/database_helper.dart`, expenses schema | Amount, category, status, note/photo/staff fields | Only category/amount aggregates may be considered; no note/photo/staff |
| `lib/services/owner_business_sync_service.dart` | It explicitly says owner backup is not commercial intelligence and has no contribution method | Patch 16 requires separate contribution service/queue |
| `lib/services/backend_service.dart` | Authenticated backend client and existing operational sync APIs; no commercial-contribution method was found in v84 | Patch 16 adds a separate backend contract using current client/auth pattern |

## Existing backend/admin status

The original Commercial Intelligence Plan v13 says:

- existing admin panel is implemented and must be extended, not rebuilt;
- inspect existing routes, authentication, data model, API clients, analytics/jobs, audit logs and partner support;
- integrate contribution pipeline with the existing backend and admin panel;
- admin must show actual backend pipeline/dataset data, with restricted contribution ledger.

The Flutter v84 archive does not provide those backend/admin source repositories. The implementation agent must map Patch 16's logical API contracts into the existing backend/admin repositories. No new admin frontend, auth system or speculative route tree should be created.

## Explicitly unverified (do not claim present)

- The actual Go backend route names and database tables for commercial contribution.
- The admin panel's route/component filenames, current Data Intelligence tab/page or exact role names.
- Existing partner API credentials, dataset tables, aggregation jobs, retention jobs and audit-log implementation.
- Whether ODPC registration is already held and in which controller/processor capacities.
- Hosting countries/subprocessors and current cross-border transfer safeguards.

## Required first agent action

Before coding Patch 16, inspect backend and admin repositories and create a map:

`existing route → auth role → handler/service → DB entity → query/job → admin API client → UI route/component`.

Reuse the primitives already implemented. Add only missing contract pieces. Do not guess endpoint names or assume the plan's target is already live just because the admin app exists.

## Scope rule

The only files in the new deliverable are patches and supporting documents for 13–18. No files from patches 00–12 and no v84 source files are included or changed.
