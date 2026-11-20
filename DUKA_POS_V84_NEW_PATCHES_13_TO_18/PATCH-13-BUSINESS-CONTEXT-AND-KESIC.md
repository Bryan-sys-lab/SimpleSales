# PATCH 13 — Structured Business Context and KeSIC Classification

## Goal

Give each business a consistent, machine-readable description that supports market segmentation and digitisation research without confusing a SimpleSales profile with the business's real economic activity.

**No new POS profile. No compulsory survey. No questions in Record Sale, QuickSale, stock receipt or shift-close.**

## Source facts in v84

- `lib/db/database_helper.dart`, `_createShopProfileTable()`: `shop_profile` stores only `id`, four-value `profile` (`drinks`, `duka`, `fashion`, `open`) and `updated_at`.
- `lib/services/workspace_service.dart`: workspace identity and shop display details are operational identity, not automatically approved commercial data.
- `lib/services/owner_business_sync_service.dart`: owner-controlled backup/sync is deliberately separate from commercial intelligence.
- `plan/SimpleSales_Codex_Commercial_Intelligence_Plan_v13.md`, §§47–54: one cross-profile intelligence pipeline, separate commercial opt-in, minimization, existing-admin integration and a restricted contribution ledger.

The app profile describes the POS configuration. It does **not** replace KeSIC. The same Duka profile may be a grocery retailer, hardware retailer, wholesaler or mixed shop.

## Required logical model

Add a dedicated, workspace-scoped `business_context` record (or extend an existing backend business entity after inspection). Do not put commercial-data consent fields in the business profile row; consent is a separate purpose/authorization record in Patch 15.

| Field | Type / controlled values | Capture rule |
|---|---|---|
| `business_context_id` | UUID | Stable record identity, not a partner identifier |
| `app_profile` | `drinks`, `duka`, `fashion`, `open` | Derive from current POS profile; read-only here |
| `primary_activity_code` | KeSIC code | Owner selects from official versioned taxonomy; allow `pending` |
| `activity_scheme` | `KESIC` | Required when a code is selected |
| `activity_version` | Reference-data version/date | Required with a KeSIC code |
| `secondary_activity_codes` | Set of KeSIC codes | Optional; duplicates forbidden; cap to a small useful set (e.g. 4) |
| `operator_roles` | `producer`, `manufacturer`, `importer`, `distributor`, `wholesaler`, `retailer`, `service_provider`, `mixed`, `other` | Optional multi-select; never infer from app profile alone |
| `sales_channels` | `physical_shop`, `market_stall`, `mobile_route`, `online_store`, `social_commerce`, `wholesale`, `delivery`, `other` | Optional multi-select |
| `county_code` | Official Kenya county code | Optional, owner-selected; no GPS inference |
| `settlement_context` | `urban`, `peri_urban`, `rural`, `unknown`, `prefer_not_to_say` | Optional broad band only; no town/estate/market-stall location |
| `business_age_band` | `under_1y`, `1_to_2y`, `3_to_5y`, `6_to_10y`, `over_10y`, `unknown`, `prefer_not_to_say` | Optional; never require exact founding date |
| `employee_count_band` | `1`, `2_to_4`, `5_to_9`, `10_to_19`, `20_plus`, `unknown`, `prefer_not_to_say` | Optional self-report; no employee names, IDs, phone numbers or payroll records |
| `outlet_count_band` | `1`, `2_to_5`, `6_to_10`, `11_plus`, `unknown`, `prefer_not_to_say` | Optional; no outlet names or addresses in contribution data |
| `business_registration_status` | `registered`, `not_registered`, `unknown`, `prefer_not_to_say` | Optional categorical status only; do not request TIN, certificate or registration number for intelligence |
| `primary_sales_mode` | `retail`, `wholesale`, `mixed`, `service`, `production`, `unknown` | Optional derived/confirmed classification; keep definition in dictionary |
| `provenance` | `owner_confirmed`, `staff_entered`, `imported`, `system_derived`, `admin_reviewed` | Required for each value |
| `confirmed_at_utc` | UTC timestamp | Refresh when owner confirms a field |
| `schema_version` | Version | Required |

Store list fields as normalized child rows or a JSON array with strict server validation; do not store comma-separated display text as the authoritative value. One primary activity only. Secondary codes cannot duplicate the primary code.

## KeSIC rules

1. Use the official Kenya Standard Industrial Classification (KeSIC) as the business activity classification. The official KLMIS description says KeSIC is adapted from ISIC Rev.4 with Kenyan modifications and maintains comparability to ISIC at three-digit group level.
2. Store code, scheme and reference-data version, not only the display label.
3. Ship a versioned reference file or maintain a controlled backend reference-data endpoint with an offline cache. The merchant must still be able to complete normal POS operations when taxonomy refresh is unavailable.
4. Search labels and descriptions. Show a breadcrumb (section → division → group/class/subclass) and a short plain-language example.
5. Allow `not sure yet` and `prefer not to say`. Unknown is not “other” and must not be translated into a fabricated classification.
6. Use a reviewed manual-mapping queue for ambiguous descriptions. Do not let an LLM invent a KeSIC code; any assisted suggestion is explicitly provisional until selected/approved.
7. A business may have secondary activities. Keep one primary activity and optional secondary classifications; do not make “mixed” a reason to discard useful sector data.

## UX / capture placement

- Add a compact **Business details** section in existing Settings / Shop details.
- Optionally show a dismissible setup card after initial setup; keep it skippable and resumable.
- Save per field or as an atomic validated form with visible save state.
- Explain why each field is requested and whether it is optional. Separate core operation from commercial contribution consent.
- Show “Duka profile” and “Retail trade / grocery” as separate values.
- Only owner / explicitly authorized manager can edit the profile and consent. A cashier must not be able to enable sharing by completing a form.
- No personal traits, household/family questions, exact address, GPS, government identifier, bank details, tax PIN or sensitive attributes in this profile.

## Contribution boundary

The operational business context is retained in the shop's operational record. It may enter a commercial contribution only when Patch 15 has a current, matching grant for the selected purpose/scope. The contribution normalizer must emit only approved coarse fields (e.g. app profile, KeSIC group, broad county bucket) and must suppress them further if a released cohort is too small.

A sole proprietor's business record may still relate to an identifiable natural person. Treat stable shop-linked data as potentially personal/pseudonymous until a documented assessment says otherwise. A contributor HMAC token, if required, stays server-side and never appears in partner outputs.

## Local persistence, backup and migration

- Use additive migration(s) and make fresh-install schema exactly equivalent.
- Preserve the existing four profile values and all old records.
- Business-context backup, if supported, remains under the separately disclosed owner backup contract; it is not a commercial-contribution payload.
- Do not add fields to the existing owner backup payload merely because they exist in the business form. Review the current owner-sync allowlist and update its own disclosure if required.
- Revalidate taxonomy codes at sync; preserve unknown historical codes for manual review rather than destructive rewriting.
- Scope every record to the authenticated workspace/tenant context. A client-provided workspace ID is not authorization.

### Current implementation contract

The Flutter app keeps an offline workspace-local copy and sends it through the separate owner-controlled `PUT /api/tenant/business-context` operational endpoint during owner sync. The API derives tenant and POS profile from authenticated server state and rejects non-owner reads/writes. The existing admin panel can inspect one tenant's record at `GET /api/admin/tenants/:tenantId/business-context` under `tenants:read`; each view is audit-logged. This operational record is separate from contribution policy, ledger, aggregation and partner routes. Its inclusion in the encrypted owner backup is separately disclosed to the shop owner.

## Acceptance tests

- [ ] All four POS profiles can record the same business context while retaining the app profile.
- [ ] Primary and secondary KeSIC codes persist with scheme/version and correct provenance.
- [ ] Unknown / prefer-not-to-say / not-applicable are distinct from zero and from “other”.
- [ ] Optional details can be skipped and completed later; they never block checkout.
- [ ] Staff without owner-level authorization cannot edit business context or consent.
- [ ] No prohibited personal fields appear in the commercial payload fixture.
- [ ] A restored workspace retains correct mappings and unknown codes without cross-workspace leakage.
- [ ] Merchant API access is constrained to the caller's own authorized workspace.

## Official classification reference

- KeSIC overview: https://kesic.labourmarket.go.ke/about-kesic/
- KLMIS classification page: https://www.labourmarket.go.ke/classifications/

## Acceptance checkpoint (2026-11-19)

The owner accepted proceeding with the documented versioned offline catalogue limitation by instructing “advance to 14”. Exact parity with the live portal and the ambiguous `016190` descriptions remain unresolved; that code and uncached codes remain pending, and the shipped list is not represented as complete or current. Patch 13 is closed with this limitation visible in the implementation baseline.
