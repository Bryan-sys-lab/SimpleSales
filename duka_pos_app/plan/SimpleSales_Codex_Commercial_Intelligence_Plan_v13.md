# SimpleSales (Duka POS) — Codex Execution, Cross-Shop and Commercial Intelligence Plan

**Version:** 13  
**Status:** Hardened integration, source-of-truth data governance, access isolation and monetization plan  
**Target:** Extend the existing SimpleSales app; do not rebuild it.  
**Authoritative profile specification:** `SimpleSales (Duka POS): Business Profiles Specification`  
**Profiles in this plan:** **Drinks, Duka, Fashion, Open — exactly four.**

**Review outcome:** Version 13 preserves the four-profile, multi-shop and commercial-intelligence requirements, and explicitly adds an admin-only sanitized contribution ledger/source-of-truth explorer, reproducible data lineage, privilege controls, and a hard wall preventing platform commercial intelligence from leaking into merchant-facing screens, APIs, exports, logs or caches. It supersedes conflicting profile/setup/schedule instructions from earlier drafts. The existing repository and already implemented admin/backend components remain the source of truth.

------------------------------------------------------------------------

## 0. Codex execution contract

This document is an implementation specification for an existing application.

### Non-negotiable rules

1.  **Extend the existing app. Do not rebuild it.**
2.  Before changing any file named in this plan, inspect the current repository and use the actual implementation as the source of truth.
3.  If a class, service, repository, table, screen, or helper already performs the required job under another name, extend it rather than creating a duplicate.
4.  **Exactly four business profiles exist in the product:**
    - `drinks`
    - `duka`
    - `fashion`
    - `open`
5.  The existing app may currently have generic/general-retail behaviour. **That behaviour is not a fifth profile.** It becomes the baseline for the **Duka** profile.
6.  Do not recreate the old seven-profile plan (`generalRetail`, `looseGoods`, `cerealStore`, `hardware`, `pharmacy`, `quickRecord`, `soloSeller`).
7.  Business types previously represented by those concepts are mapped into the four authoritative profiles:
    - general retail, cereals, hardware, pharmacy-type retail → **Duka**
    - mtumba, casual sellers, resellers, solo service businesses and makers → **Open**
    - bars, taverns, wines/spirits, keg/tank outlets → **Drinks**
    - boutiques, garments, shoes and accessories → **Fashion**
8.  Profiles are **presets over shared engines**, not separate apps, schemas, or databases.
9.  All profiles receive the **full enhanced analytics system**. Profile-specific KPI sets change the emphasis and drill-down, not whether analytics exists.
10. Financial correctness is a core domain requirement, not an analytics afterthought.
11. Every sale, expense, purchase, repayment, refund, owner transaction, and job payment must flow through deterministic accounting/cash-flow rules.
12. Money is stored as integer minor units. Never add new floating-point money fields.
13. History is append-only. Corrections are adjustment/reversal records, never destructive edits.
14. Every new writer must participate in integrity/backup/restore coverage from its first implementation.
15. Every feature must include migration/upgrade tests, permissions, ARB strings, backup coverage, relevant integrity hooks, profile configuration, and low-end performance checks.
16. Do not introduce two-way multi-device sync in Release 1.
17. Do not introduce a proprietary credit score.
18. Do not implement lender sharing in Release 1. Release 1 stores the owner’s synced business records; Release 2 adds lender-specific access.
19. **Integrate every shared feature into all applicable profiles in the same implementation phase.** Do not build a feature for one profile and leave the others as future ports.
20. **No parallel implementations for reusable features.** Sales, expenses, payments, refunds, reports, transactions, analytics, backup, sync, and shared UI are implemented once and configured for each profile. Profile-specific behaviour is configuration or a small adapter over the common engine.
21. **Account setup asks for the initial shop’s profile once.** A returning user is never repeatedly asked to select it. The create-shop flow asks for the new shop’s profile every time a new shop is created. Profiles are per shop, not per account.
22. **The account-level “All shops” view is a first-class requirement.** It must show a useful blended view across Drinks, Duka, Fashion, and Open, including comparable financial totals, shop health/activity, and one unified transaction view.
23. Cross-shop dashboards and views are read-only aggregations. A drill-down must navigate to the correct source shop and enforce that shop’s permissions. Never execute a write using an ambiguous or stale active-shop context.
24. Use the smallest implementation that satisfies the requirements. Reuse existing code and dependencies; do not add a new dependency, duplicate ledger, event bus, state-management system, or generic plugin framework without a demonstrated need.
25. A feature is not done until it has been integrated and tested across all four profiles, the cross-shop view where relevant, and the existing app regression suite.
26. **Commercial intelligence is a separate, explicitly disclosed processing purpose.** It is not silently included in account creation, app telemetry, the owner’s backup/evidence sync, or lender-sharing consent.
27. The existing admin panel is already implemented. **Integrate into it; do not rebuild it.** Inspect its current routes, auth, data model, API clients and UI, then extend the smallest compatible pieces.
28. Commercial contributions must be minimized before leaving the app/backend boundary. Never push raw database tables, unrestricted receipts, free text, customer/supplier identities, phone numbers, exact addresses, photos, M-Pesa references, or staff identifiers into the commercial intelligence pipeline.
29. **Do not label pseudonymous data “anonymous.”** Any stable shop/token reference that permits longitudinal linking is restricted pseudonymous contribution data. Only publish partner datasets after aggregation and a documented re-identification-risk assessment.
30. Data partners must not receive row-level transaction feeds, shop-level identifiers, customer-level profiles or raw event exports. They receive purpose-limited aggregated products with coverage, freshness, units, quality and suppression metadata.
31. The admin panel must be commercially useful end-to-end: data coverage, freshness, quality, trends, product datasets, partner delivery status, consent/retention state and revenue/usage signals. “Show everything” means all authorized intelligence and operational signals; it does not mean exposing identifiable or reconstructable source records.
32. The core app remains free under this strategy. Do not condition core selling, financial records, backups or basic analytics on commercial-data participation. Build revenue from paid aggregated intelligence, research/reporting, licensed APIs and carefully governed partner services.
33. Prefer deterministic SQL, existing server capabilities and simple scheduled/batch aggregation. Do not add an ML pipeline, streaming infrastructure, warehouse or analytics vendor until measured volume or a paying customer justifies it.
34. **The commercial source of truth must be inspectable in the existing admin panel.** Implement a restricted “Contribution Ledger” view of minimized contribution records as accepted by the server, before partner-facing aggregation. Do not store or expose raw identifiable POS rows in the commercial data store.
35. “Raw anonymized data” is not a safe technical guarantee. Use the UI label **Sanitized Contributions (Restricted)** or **Contribution Ledger** for the minimized, row-level commercial input. Treat anything that remains linkable as pseudonymous/confidential, even after direct identifiers are removed.
36. **No platform-level commercial intelligence may be exposed to normal SimpleSales users.** A merchant sees their own shop records/analytics, and the account owner sees only their own authorized shops in “All shops”. Platform-wide market intelligence, contribution ledger rows, contributor coverage by identifiable shop, partner datasets and admin controls are server-authorized only for internal admin roles or approved partner access to aggregates.
37. Build explicit access boundaries for merchant app, account-level cross-shop analytics, internal admin, restricted data steward, and partner API. Do not rely on hidden UI elements alone; every backend endpoint must authorize scope independently.
38. Keep an authoritative provenance chain: accepted contribution batch → normalized contribution version → aggregation job/version → dataset snapshot → partner export/API response. Every derived figure must be traceable and reproducible from retained, lawful source versions.
39. Retention and data-subject rights override “keep forever”. Preserve an auditable, versioned source of truth for as long as there is a lawful, disclosed purpose; implement correction, deletion, withdrawal and derived-data impact workflows. Do not promise indefinite retention of linkable contributions.
40. Raw/minimized contribution access and export are separate permissions. Default to read-only, masked internal IDs and no bulk export. Exceptional access/export requires step-up authentication, a reason, time-bounded authorization, audit logging, and policy approval.
41. Every partner-facing chart, download, query and API must use the same server-side aggregation/disclosure controls. No endpoint may bypass suppression by choosing different filters or downloading underlying rows.

------------------------------------------------------------------------

# 1. Product objective

SimpleSales is a lightweight Kenyan small-business POS and business-record system.

The application must allow a shop owner to:

- sell goods or services;
- track stock where useful;
- record purchases and other costs;
- record operating expenses;
- track cash, M-Pesa and credit;
- distinguish revenue from cash received;
- distinguish direct costs from operating expenses;
- calculate gross profit, net profit and cash flow correctly;
- understand break-even where the Open profile uses pooled stock costs;
- manage customer and supplier balances;
- see profile-specific operational KPIs;
- maintain a verifiable business record;
- back up and restore the complete shop;
- optionally maintain a server copy of business records in Release 1;
- later share selected evidence with lenders in Release 2.

The app must remain usable on low-end Android hardware and must not force every shop through every feature.

SimpleSales is also intended to become a **merchant-safe commerce intelligence network** that can support a free app through paid business-to-business market insights. Commercial intelligence is a separate, documented pipeline: source records stay in the shop’s operational domain; a minimized contribution stream is processed under a separately recorded purpose/consent; partner-ready outputs are aggregated and disclosure-controlled. The existing admin panel is the operational interface for this data network and must be extended through integration, not replaced.

------------------------------------------------------------------------

# 2. Authoritative profile model

## 2.1 Exactly four profiles

| Profile | Primary users                                                                                                                                                          | Core model                                            |
|:--------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|:------------------------------------------------------|
| Drinks  | Bars, taverns, wines/spirits, keg/tank outlets, beverage retailers                                                                                                     | Measured drinks, pours, tabs, tanks, crates           |
| Duka    | General shops, supermarkets, groceries, cereals, loose goods, hardware, cosmetics, stationery, kiosks, pharmacy-type shops                                             | Product catalogue + counted/measured goods            |
| Fashion | Boutiques, garment shops, shoe shops, accessories                                                                                                                      | Styles + size/colour variants + lay-by/exchanges      |
| Open    | Mtumba, bale traders, resellers, produce sellers, hawkers, barbers, salons, mechanics, tailors, cleaners, photographers, makers, freelancers and other solo businesses | Money-first records + optional stock + jobs/materials |

The profile specification explicitly defines these four profiles and says profiles are presets rather than separate apps or databases.

## 2.2 Existing app migration interpretation

The existing application is expected to contain generic catalogue/retail functionality but does not need to have the new four-profile architecture.

Treat existing behaviour as the **Duka baseline**.

On first launch after this feature ships:

1.  Only existing shops with no persisted profile enter one-time profile resolution; shops with a saved profile open normally.
2.  Until a legacy shop profile is chosen or resolved, behaviour defaults to Duka.
3.  Existing catalogue data remains intact.
4.  Existing products are retained.
5.  No data is deleted during profile selection.
6.  Profile switching later must also preserve data.
7.  If existing data clearly suggests Drinks or Fashion, the app may suggest that profile, but the owner confirms it.
8.  Do not invent automatic migration into old seven-profile concepts.

------------------------------------------------------------------------

# 3. Architecture

## 3.1 Shared engines

Build the four profiles on shared engines.

### Engine A — Profile/capability engine

Responsibilities:

- selected profile;
- feature defaults;
- terminology;
- navigation;
- dashboard panels;
- product-editor defaults;
- analytics emphasis;
- onboarding.

Suggested structure:

``` text
lib/profile/
  shop_profile.dart
  profile_capabilities.dart
  profile_terminology.dart
  profile_navigation.dart
  profile_analytics.dart
```

Only this layer may branch on `ShopProfile`.

Screens must consume capabilities rather than writing:

``` dart
if (profile == ShopProfile.duka) ...
```

outside the profile layer.

## 3.2 Engine B — Selling/checkout

There must be one sale writer.

Conceptually:

``` text
UI
 ↓
CheckoutController
 ↓
Sale calculation
 ↓
recordSale()
 ↓
financial posting
 ↓
stock posting
 ↓
payment posting
 ↓
analytics projections/queries
 ↓
integrity record
```

No profile gets a separate sale writer.

## 3.3 Engine C — Inventory and cost

Supports:

- counted stock;
- measured stock;
- packs;
- break-bulk;
- repack;
- variants;
- batches/expiry;
- optional stock tracking;
- purchases;
- direct costs;
- stock adjustments.

## 3.4 Engine D — Finance

This is a new cross-profile foundation.

Every profile gets it.

The finance engine must distinguish:

### Revenue

Value earned from completed sales.

### Cash received

Money actually received through:

- cash;
- M-Pesa;
- bank/other supported payment;
- customer repayment;
- deposits.

Cash received is not automatically revenue.

### Direct cost / COGS

Cost directly attributable to goods or jobs sold.

For catalogue products this is derived from the configured cost model.

For Open pooled stock, it is represented by cost-pool allocation.

For jobs it includes direct materials, labour/helper pay, transport and other direct job costs.

### Operating expenses

Costs of running the business that are not directly attached to a specific sale/job.

Examples:

- rent;
- electricity;
- internet;
- airtime;
- advertising;
- licences;
- transport not allocated to stock/job;
- repairs;
- bank/payment fees;
- wages not treated as direct job labour;
- stationery;
- cleaning;
- other operating costs.

### Owner transactions

Never classified as revenue or expense:

- owner capital in;
- owner drawings;
- loan received;
- loan principal repayment.

Interest/finance cost, if later supported, is an expense; principal is not.

### Receivables/payables

Customer credit and supplier credit are tracked independently from revenue and cash.

------------------------------------------------------------------------

# 4. Universal expense system

## 4.1 Requirement

**All four profiles must have an Add Expense flow.**

The old plan limited expenses mainly to Solo seller. That is no longer correct.

The user requirement is:

> Every profile needs a proper expense form so that when sales happen, revenue, costs, KPIs, cash flow and profit are calculated correctly.

Therefore:

``` text
Drinks → Expenses
Duka   → Expenses
Fashion → Expenses
Open   → Expenses
```

## 4.2 Add Expense form

One shared form, profile-aware.

Fields:

- amount — required;
- expense category — required;
- date/time — default now;
- payment method/source — required;
- description/note — optional;
- supplier/payee — optional;
- receipt/photo — optional;
- direct-cost flag — derived/controlled depending on flow;
- job linkage — only when Jobs capability is active;
- stock/purchase linkage — when the expense belongs to stock acquisition;
- tax information — only when tax capability requires it.

Do not create four separate expense forms.

## 4.3 Expense categories

The underlying category model should be shared.

Initial categories:

``` text
Rent
Utilities
Internet / Airtime
Transport
Advertising / Marketing
Repairs / Maintenance
Wages / Labour
Packaging
Cleaning
Bank / Payment Fees
Licences / Permits
Stationery
Professional Services
Security
Other
```

Profile-specific starter categories may be supplied through configuration.

Do not hard-code category logic into financial calculations.

## 4.4 Direct cost vs operating expense

The UI must make the distinction understandable.

Examples:

- fabric bought specifically for a tailoring job → direct job cost;
- helper paid for a specific job → direct job cost;
- transport specifically attached to an Open bale/lot → cost-pool cost;
- rent → operating expense;
- shop electricity → operating expense;
- general advertising → operating expense.

Do not simply subtract every outgoing transaction from gross profit.

------------------------------------------------------------------------

# 5. Financial event model

Every financial event must have explicit accounting semantics.

## 5.1 Sale

A completed sale can affect:

- revenue;
- tax;
- payment/cash;
- receivable if credit;
- inventory;
- direct cost;
- gross profit;
- cash flow;
- profile KPIs.

For a normal paid sale:

``` text
Revenue += sale_total
Cash += payment_received
COGS += cost_of_goods
Gross Profit = Revenue - COGS
Net Profit = Gross Profit - Operating Expenses
```

For a credit sale:

``` text
Revenue += sale_total
Receivable += sale_total
Cash += 0
COGS += cost_of_goods
```

When the customer later pays:

``` text
Cash += repayment
Receivable -= repayment
Revenue += 0
Profit += 0
```

## 5.2 Expense

For an operating expense:

``` text
Expense += amount
Cash -= amount
Net Profit -= amount
```

For an unpaid expense:

``` text
Expense += amount
Payable += amount
Cash += 0
```

When later paid:

``` text
Cash -= payment
Payable -= payment
Expense += 0
```

## 5.3 Purchase

A stock purchase must not automatically become an operating expense.

For tracked inventory:

``` text
Inventory/cost basis += purchase cost
Cash -= payment
```

COGS is recognized when stock is sold.

For Open cost pools:

``` text
CostPool.Invested += purchase + eligible attached costs
Cash -= payment
```

## 5.4 Refund

Refunds reverse the financial effect of the original sale.

They must:

- reduce net revenue;
- reverse or adjust tax as appropriate;
- return/refund payment;
- reverse stock movement where applicable;
- reverse the corresponding cost allocation;
- update KPIs;
- remain linked to the original transaction.

No sale is deleted.

## 5.5 Void

A void is an audited correction.

It must create an adjustment/void record rather than mutate historical sales.

------------------------------------------------------------------------

# 6. Core financial calculations

The app must expose consistent definitions.

## 6.1 Revenue and tax separation

Use one documented definition everywhere: local dashboard, shop analytics, All shops, transaction exports, statements and server reports.

``` text
Net Revenue
= eligible completed sale value excluding sales tax collected for the authority
- discounts excluding the tax effect
- refunds/credit notes excluding their tax effect
- voided sales
```

For VAT-inclusive prices, split the amount into taxable value and tax using the single `TaxCalculator` and the stored per-line tax snapshot. Collected tax is a liability/pass-through, not business revenue or profit. The receipt total may include tax; the financial revenue metric must not silently count collected tax as earnings.

Pending/failed M-Pesa STK prompts are not receipts. An initiated payment is counted as cash received only when confirmed by the existing verified payment flow. If manually entered payment information is not independently verified, label it as recorded/unverified and do not present it as provider-confirmed.

Lay-by/customer deposits taken before a sale or service is recognised are cash inflow and a customer-deposit liability, not automatically revenue. Resolve the final tax-invoice timing with current KRA/accounting guidance before release.

## 6.2 Direct costs

``` text
Direct Cost
= Product COGS
+ Open pool allocated cost
+ Direct job materials
+ Direct job labour
+ Direct job transport
+ Other explicitly allocated direct costs
```

## 6.3 Gross profit

``` text
Gross Profit = Net Revenue - Direct Cost
```

## 6.4 Operating expenses

``` text
Operating Expenses
= sum of valid operating-expense entries
```

## 6.5 Net profit

``` text
Net Profit = Gross Profit - Operating Expenses
```

Owner drawings, owner capital and loan principal must not change profit.

## 6.6 Cash flow

At minimum:

``` text
Cash Flow
= Cash In
- Cash Out
```

Cash In includes actual completed/confirmed movements:

- cash tender received;
- confirmed M-Pesa receipts;
- customer-credit repayments;
- job/lay-by deposits actually collected (while preserving their liability classification if not yet earned);
- owner capital;
- loan proceeds;
- other actual receipts.

Cash Out includes actual completed movements:

- stock/material purchases paid;
- operating expenses paid;
- supplier/payable repayments;
- refunds paid;
- owner drawings;
- loan principal repayments;
- other actual payments.

A credit purchase creates a payable but is not cash out until paid. An unpaid operating expense affects the expense/profit report under the selected accounting treatment but does not reduce cash until payment. Maintain payment/account-level detail where supported; do not merge cash, M-Pesa wallet and bank balance into one falsely precise number. Keep “recorded movement” distinct from “verified movement”.

The dashboard must distinguish:

``` text
Profit
vs
Cash Position
```

A profitable shop can have low cash because customers owe it money or stock has consumed cash.

## 6.7 Business cash position

``` text
Opening Cash
+ Cash In
- Cash Out
= Closing Cash
```

Where a true opening balance exists, use it.

Otherwise the app must clearly label the calculated position and not pretend historical cash is known.

## 6.8 Default management-accounting basis

Use one documented management-reporting basis throughout SimpleSales:

- Recognize a completed goods sale or delivered service as revenue at the app's defined completion point, regardless of whether it is paid immediately or on credit.
- Recognize an operating expense when the business incurs it/records the valid expense, including unpaid amounts; unpaid amounts create a payable. Payment later reduces cash and the payable but must not record the expense a second time.
- Inventory purchases for tracked goods increase inventory/cost basis. They do not immediately reduce gross profit. Cost is recognized as COGS when the goods are sold, adjusted for returns, write-offs and stock-loss rules.
- Open pool purchases and pool-attached costs belong to the cost pool and are not also posted as generic operating expenses or product COGS.
- Direct job costs must not also be counted as general operating expenses. Link them to the job/direct-cost source.
- Owner capital, drawings and loan principal affect cash/equity/liabilities, not profit.
- Customer/supplier deposits before completion are liabilities/advances until earned or refunded; never count the same deposit as revenue and as the final sale receipt twice.

These are consistent management figures, not a claim that the app replaces an accountant's statutory books. Validate tax-invoice timing, statutory classification and final accounting treatment with a qualified Kenyan accountant/KRA guidance before release.

## 6.9 Single-posting invariant

Every economic event must affect each relevant metric exactly once. Reusing a source record in two views does not create a second posting. The canonical writer and its transaction must commit the source event and required accounting/payment/stock effects atomically where they share a database. Any derived cross-shop summary is a read model only. Corrections use linked reversal/adjustment entries and must be idempotent.

------------------------------------------------------------------------

# 7. Open profile financial model

Open retains the profile specification’s money-first model.

## 7.1 Cost pots

Two types:

- Lot;
- Rolling Stock Money.

A pot contains:

``` text
Invested
Recovered
Remaining
Profit
Loss
```

### Rules

``` text
Remaining = max(0, Invested - Recovered)

Profit = max(0, Recovered - Invested)
```

Recovered money is allocated from sales.

Default allocation:

``` text
oldest open pot first
```

Other modes:

- group tags;
- ask me.

## 7.2 Pool costs

Invested includes:

- purchase;
- transport;
- packaging;
- sorting;
- other costs explicitly attached to the pool.

These are direct costs for the pool.

## 7.3 Open sale without a cost pool

Record as revenue/cash/receivable, but clearly mark cost as unrecorded.

Do not invent profit.

The Business Record should show reduced cost coverage.

## 7.4 Open individual items

Items bought individually use normal item-level cost:

``` text
profit = selling price - item cost
```

No pool allocation is required.

## 7.5 Open jobs

A job includes:

- customer;
- title;
- quote;
- final price;
- due date;
- status;
- payments;
- direct costs.

Job direct costs:

- materials;
- helper/labour;
- transport;
- other direct costs.

Optional owner-time valuation:

``` text
Owner Time Cost = hours × configured hourly value
```

This is a management metric and must not be silently mixed into statutory cash expense unless the owner records it as an actual cost.

------------------------------------------------------------------------

# 8. Universal business statement

Every profile gets a Business/Analytics statement.

At minimum:

``` text
Revenue
Direct Costs
Gross Profit
Operating Expenses
Net Profit

Cash In
Cash Out
Net Cash Flow
Closing Cash / Cash Position

Accounts Receivable
Accounts Payable

Owner Capital
Owner Drawings
Loans Received
Loan Principal Repaid

Inventory Value where applicable
```

Open additionally gets:

``` text
Open Pots
Invested
Recovered
Still to Recover
Profit after Break-even
Loss Lots
Jobs
Job Margin
```

------------------------------------------------------------------------

# 9. Enhanced analytics — all four profiles

## 9.1 Universal analytics

All profiles must have:

### Financial overview

- gross sales;
- net sales;
- revenue trend;
- direct cost;
- gross profit;
- gross margin %;
- operating expenses;
- net profit;
- net margin %;
- cash in;
- cash out;
- net cash flow;
- cash position;
- receivables;
- payables;
- owner drawings;
- owner capital;
- loan balance where applicable.

### Sales

- sales count;
- average transaction value;
- sales by payment method;
- sales by day;
- sales by hour;
- sales by category;
- sales by staff where applicable.

### Cost

- direct cost;
- expense trend;
- expense categories;
- cost coverage;
- margin leakage;
- discounts;
- refunds;
- voids.

### Record quality

- months of history;
- consistency;
- payment-method completeness;
- purchase proof;
- cost coverage;
- expense completeness;
- personal/business separation;
- M-Pesa reconciliation where supported;
- customer repayment performance;
- supplier repayment performance.

------------------------------------------------------------------------

# 10. Profile-specific enhanced analytics

## 10.1 Drinks

Home emphasis:

- sales by hour;
- open tabs;
- tank levels;
- low stock;
- shrinkage;
- today’s profit/cash summary.

Analytics:

- pour cost %;
- litres sold;
- expected vs actual litres;
- dip variance;
- waste %;
- bottle vs tot mix;
- margin by selling option;
- peak hours;
- open tabs outstanding;
- shrinkage value;
- expenses;
- gross profit;
- net profit;
- cash flow.

## 10.2 Duka

Home emphasis:

- today’s sales;
- cash/M-Pesa/credit;
- money owed;
- low stock;
- expiring stock;
- top products;
- profit/cash summary.

Analytics:

- sales and profit by category;
- margin by product;
- loose goods by weight/volume;
- sales by amount vs quantity;
- singles vs packs;
- stock cover days;
- dead stock;
- repack yield;
- receivables and ageing;
- expiry write-offs;
- shrinkage;
- expense categories;
- gross/net margin;
- cash flow.

Duka absorbs the old concepts of:

- general retail;
- loose goods;
- cereals;
- hardware;
- pharmacy-type shops.

These are **use cases inside Duka**, not profiles.

## 10.3 Fashion

Home emphasis:

- sales;
- units per transaction;
- lay-by balances;
- broken size runs;
- returns/exchanges;
- profit/cash.

Analytics:

- sell-through by style;
- sell-through by size;
- sell-through by colour;
- size-run completeness;
- stock age;
- ageing buckets;
- markdown rate;
- markdown margin;
- margin by style;
- units per transaction;
- returns rate;
- exchange rate;
- exchange reasons;
- lay-by balances;
- lay-by expiry;
- sales by assistant;
- gross margin return on inventory;
- operating expenses;
- net profit;
- cash flow.

## 10.4 Open

Home emphasis:

- money in;
- money out;
- still to recover per pot;
- jobs due;
- money owed to owner;
- money owner owes;
- record quality;
- profit/cash.

Analytics:

- break-even progress;
- days to break-even;
- profit after break-even;
- loss lots;
- job margin;
- average job value;
- materials as share of job price;
- owner drawings vs profit;
- revenue trend;
- cash-flow trend;
- receivables;
- payables;
- repayment performance;
- record consistency;
- months of history.

Open drill-down is:

``` text
pot
job
tracked item
described sale
```

rather than a traditional product-margin report.

------------------------------------------------------------------------

# 11. Profile capability matrix

Use this as the implementation source of truth.

| Capability              |           Drinks |                       Duka |          Fashion |                     Open |
|:------------------------|-----------------:|---------------------------:|-----------------:|-------------------------:|
| Product stock tracking  |               On | On, per product can be off |  On, per variant | Off by default, optional |
| Selling options         |               On |                         On |         Optional |                 Optional |
| Sale by money amount    |         Optional |                         On |              Off |                 Optional |
| Pours                   |               On |                        Off |              Off |                      Off |
| Tanks/taps              |               On |                        Off |              Off |                      Off |
| Packs/crates/break-bulk |               On |                         On |         Optional |                 Optional |
| Repack                  |         Optional |                         On |         Optional |                 Optional |
| Size/colour variants    |         Optional |                   Optional |               On |                 Optional |
| Lay-by                  |              Off |                   Optional |               On |                 Optional |
| Exchanges               |         Optional |                   Optional |               On |                 Optional |
| Expiry                  |         Optional |                   Optional |              Off |                      Off |
| Tabs/held sales         |               On |                         On |         Optional |                 Optional |
| Credit sales            |         Optional |                         On |         Optional |                       On |
| Suppliers/reorder       |               On |                         On |               On |                      Off |
| Receive stock           |               On |                         On |               On |             Add purchase |
| Stocktake               |               On |                         On |               On |                      Off |
| Price tags              |         Optional |                   Optional |               On |                      Off |
| Break-even pots         |              Off |                        Off |              Off |                       On |
| Jobs/materials          |              Off |                        Off |              Off |                 Optional |
| Business record         |         Optional |                   Optional |         Optional |                       On |
| Staff/shifts            |               On |                         On |               On |           Off by default |
| Customer profiles       |         Optional |                   Optional |               On |                 Optional |
| eTIMS/VAT               |         Optional |                   Optional |         Optional |                 Optional |
| Expenses                | **On/available** |           **On/available** | **On/available** |         **On/available** |
| Enhanced analytics      |           **On** |                     **On** |           **On** |                   **On** |

------------------------------------------------------------------------

# 12. Profile selection, persistence and explicit changes

Profiles are assigned **per shop**. Account membership and a shop’s business profile are separate concepts.

## 12.1 First account setup

When a user creates an account and creates their first shop, the shop creation/onboarding flow requires them to choose exactly one profile:

- Drinks
- Duka
- Fashion
- Open

Profile selection must be part of initial setup, not an extra recurring question after login. Persist the selected profile before the shop setup flow completes.

## 12.2 Returning users

On later app launches and logins:

1.  Restore the authenticated account/session using the existing auth flow.
2.  Load the account’s shop registry and permissions.
3.  Resume the last active shop if it still exists and the user can access it; otherwise show the shop selector or All shops overview.
4.  Load the stored profile for the selected shop.
5.  Do **not** show the profile chooser again when the profile has already been saved.

A returning user may see normal authentication, an expired-session login, or required security confirmation; that is not a reason to ask for the profile again.

## 12.3 Adding another shop

Every Add Shop flow must ask for that new shop’s own profile before final creation. This applies even when the new shop has the same owner and a different profile from all existing shops.

Shop creation should collect only necessary fields up front, such as shop name and profile. Currency/timezone/tax setup uses safe defaults and targeted follow-up settings rather than a long questionnaire.

Creation must be all-or-nothing:

1.  Validate the account permission and selected profile.
2.  Reserve a unique stable `shop_id`.
3.  Create the shop database/workspace and required base schema.
4.  Save its profile and default capabilities.
5.  Register the shop against the account.
6.  Set the new shop as active only after all required steps succeed.
7.  On failure, roll back the registry record and remove any incomplete workspace safely; never leave an invisible half-created shop.

## 12.4 Legacy installs and missing profile state

If an upgraded existing shop has no profile, run a **one-time migration/setup resolution** only for that shop. Use an existing-data suggestion where reliable; otherwise present the four-profile chooser once. If the owner dismisses or skips this legacy-only prompt, persist Duka as the selected fallback and mark profile resolution complete; the owner can deliberately change it later in Settings. Never reopen the prompt on ordinary app return. A new shop, unlike a legacy shop, cannot complete creation without selecting a profile.

Migration must not rename, delete, or duplicate existing products, sales, customers, or stock. Existing general-retail behaviour becomes the Duka baseline.

## 12.5 Changing a profile later

Do not show automatic profile prompts on return. A profile can be changed only through an intentional action such as **Settings → Shop → Business profile**.

Before applying a change, show a preview of feature/navigation/terminology changes and warn about any setup required. Keep all existing records. A feature being hidden by the new profile must not delete its data. Features already used must remain accessible through an appropriate history/detail route or an advanced setting where safe. Record the change in an audit log.

Changing a profile must not change transaction history, cost basis, tax snapshots, cash balances, or financial results.

------------------------------------------------------------------------

# 13. Account and multi-shop lifecycle

## 13.1 Account model

An account may own or be allowed to access multiple shops. The first cross-shop release covers every shop in the authenticated account's shop registry that is accessible to the current installation. It reads each available local shop workspace and must label any registry entry whose data is not available locally. Release 1's one-way phone-to-server sync does not silently become multi-device two-way editing. If a remote-only shop can be included from a secure existing/server summary, show it with source/freshness metadata; otherwise mark it unavailable/incomplete rather than reporting it as zero.

Each shop has:

- a stable immutable `shop_id`;
- a display name;
- one of the four profiles;
- a separate shop database/workspace under the existing architecture;
- its own settings, tax configuration, currency, timezone, products, transactions, people, and permissions;
- account membership/role grants;
- sync/backup/health metadata.

Do not use a shop name, database filename, list index, or currently selected tab as the shop’s identity.

## 13.2 Navigation states

The app must have three distinct states:

- **No shop exists:** continue initial setup and create the first shop/profile.
- **Shop exists and is active:** open that shop using its stored profile; never ask the profile again.
- **Multiple shops exist:** expose an All shops overview/shop selector and allow the user to switch to a shop. Returning users resume their last accessible shop when appropriate.

“All shops” is a reporting/activity context, not a fifth profile and not a separate database.

## 13.3 Active-shop transition safety

On shop switch:

1.  Disable new writes briefly while the active workspace transition is in progress.
2.  Finish or safely cancel pending local operations; never silently drop a sale or payment.
3.  Close the prior shop’s database/repositories where required.
4.  Cancel or invalidate shop-scoped async tasks and subscriptions.
5.  Clear or re-key UI state, image caches and query caches by `shop_id`.
6.  Open the selected workspace.
7.  resolve profile/capabilities/settings from that shop;
8.  refresh the backend tenant/shop context from the selected shop’s authenticated mapping;
9.  show an unambiguous shop name/profile indicator before writes resume.

Use a session/workspace generation token or the repository’s existing equivalent so a late async result from Shop A cannot render into Shop B. A stale background operation must not post to a different shop after a switch.

## 13.4 Account-level access and role boundaries

- Owners/account admins can see all shops they own or administer.
- Managers see only shops explicitly granted to them.
- Cashiers are shop-scoped by default; they do not gain cross-shop financial reporting just because they use the same device.
- Cross-shop financial and export permissions must be checked server-side for server endpoints and locally for on-device workspaces.
- A cross-shop activity item may reveal only fields permitted to that viewer. Customer personal data is not displayed in the account overview by default.

## 13.5 “All shops” and unified activity

The account overview must work even when shops use different profiles. At minimum, show each accessible shop’s:

- name and profile;
- today’s sales/revenue and transaction count;
- gross/net profit when costs are sufficiently recorded;
- operating expenses;
- cash inflow/outflow and known cash position;
- receivables/payables where supported;
- open tabs/lay-by/jobs/pots where relevant;
- low-stock, expiry, overdue-balance or other profile-specific alerts where relevant;
- last local activity;
- backup/sync state and last successful sync when enabled;
- visible warnings for stale/incomplete/unverified data.

The overview must also show a single blended account summary for metrics that have common definitions across profiles. Profile-specific metrics remain visible by shop/profile and are never incorrectly added together (for example litres, pieces, size variants and jobs are not a common quantity).

## 13.6 Unified transactions view

“All shops → Transactions/Activity” must present transactions from all accessible shops in one normalized, chronologically sorted view. Support filters for shop, profile, date range, transaction type, payment method, status and amount range.

Every row carries a stable `shop_id` and displays at least the shop name, profile, local time, type, display description, amount/currency, payment method, status, and cash impact where relevant. Available optional fields are rendered without forcing every profile to invent a product/customer/job.

Opening a row must switch to the source shop safely and open the existing detail route for that source record. No new parallel transaction-detail implementation is permitted. Edits/voids/refunds must execute only after the source shop and permissions are revalidated.

------------------------------------------------------------------------

# 13A. The profile onboarding cards

There are exactly four profile cards, shown in the initial shop-creation flow and the Add Shop flow.

### Drinks

> Bar, wines & spirits, keg/tank or drinks shop

### Duka

> General shop, grocery, cereals, hardware or products with stock

### Fashion

> Clothes, shoes, boutique or accessories

### Open

> Mtumba, services, reselling, produce, makers or another business where you need to track the money

An optional “Not sure?” helper can ask:

1.  Do you count how many of each item you have?
2.  Do you sell by the glass, tot or from a tank?
3.  Do your items come in sizes and colours?

The answers may suggest a profile, but the owner confirms it. Do not create a hidden extra profile for any answer.

# 14. Data model

Do not blindly create every table below if an equivalent exists in the current app.

Use repositories under `lib/data/` for new domains.

## 14.0 Account and shop registry

Reuse the existing `WorkspaceService`/shop registry if it already supplies these concepts. Add only missing fields; do not create a second registry.

Each shop registry entry needs, directly or through an equivalent existing model:

- immutable `shop_id`;
- `account_id`/owner identity;
- display name;
- profile summary for the shop picker (derived from the shop database and reconciled on open, not a competing source of truth);
- workspace/database reference;
- role/membership grants or a secure reference to them;
- created/updated times;
- last-active metadata;
- sync/backup health summary.

The per-shop database is authoritative for shop business records and settings. Any registry profile/status copy is a cache/index used to render the shop list without opening every database. Update it after a successful database commit and reconcile it when opening a shop. Never let the cache silently override a valid profile in the shop database.

Shop IDs are used to key database selection, async work, caches, analytics rows, server requests and navigation arguments. Use parameterized SQL. Do not derive access rights from a client-provided `shop_id` alone.

## 14.1 Profile

``` text
shop_profile
- profile_key
- chosen_at
- chosen_by
```

Values:

``` text
drinks
duka
fashion
open
```

## 14.2 Feature flags

``` text
feature_flags
- key
- enabled
- source
- changed_at
```

## 14.3 Selling options

``` text
product_sell_options
- id
- product_id
- variant_id nullable
- label
- qty_base
- price_minor
- barcode
- by_amount
- pour
- is_default
- active
- sort_order
```

## 14.4 Finance

If no existing finance ledger exists, introduce domain repositories for:

``` text
financial_entries
expenses
expense_categories
cash_movements
```

Do not duplicate sale/payment tables unnecessarily. Existing sales and credit tables remain authoritative where they already provide the event.

The finance layer may be a projection/query layer over canonical records rather than another competing ledger.

## 14.5 Expenses

Minimum:

``` text
expenses
- id
- uuid
- amount_minor
- category_id
- date
- payment_method
- description
- payee_id nullable
- job_id nullable
- direct_cost flag / cost classification
- receipt_photo_path nullable
- created_at
- voided_at nullable
```

Exact fields should follow the current repository conventions.

## 14.6 Open

Use the specification’s concepts:

``` text
cost_pools
cost_entries
sale_pool_allocations
wastage_entries
jobs
job_costs
owner_transactions
loans
statements
passport_shares
```

## 14.7 Integrity

Every financial record that participates in evidence must have stable fields suitable for hashing.

Never hash:

- display labels;
- mutable status;
- customer names;
- phone numbers;
- prescription text;
- photos.

------------------------------------------------------------------------

# 15. Transaction propagation contract

This is one of the most important Codex requirements.

A completed sale must update the relevant domains atomically.

Conceptually:

``` text
recordSale()
  ├─ validate cart
  ├─ calculate totals
  ├─ calculate tax snapshot
  ├─ calculate direct cost
  ├─ write sale
  ├─ write sale items
  ├─ deduct stock
  ├─ write credit/payment effect
  ├─ allocate Open cost pool when applicable
  ├─ append integrity event
  └─ commit
```

Analytics must then derive:

``` text
revenue
direct cost
gross profit
expenses
net profit
cash flow
receivables
stock
profile KPIs
```

Do not let individual dashboard widgets independently reinvent accounting arithmetic.

------------------------------------------------------------------------

# 16. Analytics architecture

Use a single finance calculation layer/query contract.

Suggested conceptual interfaces:

``` dart
FinancialSummary getFinancialSummary(period);

CashFlowSummary getCashFlow(period);

ProfitSummary getProfitSummary(period);

ExpenseSummary getExpenseSummary(period);

ReceivableSummary getReceivables(period);

PayableSummary getPayables(period);

ProfileAnalytics getProfileAnalytics(
  ShopProfile profile,
  DateRange period,
);
```

The actual implementation should match the existing architecture.

### Required invariant

For any period:

``` text
Net Profit
= Net Revenue
- Direct Costs
- Operating Expenses
```

And:

``` text
Net Cash Flow
= Actual Cash In
- Actual Cash Out
```

These numbers must not be derived from each other.

## 16.1 Cross-shop analytics and reporting contract

Cross-shop reporting is a required integrated feature, not a future profile-specific add-on.

### One canonical calculation, many scopes

Use the same canonical financial definitions and repository/query implementations for:

- one shop;
- a profile’s analytics;
- the account’s All shops dashboard;
- the cross-shop transaction/activity viewer;
- exports and statements;
- server reports if an existing authorized API supports them.

The only difference is the set of `shop_id` values included. Do not write a second finance engine or duplicate financial formulas in an account dashboard.

### How to aggregate across shops

- Aggregate additive values from the same period and currency: net revenue, direct costs, gross profit, operating expenses, net profit, verified cash in/out, receivables and payables.
- Derive ratios from aggregated numerators and denominators. Do not average shop margin percentages or average transaction values without weighting.
- Keep each shop’s currency visible. Multi-currency conversion is out of scope. Never add amounts with different currencies into a fake combined total; show separate currency subtotals and explain why there is no grand total.
- Respect each shop’s timezone for shop-local “today” and show the reporting timezone/range in cross-shop reports. Use a consistent account-wide date range for comparisons, and label any shop-local boundary differences.
- Do not add incomparable units. Litres, pieces, kilograms, size variants, pots and jobs remain per-shop/profile metrics. A common financial valuation may be compared only when currency/cost coverage is adequate.
- Unknown or uncosted sales must remain visible and must reduce cost-coverage completeness; they cannot be silently treated as zero-cost profit.
- Distinguish verified, pending, estimated and stale values. Missing/offline/unavailable shops must be marked as such; do not treat them as zero-activity shops.

### Efficient implementation

Prefer SQL aggregation over loading raw records. Query each accessible shop’s existing database through existing workspace/repository services, using indexed time and status fields. For the activity list, fetch bounded pages from each source and merge the sorted pages by timestamp; do not read every transaction into memory. Use a single normalized `CrossShopActivityItem`/view model (or existing equivalent) as a transient read model only. Do not persist a duplicate copy of every transaction just to render the All shops list.

If profiling demonstrates that querying shop databases sequentially is too slow, first add the smallest useful index/query improvement. Add a derived summary cache only if measured; key it by shop ID, report period, currency and source-data revision, and invalidate it on every relevant commit, profile/shop change, restore, sync acknowledgement or deletion. Never maintain a second authoritative total.

### Read-only semantics and navigation

Account-level reports are read-only. A selected activity row carries its source `shop_id` and source record ID. Drill-down switches to that shop through the safe workspace transition, verifies access, and opens the existing detail screen. Any write then occurs inside the selected shop’s existing transactional writer. Every cross-shop screen must make the current scope clear: “All shops” or a named shop.

## 16.2 Cross-shop comparison set

All profiles participate in the common comparison set:

- net revenue;
- direct costs;
- gross profit and margin;
- operating expenses;
- net profit and margin;
- cash in/out/net movement;
- known closing cash/wallet balance where reconciled;
- receivables and payables;
- sale/transaction count and average transaction value;
- refund/void totals;
- cost coverage and unverified/pending totals;
- last activity, backup status, sync status and outstanding alerts.

If the current app supports transfers of money or stock between shops, represent them as explicitly linked internal-transfer records. They may change the source/destination shop's balances or stock, but must not be counted as external account-level revenue, expense, or cash inflow/outflow twice. If the app does not already support such transfers, do not build a separate transfer subsystem as part of this plan; ensure existing records are not misclassified.

Profile-specific cards should be grouped by shop or profile beneath this common set. The account summary should surface “needs attention” items across shops without blending incompatible units or leaking data to unauthorized users.

## 16.3 Cross-shop alerts, exports and reporting completeness

The account overview should surface actionable, explainable notices across shops, including where the underlying profile supports them:

- shop has no recorded activity for a selected period;
- low stock, expiry or tank/dip discrepancy;
- open tabs, overdue customer balances, supplier balances or lay-bys;
- unusual expense increase compared with the shop’s own recent history;
- negative/unknown margin, missing cost coverage or unexplained stock/cash variance;
- backup overdue, sync paused/failed, records unanchored or verification mismatch;
- data from a shop is stale, unavailable or not included in the current totals.

These are informational flags, not unsupported fraud claims or automatic credit scores. Use deterministic thresholds and show why an alert exists. Reuse the existing attention/notification component where present; do not add a second event/notification subsystem for the overview.

Cross-shop export/reporting must:

- respect the same shop-access and field-level permissions as the screen;
- include report period, generation time, included-shop list, excluded/unavailable-shop list, currencies, calculation definitions and completeness warnings;
- omit customer personal data by default;
- never include a shop outside the authorized scope;
- apply the same aggregate calculations as the on-screen view;
- be generated from a bounded consistent snapshot so later activity cannot silently change an already issued export.

## If a snapshot cannot be made perfectly atomic across separate shop databases, capture each shop’s source revision/time and label the report with its per-shop snapshot time. Do not imply all shops were read at one global instant when they were not.

# 17. Dashboard

The dashboard is capability-driven.

Every profile must have:

### Financial strip

- Sales/revenue;
- Gross profit;
- Net profit;
- Cash flow;
- Cash position.

Avoid overwhelming the home screen.

Detailed analytics belongs in Analytics/Business.

### Profile-specific cards

Use the profile KPI sets defined above.

### Drill-down

Every KPI should lead to the records that produced it.

Example:

``` text
Net Profit KSh 42,000
→ Revenue KSh 150,000
→ Direct Cost KSh 70,000
→ Expenses KSh 38,000
→ Profit KSh 42,000
```

A user must be able to inspect the underlying records.

## 17.1 All shops dashboard

The account-level overview is a first-class route accessible from the shop selector/navigation. It is not a profile and must not change the active shop merely because the owner views it.

Show:

- account-level totals for the selected period (only comparable currencies are combined);
- a card/row for every shop the user is permitted to view, with shop name, profile, revenue, expenses, profit/cost coverage, cash movement, receivables/payables, last activity, backup/sync state and attention alerts;
- blended activity across all profiles;
- a profile-specific KPI area for each shop, using the same analytics engine;
- warnings for missing cost data, unverified payment records, unanchored history, offline shops and stale sync;
- a reporting scope/date range selector and a “last updated” time.

One shop being offline or unavailable must not crash the overview or erase its identity. Show that shop as stale/unavailable and calculate totals from explicitly identified included shops, with a completeness indicator. Do not silently represent missing values as zero.

Every card opens the appropriate shop or the cross-shop transactions filter. Drill-down must preserve the chosen period and return route. The account overview cannot execute sales, expense edits or refunds.

------------------------------------------------------------------------

# 18. Expenses and cash-flow UX

## 18.1 Add Expense access

Provide a fast Add Expense action in every profile.

Possible locations:

- Money screen;
- Analytics/Business;
- quick action on home.

Do not duplicate the form.

## 18.2 Money timeline

All profiles should have a unified money timeline showing:

``` text
Sales
Purchases
Expenses
Customer repayments
Supplier payments
Owner drawings
Owner capital
Loans
Loan repayments
Job deposits/payments
Refunds
```

Filters:

- today;
- this week;
- this month;
- custom period;
- money in;
- money out;
- category;
- payment method.

## 18.2.1 Cross-shop transactions/activity view

The same timeline component must support a shop-scoped mode and an All shops mode. The All shops mode uses a normalized presentation, not a duplicated transaction system.

Each row should show, when applicable:

- timestamp and clear timezone;
- shop name and profile badge/label;
- type: sale, refund, void/adjustment, purchase, expense, repayment, deposit, owner transaction, loan movement, job payment or stock adjustment;
- concise description (never require a product name for Open quick sales);
- amount and currency;
- payment method/account;
- status: confirmed, pending, failed, voided, refunded, unverified or locally recorded;
- revenue/profit/cash impact labels when meaningful.

The view must sort chronologically across the source shops. Pagination must be stable and bounded; use a deterministic tie-breaker such as `(recorded_utc, shop_id, record_id)` so equal timestamps do not cause duplicates or gaps. Preserve filter and scroll context when drilling into a source shop and back.

Do not show customer phone, full customer notes, prescription text, or private receipt photos in the All shops feed by default. Respect role-level field permissions. A permitted source detail screen can reveal more after shop context and authorization are revalidated.

## 18.3 Expense correction

Expenses are never silently edited after becoming part of the record.

Correction flow:

``` text
Void original expense
+
create corrected expense
```

Reason is required.

------------------------------------------------------------------------

# 19. Credit

Customer credit:

- charge;
- repayment;
- balance derived from entries;
- ageing;
- reminders;
- payment method;
- verification state.

Supplier/seller credit:

- purchase on credit;
- amount owed;
- repayment;
- repayment history.

Credit must affect:

- receivables/payables;
- cash flow when payment happens;
- record quality.

Credit sales affect revenue when the sale occurs, not when cash arrives.

------------------------------------------------------------------------

# 20. Tax

Per-shop tax state.

Rules:

- new shop is not VAT registered by default;
- tax configuration is shop-scoped;
- no device-wide tax settings;
- tax snapshots belong to transactions;
- queued receipts must not be recomputed using a newer rate;
- one `TaxCalculator`;
- eTIMS state is per shop.

Tax/legal details must be validated against current KRA/accounting requirements before release.

------------------------------------------------------------------------

# 21. Drinks implementation

## Core

- bottles;
- crates;
- tanks;
- pours;
- tots;
- cups;
- tabs;
- stocktake;
- tank dip;
- waste/spillage;
- staff/shifts;
- cash drawer;
- optional credit.

## Deposit module

Returnable bottle/crate deposits remain optional pending confirmation.

Deposits are not sales revenue.

Track:

- deposits collected;
- deposits refunded;
- empties;
- balance owed in either direction.

## Acceptance test

A bartender:

1.  sells one whisky bottle;
2.  sells three tots;
3.  sells drinks from a tank;
4.  opens a table tab;
5.  receives M-Pesa;
6.  closes the tab;
7.  performs next-day dip check.

All stock, cash, revenue and KPI calculations must reconcile.

------------------------------------------------------------------------

# 22. Duka implementation

Duka is the broadest product profile.

## Core

- counted goods;
- measured goods;
- by-money sales;
- weight;
- volume;
- packs;
- break-bulk;
- repack;
- quick keys;
- suppliers;
- reorder;
- receiving;
- stocktake;
- credit;
- customer records;
- optional expiry;
- staff/shifts;
- receipts;
- eTIMS;
- expenses.

## Duka sub-use cases

### General retail

Use counted products, packs and barcodes.

### Loose goods

Use measured engine:

``` text
KSh 50 sugar
→ quantity calculated
→ exact sale line
```

### Cereals

Use measured products and configurable prices.

### Hardware

Use:

- length;
- mass;
- volume;
- counted pieces;
- credit;
- quotes where enabled.

### Pharmacy-type shop

Use:

- whole-piece counting;
- batches;
- expiry;
- FEFO;
- optional prescription note.

Regulated pharmacy-specific functionality remains outside this version.

## Acceptance test

Receive:

- 50 kg sugar;
- cigarettes by carton/pack/single;
- eggs by tray/single.

Then:

- sell KSh 50 sugar;
- sell one cigarette;
- sell one pack;
- repack 10 kg into 500 g packets;
- record one credit sale.

All stock, costs, revenue and receivables must reconcile.

------------------------------------------------------------------------

# 23. Fashion implementation

## Core

- styles;
- size/colour variants;
- barcode per variant;
- price/cost inheritance;
- size runs;
- seasons;
- markdowns;
- exchanges;
- returns;
- lay-by;
- customer profiles;
- served-by;
- staff;
- price tags;
- suppliers;
- stocktake;
- expenses.

## Exchange

One atomic business flow:

``` text
return original item
+
credit note
+
replacement sale
+
price difference
```

Price difference can be:

- collected;
- refunded.

Both stock movements and documents must link to the exchange.

## Lay-by

- customer required;
- deposit;
- balance;
- reservation;
- payments;
- due date;
- completion;
- cancellation;
- expiry.

Do not count the lay-by as a completed sale until the specified completion rule is met.

Tax invoice timing must be confirmed with KRA/accounting guidance before release.

------------------------------------------------------------------------

# 24. Open implementation

## Core navigation

``` text
Sell
Money
Items (when enabled)
Business
Settings
```

## Quick sale

Three-tap target:

``` text
amount
→ payment
→ done
```

Optional:

- description;
- quantity;
- customer;
- credit.

## Purchases

Add Purchase supports:

- new lot;
- rolling stock money;
- existing lot;
- purchase on credit.

## Expenses

Same universal expense system as every other profile.

## Owner money

Record:

- drawings;
- capital in;
- loan received;
- loan repayment.

None of these are revenue/expense except applicable interest when separately supported.

## Business record

Track:

- history;
- consistency;
- payment completeness;
- purchase proof;
- cost coverage;
- expense completeness;
- separation of business/personal money;
- M-Pesa reconciliation;
- repayment history.

Business record is a statement and verification record, not a proprietary credit score.

------------------------------------------------------------------------

# 25. Backup and restore

The backup must represent the whole shop, not only products and sales.

Include, where present:

- profile;
- feature flags;
- products;
- variants;
- stock;
- sales;
- payments;
- credit;
- customers;
- suppliers;
- expenses;
- jobs;
- job costs;
- cost pools;
- owner transactions;
- loans;
- tax configuration;
- integrity chain;
- media references and supported media;
- statements.

Restore must:

1.  restore the database;
2.  restore supported media;
3.  verify the integrity chain;
4.  record a restore event;
5.  increment device epoch as required;
6.  expose missing history rather than silently claiming a complete chain.

------------------------------------------------------------------------

# 26. Release 1 server sync

Release 1 includes server business-data sync.

**Critical separation:** this section describes the owner-controlled backup/evidence/operational server copy. It is not consent to commercialize the shop’s data. The commercial intelligence contribution stream is specified separately in Sections 47–54, with its own purpose notice, opt-in/opt-out state, minimized schema, aggregation controls and partner-use terms. A merchant must be able to use SimpleSales when commercial sharing is off.

## 26.1 Evidence layer

Contains canonical financial/evidence records needed to verify business history.

Do not send:

- customer names;
- phone numbers;
- prescription text;
- photos;
- free-form sensitive notes;
- product names when not required by the evidence schema.

Use stable/salted references where needed.

## 26.2 Operational layer

Can contain the owner’s operational business data required for backup/restore, including product/stock/customer information according to the final consent contract.

It must be:

- private to the owner;
- encrypted;
- never exposed to lenders in Release 1;
- separately deletable.

## 26.3 Sync

One-way:

``` text
phone → server
```

Release 1 does not support multi-device two-way conflict resolution.

## 26.4 Consent

Use a clear disclosure before enabling the relevant server copy.

The user can disable each layer from Settings.

“Delete my server copy” must delete the server copy while preserving the local history and anchored hash evidence as specified by the final legal/data-protection design.

------------------------------------------------------------------------

# 27. Integrity and anchoring

Integrity starts before analytics.

Stable fields include:

- integer monetary values;
- UTC time;
- staff/device identifiers;
- stable transaction identifiers;
- canonical event fields.

Do not hash mutable display fields.

Server anchoring:

``` text
phone record
→ canonical serializer
→ hash
→ server anchor
→ acknowledgement
```

For synced canonical records:

``` text
server recomputes hash
→ compares to anchor
→ verified / mismatch
```

Duplicate upload must be idempotent.

A conflicting record with the same identity/sequence but different hash must be flagged.

------------------------------------------------------------------------

# 28. Backend contract

The Go backend must provide only the APIs required by the implemented client.

At minimum Release 1 needs contracts for:

- tenant validation;
- integrity anchor;
- anchor status;
- evidence record sync;
- sync consent;
- server copy deletion;
- operational sync;
- restore/download where included.

Backend must validate tenant identity from authenticated context, not trust an arbitrary device-wide tenant setting.

All endpoints must enforce shop isolation. The same backend must integrate the commercial-intelligence contribution endpoint and the existing admin panel described in Sections 47–54. Before implementing anything new, inspect the existing admin-panel routing, authentication, endpoint contracts, jobs, analytics queries and partner-management primitives. Reuse these. Do not create a second admin app, second authentication system or parallel data-ingestion framework.

## 28.1 Cross-shop authorization and request binding

- The authenticated account/user identity comes from the validated session/token, not a request body field.
- The server verifies that the authenticated identity has access to every requested `shop_id` and every requested reporting scope.
- Cross-shop list/summary endpoints return only authorized shops and fields. Client filtering is not an access control.
- Do not trust `x-tenant-id`, `shop_id`, an active-shop preference or a database filename as proof of ownership.
- Each transaction request is bound to one shop. A bulk cross-shop report may read across authorized shops, but a write must specify and validate exactly one source shop.
- Use parameterized queries, input bounds, pagination, rate limiting where appropriate, safe error messages, TLS and audit logs for permission/profile changes, data exports, backup/restore, sync-consent changes and server-copy deletion.
- Keep tokens and secrets out of logs. Do not log full customer details, receipt contents or financial payloads unnecessarily.
- Store credentials/tokens only through the app’s existing secure credential storage. Backups must be encrypted; backup keys must not be hard-coded or stored beside the encrypted backup.
- Audit local database/media at-rest exposure during Week 1. Record the threat model and use the smallest compatible protection that meets it; do not silently add a heavy storage dependency without a security and migration review.
- Tests must attempt cross-account and cross-shop IDOR access, stale-session requests and requests issued during shop switching.

If the current backend has no account-to-shop membership mapping, design the smallest secure mapping needed and add it once. Do not add a parallel identity system.

------------------------------------------------------------------------

# 29. Release 2 — lender layer

Do not block Release 1 on lender integration.

Release 2 adds:

- lender-specific consent;
- scope;
- period;
- expiry;
- revocation;
- evidence pack;
- verification page;
- optional live read-only viewing;
- pilot with bank/microfinance partner.

No proprietary credit score.

The lender receives transparent evidence and can make its own lending decision.

------------------------------------------------------------------------

# 30. Implementation map

Before coding, locate the current equivalents.

Expected areas from the previous app snapshot include:

``` text
lib/profile/
lib/data/
lib/models/
lib/screens/
lib/services/
lib/widgets/
db/
```

Existing functionality that should be reused where present:

- workspace/shop switching;
- existing sale writer;
- measured/pour engine;
- product variants;
- M-Pesa STK push;
- receipt builder;
- printer service;
- eTIMS;
- navigation;
- dashboard panels;
- shop settings;
- encrypted backup;
- image service;
- roles and permissions.

Do not assume exact paths are still unchanged.

------------------------------------------------------------------------

# 31. Recommended repository structure

Use the existing architecture if it differs, but keep domain boundaries similar to:

``` text
lib/
  profile/
    shop_profile.dart
    profile_capabilities.dart
    profile_terminology.dart
    profile_analytics.dart

  data/
    finance/
      finance_repository.dart
      expense_repository.dart
      cash_flow_repository.dart
      analytics_repository.dart

    sales/
      sale_repository.dart

    inventory/
      inventory_repository.dart

    credit/
      credit_repository.dart

    open/
      cost_pool_repository.dart
      job_repository.dart

    tax/
      tax_repository.dart

    integrity/
      integrity_repository.dart

  models/
    ...

  services/
    finance_service.dart
    analytics_service.dart
    integrity_service.dart
    sync_service.dart
```

This is a target, not permission to duplicate existing code.

------------------------------------------------------------------------

# 32. Migration strategy

Migrations must be additive.

Rules:

1.  Never modify a shipped migration block.
2.  Add one migration per schema version.
3.  `_onCreate` must produce the same final schema as an upgraded database.
4.  Test:
    - fresh install;
    - current database upgrade;
    - repeated migration;
    - backup/restore after migration.
5.  Existing data must remain valid.

Potential new schema areas:

- profile;
- feature flags;
- selling options;
- tax classes;
- batches;
- expenses;
- jobs;
- cost pools;
- owner transactions;
- statements;
- sync metadata.

Only create a table when the existing database cannot safely represent the domain.

------------------------------------------------------------------------

# 33. Testing strategy

## 33.1 Financial invariants

Test:

### Sale

``` text
revenue += sale
cash += paid amount
receivable += unpaid amount
COGS += cost
gross profit = revenue - COGS
```

### Expense

``` text
expense += amount
cash decreases if paid
net profit decreases
```

### Purchase

``` text
inventory/cost basis increases
cash decreases if paid
COGS unchanged until sale
```

### Credit repayment

``` text
cash increases
receivable decreases
revenue unchanged
profit unchanged
```

### Owner capital

``` text
cash increases
capital increases
profit unchanged
```

### Drawing

``` text
cash decreases
drawings increase
profit unchanged
```

### Loan principal

``` text
cash changes
liability changes
profit unchanged
```

### Refund

Reverse the original financial effects.

------------------------------------------------------------------------

# 34. Cross-profile and cross-shop integration tests

Test all four profiles and the account containing multiple shops, including a mixed set such as Drinks + Duka + Fashion + Open.

### Account/profile lifecycle

- New account setup creates its first shop and requires one of the four profiles.
- On successful setup, the selected profile is persisted.
- Logout/login, app restart, process death, offline restart and token refresh do not show the profile picker again.
- Add Shop requires a new profile choice for the new shop, even when it differs from the active shop.
- The new shop is not partially visible if database creation fails.
- Reopen/switch between shops restores each shop’s profile, settings, active tab and data without cross-contamination.
- Legacy shop migration resolves a missing profile at most once.
- Explicit profile change in settings is audited and never changes historical financial results.

### Cross-shop overview and transactions

- Dashboard contains exactly the authorized shops across all four profiles.
- Blended totals equal the sum of included shop-level canonical figures for the same period/currency.
- Margins and averages are recalculated from aggregate components, not arithmetic means of shop percentages.
- Uncosted and unverified records remain visibly unverified and do not inflate confirmed profit/cash.
- Mixed currencies display per-currency subtotals; no invalid grand total is created.
- Profile-specific units are not combined.
- One shop being offline/stale does not appear as zero or crash the screen; completeness is explicit.
- Transaction rows sort and paginate correctly across equal timestamps and large data sets.
- Tapping a row opens the correct shop/record; back navigation preserves scope and filters.
- A cashier cannot view another shop without a grant; a manager sees only authorized shops.
- Stale async results, cached data and image thumbnails cannot appear after switching from Shop A to Shop B.
- A read-only All shops view cannot execute mutations against the wrong workspace.

### Matrix

Every capability must be:

- On;
- Optional;
- Off

exactly as specified.

Hidden features must not appear in navigation.

### Switching

Test every pair:

``` text
Drinks → Duka
Drinks → Fashion
Drinks → Open
Duka → Drinks
...
```

Verify:

- no data loss;
- no duplicated data;
- existing features remain coherent;
- terminology changes;
- audit event exists.

### Existing-shop migration

Fixture existing shops into:

- Duka;
- Drinks;
- Fashion;
- Open.

Verify data preservation.

------------------------------------------------------------------------

# 35. Performance, efficiency and anti-bloat requirements

Test realistic datasets and compare against the pre-change baseline captured during the Week 1 audit.

At minimum:

- Duka: 10,000 products;
- Fashion: 3,000 styles / 30,000 variants;
- Open: 20,000 quick sales.

Also test:

- analytics for 12 months;
- expense history;
- large sales history;
- offline operation;
- backup creation;
- restore;
- sync queue;
- All shops reporting across the maximum realistic number of local shops;
- unified transaction feed with large history and filters;
- a stress fixture of at least 10 shops and 100,000 total activity records across mixed profiles, with bounded pagination and measured memory use.

Target low-end Android hardware.

### Anti-bloat rules

1.  Capture baseline app size, startup time, memory, checkout latency, analytics latency and database size before implementation. Repeat on the same representative device/build configuration.
2.  Prefer existing dependencies and built-in SQLite aggregation. A new package needs a written reason, size/maintenance cost and security/license check.
3.  Do not add one copy of sale, payment, expense, analytics, dashboard, transaction, image, backup or sync logic per profile.
4.  Do not introduce a second state-management library, service locator, event bus, generic plugin framework or cross-shop shadow database unless the existing architecture demonstrably cannot meet requirements.
5.  Keep the existing canonical sale/payment/expense records authoritative. Financial summaries should be SQL aggregates/read models, not a competing ledger.
6.  Do not load every shop’s complete history into memory. Use indexed, bounded queries, pagination and incremental merge.
7.  Avoid polling. Update the overview after a relevant transaction/restore/sync event, on refresh, and when entering the screen. If a cache is required by profiling, invalidate it deterministically.
8.  Keep image/media work on the existing media service. Keep thumbnails bounded and cache keys shop-scoped.
9.  Avoid work on the sale critical path that can happen later. A sale must commit locally and offline; analytics refresh and sync enqueue must not require network availability.
10. Add indexes only for demonstrated query patterns. Check query plans and migration cost. Never add wide indexes blindly.
11. Keep optional capabilities off when not needed, but all four profiles’ required shared features (expenses, financial analytics, transaction view, account-level reporting) must still be integrated.
12. If an implementation exceeds the measured budget, profile first; cut redundant UI/queries/dependencies before removing required financial or security guarantees.

Suggested release targets (validate against the baseline rather than pretending they are already achieved): checkout local commit stays within the existing app’s latency budget; profile switching never leaks stale state; All shops initial render uses bounded reads and does not block checkout; no unbounded growth proportional to full transaction history is introduced.

------------------------------------------------------------------------

# 36. Accessibility and UX

Minimum:

- 320 dp width;
- text scale 2.0;
- touch targets;
- readable monetary figures;
- clear error states;
- minimal typing for common sales;
- profile-specific terminology.

Open must remain especially fast.

Duka loose-goods selling must not require unnecessary navigation.

Fashion variant selection must be visual and fast.

Drinks pour selection must be immediate.

------------------------------------------------------------------------

# 37. 28-week implementation and integration plan

This is a planning target for one developer integrating the existing Flutter application and Go backend. It is not a promise. Re-estimate after Week 1 and at each checkpoint. **A shared feature must be integrated into all four profiles when the feature itself is completed; profile wiring is not deferred to a separate future port.**

## Week 1 — Repository and performance audit

- Inspect the current app, backend, schema, workspace/shop registry, auth flow, existing `recordSale`, payment confirmation, credit, receipt/eTIMS, media, backup, navigation and analytics code.
- Establish current app-size/memory/startup/checkout/analytics baselines.
- Inventory existing functionality and map each requirement to its current owner.
- Identify one source of truth per domain; document all duplicates to remove/avoid.
- Audit account identity, token handling, tenant resolution, workspace switch and current database creation/restore paths.

**Gate:** a verified integration map exists; existing source code—not assumed old paths—sets the implementation plan.

## Week 2 — Account/shop lifecycle and four-profile persistence

- Add/extend the profile enum and capability configuration for exactly Drinks, Duka, Fashion, Open.
- Add one-time first-shop profile selection during initial account/shop setup.
- Make Add Shop require a profile for the new shop.
- Persist profile per shop and ensure returning sessions load it without prompting.
- Add safe legacy migration for shops missing a profile.
- Extend existing shop registry only where fields are missing; do not create a second registry.
- Add All shops route skeleton and access-scope model.

**Gate:** app restart/login never repeats profile selection; a newly created shop is assigned its own profile; existing data remains intact.

## Week 3 — Tenant isolation, settings migration and integrity foundation

- Audit active shop switching, async work, per-shop preferences, media paths and backend tenant selection.
- Make all shop-specific settings explicitly shop-scoped.
- Add/fix UTC timestamps, stable IDs and integrity hooks from first new writer.
- Add migration safety copy and recovery path.
- Start legal/KRA/data-protection checks.

**Gate:** Shop A settings, requests, images and results cannot bleed into Shop B.

## Week 4 — Shared measured/product model

- Extend the existing measured engine for required mass, volume, length, area and count cases.
- Implement common selling options and pack conversions, using existing structures where possible.
- Integrate the relevant options into Drinks, Duka, Fashion and Open editor/sell flows in the same work item.

**Gate:** shared arithmetic tests pass and all four profiles use the same underlying pricing/stock rules.

## Week 5 — Shared checkout extraction and financial event contract

- Characterize existing checkout and protect it with regression tests.
- Extract a shared checkout controller only if the current screen needs it.
- Define the canonical revenue/tax/COGS/payment/cash/receivable posting semantics.
- Ensure every profile routes through the same sale writer.

**Gate:** old behaviour is preserved and no parallel sale writer exists.

## Week 6 — Profile-driven sell/product UI integration

- Implement Drinks pours/tanks UI, Duka counted/measured/amount selling, Fashion variant path, Open quick-sale path on shared engines.
- Implement profile capability navigation/terminology and product editor presets.
- Make the profile indicator and shop switcher clear.

**Gate:** every profile can execute its core selling flow and uses existing common sale/payment infrastructure.

## Week 7 — Open money-first core + first pilots

- Quick Sale;
- cost pools/lots/rolling pot;
- purchase recording;
- break-even allocations;
- individual resale items;
- owner-money classification;
- early Open and Duka pilot.

**Gate:** pot arithmetic, cash/receivable treatment and ≤3-tap common sale path pass.

## Week 8 — Shared credit and payment-state correctness

- Customer credit and repayment;
- supplier credit and repayment;
- deposit/payment linkages;
- drawer reconciliation;
- pending/confirmed/failed/unverified payment states;
- receivable/payable aging.

Integrate tests for all four profiles according to their capability defaults.

**Gate:** a credit sale is revenue/receivable, not cash; repayment is cash, not new revenue.

## Week 9 — Integrity chain and anchoring

- Append-only record chain;
- server hash anchoring;
- idempotent upload;
- mismatch detection;
- late-entry/clock-skew flags;
- device epoch and restore events.

**Gate:** client and backend agree on a canonical hash; tampering and conflict tests fail closed.

## Week 10 — Complete backup/restore

- Audit all existing business tables and media;
- include profiles, settings, finance, credit, expenses, jobs, variants, cost pools and integrity records as applicable;
- restore verification and restore event;
- safe failure/recovery.

**Gate:** restored test shop reconciles to the original and no shop/media crossover occurs.

## Week 11 — Release 1 evidence sync

- Consent and disclosure;
- canonical stable serializer;
- evidence layer upload;
- server recomputation/verification;
- layer status and server-copy deletion;
- retry/backoff without blocking selling.

**Gate:** each synced record matches its anchor; sync can be disabled; local records remain usable offline.

## Week 12 — Pricing + Drinks

- Price tiers, bargaining, daily prices and history;
- Drinks pours/tanks/tabs/waste/dip checks;
- optional returnable deposits only if confirmed;
- ensure Drinks uses common expenses/finance/analytics contracts, even if UX labels differ.

**Gate:** Drinks pilot passes and common financial KPIs match canonical records.

## Week 13 — Tax stage B

- Tax classes and per-product assignment;
- mixed-tax baskets;
- stored tax snapshot;
- receipt/eTIMS tax consistency.

**Gate:** tax totals are stable after rate changes and align across sale, receipt and report.

## Week 14 — Core financial reporting and universal money timeline

- Shared profit/cash-flow/receivable/payable queries;
- statement generator;
- one Money timeline reusable by each profile;
- clear expense/purchase/owner-money distinctions;
- account/shop report scope plumbing.

**Gate:** one shop’s numbers reconcile from canonical records; no duplicated calculation logic.

## Week 15 — Fashion variants and shared integration

- Style/size/colour matrix;
- variants/barcodes;
- served-by attribution;
- size-run/sell-through analytics;
- maintain common finance and expense flows.

**Gate:** Fashion feature suite and cross-profile finance integration pass.

## Week 16 — Fashion lay-by, exchange and returns

- Reservations and lay-by payments;
- exchanges and linked returns/credit notes;
- due/expired states;
- deposit liability and confirmed tax timing.

**Gate:** stock, cash, revenue, tax and document links reconcile.

## Week 17 — Open jobs/materials

- Jobs/quotes/statuses;
- materials and direct costs;
- helper/labour/transport costs;
- deposits/part-payments;
- invoices and job margin.

**Gate:** job margin, receivables and actual cash movements reconcile; common expenses are reused.

## Week 18 — Universal expenses in all four profiles

- One shared Add Expense form and repository;
- shared categories and optional profile defaults;
- paid/unpaid state;
- direct cost vs operating expense classification;
- void/correction flow and receipt attachment via existing media service.
- integrate navigation, permissions, backup, integrity and analytics in Drinks, Duka, Fashion and Open in this same phase.

**Gate:** the same expense semantics and feature are usable in all four profiles; no profile-specific expense table/form is created.

## Week 19 — Enhanced analytics across all profiles

- Universal revenue/cost/profit/cash-flow/expense/credit reports;
- profile KPI sets;
- drill-down to source records;
- data completeness and cost coverage;
- same release integration in all four profile dashboards.

**Gate:** four profile-specific analytics views are configured over one analytics layer, not independently implemented.

## Week 20 — Payments, refunds, receipts and eTIMS hardening

- Confirmed M-Pesa only counts as received;
- payment status/retry/reconciliation;
- sale voids/refunds;
- tax credit notes;
- receipt/printer updates;
- drawer and wallet/bank movement reconciliation.

**Gate:** sale/refund/payment/tax/cash totals reconcile.

## Week 21 — All shops dashboard and common financial aggregation

- Implement account-level All shops dashboard;
- one shared aggregate query contract;
- same-currency totals and separate subtotals where needed;
- profile-specific per-shop cards;
- freshness, completeness, backup/sync and attention indicators;
- role filtering for shops.

**Gate:** mixed-profile revenue/profit/cash/receivable totals match sum-of-shops truth; incomparable units are not merged.

## Week 22 — Cross-shop transactions/activity viewer

- Normalized transient activity view model;
- unified timeline and filters across all accessible shops;
- stable ordering, pagination and bounded reads;
- source-shop deep links;
- safe switching and permission revalidation on drill-down;
- cache invalidation after every relevant local or sync event.

**Gate:** large mixed-profile activity feed is correct, efficient, read-only at account scope and cannot cross-write shops.

## Week 23 — Operational sync and cross-shop source completeness

- Product/stock/customer operational sync according to the agreed consent contract;
- ensure server ownership mapping allows only authorized account/shop views;
- label shops with missing/stale/offline data;
- restore from server if supported by the existing sync contract.

**Gate:** operational sync cannot leak data across owners/shops and the All shops screen reports incomplete inputs honestly.

## Week 24 — Sync/restore hardening + cross-shop edge cases

- idempotency and conflict handling;
- server copy deletion;
- concurrent switching;
- app restart during sync;
- stale in-flight responses;
- partial database/registry creation failures;
- retry and backoff.

**Gate:** no duplicate transactions, orphaned shops, stale UI writes or silent data loss.

## Week 25 — Four-profile and account-level pilots

Run an actual pilot for Drinks, Duka, Fashion and Open, plus at least one owner/account with multiple shops of different profiles.

**Gate:** each profile passes its acceptance scenarios; cross-shop overview and transaction feed reconcile exactly; no unexplained till variance.

## Week 26 — Security, performance and release candidate

- Full regression/migration suite;
- access-control and cross-shop isolation review;
- penetration test before Release 1 server sync is publicly enabled;
- low-end device performance comparison;
- accessibility;
- restore drill;
- release notes and operational runbook.

**Release gate:** no critical financial, cross-shop authorization, integrity, backup, privacy or payment defects. If not met, replan; do not weaken a gate to preserve the date.

# 38. Pilot plan

## P1 — Open / mtumba

Verify:

- quick sale;
- purchase;
- cost pool;
- break-even;
- profit;
- expenses;
- owner drawings;
- cash flow.

## P2 — Duka / loose goods

Verify:

- measured sale;
- stock;
- repack;
- expense;
- profit;
- cash flow;
- credit.

## P3 — Drinks

Verify:

- pours;
- tank;
- tab;
- M-Pesa;
- waste;
- shrinkage;
- profit/cash.

## P4 — Fashion

Verify:

- variant;
- sale;
- exchange;
- lay-by;
- markdown;
- expenses;
- analytics.

## P5 — Multi-shop owner, mixed profiles

Create or use one account with at least four shops: Drinks, Duka, Fashion and Open. Generate sales, refunds, expenses, credit repayments and other money movements in each. Verify the All shops dashboard, unified transactions feed, filters, drill-down, roles, profile persistence, switching, offline/stale indicators, backups and cross-shop totals.

All pilots must have:

- no unexplained till variance;
- successful backup/restore;
- first common sale in under 3 minutes;
- correct financial statement;
- correct profile analytics;
- correct account-level cross-shop summary and transaction feed;
- no customer/tenant/profile leakage after switching shops.

------------------------------------------------------------------------

# 39. Release gates

Release 1 cannot ship if any of these fail:

### Financial

- profit does not reconcile;
- cash flow does not reconcile;
- refund changes are wrong;
- credit repayment changes profit;
- owner drawings change profit;
- loan principal changes profit;
- expense double-counts COGS.

### Data

- shops can see another shop’s data;
- server copy leaks customer data;
- backup omits a core domain;
- restore silently loses financial records.

### Integrity

- historical sales can be silently edited;
- hash mismatch is not detected;
- duplicate sync changes data.

### Profile and setup

- old seven-profile model remains;
- a hidden feature appears in navigation;
- profile chooser reappears after a completed setup/login;
- Add Shop fails to ask for the new shop’s profile;
- a profile is stored globally instead of per shop;
- profile switch loses data or changes financial history;
- profile-specific terminology leaks.

### Cross-shop

- All shops omits an authorized shop without marking the data incomplete;
- users can see a shop without permission;
- different currencies are added into a false total;
- incompatible profile units are aggregated;
- averages/ratios are aggregated incorrectly;
- activity row opens or mutates the wrong shop;
- pagination skips or duplicates rows;
- stale caches or async responses leak data after a switch;
- cross-shop summary disagrees with the included shop summaries.

### Performance

- sell flow becomes unusably slow;
- analytics blocks checkout;
- large catalog causes unacceptable memory growth.

------------------------------------------------------------------------

# 40. Out of scope

Do not add these during this implementation unless explicitly approved:

- seven old profiles;
- proprietary credit score;
- two-way multi-device sync;
- supplier purchase-order system;
- barcode label printing as a major standalone subsystem;
- multiple currencies;
- loyalty points;
- delivery tracking;
- drug interaction checks;
- insurance/NHIF claims;
- electronic prescription workflows;
- controlled-substance submission;
- cold-chain monitoring;
- compounding;
- appointment booking;
- lender integrations in Release 1;
- family/co-owner viewer access;
- Bluetooth scales in this version.

------------------------------------------------------------------------

# 41. Open decisions that must not be silently invented

Before the relevant feature ships, confirm:

1.  Drinks returnable bottle/crate deposits.
2.  Fashion tax invoice timing for lay-by.
3.  Fashion staff commission: calculate or report only.
4.  Open turnover-tax set-aside wording.
5.  Open helper/labour treatment: direct job cost vs staff model.
6.  Final server-sync consent wording and data-protection treatment.
7.  Exact KRA/eTIMS requirements.
8.  Exact pharmacy regulatory requirements for Duka’s expiry/batch use.

Codex should create TODOs/blockers rather than invent legal behaviour.

------------------------------------------------------------------------

# 42. Codex workflow

For each work item:

### Step 1 — Inspect

Search the repository for:

- existing model;
- existing table;
- existing writer;
- existing screen;
- existing service;
- existing test.

### Step 2 — Map

Write a short implementation note:

``` text
Existing:
Target:
Files:
Migration:
Tests:
```

### Step 3 — Extend

Modify the smallest existing component that owns the behaviour. Reuse the same writer, repository, model and UI component for every profile that shares the behaviour. Do not build a profile-local fork.

Before calling a shared feature complete, maintain an integration matrix:

| Shared feature           | Drinks     | Duka       | Fashion    | Open       | All shops / cross-shop      |
|--------------------------|------------|------------|------------|------------|-----------------------------|
| Sales, payments, refunds | integrated | integrated | integrated | integrated | included where relevant     |
| Expenses                 | integrated | integrated | integrated | integrated | combined and filterable     |
| Financial analytics      | integrated | integrated | integrated | integrated | aggregated                  |
| Activity/transactions    | integrated | integrated | integrated | integrated | unified feed                |
| Backup/restore/integrity | integrated | integrated | integrated | integrated | all accessible shops marked |

A cell cannot be marked done because a screen exists. It must be backed by the shared engine, permission checks and tests.

### Step 4 — Test

Run:

1.  unit tests;
2.  widget tests;
3.  migration tests;
4.  integration tests;
5.  existing regression suite.

### Step 5 — Verify

Check:

- financial invariants;
- profile capability;
- permissions;
- backup;
- integrity;
- low-end performance.

### Step 6 — Update

Record:

- files changed;
- migration version;
- tests added;
- unresolved questions;
- deviations from this plan.

------------------------------------------------------------------------

# 43. Definition of done

A feature is not complete when the screen works.

It is complete only when:

- [ ] existing architecture reused;
- [ ] no duplicate writer introduced;
- [ ] migration added;
- [ ] fresh-install schema updated;
- [ ] upgrade test passes;
- [ ] financial semantics defined;
- [ ] backup includes it;
- [ ] restore includes it;
- [ ] integrity hook added where applicable;
- [ ] permissions verified;
- [ ] ARB strings added;
- [ ] profile capability defined;
- [ ] analytics updated;
- [ ] drill-down works;
- [ ] low-end performance checked;
- [ ] accessibility checked;
- [ ] regression suite passes;
- [ ] documentation updated.

------------------------------------------------------------------------

# 44. Final target architecture

``` text
Account / Authentication / Membership
                 │
          Shop Registry (IDs + roles)
                 │
       ┌─────────┴─────────┐
       │                   │
   Shop A DB            Shop B DB ... Shop N DB
   (Drinks)               (Fashion)       (Duka/Open)
       │                   │
       └─────────┬─────────┘
                 │
       Existing workspace/repository layer
                 │
         Shared domain engines
  ┌──────────────┼────────────────────────┐
  │              │                        │
Selling      Inventory/Cost       Finance/Payments
  │              │                        │
  └──────────────┼────────────────────────┘
                 │
     One analytics + transaction query layer
                 │
     ┌───────────┴─────────────────────┐
     │                                 │
 Active shop views                 All shops views
 profile-configured                 read-only, blended
     │                                 │
     └────────────────┬────────────────┘
                      │
             Integrity / Backup / Sync
                      │
       Evidence layer + private operational layer
                      │
              Release 2 lender layer
```

The central architectural principle is:

> **Four profiles, many shops, one shared implementation per domain, one accounting definition set, one integrity model, and one analytics/query foundation.**

Profiles configure the active shop’s experience; they do not fork the underlying app. The account-level view blends all authorized shops using common financial definitions while keeping profile-specific operational metrics distinct.

# 45. Final implementation priorities

If Codex must choose what to do next, use this order:

1.  Inspect and preserve the actual existing app; never rebuild it blindly.
2.  Make account/shop identity, creation and switching safe.
3.  Persist a profile per shop: select it during first shop setup and Add Shop only; never ask repeatedly on return.
4.  Deliver exactly Drinks, Duka, Fashion and Open.
5.  Establish one shared selling/payment/financial event implementation.
6.  Make revenue, tax, direct costs, operating expenses, profit, cash flow, receivables and payables correct.
7.  Deliver the shared expense form in all four profiles in the same phase.
8.  Deliver Open’s pool/break-even and job models on top of common financial primitives.
9.  Integrate Drinks, Duka and Fashion capabilities into shared engines; do not create profile-specific duplicates.
10. Deliver enhanced analytics in every profile from one analytics foundation.
11. Deliver account-level All shops overview and unified transactions across different profiles.
12. Make drill-down, profile persistence, permissions, tenant selection and caching safe across shop changes.
13. Make full backup/restore, integrity and Release 1 server sync reliable.
14. Harden, pilot all four profiles and a mixed-profile multi-shop account, then release.
15. Implement Release 2 lender access only after Release 1’s data security and owner-consent controls are proven.

## Success definition

An owner can open SimpleSales and immediately resume the correct shop without being asked about its profile again. When they add a new shop, they select that new shop’s profile once. The owner can then open **All shops** and understand how every shop is performing, even when the shops use different profiles. They can view one combined activity/transactions feed, filter it, and safely drill into the correct originating shop.

For every shop and across the account, the numbers answer:

> How much did we sell, what did the goods/jobs cost, how much did we spend running the business, what profit did we make, where did the money actually move, who owes us, whom do we owe, what stock or working capital is tied up, what needs attention, and how complete/verified are the records?

Those answers must be traceable to canonical source records, consistent in every profile, honest about missing/unverified data, isolated by shop and permission, and efficient enough for low-end Android devices.

------------------------------------------------------------------------

# 46. Mandatory final acceptance checklist

- [ ] Exactly four profile values exist: `drinks`, `duka`, `fashion`, `open`.
- [ ] The generic legacy app maps to Duka by default; no old seven-profile set remains active.
- [ ] First-shop creation during account setup requires a profile and persists it.
- [ ] Returning users are never prompted for an already assigned profile.
- [ ] Every Add Shop flow asks for the profile of the new shop.
- [ ] Each shop may have a different profile under the same account.
- [ ] Failed shop creation leaves neither an orphaned database nor an orphaned registry row.
- [ ] Shop switching cannot leak settings, tenant context, navigation, images, customers, transactions, async responses or cached analytics.
- [ ] Shared selling, payment, expense, refund, transaction and analytics logic is implemented once.
- [ ] Each completed shared feature is integrated into all four profiles in the same phase and tested in an integration matrix.
- [ ] All four profiles have the shared expense form and enhanced analytics.
- [ ] Revenue excludes sales tax collected on behalf of the authority; collected tax is shown separately.
- [ ] Pending STK pushes and unverified records are not counted as confirmed receipts.
- [ ] Credit sales, repayments, deposits, refunds, purchases, expenses, owner money and loan principal have distinct semantics.
- [ ] Profit and cash flow are separately calculated from canonical records.
- [ ] Unpaid expenses affect profit when incurred and payables when unpaid; later payment reduces cash/payable without duplicating the expense.
- [ ] Tracked-inventory purchases affect inventory cost basis and become COGS when sold; they are not also counted as operating expenses.
- [ ] Internal transfers, if already supported, are linked and excluded from consolidated external revenue/expense totals.
- [ ] Open pools, individual resales and jobs preserve their distinct direct-cost models without creating a second financial engine.
- [ ] The All shops dashboard includes all authorized shops or clearly flags missing/unavailable data.
- [ ] The All shops dashboard aggregates comparable financial figures correctly and never sums incompatible currencies or units.
- [ ] The unified transactions feed is sorted, paginated, filterable, permission-checked and links to the correct source shop/record.
- [ ] Cross-shop views are read-only; any mutation runs only within a revalidated source shop.
- [ ] Access-control tests cover unauthorized shop IDs, cross-account access, stale sessions and switch races.
- [ ] Backup/restore includes all relevant financial, profile, integrity and media records.
- [ ] Server sync is idempotent, verifies hashes and never makes selling depend on network availability.
- [ ] App-size, memory, startup, checkout, analytics and All shops query performance are measured against the baseline.
- [ ] No unjustified dependency, parallel data store, copied ledger, or per-profile duplicate feature has been introduced.
- [ ] All release gates pass for Drinks, Duka, Fashion, Open and at least one multi-shop mixed-profile account.
------------------------------------------------------------------------

# 47. Commercial intelligence: product goal, boundaries and consent

## 47.1 Business objective

Keep SimpleSales free for everyday shops while building a recurring B2B revenue stream from useful, aggregated market intelligence. The asset is not a list of merchants or customers. The asset is a growing, well-normalized picture of commerce activity that is otherwise difficult to measure: price bands, category demand, stock availability/stockouts where inventory data is reliable, seasonality, transaction-size distributions, payment mix, discount/return behaviour and business-category trends.

The commercial intelligence system must be useful across **Drinks, Duka, Fashion and Open** without four different collection systems. It uses one event vocabulary, one product/category taxonomy, one pipeline, one aggregation policy and one admin-panel integration. Each profile contributes the relevant fields and profile-specific measurements using common definitions.

## 47.2 Four separate data purposes

Never conflate these streams:

| Stream | Why it exists | Contents | Permission and use |
|---|---|---|---|
| App operations and security telemetry | Reliability, abuse prevention, crash diagnosis and product improvement | App version, coarse device/app health, sync errors, latency and feature use where needed | Minimized and purpose-limited; never use diagnostic logs as a back door for commercial records |
| Owner business-data backup/evidence sync | Owner backup, recovery and record verification | The owner’s configured synced business records, under Section 26 | Separate owner-facing disclosure and controls; not commercial-data consent |
| **Commercial intelligence contribution** | Build aggregate market datasets and paid partner insights | Minimized, pseudonymous contribution facts processed into aggregated market products | Separate, clear, specific opt-in and recorded terms; opt-out must stop future contribution |
| Lender/business-record sharing | Let a merchant share an individual business record with a named financial partner | Merchant-authorized statement/record scope | Separate explicit grant, recipient, scope, expiry and revocation; not covered by commercial intelligence participation |

A user must not be forced to accept commercial intelligence sharing to access core POS functionality. The account/shop may continue selling, recording expenses, using local analytics and backing up according to its separate settings when commercial sharing is disabled.

## 47.3 Merchant and customer privacy

Commercial data may be confidential even when it is not personal data. In addition, a sole trader, a precise timestamp/location combination, a rare product basket or a small market segment can be identifiable. Therefore:

- Exclude direct identifiers before contribution: shop/business name, owner name, email, phone, registration/TIN, customer name/phone/ID, supplier contacts, staff names/IDs, payment references and receipt identifiers.
- Never collect customer lists, supplier contact lists, free-text notes, prescriptions, photos, exact addresses, GPS coordinates, raw receipts or message contents for the market-intelligence product.
- Do not infer or sell individual shop creditworthiness, customer behaviour or a targetable list of merchants from the commercial contribution dataset.
- Do not expose a contributor identifier in partner datasets.
- Never promise that pseudonymization alone is anonymization.
- Describe the product accurately: “aggregated market intelligence” rather than “fully anonymous” unless a documented assessment supports that claim.

Commercial-intelligence consent must explain in plain language what commercial signals are contributed, how the contribution is transformed, which classes of buyers may use the resulting aggregates, the product/revenue purpose, the right to opt out of future contributions, retention rules and the contact/rights process. Store consent version, timestamp, account/shop scope, purpose and withdrawal timestamp.

## 47.4 Legal and governance gate

Before enabling commercial contribution in production:

1. Obtain Kenya data-protection counsel review of the data map, consent wording, commercial terms, retention, international transfer and the distinction between the shop owner’s business data and information about identifiable people.
2. Determine SimpleSales/NERVA’s applicable controller/processor roles and whether ODPC registration or other steps are required for the planned processing.
3. Complete a Data Protection Impact Assessment if required by the risk and applicable law. The ODPC publishes DPIA guidance.
4. Establish a data-processing/partner agreement defining permitted uses, security, onward disclosure, retention, re-identification prohibition, breach notification, audit rights and deletion/withdrawal handling.
5. Maintain an auditable record of the approved schema, purpose, recipients/data-product classes and policy version.
6. Do not enable commercial collection until these gates are signed off.

Kenya’s Data Protection Act Section 37 contains specific provisions for commercial use of personal data and anonymization where possible; the Act’s principles also address lawful/fair/transparent processing, specified purposes, minimization, accuracy, retention and security. The General Regulations address how consent is obtained and when it is freely given. This plan is an engineering design, not legal advice; counsel must verify the applied legal basis and exact wording before release.

Reference links:
- Kenya Data Protection Act, 2019 (Kenya Law): https://new.kenyalaw.org/akn/ke/act/2019/24/eng@2022-12-31/source
- Data Protection (General) Regulations, 2021 (Kenya Law): https://new.kenyalaw.org/akn/ke/act/ln/2021/263/eng@2022-01-14/source
- ODPC Guidance Note on Data Protection Impact Assessment: https://www.odpc.go.ke/wp-content/uploads/2024/02/ODPC-Guidance-Note-on-Data-Protection-Impact-Assessment-1.pdf
- ODPC rights of data subjects: https://www.odpc.go.ke/rights-of-a-data-subject/

------------------------------------------------------------------------

# 48. Commercial data pipeline and schema contract

## 48.1 Source of truth and pipeline

The shop database remains the source of truth for individual transactions. The commercial pipeline is a separate derived contribution path:

```text
Canonical shop records (local)
        │
        ▼
Allowlisted normalizer (shared semantics)
        │
        ▼
Minimized contribution batch
(no direct identifiers, no raw free text)
        │
        ▼
Authenticated contribution endpoint
        │
        ▼
Restricted contribution store / aggregation jobs
        │
        ▼
Disclosure-controlled aggregate datasets
        │
        ├──► Existing Admin Panel: coverage, quality, trends, pipeline health
        │
        └──► Contracted partner API / export: approved aggregates only
```

Do not post a full SQLite database, arbitrary JSON, full `sales` rows or a generic “sync every table” payload to the intelligence pipeline.

Commercial contribution is processed off the checkout critical path. The local sale commits when offline; the contribution is queued and retried later. A commercial ingestion failure must never block a sale or corrupt local financial records.

## 48.2 Contribution model

Inspect the existing backend schema and ingestion/analytics implementation first. Prefer extending existing endpoints/tables/jobs. If the current backend has no suitable primitive, create the smallest viable contribution contract.

A contribution batch should contain only approved fields similar to:

- `schema_version`;
- non-identifying batch UUID/idempotency key;
- consent purpose/version confirmation;
- coarse shop profile (`drinks`, `duka`, `fashion`, `open`);
- broad geography only where safe and agreed (for example county or a larger region, not address/GPS);
- time bucket, normally day/week/month depending on sensitivity and volume;
- normalized product/category/subcategory code;
- normalized dimension/unit code and currency;
- aggregate transaction count and unit count;
- aggregate gross/net sales and discount/refund totals, when the selected product is permitted to use these signals;
- price distribution statistics or bands rather than a stream of exact individual prices;
- aggregate payment-method mix;
- aggregate expense categories/totals, only where included in the stated purpose and safe to publish;
- inventory, availability or stockout indicators only where data quality and stock tracking are reliable;
- `contribution_period` and data-quality/completeness indicators.

The exact schema must be a short, versioned allowlist owned by the server contract, not inferred from whatever columns happen to exist in the app.

### Never include in the commercial contribution payload

- owner or business names;
- email, telephone, TIN, registration number or exact address;
- customer/supplier names, phones, IDs, notes or contact information;
- payment-provider references or account credentials;
- staff identifiers;
- unredacted transaction IDs or receipt numbers;
- line-level free-text descriptions;
- prescription information;
- photos, documents, message content or device contacts;
- precise location, device advertising ID or unrelated device fingerprint;
- raw logs containing request bodies/tokens/personal data.

## 48.3 Pseudonymous contributor tracking

Some internal operations require deduplication, opt-out handling, data-quality checks and period-to-period coverage. If a stable contributor token is required:

- generate it using the backend’s secret-keyed HMAC or equivalent server-controlled mapping, not a plain hash of an easily guessable shop ID;
- store the identity-to-token mapping separately with stricter access controls;
- never expose the token in partner exports or partner-queryable dimensions;
- classify this layer as **restricted pseudonymous contribution data**, not anonymous data;
- rotate/retire tokens under the retention policy where feasible;
- do not use the token to build shop-level partner profiles;
- log any administrative access to the mapping.

Prefer pre-aggregated contribution batches where sufficient for the planned market products. Only retain pseudonymous event-level detail if a documented analytical need cannot be met with the smaller aggregate and the privacy review approves it.

## 48.4 Aggregation, suppression and re-identification defence

Partner-facing datasets are aggregated only. Start with the following conservative defaults, then adjust only after privacy review and measured coverage:

- Publish a cell only when it includes at least **10 independent contributing shops and 100 underlying transactions** for the period. If that threshold leaves too few observations, suppress the cell or widen the period/geography/category; do not lower the threshold automatically to make a chart look complete.
- Hide precise times; use day/week/month buckets appropriate to density.
- Suppress rare categories, unique price points, unusual baskets and small geographic segments.
- Avoid intersecting too many filters in a single query. Apply query controls to prevent differencing attacks (subtracting two reports to infer one contributor).
- Do not expose store-level minima/maxima or single-store outliers.
- Use price bands, medians, quantiles and indexed trends where exact values could expose a merchant.
- Maintain contributor-count, transaction-count and suppression metadata internally; partner outputs show useful coverage/confidence labels without revealing which shops contributed.
- Assess re-identification risk on the *combined output*, not just each column independently.
- Re-run the assessment whenever fields, filters, geography, refresh rate or buyer access changes.

The threshold is a default engineering guardrail, not proof of anonymization. Counsel/privacy review must determine whether extra aggregation or statistical disclosure controls are needed. Differential privacy may be evaluated later for high-risk/queryable datasets, but do not add it as a heavy dependency before there is a clear threat model and paying use case.

## 48.5 Canonical definitions and data quality

Use a versioned data dictionary for:

- gross and net sales;
- tax collected;
- discounts;
- refunds/voids;
- transaction count;
- quantity and standard unit;
- average/median price and the exact statistical definition;
- expense categories;
- stockout and inventory coverage;
- profile mappings;
- currency;
- time bucket/timezone;
- contributor and transaction coverage;
- data freshness and quality grade.

Rules:

- Sales, refunds, voids, and duplicated/retried events must be netted exactly once.
- Tax collected for government must not be described as merchant revenue.
- Cash receipt is not the same metric as sale value.
- An unverified M-Pesa prompt is not a confirmed payment.
- Counted inventory, measured stock and Open’s untracked/money-first records are not interchangeable. Label coverage and compare only valid dimensions.
- Currency and units must never be mixed silently.
- Do not market a panel sample as the whole Kenyan market. Every product must disclose actual coverage, period, profile mix and known sampling bias.
- Use normalized internal taxonomy IDs; preserve original product/user text locally only, and do not upload it for this purpose.
- Do not add an AI/ML model just to normalize products in the first version. Start with deterministic mapping/rules and a reviewed manual-mapping workflow in the existing admin system.

## 48.6 Idempotency, deletion and retention

- Every batch has a deterministic idempotency key and schema version.
- Retrying an upload does not increment aggregate totals twice.
- Reprocessing a corrected batch uses explicit version/replacement semantics with audit history; it does not silently double-count old and new values.
- On opt-out, stop creating new contribution batches immediately. Queue entries not yet uploaded are deleted or marked permanently ineligible.
- Handle already received restricted contribution records according to the approved retention/deletion policy. Where a contribution can still be linked to a shop, process the request against the mapping. For irreversible aggregates, counsel must approve the policy and notice; never promise deletion from an already published aggregate if technically/legalistically impossible.
- Separate backup/evidence deletion from commercial contribution deletion; neither control silently changes the other.
- Apply retention/TTL to restricted intermediate records; retain aggregate products only under an approved schedule.
- Keep an audit of opt-in, opt-out, schema/purpose version, partner export and deletion processing.

------------------------------------------------------------------------

# 49. Integration into the existing admin panel

## 49.1 Integration-only constraint

The admin panel is already implemented. **Do not create a replacement admin application.** In Week 1, inspect its repository and document:

- existing admin route/navigation;
- authentication and role model;
- API client/base URL;
- current overview widgets and tables;
- existing analytics or metrics endpoints;
- dataset/job/billing/partner support, if any;
- audit-log mechanism;
- deployment environment and secrets management.

Then extend the existing app using its current components, design tokens, auth and API conventions. Reuse existing backend routes/jobs where possible. Add only the endpoint, view or schema pieces that are actually missing. Do not presume that a named table or endpoint exists without inspection.

## 49.2 “Show everything” — the useful intelligence view

Build one cohesive **Data Intelligence** area in the existing admin panel with tabs/sections using the current UI architecture. It must include aggregate intelligence, pipeline operations, and the restricted **Contribution Ledger** source-of-truth explorer defined in Section 54. The ledger is not an unrestricted raw POS view: it contains only minimized, allowlisted contribution facts and provenance, with no direct identifiers, raw receipts, free text, customer/supplier identities, or individual-source-shop browsing for ordinary admin/partner roles.

### A. Network overview

- contributing shops count and trend, only as aggregate/internal counts;
- contributing shop counts by profile;
- active contribution share vs opted-out/unavailable contributions;
- transaction/category coverage;
- geography coverage at safe aggregation levels;
- data freshness and last successful ingestion;
- event/batch ingestion volume;
- suppressed cells and why they were suppressed;
- data quality/completeness indicators;
- data-product usage and partner delivery health;
- aggregate revenue/use signals for the data products.

Do not show the underlying list of contributing shop identities to data analysts or partners.

### B. Commercial pulse

- aggregated sales/revenue indices by period/category/profile and safe geography;
- median and percentile price bands;
- category demand and growth trends;
- volume/quantity trends with normalized units;
- payment-method mix;
- discounts, refund/return and void rates;
- stockouts/availability where the source cohort has reliable tracked inventory;
- inventory/stock-turnover indicators where comparable;
- expense-category trends only if included in the defined purpose and adequate cohorts exist;
- Drinks: beverage/pour/tank signals where valid;
- Duka: counted/measured-category signals, pack/loose-goods patterns;
- Fashion: seasonal, size/colour and markdown trends where variants are consistently coded;
- Open: service price bands, job category/value trends, lot/break-even aggregates where captured consistently.

All of these are different visualizations over shared normalized data, not separate ingestion systems by profile.

### C. Pipeline and data-quality operations

- pending/failed/retried batches;
- schema/version mismatches;
- duplicate batches blocked;
- stale data;
- coverage changes;
- taxonomy-mapping backlog;
- invalid unit/currency records;
- suppressed output reasons;
- data-quality trend;
- consent-policy version in effect and counts of active/inactive contributions;
- retention/deletion job status;
- server/storage/processing cost signals.

Provide an error code, safe message, retry action and audit trail. Do not show raw payloads with personal or commercially sensitive fields in generic logs.

### D. Datasets and partner delivery

- approved dataset catalog and data dictionary;
- owner/business purpose for each dataset;
- fields, units, aggregation grain, coverage, freshness and quality limitations;
- partner agreements and allowed product scopes;
- API/export usage, quotas and last successful delivery;
- API key creation/rotation/revocation through existing credential primitives;
- export logs, billing state and renewal status where supported;
- contract/policy version and access review reminders.

Use the existing admin role system. Add `data_admin`, `data_analyst` or other roles only if the existing roles cannot express these permissions. Enforce permissions on the backend, not merely by hiding a button.

## 49.3 Internal admin vs data-partner access

The internal admin panel is not the partner portal.

- Internal staff see aggregate intelligence and pipeline quality according to role.
- A designated platform owner/data steward may inspect minimized contribution records through the restricted Contribution Ledger, with field-level masking and a complete audit trail. This does not grant access to original shop databases or direct identifiers.
- Data partners access only explicitly licensed datasets through the existing partner integration if one exists; otherwise start with scoped API keys and controlled exports rather than building a whole new portal.
- Partner credentials are scoped per organization/dataset/endpoint, have quotas/expiry/rotation, and are revocable.
- A partner can never use admin routes, inspect contributing shops, query contribution-ledger rows, retrieve customer data, or infer a single shop’s figures.
- Internal support must not have a casual “view all raw transaction payloads” feature. If diagnostics require a sample, show redacted/aggregate examples; any exceptional access to the restricted contribution ledger must be justified, approved, time-limited and audited.

## 49.4 Admin panel acceptance criteria

- Existing admin login, navigation, design and routes still work.
- No second admin app or auth system is created.
- Data Intelligence reads the real approved pipeline, not demo/static values.
- Every metric shows period, units, coverage and freshness.
- Suppressed/missing data is labelled; it never appears as zero without explanation.
- A user without the right role cannot call the API directly to view restricted datasets.
- Partner keys do not allow cross-dataset access.
- Exports use the same suppression and aggregation policy as charts.
- Admin logs contain neither tokens nor raw PII.
- Data product availability and billing status do not affect the POS checkout path.
- The Contribution Ledger is visible only to the designated platform-owner/data-steward role; all read/search/detail/export operations are server-authorized and audited.
- Merchants cannot access platform-wide market intelligence or contribution records through the app, APIs, exports, notifications, dashboard widgets, support links or cached data.
- A merchant account’s All shops view aggregates only shops owned/authorized by that account; it never includes other contributors.

------------------------------------------------------------------------

# 50. Monetization strategy for a free SimpleSales app

## 50.1 Positioning

The sellable asset is **high-coverage intelligence about Kenyan commerce segments that are under-measured**, delivered with understandable coverage and quality. Do not sell raw shop histories or customer identities.

Examples of comparable market patterns include providers offering aggregate transaction intelligence through dashboards/APIs (for example, Mastercard describes aggregated/anonymized spend and competitive benchmarking; Billsight describes ingesting POS contributions, standardizing/anonymizing them and delivering market intelligence through dashboards and APIs). These show that the product pattern exists internationally; they do **not** prove that Kenyan buyers will pay. Validate demand before overbuilding.

References:
- Mastercard Shopper Intelligence: https://www.mastercard.com/us/en/business/insights-intelligence/economic-market-insights/solutions/shopper-intelligence.html
- Billsight market-intelligence model: https://www.billsight.tech/

## 50.2 Best initial buyer segments

Test willingness to pay with:

1. **Consumer-goods brands and distributors:** category demand, price dispersion, stockouts and promotion/discount performance.
2. **Wholesalers and supply networks:** restocking patterns, demand shifts and geographic/category opportunities.
3. **Payments providers/fintechs:** aggregate cash/M-Pesa/credit payment mix and broad merchant-sector trends; no individual merchant/customer profiling through this dataset.
4. **Researchers, NGOs and development programs:** formalization, SME resilience, business activity and category-level economic indicators.
5. **Financial institutions:** aggregate/sector insights; individual business record access remains a separate merchant-authorized product in Release 2.

Do not start by building a large catalog for every possible industry. Interview buyers and find one expensive decision that a small reliable dataset can improve.

## 50.3 First commercial products

### Product 1 — Kenya Micro-Retail Pulse (first product to validate)

A weekly/monthly report or dashboard with:

- sales/demand indices by supported category;
- median/price bands and changes over time;
- broad geographic trend where enough contributors exist;
- payment-method mix;
- seasonality and category growth;
- coverage, confidence and data-quality disclosures.

Sell a report first if buyers want insight before they need API integration. A small number of manually quality-checked reports can test demand without a large analytics build.

### Product 2 — Supplier/Brand Demand Intelligence

For approved categories/brands with sufficient coverage:

- category/brand demand trends;
- price distribution;
- promotion/discount movement;
- stockout rates and availability for stock-tracked cohorts;
- opportunity areas at safe geographic resolution.

Do not claim real market share unless coverage and sampling support that statement. Prefer “share of observed participating network” or an index unless the full market denominator is defensible.

### Product 3 — Licensed aggregate API

Once multiple customers need the same repeatedly refreshed measures:

- versioned endpoints;
- documented metrics/schema;
- query filters approved by policy;
- quotas, audit, support and uptime monitoring;
- coverage/freshness fields;
- stable billing/contract scope.

Do not build a complex self-service API product before the first paid reporting customers validate which data fields matter.

### Product 4 — Custom research and sector briefs

Create commissioned reports using the same approved aggregate foundation. This can earn initial revenue sooner than a full self-service platform and reveals the fields most worth productizing.

### Later or separate products

- in-app peer benchmarks for contributing merchants;
- supplier offers/referrals with clear labelling and no hidden ranking;
- optional, merchant-authorized Business Passport and lender integrations;
- licensing the analytics layer to a larger platform.

Lender products must use a separate grant per merchant/recipient/scope/period and must not be bundled into commercial-intelligence consent.

## 50.4 Pricing hypotheses to test (not market facts)

Start with paid design-partner conversations, not a large pricing page. Possible experimental bands to test in interviews:

| Offer | Initial hypothesis | What the buyer receives |
|---|---:|---|
| Narrow pilot report | KSh 25,000–75,000/month | One category/region, weekly or monthly trend brief, fixed coverage statement |
| Recurring dashboard/report package | KSh 50,000–150,000/month | Defined dataset bundle, dashboard and periodic analysis |
| Bespoke research brief | KSh 75,000–300,000/project | One scoped question answered from available aggregate data |
| Enterprise/API contract | Quote after pilot | Approved endpoint scope, refresh rate, SLA/support and coverage commitments |

These are **pricing experiments**, not evidence of Kenyan market prices. Test whether buyers will pay, what budget they control, what decision they will improve, the minimum viable coverage and the cost of servicing them. Adjust down/up or abandon a product based on real commitments. Never promise a data field or coverage level that the current contributor network cannot support.

## 50.5 Minimum go-to-market before major build

- Conduct 15–20 structured buyer interviews across at least three buyer segments.
- Ask each buyer what decision is currently made with poor data, how often it occurs, the cost of being wrong, and who has budget authority.
- Show sample aggregate outputs only; never share real identifiable merchant records in sales conversations.
- Seek at least two written design-partner commitments and aim for one paid pilot before building advanced API features.
- Deliver the first pilot with a tightly scoped report using the existing admin/analytics infrastructure; learn from buyer feedback.
- Turn repeated report requests into a product only after two or more customers need the same metrics.
- Reassess contributor density and opt-in rate before committing to geographic/product granularity.

## 50.6 Revenue model and survival math

The objective is to cover hosting, data operations, sales, support, development payroll and a cash reserve while leaving the app free.

Track:

```text
Monthly recurring revenue (MRR)
= recurring data subscriptions
+ recurring API contracts
+ recurring research retainers
+ contracted sponsorship/partner revenue
```

Track contribution margin:

```text
Data product contribution
= data product revenue
- directly attributable hosting/compute
- partner delivery costs
- customer-specific analysis/support
- any agreed contributor/partner payouts
```

Calculate the minimum partner count rather than guessing:

```text
Break-even active contracts
= (monthly fixed operating costs + target payroll + reserve contribution)
  / average monthly contribution per active contract
```

Use actual cost and contract data and round up. Maintain at least a monthly operating dashboard for hosting/cloud, data processing, sales, support, payroll and receivables. Do not hire or scale infrastructure based on uncontracted pipeline value alone.

A practical priority order is:

1. Paid custom reports/design partnerships (test demand with low build cost).
2. Repeatable subscription reports and category dashboards.
3. API licenses for repeatable high-value metrics.
4. Partner-funded enrichment/referral products with explicit agreements and safeguards.
5. Broader coverage, forecasting and advanced modeling only when revenue and data quality support it.

## 50.7 Contributor trust and adoption

Data quality and opt-in are business assets. Track:

- commercial opt-in rate by profile/cohort;
- opt-outs and reasons where voluntarily supplied;
- contributing-shop retention;
- contribution latency and completeness;
- profile/geography concentration;
- support complaints/privacy requests;
- merchant value returned (e.g. free peer benchmarks or category tips).

Give participating merchants practical value back, such as aggregated category/price benchmarks where the sample is sufficient. Do not expose other shops. Do not penalize non-participants or degrade their core POS experience.

------------------------------------------------------------------------

# 51. Security, privacy, commercial confidentiality and partner governance

## 51.1 Threat model

Explicitly defend against:

- re-identifying a shop from precise time, rare items, a small location cohort or unique prices;
- a partner narrowing queries until one shop can be inferred;
- insiders exporting data beyond role/contract;
- compromised API keys;
- consent being inferred from backup sync or app usage;
- identifiers leaking through logs, crash reports, filenames, receipt references or error traces;
- duplicate uploads inflating revenue/volume;
- consent withdrawal not stopping future uploads;
- one partner seeing a different partner’s datasets;
- data being silently repurposed beyond the published purpose.

## 51.2 Required controls

- TLS for transport and encryption at rest using existing secure infrastructure.
- Server-side role and dataset authorization on every request.
- Secrets stored in the existing secrets manager/environment, never in app code or repository.
- Key rotation and revocation.
- Rate limits, request bounds and query complexity limits.
- Query allowlists and aggregation/suppression applied server-side.
- Audit logs for admin access, exports, partner API access, consent changes, retention/deletion actions and schema/policy changes.
- Data retention and deletion jobs with observable success/failure.
- PII-safe logs and telemetry by default.
- Dependency/licence/security review for any new package.
- Backup and disaster recovery for the ingestion/aggregation metadata, without expanding raw data collection.
- Incident response process, breach escalation and partner notification terms.
- A dataset release checklist before every new product or new field.
- Annual/periodic re-identification and access-control review, and immediate review for material schema changes.

## 51.3 Contracts and use restrictions

Each data partner contract must specify:

- exact licensed dataset(s) and metrics;
- permitted purpose/use;
- geographic/time granularity;
- update cadence and quality limits;
- permitted user roles;
- no re-identification, singling out or attempts to identify contributors;
- no unauthorized onward sharing/resale;
- retention/deletion;
- API key security and acceptable use;
- incident notification;
- audit/cooperation rights;
- pricing, service levels and data coverage disclaimers;
- pause/suspension and termination rights.

Commercial data should be licensed as **purpose-limited aggregate intelligence**, not sold as an unrestricted dump.

------------------------------------------------------------------------

# 52. Roadmap and definition of done for commercial data

## Week 1 — add to the repository audit

- Locate and inspect the existing admin panel and its API/backend dependencies.
- Identify existing metrics, data tables, scheduled jobs, exports, partner functions and role permissions.
- Do not rebuild implemented functionality.
- Capture the current data path and a map showing where potentially identifying data currently travels.
- Record current production schema, endpoints and auth before edits.

## Weeks 2–3 — legal/purpose and consent foundation

- Add commercial-intelligence purpose and separate consent state/version.
- Keep backup/evidence sync, security telemetry and lender sharing separate.
- Add an account/shop-level commercial participation status only where the actual business contract requires it; do not store an ambiguous global Boolean.
- Implement opt-out stop rules and tests.
- Obtain the release gate from counsel before live commercial collection.

## Weeks 6–7 — canonical taxonomy and event normalization

- Define normalized categories, dimensions, currencies, profile mapping and aggregate metric dictionary.
- Reuse the same normalizer for all four profiles.
- Create fixture data for Drinks, Duka, Fashion and Open.
- Ensure existing commercial labels/free text remain local and do not flow into the contribution contract.

## Weeks 18–22 — analytics foundations and cross-shop reporting

- Expose canonical metric queries already used by shop analytics and the All shops view.
- Reuse those definitions for commercial aggregates where purposes permit, but do not directly export the owner-facing All shops dataset as a partner dataset.
- Add data quality/coverage metadata and suppression checks.

## Week 23 — commercial contribution pipeline integration

- Integrate the approved contribution batch into the current backend.
- Reuse existing auth, request client, job runner and sync infrastructure where fit.
- Add idempotency, schema validation, retry/backoff and consent checks.
- Keep ingestion off the checkout path and safe while offline.

**Gate:** no raw source tables or direct identifiers are sent; opt-out blocks future uploads; replaying a batch does not double-count.

## Week 24 — existing admin-panel integration

- Add the Data Intelligence pages/widgets to the implemented admin panel.
- Wire real endpoints/queries for network overview, commercial pulse, dataset coverage, pipeline health, consent status, partner delivery and usage.
- Add dataset/data-dictionary views and safe export/API controls.
- Reuse existing design/auth; no replacement panel or parallel auth.

**Gate:** admin numbers trace to aggregate source data; no admin route exposes raw identifiable records; role/API tests pass.

## Week 25 — disclosure controls and partner-ready output

- Add aggregation thresholds, suppression, safe geography/time grains, query allowlists and export tests.
- Add partner-specific dataset permissions, quotas and audit records using existing primitives.
- Produce a sample report/API response using synthetic fixtures and approved aggregates.

**Gate:** no partner output identifies or permits reconstruction of an individual shop under the reviewed threat model.

## Week 26 — mixed-profile data pilot and operational hardening

- Generate contributions from at least one pilot shop in each of Drinks, Duka, Fashion and Open.
- Test consent, offline queue, retries, opt-out, delete/retention handling, coverage, category mappings and data quality.
- Compare commercial aggregates with local canonical records while retaining only approved aggregate outputs for partners.
- Complete security and performance review.

**Gate:** all four profiles contribute through one pipeline and one normalized contract.

## Week 27 — paid buyer discovery and pilot delivery

- Complete 15–20 structured buyer interviews.
- Select one product with the strongest validated buyer problem.
- Deliver sample or paid pilot output with coverage, privacy and limitation notes.
- Measure delivery effort, buyer usage, renewal intent and gross contribution.
- Do not build advanced forecasting or a public self-service portal without evidence of demand.

**Gate:** at least one concrete paid pilot or written design-partner commitment is pursued; the owner can calculate service cost and expected margin.

## Week 28 — final integrated release candidate

- Run the full four-profile, mixed-shop, commercial-data and security suite.
- Verify the existing admin panel, POS, backup/evidence sync and partner data pipeline remain isolated by purpose and role.
- Review all exports/datasets/consent screens with counsel.
- Produce deployment and data-product runbooks.
- Release only after all financial, privacy, cross-shop and operational gates pass.

**Schedule caveat:** the 28 weeks are a planning sequence, not a guaranteed estimate. Actual duration depends on the repository’s current state, legal review, sample density and partner integration. Replan at existing checkpoints rather than weakening privacy/financial gates to preserve a date.

------------------------------------------------------------------------

# 53. Commercial-data final acceptance checklist

- [ ] The admin panel was inspected and extended; no replacement admin panel/auth system was created.
- [ ] All four profiles contribute through one shared normalizer and one versioned pipeline.
- [ ] Contribution is separate from business backup/evidence sync, app telemetry and lender sharing.
- [ ] Commercial purpose and consent wording have legal review and a versioned consent record.
- [ ] Core POS functionality works when commercial contribution is disabled.
- [ ] Opt-out prevents future contribution batches; pending unuploaded batches are handled as specified.
- [ ] The payload excludes direct identifiers, contacts, precise location, free text, photos, raw receipts, M-Pesa references and staff/customer/supplier identifiers.
- [ ] Any stable contributor token is classified as restricted pseudonymous data and is never shared with partners.
- [ ] Partner access is aggregate-only and cannot query source shops or record-level transactions.
- [ ] Minimum contributor/transaction thresholds, suppression and differencing controls are applied server-side to dashboards, exports and APIs.
- [ ] Currency, units, tax, refunds, discounts, payment verification and profile semantics are normalized correctly.
- [ ] Coverage, freshness, quality, suppression and sampling limits are visible in the admin panel and partner output.
- [ ] The admin panel shows actual pipeline and aggregate data rather than sample values.
- [ ] Each partner is scoped to licensed datasets and endpoints; key rotation, revocation, quotas and audit logs work.
- [ ] The pipeline is idempotent, retryable, observable, and non-blocking for offline sales.
- [ ] No unnecessary warehouse, streaming platform, ML service or app dependency is added before justified by scale or a paying customer.
- [ ] Initial data products and prices are hypotheses validated through buyer discovery, not stated as established market demand.
- [ ] Revenue, direct delivery cost, gross contribution, MRR, retention and payroll break-even are tracked.
- [ ] At least one paid design partner/pilot is sought before advanced commercial features are built.
- [ ] Commercial-data terms, retention, deletion, partner contracts and the DPIA/legal gate are reviewed before live collection.
- [ ] All existing profile, financial, cross-shop, backup, security and regression acceptance criteria still pass.
- [ ] The existing admin panel contains a restricted Contribution Ledger view before aggregation, available to the designated platform owner/data steward only.
- [ ] The Contribution Ledger displays minimized allowlisted contribution fields and provenance, not raw identifiable transaction rows.
- [ ] A user can trace an aggregate snapshot to source contribution versions, the aggregation job/version and any partner export that used it.
- [ ] Corrected contributions supersede prior versions without silently erasing audit history; deletion/withdrawal requests follow the approved retention policy and update eligible derived datasets.
- [ ] Normal merchants cannot access platform-wide commercial data from any mobile/web endpoint, export, cache, deep link, notification, error response or admin route.
- [ ] Cross-shop merchant analytics includes only shops the signed-in account is authorized to access; mixed profiles normalize into comparable metrics without exposing other accounts.
- [ ] A normal data analyst or partner cannot view ledger rows, reveal internal contributor references or perform unsuppressed exports.
- [ ] Restricted ledger search/detail/export access has role checks, step-up authentication where appropriate, reason capture for exceptional operations and tamper-evident audit records.
- [ ] The product does not promise indefinite retention of potentially linkable contribution records; retention, deletion and anonymized aggregate preservation have counsel-approved rules.

------------------------------------------------------------------------
------------------------------------------------------------------------

# 54. Source of truth: sanitized contribution ledger and admin-only explorer

## 54.1 Direct answer to the “raw anonymized data” requirement

The existing Version 13 plan described aggregate intelligence and ingestion health, but **did not explicitly require a row-level view of the pre-aggregation commercial contribution data**. This section makes that a required deliverable.

The product must provide an admin-only **Contribution Ledger** in the existing admin panel. Its purpose is to give the platform owner/data steward a trustworthy view of the data accepted into the commercial-intelligence pipeline, diagnose data quality, reconcile aggregates, and prove how each published dataset was derived.

Do not call this data “guaranteed anonymous” merely because names and phone numbers were removed. A record may still be identifiable through rare categories, exact timestamps, prices, location or longitudinal patterns. UI labels must therefore be **Contribution Ledger** or **Sanitized Contributions (Restricted)**. The default contribution grain should be a minimized shop-period-category/unit aggregate rather than one row per sale. Retain individual event-level commercial contributions only when a documented need and privacy review justify them.

This approach follows established de-identification guidance: removing direct identifiers alone is not sufficient; disclosure risk must be evaluated against the actual release model and the information available to a recipient. See NIST SP 800-188: https://csrc.nist.gov/pubs/sp/800/188/final

## 54.2 Three internal layers and one external product layer

```text
1. Merchant source of truth
   Individual shop ledger and source records
   Stored in the shop's own data boundary; accessible to that shop only
                │ approved, separately consented minimization
                ▼
2. Restricted Contribution Ledger  ← admin owner/data steward only
   Allowlisted, minimized contribution facts + provenance + versions
                │ versioned deterministic aggregation
                ▼
3. Aggregate Dataset Store        ← authorized admin analytics
   Reproducible, reviewed dataset snapshots and data dictionary
                │ release gate + partner contract + disclosure controls
                ▼
4. Partner Products                ← licensed aggregate outputs only
   Approved report, download or API; never contribution-ledger rows
```

Do not merge these layers into one table with UI filters. Enforce the boundary in server routes, query/repository methods, roles and credentials.

## 54.3 What the Contribution Ledger shows

The restricted ledger should support paginated search/filter over:

- accepted contribution batch ID and minimized record ID;
- schema version and normalizer version;
- profile: Drinks, Duka, Fashion or Open;
- broad, approved category/subcategory code;
- coarse region only where the cohort passes the publication policy;
- time bucket and period—not precise sale timestamps;
- normalized unit, currency and metric definitions;
- aggregate transaction/unit counts;
- approved aggregate sales, discount, refund, payment-mix or expense signals;
- source completeness and quality flags;
- consent-purpose version and eligibility state, without displaying the owner’s identity;
- received/processed timestamps;
- payload checksum or HMAC/signature verification result;
- supersession, correction, retention or deletion state;
- contribution pipeline status and safe failure code.

Do not show original business/shop name, user name, phone, email, TIN, exact address, customer/supplier identity, staff identifier, receipt ID, M-Pesa reference, raw source text, individual baskets, photos or original source transaction IDs in the ledger.

A restricted pseudonymous contributor token may be present in backend storage only if needed to deduplicate, apply consent withdrawal or measure coverage. It must be masked by default in the admin view, never sent to partners, and unmasked only with an explicit platform-owner/data-steward privilege, step-up authentication and a logged reason. Prefer aggregation that does not require a stable contributor token whenever feasible.

## 54.4 Source-of-truth and lineage contract

For every accepted contribution, persist enough restricted metadata to answer:

- what schema and normalization rules were applied;
- when the batch was received and validated;
- which consent/purpose version made it eligible;
- whether it was accepted, rejected, deduplicated, superseded or deleted;
- which aggregation job and code/config version consumed it;
- which aggregate dataset snapshots it contributed to;
- which partner export/API release included a derived aggregate;
- whether a correction, consent withdrawal or deletion changed subsequent versions.

Each aggregate snapshot must carry:

```text
dataset_id
snapshot_id
schema_version
metric_dictionary_version
aggregation_job_version
period_start / period_end
eligible_contributor_count (internal; release only safe cohorts)
source_batch_version_set or reproducible manifest
created_at
quality_report_id
suppression_report_id
content_hash
publication_status
```

Keep a dataset manifest and content hash so the same retained inputs plus the same versioned deterministic calculation can reproduce the same output. If the result differs, surface a reproducibility warning and preserve both versions rather than silently replacing the previous published dataset.

Use idempotent ingest keys, database transactions, unique constraints and explicit supersession rules. Do not rely on an in-memory queue or the admin UI as the source of truth.

## 54.5 “Always have the source of truth” without retaining forbidden data forever

The objective is an auditable and reconstructible source of truth—not an unconditional promise to retain linkable data forever.

- Preserve the current approved sanitized contribution ledger with backups, integrity checks and a documented retention period.
- Keep aggregate dataset snapshots, manifests, metric definitions, quality reports and publication/export lineage under the approved business-retention policy.
- Corrections append a superseding version; do not silently overwrite accepted history.
- When law, a valid rights request, withdrawal terms or the retention schedule requires deletion, remove or irreversibly de-link the affected restricted contribution records as approved. Keep only a minimal non-identifying deletion/audit marker when lawful.
- Recompute or withdraw affected unpublished/published dataset snapshots when required by the approved policy; record the decision and outcome.
- Never claim a previously published static aggregate can always be deleted from a recipient’s systems. Partner contracts must define the feasible recall/correction process.
- Backups must have a deletion/expiry lifecycle too; deleting a live row while retaining it forever in backups defeats the policy.

“Immutable” means no silent edits and a traceable correction chain; it does not override legal deletion requirements.

## 54.6 Admin role and UX

Integrate with existing authentication and authorization. Do not build another login system.

Recommended permission levels, mapped to existing roles before adding anything new:

- **Platform Owner / Data Steward:** view minimized ledger rows, lineage, quality details and controlled troubleshooting; can approve dataset releases and retention/deletion jobs if their existing role legitimately permits it.
- **Data Analyst:** view aggregate datasets, suppressed-cell summaries, metric definitions, lineage summaries and quality reports; cannot inspect restricted ledger rows or reveal contributor references.
- **Partner Manager:** manage partner contracts, dataset grants, quotas and delivery status; cannot inspect contribution rows.
- **Partner credentials:** only access licensed aggregate endpoints/datasets; no admin endpoints or contribution ledger.
- **SimpleSales merchant/account user:** only their own shop/account records and analytics; no platform commercial intelligence.

All elevated data operations must be performed server-side, not only hidden in UI. The ledger UI should make source-of-truth inspection convenient without enabling uncontrolled extraction:

- page and filter by period, profile, normalized category, batch, status and dataset lineage;
- show the schema and quality flags inline;
- show a clear masked/minimized-data banner;
- show verification/supersession/deletion status;
- allow row detail only within the authorized minimized schema;
- allow export only through a separately authorized, scoped, audited process, disabled by default;
- never offer “export everything” to ordinary admins or partners.

## 54.7 Absolute user-facing commercial-data boundary

The mobile/merchant product must not surface platform-wide commercial intelligence—even to a merchant who opted in to contribute—unless a distinct future product is approved, privacy-reviewed and deliberately launched.

Permitted in the merchant app:

- that merchant’s own shop records and analytics;
- account-level blended analytics across only shops the signed-in account owns or is explicitly authorized to view;
- that account’s own transaction list, activity feed, expenses, financial summaries and shop health.

Forbidden in the merchant app unless explicitly approved in a separate future release:

- platform-wide market demand/price/payment/expense trends;
- network-level “other shops” rankings, benchmarks or comparisons;
- contribution ledger data, contributor counts tied to identifiable shops, partner dataset previews or partner delivery information;
- admin pipeline failures, raw contribution metadata, partner contracts, API keys or data product revenue;
- commercial-intelligence API routes or query parameters that allow shop users to request market-level aggregates.

Implement and test a deny-by-default boundary:

- use separate API route groups and authorization scopes for merchant, account owner, internal admin, data steward and partner;
- a merchant token cannot call admin/partner endpoints even if the client manually constructs the request;
- all shops analytics must take the permitted shop IDs from authenticated server context, never from an untrusted client list alone;
- cache keys must include authenticated account/scope and shop IDs; clear sensitive cached views on logout/account switch and invalidate shop-specific state on workspace switch;
- push notifications, logs, crash reporting, exports, share sheets, deep links and error details must not carry platform commercial values or restricted contribution content;
- enforce response schemas so merchant endpoints cannot accidentally include internal commercial fields;
- add automated negative tests for every protected endpoint, export, cache path and role combination.

The all-shops view is **cross-shop for the same account only**, not cross-platform. A merchant with three shops can compare their own Drinks, Duka and Open businesses; they cannot see other contributors or the network market view.

## 54.8 Reconciliation and quality controls

Before publication, each aggregate job must perform automatic checks:

- batch totals match accepted normalized rows;
- duplicate ingestion has no financial/count impact;
- refunds and voids are netted once;
- units/currency are consistent;
- expected contribution counts reconcile within known gaps;
- excluded/withdrawn/superseded records are not included in new outputs;
- the contributor and transaction thresholds pass after every filter;
- no suppressed value can be obtained through a neighbouring filter or a download;
- a small fixture dataset produces known exact expected outputs;
- aggregate outputs include freshness, coverage and quality notes.

Add a “Data quality & reconciliation” screen in the admin panel showing discrepancies and their resolution status. It must not bypass suppression or reveal contributor identity to resolve a discrepancy.

## 54.9 Security, access and audit requirements

- Apply least privilege and backend checks to every ledger operation.
- Use MFA/step-up authentication for privileged ledger access when supported by the existing auth stack; otherwise add it only through the current auth provider.
- Record viewer ID, role, timestamp, action, filters, row/batch IDs accessed, reason for exceptional access and export hash—not the full record contents—in audit logs.
- Audit logs are tamper-resistant, searchable by authorised security/admin roles and themselves exclude payload PII.
- Apply server-side pagination, maximum page size, query limits and export limits.
- Rate-limit failed/expensive queries and alert on repeated wide exports or unusual access patterns.
- Protect against SQL injection, insecure direct object references, cross-tenant access and IDOR at the API/database layer.
- Never place contribution data, pseudonymous tokens or partner credentials into client-side analytics events.
- Keep secrets out of URLs, app config and logs. Signed downloads, if used, are short-lived and restricted to the authorized internal user.
- Include the ledger in backup/restore, integrity verification, retention, incident response and disaster-recovery tests.

## 54.10 Tests and definition of done

- [ ] Admin owner/data steward can inspect sanitized contribution records in the existing panel.
- [ ] Data analyst and partner roles cannot query restricted ledger endpoints directly.
- [ ] Merchant account cannot query the Contribution Ledger or platform-wide market intelligence API.
- [ ] All-shops data is restricted to the authenticated account’s authorized shops, even if the client supplies foreign shop IDs.
- [ ] No row contains direct identifier fields or raw transaction text.
- [ ] A published aggregate can be traced to versioned source manifests and reproduced from retained eligible inputs.
- [ ] Duplicate batch retry does not double-count.
- [ ] A correction produces a superseding version and rebuilds affected unpublished snapshots according to policy.
- [ ] Consent withdrawal/retention deletion excludes affected data from future contribution and aggregation, with logged outcomes.
- [ ] Suppression controls apply equally to charts, detail views, exports and APIs.
- [ ] No partner export includes contributor tokens or row-level contribution facts.
- [ ] Logs/cache/deep-link/notification tests find no cross-shop or platform-commercial leakage.
- [ ] Restricted ledger export is disabled by default and requires explicit authorization/audit if enabled.
- [ ] Backup restore recovers the permitted ledger, manifests and audit metadata without resurrecting data past deletion/expiry policy.

------------------------------------------------------------------------
