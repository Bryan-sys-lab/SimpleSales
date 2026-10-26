# Expansion implementation TODO

This is the execution queue extracted from the Version 14 Master Codex plan
provided for integration. It extends the existing SimpleSales app; it does not
replace the P-01–P-10/R-01–R-11 order in `HANDOVER-REMAINING.md`.

## Ordering contract

R-11 must be completed and pass its full serial gate before E-01 starts. Each
item below is completed end-to-end before the next item begins: local schema and
migration, offline and online app journeys, backend authorization, backup and
restore, role/profile coverage, focused tests, analyzer/build, serial full
suites, and Compose health. Flutter tests always use `--concurrency=1`.

## Queued tasks

- [ ] **E-01 — Four-profile foundation.** Add exactly `drinks`, `duka`,
  `fashion`, and `open` as a persisted per-shop profile; map legacy shops to
  Duka without deleting data; add migration, setup selection, profile-change
  confirmation, backup, sync, and account/shop lifecycle tests.
- [ ] **E-02 — Shared capability and terminology layer.** Add profile presets
  over the existing shared sale, stock, finance, analytics, navigation, and
  onboarding engines. Screens consume capabilities/terminology rather than
  scattering profile conditionals. Cover all four profiles.
- [ ] **E-03 — Canonical financial event engine.** Establish append-only,
  integer-minor-unit postings for revenue, cash received, direct cost, tax,
  expenses, purchases, refunds, voids, owner capital/drawings, repayments and
  liabilities. Add single-posting and reconciliation invariants.
- [ ] **E-04 — Open-profile pooled costs and jobs.** Add cost pots, pooled-stock
  allocation, no-cost-pool warnings, job/material/helper/transport costs and
  break-even reporting without creating a second sale writer.
- [ ] **E-05 — Profile-integrated journeys.** Apply the shared engines to Drinks,
  Duka, Fashion and Open: onboarding cards, catalogue/service entry, checkout,
  expenses, purchases, refunds, reports, permissions, accessibility and low-end
  layouts. No profile is a separate app or schema.
- [ ] **E-06 — Account and all-shops read-only views.** Add owner-scoped blended
  dashboard, unified activity/transactions, shop health and safe source-shop
  drill-down. Bind every read/write to an explicit shop context and preserve
  manager/cashier isolation.
- [ ] **E-07 — Universal and profile analytics.** Add the shared financial
  statement, cash-flow, gross/net profit and record-quality metrics, then
  profile-specific KPI emphasis and product/service drill-downs with bounded
  queries and snapshot timestamps.
- [ ] **E-08 — Tax entity and reporting expansion.** Model taxpayer/shop
  separation, VAT/input VAT, TOT, income/corporation tax, PAYE/WHT/excise
  boundaries and local reports. Keep KRA/eTIMS activation disabled until
  explicitly approved; preserve Risiti/PesaStack provider isolation.
- [ ] **E-09 — Profile-specific operational modules.** Harden Drinks tanks,
  big/small cups, tabs and deposits; Duka loose/measured goods; Fashion
  size/colour, exchanges and lay-by; Open quick sales, purchases, owner money
  and optional stock. Reuse shared writers and add edge-case tests.
- [ ] **E-10 — Release-1 server evidence and sync.** Extend the existing
  tenant-scoped one-way sync/evidence layer for profile, finance and report
  records with idempotency, provenance, consent, retry and offline recovery.
  Do not introduce two-way multi-device sync in Release 1.
- [ ] **E-11 — Integrity, lifecycle and recovery.** Anchor financial/source
  revisions, expose correction/deletion/withdrawal workflows, preserve audit
  trails, and verify complete backup/restore plus derived-data impact handling.
- [ ] **E-12 — Restricted Contribution Ledger.** Add minimized,
  purpose/consent-bound contribution records and admin-only access. Never send
  raw receipts, customer/supplier identities, phone numbers, exact addresses,
  photos, M-Pesa references or staff identifiers.
- [ ] **E-13 — Aggregated intelligence and partner boundary.** Add versioned
  aggregation jobs/snapshots, suppression and re-identification controls,
  freshness/quality metadata, partner authorization, audit and export limits.
  Merchant users must never see platform-wide intelligence or ledger rows.
- [ ] **E-14 — Expansion release gate.** Run four-profile integration matrix,
  cross-shop authorization tests, migration/restore tests, financial invariants,
  low-end performance, accessibility/text-scale coverage, backend lint/build and
  serial Flutter/Vitest suites with clean process termination and Compose health.

## Explicit Release-1 boundaries

- Core selling, records, backups and basic analytics remain free.
- No proprietary credit score.
- No lender sharing in Release 1; lender-specific access is Release 2.
- No ML pipeline, warehouse, streaming infrastructure or new analytics vendor
  until measured volume or a paying customer justifies it.
- Commercial intelligence is separate from operational backup, telemetry and
  owner analytics consent.
