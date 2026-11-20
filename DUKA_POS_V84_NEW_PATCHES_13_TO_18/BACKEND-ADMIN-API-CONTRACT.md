# Backend ↔ Existing Admin Panel Contract (Logical API Specification)

This document is a companion to Patch 16. It describes the data that must exist and flow through the backend. Exact URLs, Go package names, table names, authentication middleware and admin component files must be mapped to the actual backend/admin repositories. Those repositories are not in the original v84 Flutter ZIP.

## 1. Authority rules

- Backend is the canonical source for commercial contribution state, aggregation, suppression, dataset snapshots and partner delivery.
- The mobile app sends minimized aggregate batches; it never talks directly to the admin panel.
- Admin panel reads backend endpoints; it never queries mobile SQLite or calculates network intelligence in the browser.
- Backend determines tenant/workspace and actor from authenticated context; never trust caller-supplied tenant/shop/role IDs.
- Partner API can only read approved aggregate snapshots under a partner grant.
- The restricted Contribution Ledger is accessible only to a designated Data Steward / Platform Owner role and contains minimized facts, not raw POS rows.

## 2. Logical API groups

### Patch 13 — operational business context (not a contribution)

| Operation | Route | Purpose / authorization |
|---|---|---|
| Upsert current shop context | `PUT /api/tenant/business-context` | App bearer token; owner profile only. Tenant ID and POS profile are derived server-side. Strict field allowlist and KeSIC code/scheme/version validation. |
| Read current shop context | `GET /api/tenant/business-context` | App bearer token; owner profile only. Resolves only the authenticated active tenant. |
| Inspect one shop's context | `GET /api/admin/tenants/:tenantId/business-context` | Admin token with `tenants:read`; records an admin audit event. |

This record is stored in the operational `business_context` table with a tenant foreign key. It contains no consent or grant state and is not an input to contribution ingestion. POS profile is derived from `Tenant.businessProfile`, not accepted from the client. The admin view is an operational inspection surface; the commercial ledger and partner APIs do not read it.

### Patch 14 — product identity and receipt lineage

| Operation | Route / field contract | Purpose / authorization |
|---|---|---|
| Sync tenant catalogue | `POST /api/products/sync` | Existing tenant-scoped owner/manager route. Keeps the stable client product UUID, item kind, versioned GPC mapping, optional string GTIN, shop-private SKU/brand label, controlled unit mapping and pack conversion. Unknown and unmapped records remain valid for POS use. |
| Sync receipt evidence | `POST /api/purchases` | Existing tenant-scoped operational purchase route. Optional `purchaseOrderUuid` and item-level `purchaseOrderLineUuid` preserve nullable partial/unlinked receipt lineage across devices. |
| Inspect aggregate identity coverage | `GET /api/admin/products` | Existing system-admin route. Adds overall counts for item kind, GPC/unit mapping states and valid supplier GTINs; does not add free-text shop identity fields or GTIN values to that coverage summary. |

`productUuid` and PO lineage values are UUID strings; local SQLite integer ids are never used as cross-device join keys. GTIN remains text so leading zeroes survive, and the backend checks supported length/check digit. A mapping marked `mapped` requires its external code and scheme version. Supplier contacts, shop labels, notes, images and SKUs remain operational-only and are excluded from the contribution schema. The admin coverage values are operational quality counts, not released commercial metrics.

### Mobile → backend

| Operation | Purpose | Auth/authorization |
|---|---|---|
| Create/update grant | Store specific optional commercial scopes and notice versions | Verified owner or delegated authorized manager for current workspace |
| Read current grant | Decide locally which scopes may be queued | Authenticated current workspace; server returns authoritative grants |
| Withdraw grant/scope | Stop future contributions and trigger queue/deletion handling | Authorized grant actor or verified owner |
| Submit contribution batch | Send schema-validated minimized period aggregate | Authenticated workspace + active server-side grant for each scope |

### Existing Admin Panel → backend

| Logical read | Response content | Minimum role |
|---|---|---|
| Intelligence overview | Aggregate counts/trends, contributing scope mix, freshness, pipeline state | Internal admin analyst |
| Dataset catalogue | Published/draft datasets, definitions, snapshots | Internal admin analyst |
| Dataset detail | Metrics, unit, period, quality, suppression, methodology | Internal admin analyst |
| Coverage | Field/category/unit/KeSIC/stock/PO-receipt coverage with denominator | Internal admin analyst |
| Pipeline quality | Ingestion, validation, duplicate, retry, dead-letter and reconciliation state | Internal admin operations |
| Contribution ledger | Restricted accepted minimized contribution facts and provenance | Data Steward / Platform Owner only |
| Governance | Aggregate grant/withdrawal/retention states and notice versions | Privacy Admin / Data Steward as authorized |
| Partner deliveries | Partner grant/dataset scope/quotas and delivery audit | Partner Manager |

Partner API is separate; it must not reuse admin routes or admin session tokens.

## 3. Batch contract — strict allowlist

Required envelope:

```json
{
  "batch_id": "UUID",
  "schema_version": "ci-contribution-v1",
  "dictionary_version": "2.0.0",
  "period": {
    "from_utc": "ISO-8601 UTC",
    "to_utc": "ISO-8601 UTC",
    "grain": "week|month|quarter",
    "reporting_timezone": "Africa/Nairobi"
  },
  "app_profile": "drinks|duka|fashion|open",
  "scope_codes": ["product_demand", "digitisation_metrics"],
  "dimensions": {},
  "metrics": {},
  "quality": {}
}
```

The object above is a shape template. It is not a licence to put arbitrary fields inside `dimensions`, `metrics` or `quality`. The backend owns a versioned JSON schema/validator and rejects unknown properties recursively.

Never accept the following in this contract:

`tenant_id`, `workspace_id`, `shop_id`, `business_name`, owner/customer/supplier/staff name/contact, `phone`, `email`, tax/registration ID, exact address/GPS, transaction/sale/receipt IDs, payment provider references, SKU, free text, notes, image/file URI, exact product label or device fingerprint.

If a backend contributor token is required, derive it internally from verified identity using a server-side keyed method and store the mapping separately. Do not accept a caller-generated stable contributor token.

## 4. Backend response envelope

All admin responses should include:

```json
{
  "data": {},
  "meta": {
    "generated_at_utc": "ISO-8601 UTC",
    "period_from_utc": "ISO-8601 UTC",
    "period_to_utc": "ISO-8601 UTC",
    "reporting_timezone": "Africa/Nairobi",
    "dictionary_version": "2.0.0",
    "schema_version": "ci-contribution-v1",
    "freshness": "current|stale|delayed|unknown",
    "coverage": {
      "numerator": 0,
      "denominator": 0,
      "ratio": null,
      "state": "sufficient|limited|suppressed|no_data|unknown"
    },
    "warnings": []
  }
}
```

Do not return a zero for suppressed or unavailable data. Use explicit state codes.

## 5. Admin overview response (example)

```json
{
  "data": {
    "accepted_batches": 0,
    "rejected_batches": 0,
    "eligible_contributors_internal": 0,
    "published_dataset_count": 0,
    "pending_validation_count": 0,
    "suppressed_cell_count": 0,
    "dataset_cards": []
  },
  "meta": {
    "generated_at_utc": "2026-11-17T00:00:00Z",
    "freshness": "current",
    "dictionary_version": "2.0.0",
    "coverage": {"numerator": 0, "denominator": 0, "ratio": null, "state": "no_data"},
    "warnings": ["Example response only — not production data"]
  }
}
```

This illustrative response uses zero placeholders and must never be shipped as a static production fixture.

## 6. Server validation rules

- Verify authenticated subject, account, role and active workspace context.
- Verify scope grants server-side and their notice/schema versions.
- Verify field allowlist and recursively reject forbidden fields.
- Validate schema, metric, unit, currency, taxonomy release and period.
- Enforce idempotency at database level using a unique key scoped to authenticated contribution identity.
- Reconcile metric totals and quality states.
- Store content hash and provenance without raw payload logs.
- Apply consent withdrawal and retention before dataset build/publish.
- Enforce suppression server-side for dashboard, CSV/PDF export, partner APIs and scheduled reports.

## 7. Existing admin UI wiring

The panel should call the backend using its existing authenticated API client. Required behaviour:

- loading state, empty state, stale state, suppressed state and server-error state;
- period filter passed to backend and validated there;
- all displayed totals derived from returned backend results;
- data freshness and coverage visible on each page;
- restricted Ledger route hidden for unauthorized roles **and** protected by server endpoint authorization;
- export generated by backend from the same approved snapshot/suppression logic;
- no client-side aggregation of batch rows or local storage of contribution payloads.

## 8. API acceptance tests

- [ ] Mobile caller cannot impersonate a different shop by changing tenant/workspace IDs.
- [ ] Batch without active scope grant is rejected.
- [ ] Batch with unknown nested fields is rejected.
- [ ] A repeat request with same batch ID/hash returns idempotent result.
- [ ] Same ID with changed body is rejected or requires explicit correction/supersession flow.
- [ ] Withdrawal invalidates unprocessed scopes and queues existing contribution reconciliation.
- [ ] Merchant role is denied admin endpoints.
- [ ] Partner role is denied admin routes and ledger endpoint.
- [ ] Analyst is denied ledger rows.
- [ ] Data Steward ledger access is paginated, role-checked, reason/audit logged and restricted to minimized fields.
- [ ] Frontend values exactly match backend response fixtures and never static production samples.
- [ ] Suppression is consistent across UI, download and partner API.
