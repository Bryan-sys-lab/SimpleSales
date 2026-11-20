# PATCH 16 — Backend Contribution Pipeline and Existing Admin Panel Integration

## Non-negotiable product requirement

**The backend is the source of truth. The existing admin panel must display live data fetched from the backend.** This is an integration into the already-implemented admin panel, not a new admin app, static dashboard, browser-side calculation or mobile-to-admin direct upload.

The original v84 Commercial Intelligence Plan v13 explicitly says the admin panel is already implemented and must be extended, not rebuilt (§§49 and 54). It also says the mobile owner backup stream and commercial contribution stream are separate.

## v84 evidence / current gap

- `lib/services/owner_business_sync_service.dart` explicitly states that it is an owner-controlled operational backup service and “has no commercial-intelligence contribution method”. Its domain allowlist includes catalogue, sales, financial evidence, credit, receipts, stock movements, expenses and other owner records.
- `lib/services/backend_service.dart` contains authenticated backend communication and operational sync methods for products, variants, sales, financial evidence, supplier/reordering data, receipts, stock movements, expenses and other records. The inspected v84 mobile source contains no dedicated commercial-contribution endpoint/method.
- The original plan says the backend is Go, and explicitly instructs developers to inspect the existing backend/admin repositories, reuse their auth, routes, analytics jobs, partner management and database primitives, and avoid a second ingestion framework.
- The v84 archive does not include the separate backend or admin-panel repository. Concrete existing route names, migrations, UI filenames, auth roles and deployment configuration must be discovered from those repositories before coding.

## 1. Required end-to-end pipeline

```text
Mobile/local shop records
  └─ dedicated CommercialContributionService
       ├─ read current scope grants
       ├─ calculate aggregate period metrics from canonical repositories
       ├─ map to approved dictionary/taxonomy codes
       ├─ remove direct and indirect identifiers
       ├─ validate payload against pinned schema
       └─ enqueue minimized batch (offline/retry-safe)
                    │
                    ▼
Existing authenticated backend API
  ├─ derive tenant/workspace from auth context (not client payload)
  ├─ verify grant and scope server-side
  ├─ validate schema, dictionary, totals and idempotency
  ├─ reject forbidden keys/PII (strict allowlist)
  └─ persist restricted minimized batch + provenance
                    │
                    ▼
Backend processing jobs
  ├─ normalize taxonomy/unit/time/currency
  ├─ deduplicate and reconcile
  ├─ apply suppression / anti-differencing controls
  ├─ build versioned aggregate snapshots
  ├─ apply withdrawal, retention and deletion changes
  └─ record lineage and audit
          │                              │
          ▼                              ▼
Existing Admin Panel                 Partner output API
  ├─ overview                        ├─ licensed aggregates only
  ├─ coverage                        ├─ scope/quota/expiry
  ├─ quality                         ├─ disclosure controls
  ├─ contribution ledger (restricted)└─ partner audit
  ├─ datasets/snapshots
  ├─ partner delivery status
  └─ governance/consent/retention
```

Do not put any of this on the checkout critical path. If the device is offline or the backend is unavailable, POS writes continue locally. The commercial queue retries with backoff and idempotency; failure cannot block a sale.

## 2. Mobile contribution implementation

Create a separate `CommercialContributionService` or equivalent feature module. It may reuse the authenticated HTTP client/identity mechanism in `BackendService`, but it must not reuse `OwnerBusinessSyncService.run()` as its job queue or add market-intelligence records to `ownerBusinessDomains`.

Requirements:

- Build contributions from canonical repositories and approved aggregate periods; never serialize full SQLite rows or use generic `toJson()` of Product/Sale/Supplier/Customer models.
- Consent check is scope-specific and must be verified locally before enqueue, then verified again by backend at ingest.
- Use deterministic batch UUID/idempotency key; include schema and dictionary versions.
- Upload only coarse aggregates for a time bucket and normalized taxonomy/unit codes.
- No shop/tenant/business ID in body; backend derives authority and restricted contributor mapping from the verified token/context.
- No direct identifiers, staff/customer/supplier details, notes, receipts, exact timestamps, GPS, images or payment-provider references.
- Keep a locally queued batch only as long as needed to retry; delete it on scope withdrawal if not yet accepted. Encrypt at rest using the existing app security approach; never print payload into logs/crash reports.
- Use a distinct database table/queue and a separate sync status. Do not mix the contribution queue with ordinary owner backup state.
- Do not send one row per sale or a long-lived exact transaction history. The default contribution grain is shop-period-category-unit aggregate as defined by Plan v13 §54.
- Batch only after period close or a controlled schedule; choose a time granularity appropriate to cohort size and sensitivity.

## 3. Backend ingest contract

The following route names are logical examples. **Map them to the backend's existing versioning, routing, identity and naming conventions after repository inspection.** Do not create duplicate routes if an equivalent primitive already exists.

### 3.1 Consent/grant APIs

Logical operations:

- `POST /v1/commercial-intelligence/grants` — create an explicit scope grant from an authenticated owner/authorized business representative.
- `GET /v1/commercial-intelligence/grants/current` — return active scope grants for the current authenticated workspace.
- `POST /v1/commercial-intelligence/grants/{grant_id}/withdraw` — withdraw all or selected scope grants and start deletion/queue reconciliation.

Server must record the actual actor, role, notice version, purpose/scope, time and evidence. Do not accept `tenant_id`, `workspace_id`, `shop_id` or actor role from the client as proof of authority. Resolve them from auth/session and role policy.

### 3.2 Batch submission

Logical operation: `POST /v1/commercial-intelligence/contributions/batches`.

Example body shape (illustrative contract, not a claim that this endpoint exists today):

```json
{
  "batch_id": "uuid",
  "schema_version": "ci-contribution-v1",
  "dictionary_version": "2.0.0",
  "period": {
    "from_utc": "2026-10-01T00:00:00Z",
    "to_utc": "2026-10-31T23:59:59Z",
    "grain": "month",
    "reporting_timezone": "Africa/Nairobi"
  },
  "app_profile": "duka",
  "business_activity": {
    "scheme": "KESIC",
    "version": "approved-reference-version",
    "group_code": "approved-code"
  },
  "geography": {
    "scheme": "KE-COUNTY",
    "county_code": "approved-code",
    "grain": "county"
  },
  "dimensions": {
    "product_taxonomy": "GS1-GPC",
    "taxonomy_version": "2026-05",
    "category_code": "approved-code",
    "unit_scheme": "UNECE-REC20-or-local",
    "unit_code": "KGM",
    "currency": "KES"
  },
  "metrics": {
    "transaction_count": 120,
    "quantity_base_units": 420.0,
    "gross_sales_minor": 48500000,
    "discount_minor": 1500000,
    "refund_minor": 500000,
    "net_sales_ex_tax_minor": 45000000,
    "price_band_code": "configured-band-v1"
  },
  "quality": {
    "sale_line_coverage": 0.98,
    "category_mapping_coverage": 0.91,
    "unit_mapping_coverage": 0.95,
    "stock_tracking_coverage": null
  }
}
```

This is a **schema illustration only**. The example values are not production facts. The backend must reject any field not on its server-owned allowlist, including hidden nested identifiers. Avoid sending `business_activity`, `geography`, `metrics` or dimensions when the relevant consent scope is not active.

Server-side validations:

1. Authenticated actor has an active contribution grant for the submitted workspace and each included scope.
2. Tenant/workspace is resolved from authentication and checked against current owner/manager authorization.
3. Batch UUID is unique within its correct server-side contributor/grant scope; repeat delivery is idempotent.
4. Period is allowed, timezone/grain valid, values non-negative or signed only where explicitly allowed, currencies/units consistent.
5. Schema version and dictionary version supported.
6. All dimension codes exist in the specified reference release or are marked unmapped and excluded from code-dependent metrics.
7. Metrics reconcile with canonical definitions; cash receipts are not treated as revenue, tax is not merchant revenue, credit receivables are not cash-in, M-Pesa pending is not confirmed payment.
8. Reject/strip direct identifiers and unapproved keys; do not merely trust a `pii_removed: true` flag.
9. Persist accepted/rejected status, validation report, grant/purpose versions, received time, schema version and batch hash. Do not log raw bodies.
10. Never block the originating POS operation if ingest fails.

### 3.3 Restricted persistence and provenance

Reuse backend datastore conventions after inspection. Logical entities:

- `commercial_contribution_batches` (batch ID, restricted contributor reference, schema/dictionary/grant versions, period, received/accepted/rejected state, validation code, content hash, timestamps);
- `commercial_contribution_facts` (strictly allowlisted minimized aggregate facts; never direct source shop identity);
- `commercial_aggregation_runs` (job version, query/config version, time, status, source manifest hash);
- `commercial_dataset_snapshots` (snapshot ID, period, schema/dictionary, contributor/transaction counts restricted internally, suppression report, quality report, content hash, publish status);
- `commercial_partner_deliveries` (partner/dataset/snapshot/scope, delivery metadata, response hash, timestamp);
- `commercial_audit_events` (consent, grant, access, export, schema, release, deletion and retention actions);
- separate restricted contributor-token mapping only where operationally required.

Prefer shop-period-category aggregates. Retain row-level contribution detail only where a documented need and DPIA/privacy review justify it. Never store the raw POS row or original customer/supplier/staff identifiers in this layer.

## 4. Existing Admin Panel integration — mandatory

Extend the implemented panel using its current navigation, auth provider, role system, API client, components and design system. Add/extend one **Data Intelligence** area; do not build another admin product.

Admin UI must read from backend APIs. The frontend must not calculate network totals from a sample file, read a local/mobile DB, call POS sync endpoints as an admin data source, or embed static JSON fixtures in production.

Required views and backend data:

| Existing Admin Panel view | Backend data source | Main display |
|---|---|---|
| Network overview | Aggregated overview endpoint | Participating shops (only authorized admin aggregate), contribution trend, time/profile/activity coverage, freshness, transaction coverage, pipeline status |
| Market pulse | Published dataset snapshots | Category demand, volume, price bands/indices, payment mix and trend with period and coverage labels |
| Data coverage | Coverage aggregates | KeSIC/product/unit mappings, sale-line coverage, stock tracking, PO/receipt linkage, sample density |
| Data quality | Validation/reconciliation jobs | Accepted/rejected/duplicate/withdrawn/stale batches, exclusions, schema errors, reconciliation drift, sample/coverage warning |
| Contribution Ledger | Restricted backend endpoint | Minimized facts and lineage; no raw sale/customer/supplier/staff/shop-identifying data; restricted role only |
| Datasets & snapshots | Dataset registry | Version, period, dictionary, quality, suppression, publish status, manifest/hash |
| Partner delivery | Partner/delivery service | Partner scope, dataset grant, quota, API key status (masked), delivery runs and errors |
| Governance | Consent/retention/audit backend | Active grants by scope (aggregated), withdrawal/deletion queue status, notice versions, retention runs, audit metadata |

### 4.1 Required logical admin read APIs

Adapt route naming to existing backend conventions; do not blindly implement duplicate APIs:

- `GET /admin/data-intelligence/overview?from=&to=`
- `GET /admin/data-intelligence/coverage?from=&to=`
- `GET /admin/data-intelligence/quality?from=&to=`
- `GET /admin/data-intelligence/datasets`
- `GET /admin/data-intelligence/datasets/{dataset_id}/snapshots`
- `GET /admin/data-intelligence/datasets/{dataset_id}/snapshots/{snapshot_id}`
- `GET /admin/data-intelligence/contributions` — Data Steward / Platform Owner only; server pagination, fixed filters, strict page size, audited access
- `GET /admin/data-intelligence/partner-deliveries`
- `GET /admin/data-intelligence/governance`

Every response must include `generated_at_utc`, reporting period, timezone, dictionary/schema version, units/currency, coverage denominator, freshness and warnings. For metrics with suppressed data, return a typed suppressed state, not a fake zero or `null` that the UI labels as zero.

### 4.2 Backend authorization

- Merchant/account roles cannot access any admin/market intelligence route.
- Admin analyst can view aggregates/quality, not restricted contribution rows.
- Data Steward / Platform Owner may view minimized ledger with reason/audit; no raw POS row drill-through.
- Partner Manager handles partner grants/delivery but cannot inspect contribution ledger.
- Partner token accesses only approved dataset snapshots and endpoints, never admin routes/ledger.
- Every endpoint enforces role and dataset scope server-side. Hiding a tab in the UI is not authorization.

## 5. Admin panel data semantics

- Use the same backend calculation and dictionary version for all charts, exports and endpoints.
- Display sample coverage and known sampling bias; never call the current participating network “all Kenya” or representative unless methodologically supported.
- Distinguish `no data`, `not collected`, `insufficient sample`, `suppressed`, `not applicable`, `stale`, `failed` and numeric zero.
- Every chart/table shows period, unit/currency, denominator, freshness and quality notes.
- A platform administrator must be able to trace a published aggregate to its snapshot manifest, aggregation run, accepted batch versions and schema/dictionary versions, with the appropriate privilege boundary.
- No “export everything.” CSV/PDF export is generated server-side with the same suppression and field allowlist as the page/API; audit it.

## 6. Job scheduling and reliability

- Aggregate on server-side jobs, never in the admin browser.
- Idempotent ingest and aggregation; retry safe.
- Maintain a pending queue and dead-letter / exception state. Do not silently drop failed periods.
- Publish only after validation, data-quality and disclosure-control gates succeed.
- Track freshness per dataset; stale dataset must show stale and must not appear as current.
- Retention/deletion/withdrawal jobs must feed back into later snapshots and partner-delivery logs.
- Ensure access to backend data is audited; restrict access to the contribution ledger and token mapping with least privilege.

## 7. Acceptance tests

- [ ] Mobile produces no contribution while all scopes are off.
- [ ] Commercial contribution uses a dedicated service/queue, not `OwnerBusinessSyncService`.
- [ ] Offline checkout works while contribution endpoint is unavailable.
- [ ] Retried batch is idempotent and cannot double-count.
- [ ] Backend rejects a batch after relevant consent has been withdrawn.
- [ ] Backend derives tenant/workspace from auth and rejects foreign workspace spoofing.
- [ ] Unknown schema fields and forbidden identifiers are rejected.
- [ ] Existing admin panel renders backend-returned values only; production has no mock/static intelligence data.
- [ ] All dashboard metrics reconcile to backend aggregation fixtures and carry period/units/coverage/freshness.
- [ ] Merchant and partner tokens are denied admin/ledger endpoints even when called directly.
- [ ] Analyst cannot access restricted ledger endpoint; Steward access is audited.
- [ ] Partner APIs return only approved aggregate snapshots and share the same suppression rules as admin exports.
- [ ] There is no second admin application, second authentication system or duplicate ingestion pipeline.
