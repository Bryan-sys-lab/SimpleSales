# Kenya Legal Purpose & Collection Matrix — Patches 13–18

**Engineering decision aid, not legal advice.** Qualified Kenyan counsel/privacy lead must validate the actual role, legal basis, notice, registration, DPIA, partner agreement, retention and transfer for each deployment before live collection.

## 1. Principles applied

The Data Protection Act (Cap. 411C) §§25, 28–32, 36–39, 48–50 and 53, ODPC Data Sharing Code and ODPC research/cross-border guidance underpin this matrix.

| Rule | Implementation consequence |
|---|---|
| Lawfulness, fairness, transparency | Map each data purpose and legal basis; explain before personal-data collection |
| Explicit/specified purpose | No general “future insights” bucket; every field needs a documented purpose |
| Adequate, relevant, necessary | Do not collect fields simply because they may be valuable later |
| Accuracy | Controlled taxonomy, provenance, version, correction and stale-state handling |
| Storage limitation | Retention schedule per queue, token mapping, ledger, logs, snapshots and backups |
| Data subject rights | Access, objection, correction/erasure and consent withdrawal workflows |
| Commercial use §37 | For personal data used commercially, express consent or written-law authority plus notice; anonymize where possible |
| DPIA §31 | Pre-processing DPIA for high-risk processing; consult Commissioner if residual high risk as specified by Act |
| Cross-border §§48–50 | Document recipient countries, safeguards and transfer basis; localisation applies to State strategic-interest data/designated purposes, not automatically every POS record |
| Data sharing code | Defined recipients, purpose, agreements, no re-identification, no unauthorized onward use, retention/deletion and audit |

## 2. Purpose-specific matrix

| Purpose | Fields needed | People/data subjects | Default basis/design | Recipient | Exclusions / controls |
|---|---|---|---|---|---|
| Core POS | Product, sale, stock, purchase, finance and account fields required for the POS service | Merchant/business; customers/staff/suppliers where merchant enters their info | Contract/legal obligation as applicable; merchant's own controller responsibilities separately documented | Merchant and authorized service providers/processors | No reuse for commercial intelligence solely because records are stored |
| Owner backup | Business operational records selected by owner | Merchant and any people appearing in records | Separate owner-controlled backup terms/contract and processor instructions | Merchant's authorized account/workspace | Never interpret backup enabled as commercial consent |
| App security/telemetry | Minimal app version, crash/error, service health and fraud signals | Device/account users where identifiable | Document applicable lawful basis and retention | Nerva operational/security staff and necessary processors | No full transaction body, customer contacts or advertising-fingerprint collection |
| Commercial activity | App profile; KeSIC category; optional broad size/channel/county bands | Business; potentially sole trader/proprietor | Separate default-off contribution grant; assess personal-data status and §37 | Nerva controller for defined purpose; partners see approved aggregates only | No business names, contact details, TIN or exact address |
| Product demand/pricing | Product taxonomy, optional verified brand category, aggregated unit/sales/price bands | Merchant businesses, potentially sole proprietors | Separate scope grant / commercial disclosure | Approved manufacturers/brands/researchers only as aggregate snapshot | No SKU, raw basket, exact shop price/volume or merchant identity |
| Availability/inventory | Tracked stock coverage, valid snapshots, availability band | Merchant business | Separate scope grant; derive only for tracked physical goods | Approved aggregate research/brand/supplier products | No precise shop stock balance; no service/fee stockout metric |
| Procurement | Normalized category/unit/order qty/cost band/linked receipt lead-time | Merchant business; supplier as counterparty in source records | Separate scope grant; validate data confidentiality and contractual rights | Approved aggregate supplier/distributor research | Never disclose supplier identity/contact or shop-supplier relationship |
| Expenses | Controlled expense category and aggregated amount bands if truly needed | Merchant / sole trader | Separate optional purpose scope and legal review | Internal aggregate; partner only when specifically licensed and safe | No expense notes, images, payroll/staff detail, named landlord/vendor |
| NGO programme evaluation | Only project-specific indicators necessary for stated project | Potentially individual beneficiaries, children or vulnerable groups | Independent project design, legal basis, notice, DPIA if high-risk, separate agreements | Named programme recipient under explicit scope | Not covered by merchant commercial consent; do not reuse POS customer/staff records |
| Lender/business-record sharing | Named statement/selected records approved by merchant | Merchant and any third parties in statement | Separate named recipient grant, exact scope, expiry and revocation; redact third parties | Named bank/MFI | Not covered by market-intelligence opt-in; no network dataset access |

## 3. Data collection by field class

### Safe to capture as business facts (still treat some as confidential)

- KeSIC business activity code and version;
- operator/sales channel category;
- owner-selected county and broad settlement context;
- business age, employee-count and outlet-count bands;
- product category/GPC code, unit code, product type and validated GTIN where available;
- aggregate sales volumes, price bands, discount/refund patterns and confirmed payment-method mix;
- stock observation coverage for tracked physical goods;
- purchase quantity/cost bands/lead-time only with reliable PO↔receipt linkage;
- workflow completeness and digitisation coverage.

These may still be commercially confidential even if not personal data. Do not automatically publish them; apply contract, consent, cohort/suppression and trade-secret controls.

### Exclude from general market intelligence

- names and contact fields of business owners, customers, suppliers and staff;
- exact shop/supplier identity, SKU and relationship map;
- government identifiers, tax PIN, registration certificates, payment references;
- precise location and device identifiers;
- free text, receipt images, notes, chat or photos;
- sensitive personal data and child data;
- named customer debt/credit histories, individual baskets or household profiling.

### Separate project only

Any collection of identifiable beneficiaries, household-level indicators, health/education/social-support records, child records or other sensitive categories must be designed separately and assessed under the appropriate legal conditions. It is not a logical extension of the general shop profile.

## 4. Registration decision

Registration Regulations reg.4 generally require controllers/processors to register. Regulation 13 provides limited exemptions, including the threshold requiring both annual turnover/revenue below KES 5 million and fewer than 10 employees, with exceptions for Third Schedule processing purposes. ODPC's current FAQs list non-exempt categories. Nerva must not self-declare an exemption without counsel checking its actual purposes/sectors and both tests. The business customers using the app may also have their own controller duties.

## 5. Release checklist

- [ ] Document controller/processor/joint-controller role by processing operation.
- [ ] Map field → purpose → data subject → legal basis → recipients → retention → transfer.
- [ ] Review current privacy policy and publish versioned notice for new data categories and buyer classes.
- [ ] Record granular opt-in and evidence for every enabled contribution scope.
- [ ] Ensure business representative has authority to grant shop contribution.
- [ ] Exclude third-party person data by design.
- [ ] Complete ODPC registration assessment and required registration.
- [ ] Complete DPIA screening and full DPIA/Commissioner consultation where required.
- [ ] Complete partner agreements and onward-transfer controls.
- [ ] Complete data location / subprocessor / cross-border assessment.
- [ ] Test withdrawal, objection, correction, deletion and retention through mobile, backend, ledger and aggregate jobs.
- [ ] Obtain documented legal approval before switching on live contribution.

## 6. Primary official sources

- Kenya Data Protection Act (revised to 31 Dec 2022): https://new.kenyalaw.org/akn/ke/act/2019/24/eng@2022-12-31/source.pdf.
- Registration Regulations: https://www.odpc.go.ke/wp-content/uploads/2024/03/THE-DATA-PROTECTION-REGISTRATION-OF-DATA-CONTROLLERS-AND-DATA-PROCESSORS-REGULATIONS-2021.pdf.
- ODPC registration FAQs: https://odpc.go.ke/faqs/.
- ODPC Data Sharing Code: https://www.odpc.go.ke/wp-content/uploads/2025/03/FINAL-DATA-SHARING-CODE.pdf.
- ODPC 2025 Research Guidance: https://www.odpc.go.ke/wp-content/uploads/2025/11/ODPC-%E2%80%93-GUIDANCE-NOTES-Processing-for-Research-Purpose.pdf.
- ODPC 2026 Cross-border Guidance: https://odpc.go.ke/wp-content/uploads/2026/09/ODPC-%E2%80%93-Guidance-Notes-for-Cross-border-Data-Transfers.pdf.
