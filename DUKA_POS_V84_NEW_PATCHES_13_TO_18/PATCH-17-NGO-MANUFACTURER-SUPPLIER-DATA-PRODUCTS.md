# PATCH 17 — NGO, Manufacturer, Supplier and Research Data Products

## Goal

Turn validated, consent-eligible contribution data into useful products for different partner classes without exposing individual shops, customers, suppliers, staff or raw transaction records.

**The buyer purchases a defined aggregate dataset or research output, not access to the merchant network.**

## 1. Partner classes and products

### A. NGOs, programme implementers and development researchers

Initial product: **SME Digitisation & Market Activity Pulse**.

Possible output measures:
- adoption/usage bands of digital sales records, stock records, receipts and purchase tracking;
- proportion of active contributing businesses with mapped economic activity and product categories;
- sector mix by broad region/county where release thresholds permit;
- sales/inventory-record completeness and coverage trends;
- category-level availability/stockout indicators for reliably tracked goods;
- broad business-size and channel bands where explicitly captured and sufficiently sampled;
- sector/market seasonality and price-band trends.

Do not provide named merchant lists, participant lists, contact details, shop-level records, individual credit histories or beneficiary-level information through this product.

An NGO commissioning a named programme evaluation, household survey or beneficiary register is a **separate data collection project**. It needs its own project specification, participant notice, legal basis, data minimization, field-by-field schedule, data-sharing agreement, access/deletion rules and DPIA if high-risk. The merchant's market-intelligence opt-in does not authorize a data collection campaign about customers, staff, children or beneficiary households.

### B. Manufacturers, brands and brand owners

Initial product: **Category / Brand Demand Pulse**.

Possible output measures:
- aggregated category-level units and net sales trends;
- brand/category demand only where product identity is verified and cohort density passes disclosure tests;
- price bands/median/quantiles and promotion/discount patterns;
- broad channel and geographic trends;
- tracked inventory availability and product-category stockout estimates where coverage supports it;
- seasonality and product-mix shifts.

Do not expose a shop's exact price, exact volume, stock balance, store list, named buyer/customer, individual basket or named competitor activity. Product/brand outputs must not identify a contributing shop by rare combination or precise time/location.

### C. Suppliers, wholesalers and distributors

Initial product: **Replenishment & Category Supply Pulse**.

Possible output measures:
- aggregated order/receipt quantities by normalized category and unit;
- purchase-cost bands/indices where enough independent businesses contribute;
- order fill-rate bands and lead-time distributions, only from verified PO-to-receipt links;
- restock frequency and inventory-coverage patterns;
- demand categories with under-supply signals when valid stock tracking exists.

Do not sell supplier contact lists, named supplier performance, shop-to-supplier relationships, account terms or private supplier notes. Named supplier comparisons require a separate arrangement and assessment; they are not part of this default product.

### D. Research / public-sector institutions

Offer controlled aggregate extracts or research briefs for a defined question. The data dictionary, sample method, coverage, limitations and disclosure controls must accompany the result. Do not represent the participating app population as a probability sample of Kenya without a valid sampling design.

## 2. Data product publication standard

Each product must be a versioned, reproducible dataset/report with:

- dataset ID and product name;
- defined purpose, intended buyer class and permitted use;
- periods, geography level, profile/activity mix and source coverage;
- schema/dictionary/taxonomy version;
- metric definitions, units/currency and formulas;
- denominator and missing/unmapped percentages;
- freshness and last-updated time;
- contributor/transaction count metadata held internally; released only as a safe cohort/label;
- suppression/exclusion summary;
- methodology and known sampling/selection bias;
- license/contract version, retention/expiry and no-redistribution terms;
- aggregation job version and manifest/hash for internal reproducibility.

Use fixed, reviewed dataset schemas first. Do not begin with free-form SQL or arbitrary partner query builders.

## 3. Disclosure and aggregation controls

Retain the original plan's conservative default release gate: at least **10 independent contributing businesses and 100 underlying transactions per released cell**. This is only a baseline guardrail, not proof of anonymity or legal compliance.

Add controls:

- Count independent shops after de-duplication and eligibility checks, not batches or devices.
- Suppress low-density cells; widen time/category/geography or omit the dimension instead of lowering thresholds.
- Apply primary and complementary suppression so a suppressed value cannot be calculated by subtracting totals.
- Block arbitrary combinations of filters and repeated adjacent queries that enable differencing.
- Use bands, medians, quantiles and indexed trends rather than store-level exact minima/maxima or exact prices.
- Prevent a partner from joining outputs with a small bespoke dataset when this creates likely singling-out; evaluate recipient context and contractual restrictions.
- Never release stable contributor tokens, tenant IDs, device identifiers, row IDs or exact timestamps.
- Reassess re-identification risk for the complete combination of fields, refresh rate, filters, buyer access and external datasets.
- Record every export, API query and snapshot version. Revoke credentials and stop new delivery if a partner breaches contract.
- No dataset is published merely because a numeric threshold passes; legal basis, scope, quality, contract and disclosure controls must all pass.

Differential privacy or other formal privacy-enhancing methods may be considered for high-query or higher-risk products. Do not promise differential privacy unless it is implemented, configured and tested; a conventional threshold is not differential privacy.

## 4. Partner agreement and API policy

Before delivery, record:

- verified legal entity and authorized contact;
- recipient/controller/processor role assessment;
- exact dataset(s), field/metric scope and purpose;
- legal basis and whether personal data is included (default is no personal data in partner data products);
- permitted analysis, retention, expiry, publication and onward disclosure;
- no re-identification, no attempts to infer contributing shops, no combination beyond permission, no sale/redistribution;
- access controls, key rotation, quotas, audit, incident/breach reporting and security obligations;
- deletion/return on expiration or termination and practical correction/withdrawal process;
- cross-border/subprocessor location and safeguards where applicable;
- audit/inspection and suspension/termination rights.

The ODPC Data Sharing Code says data-sharing arrangements should have defined periods and revocable permission, should not enable recipients to re-identify or freely combine datasets, and should specify recipient responsibilities and retention/deletion. Apply the code to arrangements involving personal data and use the same conservative contract controls for confidential aggregate business data.

## 5. Admin panel workflow (existing panel only)

Use Patch 16. In the current Admin Panel's Data Intelligence area, the authorized Partner Manager must be able to:

1. review only release-ready dataset snapshots;
2. select a permitted dataset and fixed scope/period;
3. see disclosure and quality status before release;
4. link the dataset to a partner contract and allowed purpose;
5. issue a scoped, expiring, revocable credential (if API access is approved) or a controlled export;
6. set quotas and allowed endpoints;
7. review delivery logs, usage and errors;
8. revoke the grant/key and record the reason.

Partner Manager must not have ledger row access. Partners must never use Admin Panel authentication or endpoints.

## 6. Initial launch sequence

1. Build an internal-only sample dataset from synthetic fixtures and approved test data.
2. Verify each metric and suppression rule with privacy/security tests.
3. Produce a limited **Micro-Retail Pulse** PDF/CSV manually via the existing admin backend for internal QA only.
4. Conduct partner interviews and define one concrete pilot with a written purpose and data contract.
5. Deliver only an approved aggregate snapshot; measure usefulness and risk before building a public API.
6. Build a partner API only after recurring buyer demand and the server-side control model are proven.

## 7. Acceptance tests

- [ ] NGO product contains aggregate digitisation/sector metrics, not beneficiary/customer/staff identities.
- [ ] Manufacturer product cannot reveal individual shop prices, exact quantities, stores or baskets.
- [ ] Supplier product uses category-level and linked procurement aggregates, not supplier names/contact details.
- [ ] Every product snapshot has metric definitions, cohort coverage, sample limits, freshness and known bias.
- [ ] The 10-shop/100-transaction default is enforced with complementary suppression and query-abuse controls.
- [ ] Partner credentials are scoped, expiring, revocable, quota-bound and audited.
- [ ] A partner cannot call admin or contribution-ledger endpoints.
- [ ] An NGO beneficiary data request cannot be fulfilled using the general commercial-intelligence consent.
- [ ] Data product output is built by the backend and shown/delivered through existing Admin Panel infrastructure.
