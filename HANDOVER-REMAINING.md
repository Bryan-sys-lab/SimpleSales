# HANDOVER — remaining implementation items

Written for the next session / next developer. Anything marked DONE was verified this session
by end-to-end checks (`flutter analyze` zero issues, app suite green, backend `tsc --noEmit`
clean, `vitest` green, stack healthy at `:3100`). Anything unmarked is TO BUILD. Anything marked
MID-EDIT was started this session and is currently broken/incomplete — finish or revert it first.

> **Scope rule (agreed): minimum effective implementation per feature.** Build the smallest
> version that satisfies the spec's acceptance criteria — no speculative abstractions, no
> features the spec does not ask for. Resolve open questions with the simplest workable choice.

**Companion spec:** `SIMPLESALES-SPECIFICATION-ADDENDUM.md` (specification only, no code) adds
Addendum sections 2–16 not covered by the main spec: extended defect register (X-1…X-47), shop
verification & cloud linking, eTIMS enablement checklist, printing subsystem, scanning subsystem,
in-app updates & rollback, Auth & PIN hardening, support & feedback, import/export/Sheets,
transactions & reports upgrades, audit log & multi-shop portfolio, UI hardening, data lifecycle,
and the KPI catalogue / staff & product analytics (its 16.14 roadmap slots into Phases 1–3).

Addendum placement recap:

| Addendum section | Phase (slot in this file) |
| --- | --- |
| 2 defect register blocking batch (X-1–X-6, X-15, X-16, X-18–X-21, X-36, X-37, X-40, X-41, X-44, X-46) | Phase 0 (with §0 debts) |
| 2 defect register, rest | delivered with the owning section |
| 3 verification & cloud linking | Phase 0→1, needed before eTIMS goes live |
| 4 eTIMS enablement, buyer details | Phase 1, with §5 returns/credit notes |
| 5 printing subsystem | Phase 1 (layout fixes Phase 0) |
| 6 scanning subsystem | Phase 1 |
| 7 in-app updates & rollback | Phase 1, before any schema-changing release |
| 8 Auth & PIN hardening | Phase 2 (lockout/idle fixes Phase 0) |
| 9 support & feedback | Phase 2 |
| 10 import/export/Sheets | correctness Phase 1; wizard+undo Phase 3 |
| 11 transactions & reports | Phase 1 (detail) + Phase 2 |
| 12 audit log & multi-shop | Phase 2 |
| 13 UI hardening | Phase 1 + ongoing |
| 14 data lifecycle | Phase 1–2 |
| 16 KPI catalogue & drill-down | stage A Phase 1, B Phase 2, C Phase 3 |

---

## Implementation criteria (how we build here)

These rules apply to every item below and were used to judge work "done" this session.

1. **One feature per pass.** Schema bump (`schemaVersion` +1) in
   `duka_pos_app/lib/db/database_helper.dart` (additive only; shared create-helper used by both
   fresh install and upgrade branch — migration parity is TESTED), model file, DB API, screens,
   ARB strings (`lib/l10n/app_en.arb` + `flutter gen-l10n`), backend (prisma model + SQL migration +
   route + tests), then tests (DB + widget + contract), then verify.

2. **Verify loop after each feature:**
   - `flutter analyze` — must be zero issues.
   - `flutter test --concurrency=1 --exclude-tags=real-network`.
   - Backend: `npx tsc --noEmit` && `npx vitest run`.
   - Start the stack (`docker compose up -d db keycloak keycloak-init backend`) — backend listens
     on host **:3100**, healthcheck is a node-based `fetch` against `/health`.

3. **Data discipline:** money is integer minor units only; timestamps are local ISO strings;
   append-only ledgers write new rows, never edits; every multi-row write is one transaction;
   every new syncable table gets a `uuid TEXT UNIQUE` column from day one.

4. **Widget tests:** use `test/support/harness.dart` (`pumpApp(appState: …)`). Bridging rule
   discovered this session: **a sqflite-ffi answer lands only inside `tester.runAsync`** — bridge
   a real-time window (300–900 ms) after each tap that writes, then fixed `pump(350ms)`; never
   `pumpAndSettle` a sheet that contains a focused text field (the caret blinks forever = settle
   timeout).

5. **Owner-only gating by default** for money-adjacent config (credit, VAT, TIN, till code,
   taxes). Cashiers see nothing unless a setting explicitly allows it (spec D5).

## Ordered TODO — the active delivery queue

This is the authoritative execution order for the remaining handover and addendum work. The
queue is deliberately feature-based: finish one item end to end, run its verification gate, then
start the next item. A partial implementation is not complete until its app, local data, backend,
sync/offline behavior, role boundaries, UI states, and regression coverage all pass together.

### Stage A — finish every partial or already-started feature first

- [x] **P-01 — eTIMS buyer details.** Carry the attached customer's name/TIN from the local sale
  through offline queue, backend upload, eTIMS invoice/credit-note payload, receipt display, and
  retry/idempotency paths; verify walk-in sales remain buyer-free.

  **Verified 2026-10-24:** buyer name/TIN are snapshotted on the local sale, included in the
  offline `/sales/sync` contract and backend `Sale`, reused by eTIMS invoice retries, and carried
  from the original filed invoice into credit-note payloads rather than reading mutable customer
  data. Focused eTIMS/backend checks passed; full Flutter suite passed 1,587/1,587; full backend
  suite passed 106/106; analyzer, build and lint are clean.
- [x] **P-02 — Split payments.** Complete the tender model, payment sheet, cash/M-Pesa/manual
  retry states, pending-payment recovery, eTIMS largest-tender rule, and prorated return refunds.

  **Verified 2026-10-24:** split tenders persist one payment row per tender; pending payments
  retain tender and intended-total amounts; the payment sheet and retry/recovery paths are covered;
  eTIMS uses the largest tender method; and returns now persist deterministic largest-remainder
  allocations back to the original tenders and include them in offline return sync. Focused
  returns/database/migration checks passed 160/160; full Flutter suite passed 1,588/1,588;
  analyzer is clean and the runner terminated with no leftover test process.
- [x] **P-03 — Portable backup and restore completion.** Finish failed-media-write rollback and
  replacement-phone eTIMS release-number acceptance; prove an interrupted restore leaves the
  original database and media intact.

  **Verified 2026-10-24:** restore now applies referenced media with byte-for-byte rollback
  protection before replacing SQLite data, and rolls media back if the database transaction fails.
  Replacement-phone restore preserves the till/eTIMS receipt sequence and accepts the next
  contiguous number. Focused backup/migration checks passed 62/62; full Flutter suite passed
  1,590/1,590; analyzer and diff checks are clean, with no leftover test runner.
- [x] **P-04 — M-Pesa till matching app.** Finish setup, incoming-payment cache and screens,
  exact-match/overpayment decisions, offline disputed tenders, daily expiry job, and live arrival
  event; verify two tills cannot claim one payment.

  **Verified 2026-10-24:** the app now durably queues an offline claim after the sale commits,
  retries it during verified sync, and exposes disputed claims separately; the backend claim remains
  atomic and tenant-scoped with a conflict for a second till, broadcasts new arrivals over the live
  channel, and expires stale unclaimed rows immediately on startup plus on its daily timer. Focused
  database/migration checks passed 147/147; backend tests passed 106/106, TypeScript build and
  zero-warning lint passed, the full Flutter suite passed 1,591/1,591, analyzer and diff checks are
  clean, and all test processes terminated.
- [x] **P-05 — Receipt sharing app.** Finish the shared receipt document, text/PDF/link actions,
  masked recipient storage, revoke flow, and offline behavior; verify public links expire/revoke.

  **Verified 2026-10-24:** post-sale and transaction-detail journeys offer text, local PDF, and
  public-link sharing; optional phone/email recipients are stored only in masked form. Offline
  text/PDF sharing remains available and local share history is retained when link minting fails.
  Backend tests cover tenant-owned immutable snapshots and 410 responses for revoked and expired
  links. Focused receipt checks passed 48/48; full Flutter suite passed 1,594/1,594; backend
  tests passed 108/108, TypeScript build and zero-warning lint passed, Compose config is valid and
  the local backend/Postgres/Keycloak/object-storage stack is healthy, analyzer and diff checks are
  clean, and all test processes terminated.
- [x] **P-06 — Supplier reordering.** Supplier terms/channels, product-supplier links, par levels,
  purchase orders, grouped velocity suggestions, share/receive-against-PO, and sync are complete.
  Schema v55 adds durable supplier/product-supplier/purchase-order sync flags; `/api/reorder` is
  tenant/auth protected, idempotent through the existing operational stream, and included in the
  bounded pull path. Receiving a partial/complete order re-queues its status. Focused database and
  migration checks passed 148/148; the full serial Flutter suite passed 1,595/1,595; backend tests
  passed 108/108; TypeScript build, zero-warning lint, analyzer, and diff checks are clean; and all
  test processes terminated. P-07 is next.
- [x] **P-07 — Sync Center completion.** Add every required queue/status source, role-aware actions,
  plain-language error mapping, live refresh, and safe conflict actions; no tax document may be
  deleted from this surface. Partial work now includes manager/owner-only access, live queue counts,
  queued and rejected eTIMS retry actions, and confirmed stock-conflict review that never deletes
  the queued sale or tax record, plus plain-language mappings for common KRA/network errors. The
  final surface also reports issued eTIMS rows, labels credit-note queue rows, counts pending
  M-Pesa prompts and offline claims, separates cloud-link from identity-verification status, and
  reports backup, printer, storage, operational-sync and remote-mirror state. `countPendingPayments`,
  `countPendingIncomingPaymentClaims` and `etimsStatusCounts` are covered by database tests; the
  role-gated screen and conflict-review safety are covered by widget/DB tests. Verified 2026-10-24:
  focused checks passed 99/99 plus Sync Center role coverage; the full serial Flutter suite passed
  1,596/1,596; backend build and zero-warning lint passed; full backend Vitest passed 111/111; local
  Compose services are healthy and `/health` returned `{"status":"ok"}`; diff check passed and no
  test runner remained.
- [x] **P-08 — Multi-device sync completion.** Completed 2026-10-24. Catalogue, sales, staff,
  customer/credit, shifts, serving cups, returns, receipts, reordering, stock movements,
  expenses/till controls, drawer events, M-Pesa claims, operational mirrors, and backups use
  bounded queues/pages, tenant-scoped keys, idempotent retries, and advancing cursors. Multi-item
  sales and stock movements use deterministic product ordering to avoid cross-till deadlocks.
  Losing offline sales are persisted in `sale_sync_conflicts`; managers/owners can accept with
  negative stock or void them without deleting the local receipt. HTTP tests cover conflict
  retention and authentication, while app tests cover offline queue visibility and resolution.
  Verified: backend build/lint and serial Vitest 118/118; focused app checks 99/99; full serial
  Flutter suite 1,596/1,596; Compose rebuild, migration status, health, and runner cleanup passed.
- [x] **P-09 — Analytics/dashboard completion.** Finish elapsed-aligned comparisons, payment
  split/credit views, attention and expiry cards, VAT reconciliation, slow movers, price/cost
  history, one-year exports, remote transaction detail, and dashboard performance checks.
  **Completed 2026-10-25:** local and online analytics now expose VAT-exclusive taxable sales
  and captured line VAT, with explicit non-filing wording while KRA remains inactive. Verified
  remote product-drilldown transactions now open a tenant/role-scoped receipt-detail endpoint
  with line items and tenders. Local product saves now retain indexed price/cost history and
  product drill-down displays it. Analytics now also exposes active dated batches expiring within
  seven days from the indexed local ledger. Slow movers are a bounded SQL aggregate including
  zero-sales products; default sales exports no longer hide a 10,000-row cap, while explicit
  limits remain available. A 100,000-sale aggregate regression stayed under the 500 ms budget.
  Verified: analyzer, focused analytics checks 41/41, full serial Flutter suite 1,600/1,600,
  backend build/lint, serial Vitest 119/119, Compose health, and migration status.
  The tax boundary is now enforced consistently across tenant and system-admin settings:
  local VAT reporting remains available, Risiti by PesaStack Limited is the planned
  server-side provider, and KRA/eTIMS cannot be activated while the deployment gate is false.
  **Release decision:** KRA/eTIMS activation is intentionally deferred for the current release.
  Keep `TAX_REPORTING_ACTIVATED=false`; local VAT/tax evidence and reconciliation remain available,
  but no KRA submission or production tax-rule activation is claimed. Revisit this only after
  current KRA/accountant approval, provider onboarding, reviewed effective-dated rules, and the
  tax release gates have been completed.
- [x] **P-10 — Z/X reports.** Verify or complete gapless immutable shift reports, reprints, X
  previews, KRA comparison, local PDF output, and 58/80-mm print goldens. **Completed
  2026-10-25:** closed shifts now allocate a transactional gapless Z sequence and persist an
  immutable snapshot containing cash, payment, VAT/taxable, and eTIMS outcome totals. The
  reports screen keeps the existing live X preview, shows a local-vs-KRA comparison state,
  reprints the stored Z snapshot, and exports a closed shift to a local PDF. Receipt/Z layouts
  are bounded for both 58-mm and 80-mm paper. Verified: focused shift/report/receipt checks
  51/51, affected-file analyzer, full serial Flutter suite 1,602/1,602, diff check, and
  runner cleanup.

### Stage B — only after Stage A is green, build the remaining features in this order

- [x] **R-01 — Expenses and till movements.** Categories, atomic cash controls, write-offs,
  expected-cash reconciliation, approval thresholds, reports, and offline sync.
  Completed 2026-10-25: owner-configurable cashier approval limit (default KSh 5,000), manager PIN
  escalation with approver retained on the immutable expense row, durable receipt-photo paths,
  category deactivation, 7/30/365-day reports with share bars, and shift-close component
  breakdowns. Verified by focused database/policy/shift tests 157/157, affected analyzer,
  and full serial Flutter suite 1,606/1,606; runner terminated cleanly.
- [x] **R-02 — Discounts and price overrides.** Reasons/settings/permissions, largest-remainder
  allocation, discounted VAT, receipts/eTIMS, returns, and below-cost safeguards.
  Completed 2026-10-25: seeded reasons and owner settings, role/approval gates, line and order
  discounts, shared deterministic largest-remainder allocation, discounted VAT snapshots,
  receipt/eTIMS persistence, discounted returns, and below-cost protection. Verified focused
  money/database/receipt tests 168/168, affected analyzer, and full serial Flutter suite
  1,607/1,607; runner terminated cleanly.
- [x] **R-03 — Hold and resume sales.** Durable carts, customer capture, expiry/resume validation,
  stock/price warnings, shift/sign-out handling, and offline recovery.
  Completed 2026-10-25: durable carts with customer capture and discount/portion snapshots,
  ten-cart cap, expiry cleanup, current-stock validation, explicit changed-price confirmation,
  held-sale warnings on sign-out and shift close, and offline resume. Verified focused
  database/shift/idle tests 150/150, affected analyzer, and full serial Flutter suite 1,608/1,608;
  runner terminated cleanly.
- [x] **R-04 — Cash drawer controls.** Configuration, drawer event ledger, pulse command, no-sale
  approval/audit, offline behavior, and report counts.
  Completed 2026-10-25: owner-only drawer settings with connector pin and safe pulse timings,
  exact ESC/POS pulse encoding, append-only offline drawer events with sale/approval/success
  metadata, no-sale permission/manager approval/audit flow, and report counts. Focused receipt and
  database tests 138/138, affected analyzer, full serial Flutter suite 1,608/1,608, backend
  build/lint, and backend Vitest 120/120 pass; all runner processes terminated cleanly.
- [x] **R-05 — Stocktake.** Snapshot/blind count/recount, variance calculation, atomic application,
  freeze mode, audit, and multi-till interaction.
  Completed 2026-10-25: offline stock snapshots support blind counts, variants, recounts, freeze
  mode, atomic variance movements, line-count-time reconciliation, audit attribution, and the
  existing synced stock-movement path for multiple tills. Focused database/migration tests 155/155,
  affected analyzer, and full serial Flutter suite 1,610/1,610 pass; runner terminated cleanly.
- [x] **R-06 — Packs and cartons.** Pack model/barcode namespace, unit-cost conversion,
  receive-by-pack, sale behavior, returns, and sync.
  Completed 2026-10-25: product and variant pack bindings, collision-safe pack barcode lookup,
  base-unit receiving and costing, pack sale snapshots/returns, held-cart persistence, and normal
  stock sync integration. Focused database/migration tests 156/156, affected analyzer, and full
  serial Flutter suite 1,611/1,611 pass; runner terminated cleanly.
- [x] **R-07 — Barcode labels.** Internal EAN-13 generator, assignment, templates, print jobs,
  resumable batches, and 58/80-mm goldens.
  Completed 2026-10-25: internal EAN-13 assignment, label encoding for both paper widths,
  persisted print jobs with chunked progress and retry from the unprinted suffix, and printer
  failure handling that leaves the job recoverable. Focused label/database/migration tests 193/193,
  affected analyzer, and full serial Flutter suite 1,613/1,613 pass; runner terminated cleanly.
- [x] **R-08 — Expiry and batches.** Batch receiving, oldest-first allocation, expired-stock
  blocking, write-off/dashboard cards, returns, and sync; measured tanks remain excluded as specified.
  Completed 2026-10-25: expiry batches now carry variant, batch-code, and lifecycle metadata;
  existing countable stock is backfilled when tracking is enabled; variant sales allocate and audit
  their own batches; manager write-offs update stock and the append-only ledger atomically; expired
  stock has a distinct analytics card. Focused expiry/variant/analytics tests 70/70, affected
  analyzer, and full serial Flutter suite 1,615/1,615 pass; runner terminated cleanly.
- [x] **R-09 — Granular permissions.** Permission catalogue, role defaults, staff overrides,
  owner-managed matrix, route/action guards, and approval integration. Completed 2026-10-25:
  role and staff modes now support allow/approval/deny with owner-only matrix editing; route
  guards use the same lookup; discount, expense, drawer, stock receiving/adjustment and stocktake
  application actions honor approval mode; and stock permissions do not widen a cashier's
  own-sales financial scope. Focused permission/routing checks passed 47/47, approval widgets
  5/5, full serial Flutter suite 1,620/1,620, analyzer clean, backend build/lint and Vitest
  121/121 passed, Compose `/health` returned `{"status":"ok"}`, and runners terminated cleanly.
- [x] **R-10 — Notifications.** Background checks, deduplication, quiet hours, counts-only
  content, PIN-gated routing, offline/online behavior, and lifecycle cleanup. The notification
  boundary now also includes platform-admin announcements delivered through the update manifest:
  only the system-admin allowlist can publish or clear them, publication is audit logged, and the
  app displays the tenant-neutral message without putting platform or shop data in the payload.
  Local notification deduplication is now transactional, so a foreground check and a background
  check racing each other cannot emit the same dedupe key twice. Connected tills also receive a
  tenant-neutral live-channel announcement immediately; launch/resume manifest polling remains
  the recovery path when a device was offline or backgrounded. Focused notification/update/live-
  channel tests passed 36/36, affected lifecycle tests passed 19/19, the full serial Flutter
  suite passed 1,626/1,626, analyzer was clean, and backend Vitest/build/lint passed 123/123.
  The product boundary is in-app, counts-only delivery (no lock-screen notification permission):
  the super-admin path is immediate for connected tills and recovered on launch/resume/update
  checks. The local policy is now reachable
  from the role-aware More menu's Notifications item; the shell keeps only account identity,
  logout, and owner/manager Credit visible in the top bar, while Settings, Support, Marketplace,
  and Notifications live under More. The compact/rail/drawer navigation contract and full serial
  Flutter suite were reverified at 1,627/1,627 on 2026-10-25. R-10 is complete within that
  in-app boundary; a future OS-push product decision would be a separate scope change.
- [ ] **R-11 — Swahili/localization hardening.** Hard-coded-string sweep, glossary, ARB parity,
  receipt language, pseudo-locale overflow coverage, and CI enforcement.

  **Progress (2026-10-25):** Swahili is now a supported locale with a translated shell,
  shared actions and errors; `lib/l10n/GLOSSARY.md` fixes product terminology (including big
  cup/small cup), `tool/l10n/check_arb.py` rejects unknown keys and placeholder drift, and the
  CI validation job runs that check. Receipt labels now follow the active English/Swahili
  locale for sale printing and reprints. Feature-copy sweep, complete catalogue translation,
  and pseudo-locale overflow coverage remain before this item can be marked complete.

### Expansion queue — added to the active implementation goal

The Version 14 Master Codex expansion supplied for integration is now tracked in
`EXPANSION-IMPLEMENTATION-TODO.md` as E-01–E-14. These tasks begin only after R-11 is complete
and its full serial completion gate is recorded. They preserve the four-profile rule (`drinks`,
`duka`, `fashion`, `open`), shared engines, integer-minor-unit financial postings, owner-scoped
all-shops reads, restricted commercial contributions, and the Release-1 boundaries stated in the
supplied plan.

### Completion gate for every TODO item

Before moving the checkbox to DONE, run the focused unit/database/widget/contract tests for the
item, `flutter analyze --fatal-infos`, the full Flutter suite serially with
`--concurrency=1 --exclude-tags=real-network`, backend lint/build and the full Vitest suite with
file/concurrency limits, then start the local compose stack and verify `/health`. Confirm no test
or compose child processes remain. Record the evidence and the date beside the completed item.
Do not run all Flutter shards concurrently on a development machine.

---

## Mid-edit state (left unfinished this session — resolve first)

### Credit settings UI — DONE

The owner-only credit panel, edit sheet, settings strings, persistence and widget coverage are
present and compile under the current tree.

Decision: either finish the credit settings block (panel + sheet + strings + test) or revert the
partial edits so the tree compiles. Do not commit in the broken state.

### Credit icon in top app bar — DONE

The role-gated wallet icon is in the shell app bar beside support/profile and opens the existing
customer/credit route. Cashiers do not see the shortcut unless the checkout permission allows
credit use.

---

## 0. Debts from the last session (fix first, small)

| Debt | Where | Note |
| --- | --- | --- |
| `paymentModeCodeFor` has no `credit` case — on-account invoices file as Cash | `duka_pos_backend/src/services/etims.ts` | DONE — `credit` maps to `Credit`; contract covered |
| `uploadPendingBatch` does not branch on `documentType` — credit-note docs would be filed as invoices | `duka_pos_backend/src/services/etims.ts` | DONE — credit notes build as `NC` and upload as `CREDIT NOTE`; contract covered |
| No widget test for the manager approval sheet (wrong-PIN, decline, no-managers) | `duka_pos_app/test/ui/manager_approval_sheet_test.dart` | Done this session — file exists and passes |
| Credit SETTINGS UI missing | `lib/screens/settings_screen.dart` | DONE |
| Dashboard "Owed to you" card + Manage-customers entry | `lib/screens/dashboard_screen.dart` + `dashboard_attention.dart` | `db.creditSummary()` + `creditAging()` built and tested |
| eTIMS invoice buyer fields (customer name/TIN on sale payload) not passed through | `backend_service.dart` sale upload + `etims.ts` InvoiceInput | Spec 7.6; sales already carry `customer_id` app-side |
| Aging report belongs in Analytics | analytics screen | `creditAging()` already returns buckets |

---

## 1. Phase 2 remainder (spec §8–§11)

### §8 Expenses and till movements — DONE (2026-10-25)
- Schema (v31): `expense_categories` (seeded: Rent, Electricity and water, Transport, Wages,
  Supplies, Airtime and data, Licences and fees, Bad debts (system), Other), `expenses`,
  `till_movements` (cash_in / cash_drop / float_adjustment).
- Expected-cash formula extension: replicating the pattern used when cash credit repayments were
  added to `expectedCashForShift` (`database_helper.dart` ~LINE 6412) — expenses paid from
  `till_cash` SUBTRACT, `till_movements` add/subtract by type, all scoped by `shift_id`.
- Bad-debts write-offs: `recordCreditAdjustment(type: 'writeoff')` already exists — when expenses
  land, write an `expenses` row from the same action so net profit is true (spec 7.5.6).
- Screens: Pay out sheet (amount, category, paid-from, receipt photo, cashier limit via approval
  sheet), Cash in/drop sheet, Expenses screen (7/30/365-day range bar, category
  totals + share bars, entries by day), shift-close expected-cash breakdown lists every component
  with counts, Analytics net-profit card.
- Tests: full expected-cash component query, approval thresholds at limit and limit+1; DB:
  till-cash expense tied to shift, void rules (open vs closed shift), category deactivation and
  approval retention; widget layouts remain covered by the full suite. Focused 157/157 and full
  serial suite 1,606/1,606 passed.

### §9 Discounts and price overrides — DONE (2026-10-25)
- Schema (v32): `discount_reasons` (seeded), `sale_items.list_unit_price_minor`,
  `sale_items.discount_minor`, `discount_reason_id`, `price_overridden`;
  `sales.subtotal_minor`, `order_discount_minor`, `order_discount_reason_id`,
  `discount_approved_by`. Settings: enabled, cashier %, manager %, reason required, allow below cost.
- Order discount allocation uses the shared largest-remainder primitive in `utils/money.dart`
  (also used by split refunds), so allocated pieces sum exactly and ties are deterministic.
- VAT: computed on the discounted net (extract from discounted gross, prices inclusive); the
  pattern for per-line VAT lives in the v23 tax snapshot code (`vatComponentOf`).
- Edit-line sheet on the cart (tap a line), receipt shows struck-through originals,
  eTIMS per-line discount; returns refund the DISCOUNTED amount by default.
- Ship OFF by default (D5); permission gating through the manager approval sheet.
- Verified by focused 168/168 and full serial Flutter 1,607/1,607; backend build/lint and
  serial Vitest 120/120 remain green, with no runner leftovers.

### §9.5 Hold and resume sales — DONE (2026-10-25)
- Held carts persist customer, product/variant/pack/portion, discount and price snapshots
  offline, with a ten-cart cap and expiry cleanup.
- Resume revalidates product availability and current stock, warns before using changed prices,
  restores the attached customer, and preserves the existing checkout safeguards.
- Sign-out and shift close explicitly warn when held sales remain. Focused 150/150 and full
  serial Flutter 1,608/1,608 passed; no runner leftovers.

### §10 Split payments — PARTIAL
- `sale_payments` table + recordSale writes ONE payment row today. TO BUILD: the redesigned
  payment sheet (Total due / Paid so far / Remaining block; tenders list; add-payment row;
  M-Pesa STK tender with cancel/retry/manual-code; fast path protected by a test — exact-amount
  single tender completes in two taps).
- recordSale change: accept a list of tenders, write one `sale_payments` row each (amount ≠
  tendered for cash; `payment_method` summary column becomes `split`).
- Pending-payment record: add tender amount + intended sale total fields (schema).
- eTIMS: send the largest tender's method (decision D6) — `paymentModeCodeFor` above.
- Returns of a split sale: default refund prorated by tender via largest-remainder.

### §11 Portable backup & restore — PARTIAL
- Passphrase-KDF encryption (PBKDF2-SHA256 600k), manifest verification, restore logging,
  nightly local copy, and the seven-day reminder are DONE and covered by backup tests.
- Full snapshots now include referenced local product images and the device avatar as base64 media
  entries; restore validates every media path and payload before replacing any table, then recreates
  their directories. Profile photos remain
  R2 objects with only their URL stored in the profile row. Older snapshots without `media` remain
  readable. Remaining work: verified restore-then-swap for a failed media write and eTIMS release
  numbering acceptance on a replacement phone.

---

## 2. Phase 3 remainder (spec §12–§20)

### §12 M-Pesa Till matching — BACKEND DONE, APP TO BUILD
- Backend (done, tested): public `/callback/mpesa/validation|confirmation` (key-guarded,
  idempotent, masked payer), `/api/mpesa/incoming?since=&status=`, `.../:id/claim` (atomic;
  409 with who/when), `.../:id/ignore` (manager), `expireOldUnclaimed()` (24 h) — not yet wired
  to a scheduler; add a daily job.
- Live event NOT emitted: the ws server exists (`index.ts` `wss.on('connection')`) — add a
  broadcast on new C2B rows so the till banner can push.
- APP: setup wizard (Till/Paybill, shortcode, test instructions), `incoming_payments` table
  (per-device cache), M-Pesa (paid to Till) tender in the payment sheet with unclaimed list +
  exact-match preselection, overpayment prompt (manager decision), arrival banner + sound,
  Incoming payments screen (Unclaimed/Claimed/Ignored tabs), offline claim → unverified tender
  + queue + conflict → payment-disputed flag.
- Env for the stack: `MPESA_CALLBACK_KEY`, `MPESA_TILL_TENANTS` ("shortcode=tenantId" pairs) —
  placeholders active in `docker-compose.yml`, real values via `.env`.

### §13 Hold & resume sales — DONE
- Schema: `held_carts`, `held_cart_lines` (name/price snapshots, portion fields, discount
  fields). Settings: max carts (10), expiry (24 h/shift end), reserve stock.
- Cart header Hold button + Held(n) chip sheet + resume-with-revalidation (price badge,
  deactivated removal, stock highlight); sign-out/shift-close warnings count held carts; expiry
  sweep via a fake clock in tests.
- NOTE: `_cartCustomer` was deliberately removed from the sell screen this session — when
  holding lands, the CUSTOMER must be captured in the held cart (the picker work provides it).

### §14 Receipt sharing — BACKEND DONE, APP TO BUILD
- Backend (done, tested): `/api/receipt-links` create/revoke (JWT) + `/:token/page` (public,
  keyed, 410 withdrawn/expired).
- App: the shared receipt document model (one structure → print/text/PDF/link), Share buttons on
  the sale-success sheet + transaction detail, footer editor settings, `receipt_shares` table
  (masked recipient), link revoke from transaction detail, offline behaviour (text + PDF work
  offline; link needs network).

### §15 Cash drawer — DONE
- Settings (enabled, open-on-cash-sale, connector pin and pulse timing), `drawer_events` table,
  byte-exact pulse command via the printer connector, no-sale approval/audit, offline-safe event
  queue, and Reports no-sale counts are implemented and verified.

### §16 Stocktake — DONE
- `stock_counts` and `stock_count_lines` support expected snapshots, blind mode, line recounts,
  line-count-time variance, atomic count movements, audit attribution, and freeze mode that blocks
  only already-counted items on Sell. Uncounted lines remain unchanged and stock movements remain
  in the normal multi-till sync queue.

### §17 Packs & cartons — DONE
- `product_packs` supports product/variant binding and a unique pack barcode namespace alongside
  product codes; sale lines snapshot pack identity and quantity, unit cost is derived from the pack
  line cost, and receiving by pack converts to base units through the normal stock ledger.

### §18 Suppliers & reordering — PARTIAL
- `suppliers` table + phone capture + receipts link done. TO BUILD: supplier contact fields done
  — lead_time/payments_terms/order_channel columns; `product_suppliers`; par levels;
  `purchase_orders` + lines (own series); reorder screen (velocity 30-day, grouped by supplier,
  suggestions rounded to packs); share order as message/PDF; receive against PO (the receive
  session prefill).

### §19 Barcode labels — DONE
- Internal EAN-13 range/check-digit assignment, label templates and persisted print jobs, retryable
  chunked printing, and 58/80-mm encoder coverage are implemented.

### §20 Sync Center — TO BUILD (depends on several above)
- One screen reading: eTIMS queue rows (pending/issued/rejected incl. credit notes),
  unverified M-Pesa, unclaimed incoming, backup log, cloud link/verify, printer status, storage.
  Counts <100 ms, live refresh, role gating, error-code→plain-text mapping table (never delete a
  tax doc from here). **DONE for stock-race visibility:** rejected offline sales are now retained
  in a local `sync_conflicts` ledger and shown to owners/managers in Sync Center; the sale remains
  queued until reviewed.

### §23 Granular permissions — TO BUILD (the runtime approval piece exists)
- The manager approval sheet (name + PIN → approver id, declines never approve) is built; what
  remains is the configurable matrix: `role_permissions` + `staff_permission_overrides`, the
  permission catalogue keyed from spec §2.2 (`view_profit`, `process_return`, `give_discount`,
  `record_expense`, `receive_stock`, `adjust_stock`, `stocktake`, `manage_customers`,
  `sell_on_credit`, `open_drawer_no_sale`, `export_data`, `manage_settings` + §23.2 extras), the
  matrix screen with owner verification, and route guards reading the same lookup.
- This session's features already gate inline (credit: owner/manager/cashiers-setting; receive
  stock; deliveries void owner-only) — migrating those call sites onto the catalogue is part of
  this feature.

### §26 Analytics and dashboard — PARTIAL
- Dashboard: sales/profit/shift cards exist; TO BUILD the like-for-like comparison (elapsed-
  aligned), payment-split stacked bar (with credit), attention card, expiring soon (needs §21),
  owed-to-you, low stock consistency fix.
- Analytics: range picker + persistence, per-KPI change, heatmap, breakdown cards, VAT summary
  reconciling to eTIMS + CSV/PDF export gated by `export_data`, slow movers, price/cost history
  views + `product_price_history` table.
- Product drill-down is now wired from the ranked analytics list. It shows period KPIs, trend,
  staff, payments, hourly pattern, companions, stock timeline and transaction records; local
  records open the full sale-detail sheet. The header also shows local catalogue photo,
  category, current sell price/cost, on-hand stock and status, with an explicit summary for
  remote records from another till. Remaining work is the broader KPI/catalogue roadmap and
  remote transaction-detail route.
- Online `/reports/sales` and `/reports/products` now enforce the supported one-year window
  (366 days, including leap-year boundaries), matching the app's range contract.
- Performance budgets: range query 100k sales <500 ms, dashboard <1 s.

### §27 Z and X reports — COMPLETE
- The local `shift_reports` table assigns a gapless Z sequence inside the close transaction and
  stores the cash, payment, VAT/taxable, eTIMS, and KRA-activation state as an immutable JSON
  snapshot. Closed reports can be viewed, reprinted from that snapshot, and exported as local
  PDFs. X remains a read-only live preview with no sequence allocation. The report detail makes
  the local-vs-KRA boundary explicit while KRA is inactive, and pure printer regressions cover
  both 58-mm and 80-mm column budgets.

---

## 3. Phase 4 (spec §21, §22, §24, §25)

- **§21 Expiry & batches** — `products.tracks_expiry`, `stock_batches`, `sale_item_batches`,
  oldest-first allocation at sell, expired blocked for everyone, dashboard expiring/write-off
  cards. Receive-stock gains the expiry date picker (receive session already exists as the seam).
  Measured/tank products out of scope v1. DONE: variant-linked batches, batch status/code,
  expiry backfill, atomic manager write-off, return restoration, and offline analytics cards are
  implemented and covered by focused tests.
- **§22 Multi-device sync** — the big one; staged (owner reporting → catalogue → full).
  Foundations present: stock movements ledger + uuids + harmony of append-only streams.
  `sync_outbox`/`sync_cursor` + HLC clock, devices table, deterministic
  simulation harness. Registration paths already exist on the backend (tenant/device registration).
  eTIMS per-device series follows.
  Automatic sync now drains operational backlogs in bounded loops, and catalogue uploads are
  batched at 200 products so a large offline suffix can resume without replaying prior batches.
  Catalogue pulls are now also bounded to 200-row pages with a continuation offset, so a large
  tenant cannot turn one reconnect into an unbounded response.
  Shot-cup configuration pulls now use the same stable `updatedAt|id` cursor and bounded page
  drain as the other operational streams, so a long-offline till does not stop after the first
  500 serving configurations.
  Customer/credit uploads now use 200-customer and 500-ledger-entry batches; pulls page both
  streams independently before merging the UUID-keyed snapshot locally.
  Verified remote sales reports now also return bounded daily aggregates, so the analytics line
  graph reflects all tills instead of silently falling back to the current device's days.
  The app has a durable local `sync_conflicts` ledger for last-stock sale races. The backend also
  persists each losing sale in a tenant-scoped `sale_sync_conflicts` ledger, locks multi-item stock
  in deterministic product-id order, and exposes an idempotent manager/owner resolution action
  (accept with negative stock or void) without deleting the local receipt. All staged sync streams
  are now bounded and covered by the P-08 completion gate.
- **§24 Notifications** — background checks, dedupe keys, quiet hours, tap routing through PIN;
  content = counts only.
- **§25 Swahili** — the hard-coded string sweep FIRST (build check), glossary, ARB parity in CI,
  psuedo-locale overflow shots, receipt language setting.

---

## 4. Cross-cutting open decisions (spec §28.7 — confirm before building §9, §12, §21)

KRA tax-category codes; whether one invoice may carry several payment types; credit-note reason
codes (same-day cancellations); pack unit-of-measure codes; buyer detail requirements.
Till/Paybill registration with Safaricom. Legal retention vs account deletion. Default cashier
discount; cashiers-credit default; expiry warning days; whether poured drinks can ever be returned.

---

## 5. Environment notes (from this session)

- Flutter SDK: `/home/bstudio/.local/share/flutter/bin/flutter` (not on PATH).
- Backend: `npm ci` then `npx prisma generate` (schema has `binaryTargets` for the container —
  keep them). Vitest runs against TS sources (config fixed).
- The stack binds the backend to host **:3100** (host :3000 is occupied by an unrelated
  process). `duka_pos_keycloak_init` must complete before the backend starts (compose handles
  the order; the realm is created idempotently via `docker/db-init.sql` + keycloak-init).
- `duka_pos_admin/` is effectively empty (only node_modules) — nothing to run there.
- Test tags: `--exclude-tags=real-network` skips the external-network probe tests (blackbee etc.)
  that hang without connectivity.

---

## Git state (for the next session)

There are uncommitted changes across both `duka_pos_app` and `duka_pos_backend` (`git status`).
The tree currently compiles at `flutter analyze --fatal-infos` with zero issues. The Flutter
suite and backend suite are run serially; do not launch all local shards concurrently.
