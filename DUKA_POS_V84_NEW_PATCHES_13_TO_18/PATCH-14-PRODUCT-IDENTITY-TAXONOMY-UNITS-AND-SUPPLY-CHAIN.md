# PATCH 14 — Product Identity, Taxonomy, Units and Supply-Chain Events

## Goal

Normalize the product and procurement records already produced by the POS so that different shops can be compared meaningfully. Collect the facts through catalogue, sale, stock, purchase-order and receipt workflows; do not add a mandatory questionnaire to selling.

## v84 source baseline

- `lib/data/local/repositories/inventory_repository.dart`: canonical `products` schema includes `name`, `category`, `cost_price`, `sell_price`, `stock_qty`, `track_stock`, `unit`, variant tracking, pack/expiry fields and related inventory persistence.
- `lib/data/local/repositories/sales_repository.dart`: `sales` and `sale_items` store the completed sale and item-level quantity/price/cost snapshots, discounts and tax-rule snapshots.
- `lib/db/database_helper.dart`, `_migrateReordering()`: `product_suppliers`, `purchase_orders`, and `purchase_order_lines` already exist.
- `lib/db/database_helper.dart`, `_createReceiptTables()`: `suppliers`, `stock_receipts`, `stock_receipt_items`, and `product_cost_history` exist. The local v84 receipt header does not carry a `purchase_order_id`, and receipt lines do not carry a purchase-order-line reference. Actual order-to-receipt lead time therefore cannot be assumed from the present schema.
- `lib/db/database_helper.dart`: `stock_movements` has UUID, product/variant, type, quantity delta, unit cost, reference and timestamp.
- v84 supplier records include private operational fields such as name, phone, contact person, notes and terms. Those fields must not enter the commercial-intelligence payload.

## Logical product master additions

Extend the current product record or create normalized child/reference records. Do not replace the existing local name, price or category field; preserve historic sale snapshots.

| Field | Meaning | Rules |
|---|---|---|
| `product_uuid` | Stable product record UUID | Must be stable across sync; not a global product identity |
| `item_kind` | `good`, `service`, `fee`, `unknown` | Explicitly distinguish stockable goods from services/fees |
| `internal_category_id` | Existing local category key | Retain local category label; map separately to external taxonomy |
| `gpc_code` | GS1 Global Product Classification code | Optional verified mapping; store GPC version and mapping status |
| `gpc_version` | GPC release identifier | Required when GPC code is set |
| `gtin` | Verified Global Trade Item Number | Optional; validate format/check digit and preserve leading zeros as a string |
| `merchant_sku` | Merchant-local SKU | Useful internally, never a partner join key |
| `brand_entity_id` | Normalized brand reference | Optional; create from reviewed entity/reference list, not unchecked free text |
| `brand_label_local` | Shop's original entered label | Operational display only; never copy verbatim into contribution data |
| `manufacturer_entity_id` | Verified manufacturer/brand-owner reference | Optional; do not infer from supplier |
| `variant_attributes` | Controlled variant dimensions | E.g. size/color/style; don't include arbitrary personal text |
| `base_unit_code` | Internal canonical unit | Required for measurable quantity if applicable |
| `external_unit_code` | UNECE Rec.20 code | Optional mapping; store scheme/version |
| `pack_quantity` / `pack_unit_code` | Package conversion | Must have a validated relation to base unit |
| `unit_mapping_status` | `mapped`, `unmapped`, `unknown`, `not_applicable`, `rejected` | Required for quality metrics |
| `identity_provenance` | `owner_confirmed`, `staff_entered`, `scan_verified`, `catalogue_reference`, `admin_reviewed`, `system_derived` | Required |

### Taxonomy distinction

- **KeSIC** classifies the business's economic activity (Patch 13).
- **GS1 GPC** classifies products for comparable product grouping. It is not a barcode and not the product's unique identity.
- **GTIN** is a product identifier when the item has a valid, verified GTIN. It is optional; many informal/local goods will not have one.
- **UNECE Recommendation 20** provides coded units for quantity types such as mass, volume, length and time. It does not require every locally used unit to have an external code.

Use the current official GS1 GPC version as a versioned reference at implementation time (the GS1 standards repository currently lists GPC 2026-05); do not hard-code “latest” without recording the imported version. Use the latest available UNECE Rec.20 code list after checking source/version. Keep a local extension for legitimate local units that have no external mapping, and mark it as local/unmapped rather than forcing a false external code.

## Item types and inventory semantics

- `good`: tangible item; stock may be tracked, measured or intentionally untracked.
- `service`: performed service; no physical on-hand stock and no stockout calculation.
- `fee`: separately billed charge; no inventory decrement.
- `unknown`: legacy row awaiting owner review; do not infer a service merely because `track_stock = 0`.

For Open, services are ordinary sellable catalogue lines. No new job entity, job lifecycle, job completion, job cost or job assignment is added to the data model. This supersedes older job-oriented statements in the pre-existing plan (see Patch 18).

## Product category / brand mapping workflow

1. Keep the owner's product name and category locally for POS display.
2. Let the owner choose an existing controlled category or a suggested mapping in a non-blocking bulk review screen.
3. Store the external GPC code, mapping confidence/status, taxonomy version and reviewer/provenance.
4. Use barcode scanning to resolve GTIN only when a valid barcode is present. Do not invent manufacturer or brand from a similar name.
5. Ambiguous/unmapped records stay usable in POS but are excluded from analyses requiring the unmapped dimension. Report the exclusion as a coverage gap.
6. Keep a versioned mapping history. New taxonomy releases do not silently rewrite historic published datasets.

Do not send original names, product descriptions, free-text variants, notes or images to the intelligence contribution endpoint. Map them locally/server-side to a controlled taxonomy; send only approved normalized codes and aggregates.

## Procurement and supplier events

Existing supplier names and contact fields support the shop's own operations. They are not a commercial-intelligence data source for external partners.

Add explicit PO ↔ receipt lineage so lead-time and fill-rate claims are based on an actual event link:

- Add nullable `purchase_order_id` to `stock_receipts` (with FK/index where supported).
- Add nullable `purchase_order_line_id` to `stock_receipt_items` (or a normalized allocation table if one receipt can satisfy multiple orders/lines).
- Persist `ordered_at_utc`, expected receipt date (if entered), actual `received_at_utc`, received quantity, ordered quantity, unit/cost basis and currency.
- Support partial receipts, multiple receipts per order, returns/corrections and unmatched receipts without forcing an invalid link.
- Derive observed lead time only for valid linked records: `actual_received_at_utc - ordered_at_utc`; distinguish first partial receipt, final fulfillment and expected-vs-actual. Never call supplier master `lead_time_days` actual observed performance; it is a declared estimate unless supported by linked receipts.
- Compute line fill rate from matched quantities only; exclude cancelled/open orders from “complete” denominator or label the status.
- Keep supplier identifiers, supplier name, phone, contact person, supplier PIN and supplier-specific terms private to the shop. Commercial outputs use broad product category / unit / period and sufficiently aggregated regional cohorts, not supplier rankings or named shop-supplier relationships.

## Metrics that can be produced when coverage is reliable

- product/category demand: sold units and net sales by period/category;
- price distribution: bands/median/quantiles, not row-level prices or shop-specific price points;
- promotion/discount/refund patterns with consistent netting;
- normalized package/unit conversion statistics;
- stock availability only for actively tracked physical goods with valid snapshots and a known observation denominator;
- purchase-to-receipt lead-time and fulfillment bands only where PO/receipt linkage is complete enough;
- cost movement bands only from reconciled receipts and cost history.

Do not equate stock movement with a sale. Use canonical `sale_items` / SalesRepository for sales; use stock movements and snapshots for inventory events. Do not infer stockout from missing stock data.

## Migrations and acceptance

- Additive migrations and fresh-install schema must be equivalent.
- Existing `Product`, `SaleItem`, `StockReceipt`, supplier and PO data must remain readable.
- Historical sale price/cost/tax snapshots must not be changed by current product master updates.
- GTIN validation preserves leading zeros and checks the relevant format/check digit.
- GPC/unit mappings include scheme and version; unmapped records remain operationally valid.
- PO-to-receipt linkage handles partial delivery, multi-receipt, cancellation, unlinked receipt and rollback cases.
- Services/fees do not affect stock or stockout measures.
- Supplier contact details and original free text are absent from contribution fixtures.

## Standards references

- GS1 standards repository / GPC: https://ref.gs1.org/standards/
- KeSIC: https://kesic.labourmarket.go.ke/
- UNECE code list recommendations / Recommendation 20: https://unece.org/code-list-recommendations

## Implementation checkpoint (2026-11-19)

- App schema v91 adds versionable product identity fields and nullable PO/receipt line references. Legacy rows migrate as `unknown`/unmapped; stable per-product UUIDs are backfilled without rewriting sale snapshots.
- Product editing captures item kind, GPC code/version/status, shop-private SKU/brand label, external unit code/version/status and pack quantity/unit. An Inventory review queue lists unmapped items and opens the same editor; normal selling remains available during review. Service and fee rows are saved as non-stock items; sale recording still creates normal sale lines but omits stock checks, decrements and stock movement events for those item kinds.
- Receipt posting retains nullable PO header linkage and allocates each linked receipt line against one remaining PO line. Partial receipts and unmatched receipts remain valid. Receipt sync emits order and line UUIDs instead of device-local integer references.
- Backend product sync persists the versioned identity fields, validates GPC/unit mapping prerequisites and GTIN check digits without numeric coercion, and validates PO UUID references in the operational receipt payload. The app forwards valid supplier GTINs only; shop-generated/restricted-circulation codes stay local. Private labels remain on the tenant's operational product record.
- Admin `/api/admin/products` adds tenant-free counts for item-kind, taxonomy/unit mapping and valid-GTIN coverage; the mobile admin Products view displays these totals without exposing merchant labels or GTIN values in the coverage response.
- Standards versions were checked against primary sources: GS1 GPC 2026-05 and UNECE Rec.20 Revision 17 (2021). The app does not ship a complete GPC/UNECE code browser in this patch; unmapped entries stay usable and the app accepts a mapping only when a code and version are present. Source links: https://ref.gs1.org/standards/gpc/archive and https://unece.org/trade/documents/2021/06/uncefact-rec20-0.
- Inventory import is profile-aware. The shared Excel/Sheets path reads the saved shop profile; drink imports retain legacy volume defaults and drink-category inference, while Duka/Open avoid invented bottle sizes and drink-only category guesses, and Fashion treats `Size` labels (for example `XL`) as labels rather than millilitres. Fashion variant sheets can use `Size`, `Colour`/`Color` or `Style` as a variant label. Existing explicit category, unit, volume and canonical export columns continue to be accepted.

Verification and remaining checklist are recorded in `IMPLEMENTATION-BASELINE.md`. Do not treat schema acceptance alone as a claim that every locally entered external code has been verified against the full standards catalogue.
