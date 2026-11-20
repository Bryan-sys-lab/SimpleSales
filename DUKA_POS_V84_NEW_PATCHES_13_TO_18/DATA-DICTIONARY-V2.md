# Data Dictionary v2 — Structured Business Intelligence

**Status:** proposed canonical dictionary for Patches 13–18. Version all schemas and reference mappings. Values below are logical field definitions, not a claim that every field is already present in v84.

## 1. Dictionary rules

- Canonical units: integer minor currency units (KES cents) for money; decimal quantities only with an explicit unit; UTC timestamps; `Africa/Nairobi` for Kenya reporting buckets.
- Store raw operational display text in the merchant's operational records only. Commercial contribution uses controlled codes and aggregates.
- Keep source table/event, provenance, quality state, mapping version, privacy class and contribution eligibility for each metric.
- `pseudonymous` is not `anonymous`. Any stable contributor link is restricted and never partner-visible.
- Avoid `null`/zero ambiguity: use explicit quality state and denominator.

## 2. Data domains

| Domain | Dictionary key | Definition | v84 source / capture | Commercial contribution |
|---|---|---|---|---|
| Business | `app_profile` | SimpleSales operating preset | `shop_profile.profile` | Yes, when scope granted; coarse dimension |
| Business | `kesic_primary_group` | Primary economic activity code/group | New Patch 13 business context | Yes, code/version only after grant |
| Business | `kesic_secondary_groups` | Secondary economic activity groups | New Patch 13 | Optional; suppress combinations |
| Business | `operator_role` | Producer/manufacturer/importer/distributor/wholesaler/retailer/service/mixed | New Patch 13 | Coarse only; consent scope |
| Business | `sales_channel` | Physical/mobile/online/social/wholesale/delivery channel | New Patch 13 | Coarse only; consent scope |
| Business | `county_code` | Owner-selected Kenya county code | New Patch 13 | Only at safe cohort grain |
| Business | `business_age_band` | Self-reported business-age band | New Patch 13 | Optional; coarsen/suppress |
| Business | `employee_count_band` | Self-reported employee count band | New Patch 13 | Optional; suppress rare small cohorts |
| Business | `outlet_count_band` | Self-reported outlet count band | New Patch 13 | Optional; never outlet IDs |
| Product | `item_kind` | `good`, `service`, `fee`, `unknown` | Add to product master; sale line snapshot | Yes; service excluded from inventory |
| Product | `gpc_category_code` | GS1 GPC category code + version | New Patch 14 | Yes where mapped and permitted |
| Product | `gtin_verified` | Whether a valid GTIN was verified | Existing barcode support + verification | Only as coverage measure; never expose merchant SKU |
| Product | `brand_entity_code` | Reviewed brand reference code | New Patch 14 | Optional; brand-level only after suppression |
| Product | `unit_code` | Canonical base unit / Rec.20 mapping | `products.unit` + new mapping | Yes with unit scheme/version |
| Sales | `completed_sale_count` | Eligible completed sale headers in period | `sales` | Aggregate only |
| Sales | `sale_line_count` | Eligible `sale_items` rows | `sale_items` | Aggregate only |
| Sales | `quantity_base_units` | Quantity converted to one normalized base unit | `sale_items.qty` + unit conversion | Aggregate only; one unit dimension at a time |
| Sales | `gross_sales_minor` | Gross line extended value before discounts/refunds | Persisted sale line snapshots | Aggregate only; definition pinned |
| Sales | `discount_minor` | Applied line/order discount amount | `sale_items.discount_minor`, sale snapshot | Aggregate only |
| Sales | `refund_minor` | Linked refund/return value | Existing returns/refunds events | Aggregate only; no raw reason text |
| Sales | `net_sales_ex_tax_minor` | Completed value less discounts/refunds, excluding recorded tax | Sale-time tax snapshot and refunds | Aggregate only; do not use current tax settings |
| Sales | `tax_collected_minor` | Tax from sale-time tax snapshot | `sales`/sale-line tax snapshot | Separate, not revenue |
| Payments | `payment_method_mix` | Confirmed counts/amounts by controlled method | Sale payments | Aggregate only; exclude provider refs |
| Payments | `receivable_minor` | Aggregate credit-sale / receivable indicator, not a customer balance | Credit ledger / sale payments | **Default excluded** from commercial contribution. Only consider a separately specified and legally reviewed aggregate business-credit research purpose; never export named customer balances, individual shop creditworthiness, delinquency scores or customer histories. |
| Inventory | `tracked_item_coverage` | Active physical goods with stock tracking / eligible active goods | `products.track_stock`, `item_kind` | Aggregate quality measure |
| Inventory | `observed_availability` | Valid availability observations in tracked time window | Stock snapshot/movement derivation | Only when snapshot coverage adequate |
| Inventory | `stockout_days_rate` | Valid out-of-stock observed time / valid tracked observation time | Derived from reliable stock snapshots | Do not infer from missing snapshots |
| Procurement | `po_line_qty` | Quantity ordered by normalized category/unit | `purchase_orders`, `purchase_order_lines` | Aggregate only |
| Procurement | `received_qty` | Matched quantity actually received | `stock_receipts`, `stock_receipt_items` + Patch 14 linkage | Aggregate only |
| Procurement | `po_receipt_lead_time_days` | Actual linked receipt minus PO ordered time | Requires new PO↔receipt linkage | Only aggregate, if sample reliable |
| Procurement | `po_fill_rate` | Received quantity / ordered quantity for matched lines | Requires new linkage | Aggregate only |
| Procurement | `purchase_cost_band` | Unit-cost distribution in normalized units/currency | Receipt/cost-history snapshots | Bands/index; no shop or supplier cost row |
| Expenses | `expense_category_mix` | Aggregate posted expense totals by approved category | `expenses.category_id`, amount | Optional separate scope; never note/photo/staff |
| Digitisation | `sale_line_completeness` | Completed sales with valid lines / completed sale headers | Sales + sale items | Aggregate quality metric |
| Digitisation | `category_mapping_coverage` | Eligible products mapped / eligible products | Product taxonomy mapping | Aggregate quality metric |
| Digitisation | `unit_mapping_coverage` | Eligible quantity-bearing goods with mapped units / eligible goods | Product unit dictionary | Aggregate quality metric |
| Digitisation | `procurement_capture_coverage` | Eligible POs with linked receipts / eligible POs | PO and receipt records | Aggregate quality metric |
| Digitisation | `expense_classification_coverage` | Posted expenses with controlled category / posted expenses | Expenses | Aggregate quality metric |

## 3. Excluded fields

Never include these in market contribution batches or partner datasets: shop/business names, tenant/workspace IDs, owner/staff/customer/supplier identifiers or contacts, TIN/registration IDs, exact addresses/GPS, transaction/receipt IDs, merchant SKU, payment provider references, customer credit account details, supplier terms/notes, free text, images, receipt documents, device advertising IDs/fingerprints, raw item descriptions or customer baskets.

Operational storage may require some of these fields for ordinary POS, legal, accounting or support purposes. Keeping them locally/operationally does not make them eligible for commercial intelligence.

## 4. Metric formula requirements

Every metric's full specification must additionally include:

- formula and rounding;
- source event/table and event time used;
- accepted statuses and excluded statuses;
- quantity conversion policy;
- currency and tax treatment;
- period/window and timezone;
- numerator, denominator and missing-data behavior;
- sample/coverage threshold and suppression rule;
- data-quality state;
- purpose/scope and privacy class;
- aggregation job and dictionary version.

The same metric name cannot be used with different formulas in separate dashboards or partner exports.
