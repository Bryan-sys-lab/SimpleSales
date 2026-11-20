# Agent Work Order — New Data Intelligence Patches 13–18 Only

## Instruction

Use this add-on package for the new structured business data / Data Intelligence work only. Do not reapply POS patches 00–12 from it. The original v84 source archive is read-only. The existing backend and admin panel are separate repositories and must be inspected before implementation.

## Phase 0 — Inspect actual repositories (mandatory)

1. Confirm the mobile source commit/archive fingerprint matches v84.
2. Open `plan/SimpleSales_Codex_Commercial_Intelligence_Plan_v13.md` §§47–54.
3. Inspect current backend (the plan describes Go) and existing admin-panel repositories. Record existing auth, route, migrations, aggregation jobs, API client, roles, audit, partner access and deployment config.
4. Map each requirement in Patch 16 to an existing primitive or a specifically missing implementation.
5. Inspect current privacy policy, terms, ODPC registration records, hosting/subprocessors and any partner contracts.
6. Do not start live collection until Patch 15 legal gate is signed off.

## Phase 1 — Data foundations

Implement in dependency order:

1. Patch 13 business context and KeSIC reference-data mapping.
2. Patch 14 product master, GPC, units, brand/product identity and PO↔receipt lineage.
3. Patch 18 dictionary-backed data-quality states and deterministic metrics.
4. Add migrations for both upgraded and fresh-install mobile databases. Add backend migration only after the backend schema has been inspected. Preserve operational records and sale-time snapshots.

## Phase 2 — Governance / consent

Implement Patch 15:

- purpose/role map;
- updated policy and versioned notice;
- granular default-off scope grants;
- grant evidence and withdrawal lifecycle;
- legal registration assessment, DPIA, retention and cross-border gates;
- third-party data exclusion.

Never infer consent from owner backup, telemetry, app use or a shop's participation in a programme.

## Phase 3 — Backend contribution pipeline and existing admin integration

Implement Patch 16:

- dedicated mobile contribution queue/service;
- server-owned strict schema allowlist;
- authenticated idempotent backend ingest;
- server-side scope grant validation and tenancy isolation;
- restricted contribution store and provenance;
- aggregation/suppression/quality jobs;
- Data Intelligence area in the **existing admin panel** fed exclusively from backend read APIs;
- restricted Contribution Ledger and role enforcement;
- partner delivery APIs and audit.

Do not add the commercial queue to `OwnerBusinessSyncService`. Its v84 comment expressly prohibits treating owner backup as commercial intelligence.

## Phase 4 — Partner products

Implement Patch 17 only after aggregation and suppression tests pass:

- define initial NGO/digitisation pulse and manufacturer/supplier demand products;
- keep beneficiary/individual data out of the commercial product;
- use fixed report schemas, not arbitrary partner queries;
- contract and scope each partner; no partner access to contribution ledger.

## Phase 5 — Tests and release gates

- schema/migration parity; workspace isolation; auth scopes;
- data-purpose and consent scope tests;
- payload allowlist and prohibited-field tests;
- batch idempotency, duplicate, offline retry and withdrawal tests;
- aggregation totals/reconciliation and time/unit/currency tests;
- primary + complementary suppression and filter/differencing attacks;
- admin backend data integration (no static production samples);
- partner endpoint isolation; audit; retention/deletion;
- performance, queue backlog and server failure handling;
- policy/legal approval and DPIA/registration status.

## Definition of done

The work is complete only when all of the following are true:

- [ ] All four profiles share a single canonical dictionary and contribution pipeline.
- [ ] Data is captured through normal POS work plus optional, short business-context details.
- [ ] No optional profile/classification field blocks the POS.
- [ ] Owner backup, telemetry, commercial contribution and named record sharing remain separate.
- [ ] Backend is the source of truth for grants, accepted contributions, metrics, datasets and lineage.
- [ ] Existing admin panel displays actual backend data and has no static/demo intelligence values in production.
- [ ] Contribution ledger is restricted; raw POS/customer/supplier/staff data is never copied into it.
- [ ] Every partner sees only licensed, disclosure-controlled aggregate outputs.
- [ ] Data quality, denominators, sample coverage, freshness and suppression are visible.
- [ ] Legal release gates are signed and documented.
- [ ] Open service records are normal service sale lines; no new job model/event or job analytics enters the data product.
- [ ] Tests and code diffs are delivered separately; the original v84 archive remains untouched.
