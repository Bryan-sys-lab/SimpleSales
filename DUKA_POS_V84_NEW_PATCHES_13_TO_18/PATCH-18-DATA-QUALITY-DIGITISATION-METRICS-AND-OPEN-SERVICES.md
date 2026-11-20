# PATCH 18 — Data Quality, Digitisation Metrics and Open Services Semantics

## Goal

Make the collected data measurable and trustworthy, report its coverage honestly in the existing Admin Panel, and ensure Open service sales contribute as normal sale lines without reintroducing jobs.

## 1. Source baseline

The v84 source already contains the operational events needed for many metrics:

- `SalesRepository` / `sales` / `sale_items`: sale totals, sale lines, quantities, unit prices, unit costs, discount and tax snapshots.
- `InventoryRepository`, `products` and `stock_movements`: product catalogue, stock settings, movements and balances.
- `purchase_orders`, `purchase_order_lines`, `stock_receipts`, `stock_receipt_items`, `product_cost_history`: procurement and replenishment facts (but current stock receipt records do not link to purchase-order IDs/lines; Patch 14 adds this before lead-time reporting).
- `expenses`: expense category and paid amount; free-text note and photo path must not enter intelligence payloads.
- `suppliers`: private supplier master data; do not send supplier name, phone, contact person, notes or identifiers to contribution data.
- `shop_profile`: current four-value app profile only; Patch 13 adds optional business context.

## 2. Required data-quality states

Use a common quality state for each relevant dimension/metric:

- `valid` — syntactically and semantically passes validation;
- `mapped` — mapped to a reviewed reference code/version;
- `unmapped` — usable operationally but not comparable externally;
- `missing` — no value was supplied or derived;
- `unknown` — owner/user explicitly does not know;
- `not_applicable` — field/metric does not apply (e.g. stock count for a service);
- `unverified` — entered/imported but not confirmed;
- `stale` — reference/owner confirmation has aged beyond approved refresh period;
- `rejected` — invalid and excluded from eligible contribution.

`missing`, `unknown`, `not_applicable`, `unmapped` and numeric zero are distinct. Never render them all as zero.

Each field needs provenance: `owner_confirmed`, `staff_entered`, `imported`, `system_derived`, `catalogue_reference`, `admin_reviewed`. Keep actor identities in the operational/audit system only; never contribute staff IDs.

## 3. Canonical metric definitions

All metrics must be versioned in `DATA-DICTIONARY-V2.md`, calculated by the backend and reused across admin charts, exports and partner APIs.

| Metric | Canonical definition | Required caveat |
|---|---|---|
| Completed sale count | Count of completed eligible sale headers in period, deduplicated | Exclude void/test/failed/incomplete records |
| Gross sales | Sum of eligible sale-line extended selling value before discounts/refunds, using persisted sale snapshots | Specify tax inclusion consistently; don't blend subtotal and final total |
| Discounts | Sum of line/order discount snapshots, net of reversals where relevant | Do not count discount twice |
| Refunds/returns | Reversal value and units linked to the original sale where possible | Keep gross and net measures separate |
| Net sales ex-tax | Completed sales less discounts/refunds with tax excluded according to persisted tax snapshot | Do not derive using current tax rules |
| Tax collected | Tax amount from sale-time tax snapshot | Not merchant revenue or net sales |
| Payment mix | Confirmed amount/count by controlled payment method | Credit is receivable, not cash-in; pending M-Pesa is not confirmed |
| Cash received | Confirmed tender/cash-in from payment records | Not synonymous with sale value |
| Unit volume | Quantity after validated conversion to declared base unit | Never add kg, litre, each, pair or service-hour without separate unit dimension |
| Price distribution | Approved band/median/quantile from comparable unit prices | Do not publish exact single-shop or rare product prices |
| Stock tracking coverage | Eligible active `good` catalogue items with trackable stock / eligible physical `good` items | Exclude service/fee and distinguish intentionally untracked |
| Observed availability | Time/period with valid positive/zero tracked balance over observed snapshots | Missing snapshot is unknown, not out of stock |
| Stockout rate | Valid observed stockout duration or days / valid tracked observation duration | Only for reliable tracked physical goods; publish coverage/sample size |
| PO receipt lead time | Actual receipt timestamp minus linked PO ordered timestamp | Only linked valid receipts; show partial/final fulfillment separately |
| Fill rate | Received quantity / ordered quantity for matched completed order lines | Do not treat cancelled/open orders as completed denominator |
| Digitisation coverage | Specific workflow events recorded digitally / eligible known workflow events | Label as in-app observed coverage, not all business activity |

## 4. Digitisation metrics that can be delivered responsibly

Do not use invasive device tracking. Derive the following from product workflows and contribution coverage:

- **Sales-record coverage:** completed sale records containing at least one valid sale line / completed sale records in scope.
- **Catalogue classification coverage:** active eligible sellable products with valid category mapping / active eligible products.
- **Product identity coverage:** products with verified GTIN or reviewed local identity mapping / eligible physical products. Do not require a GTIN where local goods legitimately lack one.
- **Unit standardization coverage:** eligible quantity-bearing items with a mapped base unit / eligible quantity-bearing items.
- **Inventory tracking coverage:** active physical goods actively tracking stock / active physical goods in eligible catalogue.
- **Inventory observation coverage:** expected tracked-product-period observations with valid snapshots / expected observations.
- **Procurement digitisation coverage:** purchase orders with line items and at least one linked receipt / eligible purchase orders.
- **Expense classification coverage:** posted expenses with controlled category / posted expenses.
- **Receipt workflow coverage:** completed eligible sales with a locally generated receipt/PDF/print/share event, only when this signal is needed and separately disclosed; do not collect recipient phone or share URL.
- **Business profile completeness:** optional business fields populated or explicitly declined / fields applicable to that business. Do not penalize prefer-not-to-say.
- **Commercial contribution coverage:** valid opted-in businesses/transactions represented in each dataset divided by eligible opted-in population; always disclose the denominator and its limitations.

Do not present app usage as a complete census of all sales or purchases. A POS cannot observe transactions users never record. Use language such as “recorded in SimpleSales” and include coverage limitations.

## 5. Data quality and coverage in the existing Admin Panel

Integrate into the existing panel using Patch 16. Show:

- KeSIC primary/secondary mapping coverage and version;
- product category/GPC mapping coverage;
- GTIN coverage where applicable;
- unit mapping coverage;
- sale-line completeness;
- stock-tracking and valid stock-snapshot coverage;
- PO-to-receipt linkage and eligible lead-time sample size;
- expense-category coverage;
- profile/activity/county distribution for consenting cohorts only;
- received/accepted/rejected/duplicate/superseded/withdrawn batch counts;
- freshness, retry backlog and schema mismatch;
- reasons a field/period/product was excluded from a published metric;
- suppressed cohorts and quality grade.

Every admin KPI must show a numerator, denominator, period and last-updated timestamp. Missing/unknown/unmapped/suppressed/not-applicable must not be silently displayed as zero.

The admin data-quality pages fetch their data from the backend; no frontend calculation over a mobile database or static fixture in production.

## 6. Merchant-facing data completeness

In the merchant's own Settings/Business details or a restrained dashboard card:

- show the business's own profile/category/unit completion;
- prioritize one useful correction at a time;
- show why the field improves the merchant's own reporting or purchasing;
- distinguish optional commercial contribution from operational data completeness;
- keep “not sure” and “not applicable” available;
- never display network contribution counts, market intelligence, partner data or other shops;
- never block a sale because an optional field is missing.

## 7. Open profile — service items, not jobs

The later product decision to remove all active Open job features supersedes older job-based references in the v84 intelligence plan.

- Open may sell tangible goods, services and fees through the normal shared product/sale-line model (`item_kind = good|service|fee`).
- A service is an ordinary catalogue item and sale line; it does not create a job, assignment, task, completion status, job payment or job cost record.
- No new contribution metric or event may depend on `job_id`, job description, job status, staff assignment or job payment.
- Historical job rows remain only where needed for old backups/records and must not be used for new active functionality or market intelligence.
- Service/fee sale lines count toward valid sales/revenue by service category where eligible, but never into physical stock quantity, inventory tracking coverage or stockout metrics.
- If service cost is unknown, service margin is unknown; do not assume zero cost and report 100% margin.

## 8. Quality thresholds and release gates

- No external dataset is published below the minimum cohort and transaction thresholds from Patch 17 or if re-identification/differencing risk remains.
- A category/metric with insufficient completeness is marked `limited_sample` or suppressed, not shown as zero demand.
- Never compare tracked and untracked goods as if their stockout rates were equivalent.
- Do not publish a metric without a stable definition, source, version, unit, denominator, quality grade and known limitations.
- Version mapping and formulas. A changed mapping must not silently mutate an already-published snapshot.

## 9. Acceptance tests

- [ ] Every metric fixture returns known values and denominators.
- [ ] Sales, discounts, refunds, tax, payment, credit and cash-in reconcile with canonical sale/financial ledgers.
- [ ] Pending/unverified M-Pesa is excluded from confirmed payment metrics.
- [ ] Stockout metrics exclude service/fee and untracked/stale inventory.
- [ ] Missing snapshot is unknown, not out of stock.
- [ ] Lead time is only calculated from linked PO/receipt records.
- [ ] Unit conversions preserve quantity type and never silently add incompatible units.
- [ ] Changes to taxonomy/dictionary are versioned and historical published snapshots remain reproducible.
- [ ] Admin quality metrics display numerator/denominator, period, freshness and exclusions.
- [ ] Merchant completeness displays only the current authorized shop's own data.
- [ ] Open services are included as service sale lines, not jobs or inventory.
- [ ] No active Open job fields or job-related event dimensions enter current contribution batches.
