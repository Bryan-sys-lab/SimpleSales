# PATCH 15 — Kenya Lawful Collection, Consent and Data Governance

## Release rule

This patch is a production gate, not a UI-only consent checkbox. Do not enable commercial contribution in production until the controller/processor assessment, ODPC registration assessment, privacy notice, data-sharing terms, retention schedule and DPIA decision are signed off by qualified Kenyan data-protection counsel / the responsible privacy lead.

**“Maximum legal collection” means maximum useful information for each clearly defined purpose, not broad collection in case it becomes useful later.** The ODPC's 2025 research guidance explicitly says not to collect broad data in anticipation of unforeseen purpose. The Data Protection Act principles require data to be adequate, relevant and limited to what is necessary.

## 1. v84 source context

- `assets/SimpleSales_Privacy_Policy.pdf` is the current in-app notice in v84. It identifies Nerva's different controller/processor roles, merchant customer/supplier/staff records, optional commercial-intelligence processing and general sharing/retention language. Do not assume it automatically covers every new field, partner class or use described by these patches.
- `plan/SimpleSales_Codex_Commercial_Intelligence_Plan_v13.md`, §§47–54, requires four separated purposes, separate opt-in, minimized contribution, an existing-admin integration, a restricted contribution ledger and legal review before launch.
- `lib/services/owner_business_sync_service.dart` explicitly says owner backup is not the commercial-intelligence pipeline and contains no contribution method.

## 2. Purpose separation (must be enforced in code and policy)

Keep separate processing purposes and permission records for:

1. **Core POS/service operation:** merchant's own product, sales, inventory, procurement and business records required to provide the requested POS functionality or meet applicable legal obligations. Do not use this as blanket commercial-intelligence permission.
2. **Operational telemetry/security:** minimized app reliability, abuse and crash signals; no raw business table payloads or hidden marketing analytics.
3. **Owner backup/evidence sync:** user-controlled backup and operational records. It is separate from commercial intelligence.
4. **Commercial market intelligence:** optional contribution of pre-specified, minimized business/product/sales/inventory/procurement aggregates for research, benchmarking and licensed market insight. Separate grant and scope.
5. **Named business-record sharing:** merchant-directed share of a specified business record to a named financial institution or other named recipient, with scope and expiry. It is not covered by market-intelligence consent.
6. **Specific NGO/project research involving people:** separate project protocol, data map, legal basis, notice, recipients, retention and (where high-risk) DPIA. Never bundle individual beneficiary information into the general commercial-intelligence switch.

Core POS must work when every optional sharing scope is off. Turning off commercial contribution must not disable checkout, inventory, normal merchant analytics, receipts, backups under their own settings or the paid/free app service.

## 3. Roles and who can authorize what

- Determine roles per processing activity, not by brand label. Nerva may be a processor for merchant-controlled customer/supplier/staff data under documented instructions and a controller for its separately determined commercial-intelligence purpose. A partner's role depends on who determines purposes and means.
- A shop owner / authorized business representative may authorize the shop's own eligible business/confidential operational signals within their authority.
- A merchant cannot provide consent on behalf of customers, staff, suppliers or other natural persons merely because their records exist in the POS.
- The commercial-intelligence pipeline must exclude identifiable third-party records rather than assuming merchant consent covers them.
- Sole-trader business information may identify the proprietor. Treat it as potentially personal data until assessed.

## 4. Granular opt-in model

Use explicit, optional, default-off scopes. The top-level notice must explain the overall market-intelligence purpose; each optional scope names its fields and output type. Suggested scopes:

| Scope code | Contributed signals | Excludes |
|---|---|---|
| `business_activity` | App profile, KeSIC group, broad owner-selected county/context bands | Business name, registration number, tax PIN, exact location |
| `product_demand` | Normalized category/brand code where verified, period quantity and sales/price bands | Raw basket, item description, merchant SKU, receipt line or store price |
| `availability` | Tracked physical stock coverage and coarse availability/stockout indicators | Untracked stock, services, exact stock at a named shop |
| `procurement_patterns` | Product-category quantities, cost bands, linked order-to-receipt time/fulfillment aggregates | Supplier name, contact, supplier ID or a shop-supplier relationship |
| `operating_cost_bands` | Approved expense category bands/totals at a sufficiently large cohort | Expense notes, receipts, payroll/staff details, rent counterparty |
| `digitisation_metrics` | Derived completeness/adoption indicators, broad profile and period | Device fingerprint, staff performance, individual user activity profile |

These scopes are not automatic legal bases for all personal data. They are a product-level control over shop contribution. For any personal data included for commercial purposes, verify express consent or a specific written-law authority with notice as required by DPA §37. Default to excluding personal data from the market payload even where the shop opts in.

No bundled switch that silently enables all scopes. The user may enable selected scopes and change them later. Keep the merchant's ability to withdraw just as easy as enabling.

## 5. Consent evidence and lifecycle

Persist a backend-authoritative, auditable grant record:

- consent/grant UUID;
- authenticated account and workspace/shop scope (resolved server-side);
- purpose code and each enabled scope code;
- privacy notice version and concise notice digest;
- terms/partner-class version where relevant;
- contribution schema and metric-dictionary version accepted;
- actor ID/role and evidence of authority (without exposing actor identity to partners);
- UTC time, capture method/channel, app version and affirmative action;
- grant status, effective time, withdrawal time and processing state.

Consent must be freely given, informed, specific, unambiguous and provable. No preselected controls, bundled acceptance, silence, inactivity, or continued use as consent. Explain the benefit and consequence of declining without implying the core POS will be limited.

On withdrawal:

1. Immediately stop creating future contribution batches for withdrawn scopes.
2. Mark unsent queued batches ineligible and purge them from the mobile queue.
3. Send an authenticated withdrawal command to the backend; reconcile in-flight batches idempotently.
4. Quarantine any received but unpublished contribution within the documented SLA while it is assessed for deletion/recomputation.
5. Apply the approved policy to previously published aggregate outputs; do not promise impossible recall of irreversibly aggregated copies, and ensure partner agreements address corrections/withdrawal where applicable.
6. Keep only the minimum lawful audit evidence required to prove the request and outcome.

Consent withdrawal does not automatically erase business records needed for POS operation, accounting/legal obligations or the merchant's own backup. The purposes and deletion paths must remain separate.

## 6. Collection notice and policy change

Before the new collection starts, update/version the existing privacy notice, consent screen and terms so they disclose:

- who is controller/processor for each purpose and how to contact the responsible privacy channel;
- categories of data collected and whether each field is mandatory or optional;
- purpose and legal basis for each category;
- recipient classes (NGOs/research bodies, manufacturers/brands, suppliers/distributors, where applicable) and what outputs they can access;
- transformation, aggregation and suppression rules in plain language;
- countries/regions where personal data is stored or accessed and applicable transfer safeguards;
- retention periods/criteria, opt-out, objection, access, correction, deletion and complaint channels;
- consequences of not providing optional details (normally: the merchant can still use POS; contribution coverage is lower).

Do not rely on a general sentence such as “we may use analytics.” Publish a clear data-purpose table linked from the consent view. If material categories, purposes or recipient classes change, assess whether a new notice and fresh consent are required before the changed use.

## 7. Prohibited/default-excluded data for this product

Do not collect for market intelligence:

- customer names, phone numbers, loyalty IDs, credit account names, debt balances attributable to named customers, transaction references or individual purchase histories;
- supplier names, phone numbers, contacts, private notes, tax references or named relationships;
- staff names, IDs, phone numbers, PINs, wages/payroll details or individual performance;
- owner personal name/email/phone, government ID, tax PIN, bank account or M-Pesa/paybill references;
- precise GPS, shop address, stall/building location or device advertising IDs/fingerprints;
- photos, receipts, document images, message contents or free-text notes;
- sensitive personal data (e.g. health, disability, ethnicity, religion, political opinions, biometric, family/children, sexual life/orientation, property details) for the commercial-intelligence profile;
- children's personal data;
- inferred personal traits, individual creditworthiness, household behaviour, or individual customer targeting segments.

If an NGO requires personally identifiable beneficiary or household data for a defined programme, that is a different project and legal relationship. It requires a specific purpose, data-subject notice, lawful basis, access safeguards, data-sharing agreement, retention/exit process and a DPIA where high risk. Child data requires the additional protections in DPA §33. Do not extend the shop contribution model to collect it.

## 8. Registration, DPIA and cross-border gates

- **ODPC registration:** assess whether Nerva acts as controller, processor or both for the actual purposes. Registration Regulations reg.4 generally require registration, subject to reg.13; the below-KES-5m and fewer-than-10-employee exemption does not apply to listed Third Schedule purposes. Do not assume the exemption. Review the current ODPC guidance and register in each required capacity before launch.
- **DPIA:** perform a documented screening. Given longitudinal multi-shop commerce patterns, partner outputs and re-identification risk, plan for a full DPIA before production unless counsel documents why it is not high-risk. Under DPA §31 a high-risk assessment is pre-processing; where the assessment still indicates high risk, consult the Commissioner. The Act sets a 60-day pre-processing submission period for the report.
- **Data sharing agreements:** follow the ODPC Data Sharing Code. Every partner must have purpose, legal basis, scope, permitted output, contract term, retention, deletion/return, security, onward transfer, audit, incident and no-re-identification clauses. Do not transfer raw/pseudonymous ledger rows to a partner.
- **Cross-border:** maintain a current register of data locations, subprocessors, recipient countries and support access. Apply DPA Part VI and current ODPC cross-border guidance before a transfer. Do not claim that every POS record must be hosted in Kenya: the Act's Kenya-localisation rule is for personal data processed for strategic interests of the State (and designated purposes under the General Regulations), while other transfers still need a lawful transfer mechanism and safeguards.
- **Retention:** set purpose-specific TTLs for mobile queue, restricted contribution batches, token mapping, aggregates, logs, backups and partner exports. DPA §39 requires personal data to be retained no longer than reasonably necessary unless an applicable exception applies.

## 9. Controller/processor security and accountability

- Maintain a record of processing activities and a field-to-purpose register.
- Encrypt in transit and at rest; segregate tenant operational records from restricted contribution data.
- Use role-based access on every backend endpoint; default-deny partner and merchant access to contribution ledger.
- Audit admin reads, filters, exports, consent changes, schema releases and deletions. Never log raw payloads, access tokens or direct identifiers in telemetry.
- Keep an incident response and breach assessment process; ensure contracts define notification obligations.
- Use data-quality validation and purpose checks before ingestion; do not use admin UI visibility as authorization.
- Ensure sub-processors and onward recipients are documented and controlled.

## 10. Legal source references (verified 17 November 2026)

- Kenya Data Protection Act, Cap. 411C, revised as at 31 December 2022: https://new.kenyalaw.org/akn/ke/act/2019/24/eng@2022-12-31/source.pdf (notable §§25–32, 33, 36–39, 48–50, 53, 55).
- Data Protection (Registration of Data Controllers and Data Processors) Regulations, 2021: https://www.odpc.go.ke/wp-content/uploads/2024/03/THE-DATA-PROTECTION-REGISTRATION-OF-DATA-CONTROLLERS-AND-DATA-PROCESSORS-REGULATIONS-2021.pdf (regs.4 and 13; Third Schedule).
- ODPC, Data Sharing Code: https://www.odpc.go.ke/wp-content/uploads/2025/03/FINAL-DATA-SHARING-CODE.pdf.
- ODPC, Guidance Notes — Processing for Research Purposes (2025): https://www.odpc.go.ke/wp-content/uploads/2025/11/ODPC-%E2%80%93-GUIDANCE-NOTES-Processing-for-Research-Purpose.pdf.
- ODPC, Guidance Notes for Cross-border Data Transfers (2026): https://odpc.go.ke/wp-content/uploads/2026/09/ODPC-%E2%80%93-Guidance-Notes-for-Cross-border-Data-Transfers.pdf.
- ODPC registration FAQs: https://odpc.go.ke/faqs/.

**This is an engineering specification, not a legal opinion.** Counsel must confirm the live legal position and the exact applicability to Nerva's actual activities, data subjects, partners, hosting and registration status before launch.
