# Duka POS v84 — New Data Intelligence Patches Only (13–18)

**This package contains only the new structured-data / commercial-intelligence additions.** It deliberately excludes the earlier POS UX patches 00–12. It is an add-on to the single authoritative v84 implementation plan, not a replacement for that package.

## Objective

Turn Duka POS into a structured source of business and supply-chain information for approved research, NGO, manufacturer, supplier and distributor use cases, while preserving the existing POS as a fast business tool.

The design target is:

```text
Existing v84 POS workflows
  ├─ shop/business context (owner-entered, optional)
  ├─ catalogue and product identifiers
  ├─ sales and sale lines
  ├─ stock/receipts/purchases/suppliers
  └─ operating activity / data quality
         │
         ▼
Purpose- and consent-checked contribution builder (mobile)
         │  minimized, versioned, off the checkout path
         ▼
Existing backend (source of truth)
  ├─ contribution ingest + validation
  ├─ restricted contribution ledger
  ├─ canonical dictionary/taxonomy mapping
  ├─ aggregation + disclosure controls
  ├─ lineage, retention, deletion, audit
  └─ backend APIs for admin and partner scopes
         │
         ├──────────────► Existing Admin Panel (real backend data)
         │                 Data Intelligence area; no new admin app
         │
         └──────────────► Licensed partner output (aggregates only)
```

## Package contents

| Document | Purpose |
|---|---|
| `PATCH-13-BUSINESS-CONTEXT-AND-KESIC.md` | Standardized business/establishment profile and economic activity |
| `PATCH-14-PRODUCT-IDENTITY-TAXONOMY-UNITS-AND-SUPPLY-CHAIN.md` | Product master, brands, category, units, stock and procurement linkage |
| `PATCH-15-KENYA-LAWFUL-COLLECTION-CONSENT-AND-GOVERNANCE.md` | Collection boundaries, legal gate, consent, rights and retention |
| `PATCH-16-BACKEND-CONTRIBUTION-PIPELINE-AND-EXISTING-ADMIN-PANEL.md` | Backend ingestion, source of truth, admin panel wiring and server APIs |
| `PATCH-17-NGO-MANUFACTURER-SUPPLIER-DATA-PRODUCTS.md` | Partner outputs, release controls and permitted use cases |
| `PATCH-18-DATA-QUALITY-DIGITISATION-METRICS-AND-OPEN-SERVICES.md` | Quality, coverage, digitisation indicators and no-job Open service model |
| `DATA-DICTIONARY-V2.md` | Canonical definitions and contribution eligibility |
| `LEGAL-PURPOSE-AND-COLLECTION-MATRIX-KENYA.md` | Purpose-specific collection and legal review matrix |
| `BACKEND-ADMIN-API-CONTRACT.md` | Logical request/response contracts to map to the existing backend |
| `SOURCE-REFERENCE-AND-GAP-REPORT.md` | Verified v84 evidence and repository boundary |
| `AGENT-WORK-ORDER.md` | Implementation sequence and release gates |

## Interpretation of “maximum legal data collection”

Implement **maximum useful, validated, purpose-specific business data**, not maximum personal-data collection. Capture from existing operational events automatically wherever possible. Ask the merchant only for the smallest optional business-context fields that cannot be derived from transactions. Do not collect broad personal information for possible future use.

The most useful signals are generally: normalized activity/category, product identity, normalized units, aggregate sales and price bands, discounts/refunds, payment-method mix, tracked-stock availability, purchase quantities, purchase/receipt lead time, cost bands, and digitisation/completeness indicators. These should be collected and contributed only where the exact purpose and consent/other lawful basis permit it.

## Implementation status / honesty

These are **source-grounded implementation specifications and API contracts**, not applied Dart/Go/SQL code. The original archive is a Flutter mobile source tree and contains the commercial-intelligence plan, but it does not include the separate backend or admin-panel repositories. The plan states that the existing admin panel is implemented and must be extended. Therefore:

- Agents must inspect the existing backend/admin repositories before choosing concrete route names, DTO names, SQL migrations or UI component files.
- The logical route names and payload examples in Patch 16 are contracts to adapt to the existing API conventions, not claims that those routes already exist.
- Do not build a replacement admin panel or second authentication system.
- Do not add this pipeline to `OwnerBusinessSyncService`; v84 explicitly says that service is for owner backup/operational sync and has no commercial-intelligence method.
- Do not activate commercial contributions until the legal, consent, registration, DPIA and partner-contract gates in Patch 15 are signed off.

## Authority and supersession

These patches refine the original `plan/SimpleSales_Codex_Commercial_Intelligence_Plan_v13.md`, especially §§47–54. They do not replace its purpose separation, restricted contribution ledger, aggregation controls, admin integration, partner restrictions or provenance requirements. Patch 18 explicitly supersedes older Open job-based commercial data requirements: services are saleable items; jobs are not part of this target data model.

## Source fingerprint

Original source: `duka_pos_app_source_v84.zip`

SHA-256: `59d6107f2697237c5dc146e112df352ff387a9e2660f7a74995c244191ba5a01`

The source archive remains read-only and is not included in this add-on package.
