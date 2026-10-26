# SimpleSales (Duka POS): Specification Addendum

Companion to the Feature Specification. Covers everything discussed during the audit that the
main specification does not yet specify. **Specification only: no implementation code.**

---

## 1. Coverage check

Credit selling (madeni) is fully specified in section 7 of the main specification: customers,
an append-only credit ledger, limits, repayments, ageing, reminders, receipts, returns to account
and eTIMS handling. All 23 features from the missing-features list, the unit-selector removal and
the tank redesign are also in the main specification. This addendum adds the items below.

### 1.1 Where each discussed item is specified

| Discussed item | Specified in |
| --- | --- |
| Returns, refunds, credit notes | Main 5 |
| Receive stock, purchases, cost tracking | Main 6 |
| Credit sales and customers (madeni) | Main 7 |
| Expenses and till movements | Main 8 |
| Discounts and price overrides | Main 9 |
| Split payments | Main 10 |
| Portable backup and new-phone restore | Main 11 |
| M-Pesa pay-to-Till matching | Main 12 |
| Hold and resume sales | Main 13 |
| Receipt sharing | Main 14 |
| Cash drawer | Main 15 |
| Stocktake | Main 16 |
| Packs and cartons | Main 17 |
| Suppliers and reordering | Main 18 |
| Barcode labels | Main 19 |
| Sync Center | Main 20 |
| Expiry and batches | Main 21 |
| Multi-device sync | Main 22 |
| Granular permissions | Main 23 |
| Notifications | Main 24 |
| Swahili | Main 25 |
| Price and cost history, analytics, dashboard layout, chart fixes | Main 26 |
| Z and X reports | Main 27 |
| Unit selector removal, tank taps with big and small cups | Main 29 |
| 16 prerequisite defects | Main 3 |
| Shop verification and cloud linking | Addendum 3 |
| eTIMS enablement, device registration, buyer details | Addendum 4 |
| Printing subsystem | Addendum 5 |
| Scanning subsystem | Addendum 6 |
| In-app updates and safe rollback | Addendum 7 |
| Authentication and PIN hardening | Addendum 8 |
| Support and feedback | Addendum 9 |
| Import, export and Google Sheets | Addendum 10 |
| Transactions and Reports upgrades | Addendum 11 |
| Audit log and multi-shop portfolio | Addendum 12 |
| UI hardening and visual system | Addendum 13 |
| Data lifecycle (account deletion, data export, retention) | Addendum 14 |
| All remaining audit defects | Addendum 2 (defect register) |

### 1.2 Deliberately not specified

Loyalty points, wholesale price tiers, customer-facing displays and card terminals were mentioned
only as possible ideas and were not discussed in depth. They can be specified later.

### 1.3 Implementation delivery order

The specification remains the source of acceptance criteria; the companion handover is the source
of implementation status. To prevent partially shipped money and sync behavior, implementation is
strictly serialized in the following order:

1. **Partial features first:** eTIMS buyer details; split payments; portable backup/restore
   completion; M-Pesa till matching; receipt sharing; supplier reordering; Sync Center;
   multi-device sync; analytics/dashboard; and Z/X reports.
2. **Remaining features second:** expenses/till movements; discounts/price overrides; hold/resume;
   cash drawer; stocktake; packs/cartons; barcode labels; expiry/batches; granular permissions;
   notifications; and Swahili/localization hardening.

Each numbered item is a release-sized TODO, not complete when only one layer works. Completion
requires the local schema/migration, app journey, backend contract, offline/online behavior,
tenant/role boundaries, regression tests, and the serial full-suite/compose-health gate documented
in `HANDOVER-REMAINING.md`. The next item must not begin until the previous item has recorded that
evidence. This ordering is a delivery control and does not change any feature's acceptance rules.

**Execution update (2026-10-24):** P-01 eTIMS buyer snapshots, P-02 split payments, P-03
portable backup/restore, and P-04 M-Pesa till matching are complete in the companion handover.
P-02 includes deterministic largest-remainder refund allocation to the original tenders and
offline sync of that allocation; P-03 includes failed-media rollback and replacement-phone
receipt-sequence acceptance; P-04 includes durable offline claim retry/dispute handling, atomic
tenant-scoped claims, live arrivals, and stale-payment expiry; P-05 receipt sharing is complete
with local PDF/text fallback, masked recipient history, and expiring/revocable public links. P-06
supplier reordering is complete with durable offline drafts, grouped velocity/lead-time/pack
suggestions, purchase-order receiving, and tenant-scoped sync. P-07 Sync Center is complete:
the role-gated screen covers eTIMS pending/issued/rejected status (including credit-note labels),
M-Pesa verification, unclaimed incoming payments, pending prompts and offline claims, backup and
storage status, cloud link plus identity verification, printer status, operational sync queues and
remote mirrors. eTIMS retry and conflict-review actions are safe and live refresh is wired through
the shared live channel; tax records and queued sales are never deleted from this surface. The
serial full-suite and Compose-health evidence is recorded in the companion handover.
P-08 multi-device sync is complete: all staged streams use bounded queues/pages, tenant-scoped
idempotency, and advancing cursors; multi-till sales and stock movements use deterministic product
ordering; and stock-race losers are retained in a server conflict ledger for idempotent manager or
owner resolution without deleting local receipts. The completion evidence is recorded in the
handover.

**Execution update (2026-10-25):** R-11 localization hardening is in progress. The app now
ships the `sw` locale for the shared shell/actions/errors, records the approved terminology in
`duka_pos_app/lib/l10n/GLOSSARY.md`, validates locale keys and ICU placeholders in CI, and uses
the active locale for fixed receipt labels. Remaining R-11 acceptance work is the full feature
copy sweep, complete Swahili catalogue, and pseudo-locale overflow matrix.

**Expansion queue:** The Version 14 Master Codex plan supplied for integration is tracked as
E-01–E-14 in `EXPANSION-IMPLEMENTATION-TODO.md`. It is deliberately downstream of R-11 and
follows the same serial, end-to-end completion gate; the addendum remains the acceptance
specification and the handover remains the implementation status source.
P-09 work has begun with VAT reconciliation from immutable line snapshots and a tenant/role-scoped
remote sale-detail route used by product drill-down. KRA activation remains disabled; this is an
internal reconciliation view, not a filing.
P-09 is complete: the analytics load includes bounded expiry attention and SQL slow-mover
aggregation, local product imports/restores append price/cost history without duplicates, and
default period sales exports do not silently truncate. A 100,000-sale aggregate stayed within the
500 ms performance budget; the full serial app suite passed 1,600/1,600.

P-10 is complete: shift close writes a transactional, gapless Z number and immutable snapshot;
the live X preview does not consume a number; closed snapshots include cash, payment, VAT,
taxable and eTIMS outcomes; reports expose the inactive-KRA comparison boundary; and closed Z
reports can be reprinted or exported to a local PDF. Printer layout regressions cover both
58-mm and 80-mm output. The full serial app suite passed 1,602/1,602.

Tax reporting boundary (2026-10-25): KRA/eTIMS is explicitly not activated in this deployment.
Sales retain VAT and taxable snapshots for local reconciliation and offline reporting. When
activation is approved, the server-side Risiti Platform API adapter (PesaStack Limited) is the
configured multi-tenant provider; its API key never reaches the app, invoice requests use stable
tenant/receipt idempotency keys, and the asynchronous submission state is not treated as issued
until Risiti reports a terminal successful submission. This follows KRA's eTIMS requirement for
eTIMS-generated tax invoices and Risiti's documented queued/completed/action-required lifecycle;
it does not claim current KRA certification or enable filing. The deployment gate is enforced
on both shop settings and system-admin settings, so neither path can turn KRA on while the
release flag remains false.

Notification boundary (2026-10-25): notification delivery remains counts-only and
tenant-scoped. Platform announcements are a separate system-admin capability: they are
published and cleared only through the system-admin boundary, audit logged, and exposed through
the update manifest without tenant or customer data. The till shows the message on its next
online check and connected tills also receive it over the existing live channel. It keeps the
existing update flow for release announcements; it does not treat an announcement as a KRA,
M-Pesa, or shop notification.

## 2. Extended defect register

The main specification lists 16 prerequisite defects (P0-1 to P0-16). The audit found more. This
register lists the rest, each with the outcome required. Items marked with a section reference are
delivered by that section; the others are small independent fixes for Phase 0 or Phase 1. Every fix
needs a regression test that fails before the fix.

| ID | Area | Defect | Required outcome |
| --- | --- | --- | --- |
| X-1 | Sell | After a sale the confirmation message reads the total after the cart was cleared, showing zero | Capture the total before clearing; message shows the sold total and change |
| X-2 | Sell | Offline M-Pesa sale does not rebuild reservations, deduct variant stock, or queue the eTIMS receipt | One shared finalisation path for every payment type (delivered by Main 4.1 and 4.2) |
| X-3 | Sell | The plus button on a cart line ignores stock | Availability check for every line type (variant, portion, cup) with a clear message |
| X-4 | Sell | The search filter stays applied after a session change while the box looks empty | Reset query on session change; search also matches barcode and code |
| X-5 | Sell | Text controllers are disposed while a dialog is still animating out | Dialog widgets own and dispose their controllers |
| X-6 | Sell | Staff attribution differs between payment paths (owner recorded as none on some) | One rule: record the current staff id on every path |
| X-7 | Sell | A scan arriving while another is processing is dropped | Queue scans (Addendum 6) |
| X-8 | Sell | Hardware scanner stops working after the search box loses focus | Re-request scanner focus (Addendum 6) |
| X-9 | Sell | Product tiles overflow when a photo is present; fractional stock shows rounded | Addendum 13 |
| X-10 | Inventory | Product save is not atomic; a retry can create a duplicate | Single transaction (Main 29.2) |
| X-11 | Inventory | A product marked as having variants can be saved with none and disappears from the till | Block the save |
| X-12 | Inventory | Every product must carry a size in millilitres, default 750 | Optional size (Main 29.2) |
| X-13 | Inventory | Stock adjust accepts whole numbers only, can crash when the staff name is missing, and matches errors by text | Decimal quantities, safe fallback name, typed error results |
| X-14 | Inventory | Variant stock adjustments are not audited or recorded in the ledger | Main 4.1 |
| X-15 | Backend | A wrong staff PIN can return 401 and be treated as an expired shop session | Credential checks bypass the refresh and logout path |
| X-16 | Backend | The tenant header is trusted from the client | Server validates it against the token (backend change) |
| X-17 | Backend | Shop creation links to the backend fire-and-forget with no retry | Addendum 3 |
| X-18 | Printer | Double-width shop name wraps across two lines | Pad to the column budget divided by the scale |
| X-19 | Printer | The portion label is truncated before the name | Truncate the name, then append the label |
| X-20 | Printer | Shot and cup lines carry no size on the receipt | Append the millilitres |
| X-21 | Printer | Wrong command used to select the code page | Use the code page command; test on two printers |
| X-22 | Printer | Native layer: replies from a worker thread, no chunking, unenforced connect timeout, secure-only socket, no discovery cancel, no reconnect-once | Addendum 5 |
| X-23 | Updates | Native signature check methods are missing and the pinned certificate is a placeholder | Addendum 7 |
| X-24 | Database | No downgrade handling, so a rollback build can fail to open the database | Addendum 7 |
| X-25 | Database | The cross-shop tour swaps the single global database handle | Addendum 12 |
| X-26 | Audit | Audit retention cap is shared with sale rows | Addendum 12 |
| X-27 | Media | Photos not namespaced by shop; deletion leaves avatar and photos; photo widget flickers and uses a misleading placeholder | Addendum 13 and 14 |
| X-28 | Workspaces | Registry updates race; shop rename not reflected in the switcher | Serialise registry writes; update on rename |
| X-29 | Sheets | Removed barcodes leave old rows; partial appends duplicate rows on retry | Addendum 10 |
| X-30 | Import | Barcodes can attach to an inactive duplicate; problem rows are resolved before the write succeeds | Addendum 10 |
| X-31 | Import | Fixing an import problem drops barcode, size, half and quarter prices and has no error handling | Addendum 10 |
| X-32 | Backup | Export marks a backup done when the share sheet is dismissed; the sales export is capped at 10,000 rows silently | Main 11; Addendum 10 |
| X-33 | Backup | Automatic backup is skipped when the network step fails; rotation can delete manual exports; the timer dies with the process | Local copy first; separate file prefixes; background scheduler |
| X-34 | Transactions | Cashier scope uses the display name and falls open when it is missing; 14-day cutoff uses UTC against local times | Addendum 11 |
| X-35 | Reports | Loads all history; shift export is not bounded to the shift; no error handling; lifetime staff totals | Addendum 11 |
| X-36 | Shift | Expected cash captured when the close sheet opens; shifts without a staff id show shop-wide gross | Compute in the close transaction; never fall back to shop-wide |
| X-37 | Analytics | Range switching can show an older response under the newer label (also Portfolio) | Request counter guard |
| X-38 | Portfolio | Money units from the backend are assumed to be minor units | Confirm the contract; contract test |
| X-39 | Auth | PIN reset does not clear lockout; migrated owners without an email cannot reset or delete the remote account | Addendum 8 |
| X-40 | Auth | Username lockout can be bypassed by changing letter case | Normalise the lockout key |
| X-41 | Auth | Idle timer ignores keyboard and scanner activity | Addendum 8 |
| X-42 | Support | Ticket list does not update; tapping a row resolves it; nothing reaches a backend | Addendum 9 |
| X-43 | UI | Dashboard padding and KPI wrapping; chart label overlap, invisible zero days, donut overlap, spoken total unformatted | Main 26 |
| X-44 | UI | Identity code sheet shows a field label as the error; PIN reset dialog can stay stuck on Sending | Proper messages; always clear busy state |
| X-45 | UI | Database error screen has no retry or log sharing | Addendum 13 |
| X-46 | Housekeeping | Signing keys and a stray test file in the source archive | Remove from the repository, rotate keys if shared, ignore in version control |

## 3. Shop verification and cloud linking

### 3.1 Goal and users

The app must sell fully offline, while cloud features (issuing eTIMS receipts, backup upload, sync,
M-Pesa requests and Till matching, support tickets, receipt links, portfolio view) require the shop
to be verified once with the backend. This section defines what verification is, the states a shop
moves through, what works in each state, and how the app recovers without ever losing queued work.
Used by the owner.

### 3.2 States

| State | Meaning | Still works | Blocked | Banner and action |
| --- | --- | --- | --- | --- |
| Not linked | Shop created locally; no backend link | All selling, stock, reports, printing, local backups | All cloud features | Verify your shop to unlock eTIMS and cloud features: Verify now |
| Linking | Link request in progress or retrying | Same as above | Cloud features | Connecting, will retry automatically |
| Linked, email not confirmed | Tenant exists but email unconfirmed | Local features; queues accumulate | Issuing, sync, M-Pesa | Confirm your email: Enter code |
| Verified | Email confirmed and tokens valid | Everything | Nothing | none |
| Offline | Verified but no connection | Everything locally; queues accumulate | Network actions wait | Offline: will send when connected |
| Needs sign-in again | Server definitively rejected the session | Local features; queues keep waiting, never rejected | Cloud features | Sign in again to resume: Verify again |

### 3.3 Data model

Table `cloud_link` (one row per shop): tenant_id, workspace_key, linked_at, verified_at,
last_check_at, owner_email_verified (yes or no), status (one of the states above), last_error_code,
environment (production or sandbox).

Table `link_attempts`: id, at, result, error_code. Used for diagnostics and the Sync Center.

Tokens stay in secure storage and are never part of backups. The existing workspace registry's
tenant id is migrated into this table.

### 3.4 Screens and flows

1. **After creating a shop.** A card on the dashboard, not a blocking screen: Verify your email to
   unlock eTIMS and cloud features. Selling is never blocked.
2. **Verify flow.** Enter the owner email twice (typo prevention), request a code, enter the
   6-digit code, success message listing what is now unlocked. If offline, the request is saved as
   pending and retried automatically at app start and when connectivity returns, with backoff.
3. **Settings, Cloud.** Status card with the state word, last verified time, environment, and
   actions Verify now, Change email (needs the code sent to the old email, or the owner PIN if the
   old email is unknown), Sign out of cloud.
4. **Environment switch** (owner only, hidden behind a confirmation): production or sandbox, for
   testing with KRA's test environment, with a persistent visible marker when not on production.
5. **Restore on a new phone.** After a restore (Main 11) the state is Needs sign-in again with an
   explanatory message.
6. **Gating.** Each cloud screen shows a short explanation and a Verify action instead of failing.
   The eTIMS switch can be turned on only when Verified; if verification is later lost, queued
   receipts wait and are never marked rejected.

### 3.5 Business rules

1. Verification never blocks selling, printing or stock work.
2. Only a definitive rejection from the identity provider moves the shop to Needs sign-in again.
   Network errors, timeouts and server errors never clear tokens.
3. Token refresh is single-flight so concurrent requests cannot invalidate each other.
4. Codes expire after 10 minutes, allow 5 attempts, and at most 3 codes per hour are issued.
5. Email addresses are lower-cased and trimmed; a code sent to a mistyped address is a normal
   failure the owner can correct.
6. Release builds refuse to start against placeholder endpoints.
7. Link status is shown consistently in the header, Settings and the Sync Center.

### 3.6 Backend

Request verification code; confirm code; create or return the tenant idempotently by workspace key;
status; environment configuration; structured error codes for every failure so the app can show a
specific message.

### 3.7 Tests

- State machine: every transition, including offline during each step and kill-and-relaunch.
- Offline refresh keeps the session; a definitive rejection moves to Needs sign-in again;
  concurrent refresh produces one network call.
- Gating matrix: every cloud feature in every state.
- Queues (eTIMS, sync, payments) survive an unverified period and are processed after
  verification, not rejected.
- Email typo flow; rate limits; code expiry; environment switch marker.
- Widget tests for banners and cards at 320 dp and text scale 2.0; contract tests with a fake
  identity provider.

### 3.8 Acceptance criteria

A new owner creates a shop with no internet, sells for two days, then connects; the link and email
verification complete automatically after the owner enters the code, and all queued eTIMS receipts
are issued in order without any being rejected.

## 4. eTIMS enablement, device registration and buyer details

**Provider implementation note (2026-10-24):** the server tax-provider seam now
targets Risiti by PesaStack Limited through its Platform API. KRA/eTIMS remains
explicitly **not activated** in this version: the local app continues recording
sales and VAT reports, but device registration and receipt submission return a
clear not-activated response until merchant onboarding, approval, and production
configuration are complete. Risiti API keys remain server-side only.

**Tax boundary verification (2026-10-25):** the deployment status now reflects the
single server activation gate truthfully, while the app clears any stale local eTIMS
flag and continues to present local VAT/taxable reporting as reconciliation only. The
current deployment keeps `TAX_REPORTING_ACTIVATED=false`; no shop or system-admin
settings path can enable KRA filing. Risiti's documented asynchronous lifecycle and
stable idempotency contract remain the planned production path, subject to merchant
onboarding, KRA approval/certification, and live configuration.

### 4.1 Goal and users

Make issuing KRA eTIMS receipts from the till reliable and understandable: a guided setup, the
right identity on every document, buyer details when needed, clear statuses, and a safe way to test
before going live. The owner sets it up; managers monitor it; cashiers capture buyer details.

### 4.2 Data model

| Where | Field | Notes |
| --- | --- | --- |
| Shop settings | etims_enabled, tin, environment (sandbox or production), branch id | enabled only when the shop is verified (Addendum 3) |
| Shop settings | device id, registration status (none, pending, registered, failed), registered_at, last registration error | the device id is allocated by the backend, never derived locally |
| sales | buyer_tin, buyer_name (nullable) | captured at checkout |
| sales | etims_status, error_code, attempts, issued_at | status model in 4.4 |
| customers | tin | from main section 7 |
| products (conditional) | item classification code, item code, registration status | add only if the current KRA specification requires item registration; see open questions |

### 4.3 Screens and flows

Settings, Tax and eTIMS is a checklist with six steps and a status for each.

1. **VAT and TIN.** Owner enters the TIN; the field checks the expected shape (letter, nine
   digits, letter) as a warning, and the backend confirms where it can.
2. **Verify shop** (Addendum 3). Blocked with an explanation until done.
3. **Register device.** One button; shows progress and either success or a plain-language failure
   (not verified, TIN rejected by KRA, KRA unreachable, already registered to another device).
4. **Tax classes.** A tool to assign a tax class to a category or product in bulk, with a list of
   products flagged Check tax class. The app suggests no class; the owner decides.
5. **Test receipt.** In sandbox, issues a sample sale and shows KRA's response and QR.
6. **Go live.** Switches to production and turns eTIMS on; a persistent marker shows whenever the
   environment is sandbox.

**Checkout.** The payment sheet has an optional row Buyer PIN. Selecting a customer fills it from
their record. A shop setting can make it mandatory for every sale or above a configured amount.
Once a receipt is issued its buyer details cannot change; the fix is a credit note and a new sale
(the app explains this).

**Printing.** A receipt printed before issuance shows eTIMS PENDING; after issuance it shows the
KRA number and the QR from KRA's payload. Every reprint is marked COPY. (Layout in Addendum 5.)

### 4.4 Status model

Queued, then Sending, then either Issued or Rejected; transient failures return to Queued with
backoff and show as Retrying. Rejected means KRA or the backend refused the document for a reason
that retrying cannot fix; it stays visible in the Sync Center until the owner resolves it.

### 4.5 Business rules

1. Receipts are issued oldest first, except that the sale just completed is attempted first with a
   short time limit so the customer's receipt can show its number if the network is good.
2. A document is never deleted; reversing one needs a credit note.
3. The tax class and rate are snapshotted on each line at sale time (main section 4.3).
4. Registration is once per device; reinstalling restores the registration from the backend, not
   by creating a new one.
5. Every backend failure is mapped to a message in the app language by error code.
6. The local receipt number series is independent of the KRA receipt number.

### 4.6 Backend

Device registration (existing, hardened); receipt issuing (main section 3); credit notes (main
section 5); optional item registration; environment support for sandbox; structured error codes.

### 4.7 Tests

- Setup checklist: each step in each state, including going back after a failure.
- TIN shape table (valid, too short, wrong letters, spaces, lower case).
- Registration failures each map to the right message.
- Buyer PIN capture appears in the payload; mandatory rules at the threshold amount.
- Offline sale then online issue in order; print variants (pending, issued, copy) as goldens.
- Contract tests with a fake KRA for success, validation rejection, server error and timeout.
- Sandbox marker visible on every screen header while active.

### 4.8 Acceptance criteria

An owner completes the checklist in sandbox, issues a test receipt with a KRA number and working
QR, switches to production, and the first real sale prints a receipt that carries the same kind of
number and QR.

## 5. Printing subsystem

### 5.1 Goal and users

A dependable printing layer: easy pairing, stable connection, queued jobs that survive restarts,
layouts that fit the paper, and clear help when something is wrong. Owners and managers configure;
everyone prints.

### 5.2 Data model

Table `printers`: id, name, address, transport (Bluetooth now; USB and network later), paper width
(58 or 80 mm), code page, capabilities (native barcode, native QR, drawer), column override, last
connected, last error.

Table `print_jobs`: id, uuid, created_at, document_type (receipt, credit note, Z report, X report,
label, test), document_id, printer_id, status (queued, printing, done, failed), attempts,
last_error. Retained 30 days.

Settings: default printer, auto-print after sale (by payment type), copies, wrap long names to a
second line (on by default for 80 mm).

### 5.3 Screens and flows

- **Settings, Printer.** Status card (Connected, Disconnected, Bluetooth off, Permission needed),
  Find printer, paper width, Test print, auto-print options, Troubleshooter.
- **Find printer.** Lists paired devices that look like printers first, with a Show all toggle; a
  Pair new device path; progress and a clear result. A short explanation precedes the system
  permission prompt.
- **Test print.** Prints a self-check: width ruler, character set sample, double-width line, QR,
  barcode, cut. The result is stored as the printer's capability profile.
- **Troubleshooter.** Five checks in order (Bluetooth on, permission granted, printer on and in
  range, paired, paper loaded) with a fix action for each.
- **Sell.** Printing happens in the background with a small status chip; Print again is always
  available; a failed print never blocks or undoes a sale and shows Receipt not printed with Retry.
- **Print history.** Last 50 jobs with Reprint.

### 5.4 Business rules

1. One connection manager owns the printer. Jobs run one at a time in order.
2. Connection tries the secure channel first, then the alternative channels many low-cost printers
   need, after cancelling any Bluetooth discovery, with a real time limit.
3. If a write fails because the link went stale, reconnect once and resend before reporting failure.
4. Data is sent in small chunks with a short pause so low-memory printers do not drop bytes.
5. Results are returned to the app on the main thread.
6. The link is closed after a period of inactivity and reopened on demand, to save battery.
7. Unsupported features degrade: no native QR means the verification text is printed; no native
   barcode means an image is used.
8. Layout: a double-width line fits within half the columns; long names are truncated or wrapped
   without losing the portion or size label; the correct code page command is sent at the start.
9. Jobs persist across app restarts; a job interrupted mid-print is marked failed and can be
   reprinted.

### 5.5 Tests

- Byte-level tests for each command (initialise, code page, size, alignment, QR, barcode, cut,
  drawer).
- Layout goldens at 32 and 48 columns with long names, double-width titles, shot and cup lines,
  discounts, split payments, credit notes and QR.
- Fake transport tests: chunking, partial write, mid-job disconnect, reconnect-once, queue
  ordering with concurrent jobs, replies on the main thread.
- Permission flows; Bluetooth off; app sent to the background during a print.
- Manual matrix on three printer models, including a 60-line receipt and battery impact.

### 5.6 Acceptance criteria

After the printer is switched off and on, the next receipt prints without the cashier doing
anything; a printer that is off shows a clear message and the sale still completes; the shop name,
long product names and half-portion labels all print correctly.

## 6. Scanning subsystem

### 6.1 Goal and users

One scanning service for the camera and for hardware scanners (USB or Bluetooth acting as a
keyboard) that feeds the till, receiving, stocktake, labels and the product editor. It never drops
a scan, tells the user what happened, and handles unknown barcodes gracefully. Used by everyone.

### 6.2 Data model

Settings: wedge scanner timing (maximum gap between keys, default 100 ms), accepted terminators
(Enter and Tab), minimum and maximum length, prefix and suffix to strip, sound, vibration, screen
flash, camera continuous mode, unknown-barcode behaviour. An optional diagnostic ring buffer
`scan_log` keeps the last 200 scans for 7 days (time, source, length, result).

### 6.3 Screens and flows

**Pipeline.** Source (camera or wedge) then normalise, then resolve to a product, variant or pack,
then hand to the current screen: the till adds a line; receiving adds or increments a line;
stocktake counts; labels select; the product editor fills the barcode field.

**Queue.** Scans go into a first-in first-out queue and are processed one at a time; a short
counter shows when several are waiting. The same code scanned twice by a hardware scanner is two
scans (quantity two). The camera ignores the same code for 300 ms to avoid double reads of one
label.

**Unknown barcode sheet.** Barcode not found, with Create product (barcode prefilled), Attach to
an existing product (search), and Ignore.

**Camera scanning.** Continuous mode keeps the camera open with a running list and count; torch;
tap to focus; a frame guide; a plain permission flow with a link to settings; if the camera is
unavailable the screen offers manual entry. The camera starts exactly once and pauses and resumes
with the app lifecycle.

**Hardware scanner.** Keys are captured whichever field was last focused, except while the user is
typing in a text field. A fast burst ending in a terminator inside the search box is treated as a
scan, not as typing, so scanning works even with the search box focused. Focus is restored when
returning from dialogs and sheets. A small Scanner ready indicator opens the troubleshooter.

**Feedback.** Success beep and light vibration, a different buzz for not found or out of stock, a
brief flash, and a screen-reader announcement such as Added Tusker 500 ml, quantity 2.

**Settings, Scanner.** A test area that shows raw characters and timings with a suggested gap
value, and presets for common scanners.

### 6.4 Business rules

1. Normalisation (case, spaces, hyphens) is the same on every write and every lookup.
2. Check digits are validated softly: a wrong check digit warns but is accepted if the code exists
   in the catalogue.
3. Codes shorter than six characters are accepted only if they already exist (short internal
   codes).
4. Resolution uses an indexed lookup that covers product, variant and pack barcodes together.
5. No barcode data leaves the device.

### 6.5 Tests

- Ten scans in one second are all processed in order; jitter up to 80 ms between keys; both
  terminators.
- Search-box burst detection: fast scan is recognised, normal human typing is never mistaken for a
  scan.
- Focus lost and regained after dialogs, sheets and the search box.
- Unknown barcode flows; short codes; wrong check digit that exists.
- Camera: permission denied, granted and revoked; backgrounding; double-start protection;
  continuous mode count.
- Per-screen handlers (till, receiving, stocktake, labels, editor); feedback and announcements;
  lookup under 20 ms with 10,000 barcodes.

### 6.6 Acceptance criteria

A cashier scans eight items in a few seconds with a hardware scanner while the search box is
focused; all eight appear in the cart, with duplicates as quantities, and an unknown item opens the
create-or-attach sheet without losing the others.

## 7. In-app updates and safe rollback

### 7.1 Goal and users

Deliver updates to shops that install outside an app store, verify them properly, never break the
database, and allow a safe way back if an update goes wrong. The owner updates; managers can see
status.

### 7.2 Data model

Update manifest (from the server): version, build number, release notes (per language), download
address, SHA-256 of the file, signing certificate fingerprint, the lowest and highest database
schema the build can open, mandatory flag (when the backend would no longer accept the old app),
rollout percentage, channel (stable or beta).

On the device (settings): channel, last check time, available version, download state (none,
downloading, ready, failed), consent time, install source (store or sideload).

### 7.3 Screens and flows

- **Install source.** If the app came from a store, it never installs itself; it shows a link to
  the store listing. The self-update path exists only for sideloaded installs.
- **Checking.** At launch (at most every 6 hours) and from Settings, About, Check now.
- **Update card.** Version, release notes in the app language, size, Update now and Remind me
  later. Downloading shows progress and resumes after interruptions.
- **Verification.** Before the install prompt appears, the downloaded file is checked natively:
  its hash matches the manifest, its signing certificate matches the certificate pinned in the app
  (two may be pinned to allow rotation), the package name is correct and the version is newer. A
  failed check deletes the file and shows a clear message.
- **Install.** The operating system's installer prompt appears; the app never installs silently.
  Optional automatic download only on Wi-Fi, when idle, and only if the owner has switched it on.
- **Mandatory updates.** When the backend can no longer accept the installed version, a clear
  message blocks only the cloud features. Selling continues locally.
- **After install.** Migration progress; if migration fails, a recovery screen explains the
  choices.
- **Rollback (owner).** Keeps the previous build's file. Rollback is offered only when the
  previous build can open the current database (its highest supported schema is not lower than the
  current one). If it cannot, the app offers Restore the pre-update backup, then roll back, with a
  plain warning and counts of what would be lost.

### 7.4 Business rules

1. A pre-update local backup is mandatory whenever the new build changes the database schema.
2. The update path can never install an older version.
3. Files are downloaded over a secure connection to private storage and removed after install.
4. Consent is explicit and recorded.
5. The manifest's schema range is checked before downloading, so an incompatible rollback is
   refused up front.
6. Update events carry no personal data.

### 7.5 Tests

- Manifest parsing: missing fields, unknown channel, newer manifest version.
- Hash mismatch, certificate mismatch, wrong package name, downgrade attempt (all refused).
- Resume after network loss; low storage; consent and automatic-download rules; store versus
  sideload detection.
- Rollback allowed and refused by schema range; pre-update backup created; migration failure
  screen.
- Instrumented tests with test builds signed by different keys; manual check on Android 8 to 14
  including the unknown-sources permission flow.

### 7.6 Acceptance criteria

An update that changes the schema is downloaded, verified, preceded by an automatic backup,
installed with the owner's consent, and a rollback is correctly allowed or refused with an
explanation.

## 8. Authentication and PIN hardening

### 8.1 Goal and users

Stronger PIN and session security that does not slow the counter, with consistent lockouts and
proper recovery. Applies to the owner, managers and cashiers.

### 8.2 Data model

- **Versioned PIN hashes.** Each PIN hash carries a version so stronger methods can be introduced
  and old hashes upgraded silently at the next successful sign-in.
- **Device secret.** A random secret kept in the platform's secure storage is mixed into PIN
  hashing, so a copied database file alone is not enough to guess PINs offline. The secret is
  included in encrypted backups (protected by the backup passphrase) so a restore on another phone
  still works.
- Table `auth_events`: id, at, actor reference, type (sign-in ok, sign-in failed, lockout, PIN
  changed, PIN reset, approval ok, approval failed), device. Retained 90 days and shown in the
  Activity screen.
- Settings: required PIN length per role (4 or 6 digits), idle timeout per role.

### 8.3 Screens and flows

- **PIN policy.** The owner can require 6 digits for owner and manager accounts. Weak PINs (all
  the same digit, simple sequences) are refused. A change takes effect at the next sign-in with a
  guided re-set.
- **Change my PIN.** Profile, Change PIN: current PIN, new PIN twice. Available to every role,
  including the owner while signed in.
- **Owner PIN reset by email.** After a successful reset, all lockouts are cleared. Owners
  migrated without an email are asked once, while signed in with their PIN, to add and verify one.
- **Lockouts.** Counted per normalised account name (trimmed, lower case) plus a till-wide
  throttle; the message shows the real remaining time; state survives restarts; success clears it.
  A manager can unlock a cashier, which is audited. The owner sees failed attempts in Activity.
- **Cached credentials** used for offline sign-in are cleared on PIN change, reset, deactivation
  and deletion.
- **Idle timeout.** Any touch, key press or scanner input resets the timer. A warning appears 15
  seconds before sign-out with Stay signed in. If the cart is not empty at timeout it is saved as
  a held sale (main section 13) rather than lost.
- **Approval sheet.** The manager PIN entry has its own attempt limit and audit.

### 8.4 Business rules

1. Hashing stays salted and slow, and is combined with the device secret.
2. No PIN or hash appears in logs or telemetry.
3. An inactive or removed account can never sign in by any route.
4. Failed attempts against a non-existent account behave the same as a wrong PIN, so account names
   cannot be discovered.

### 8.5 Tests

- Old hashes verify and upgrade; the device secret survives a backup and restore.
- Lockout key normalisation (case and spaces); exponential windows with a fake clock; persistence
  across restart.
- PIN policy rejects weak PINs; change-PIN flows; reset clears lockouts; cache cleared on every
  trigger.
- Idle timer reset by touch, key and scanner events; warning dialog; cart saved as held on
  timeout.
- Brute-force simulation shows the attempt rate stays within the intended limits.
- Widget and accessibility tests for the PIN pad at 320 dp and text scale 2.0.

### 8.6 Acceptance criteria

Changing the letter case of a username does not give extra attempts; resetting the owner PIN also
lifts the lockout; a scanner-only cashier is not signed out mid-sale; and a restored backup on a
new phone still accepts the existing PINs.

## 9. Support and feedback

### 9.1 Goal and users

Let staff report problems, ask questions and request features from inside the app, attach safe
diagnostics, and follow the conversation, with everything working offline. All roles can file;
managers and the owner see all of the shop's items; cashiers see their own.

### 9.2 Data model

Table `support_items`:

| Field | Type | Notes |
| --- | --- | --- |
| id, uuid, remote_id | | |
| kind | text | problem, question, feature |
| title, description | text | |
| status | text | open, in_progress, resolved, closed |
| created_by, created_at, updated_at, resolved_at | | |
| sync_state | text | queued, sent, failed |
| context | text | app version, schema, device model, operating system, language |
| diagnostics_attached | integer | |

Table `support_messages`: id, item_id, author (staff or support), body, created_at, remote_id,
read_at. Attachments: one optional screenshot and an optional diagnostics bundle.

### 9.3 Screens and flows

- **Support tab (all roles).** New request: kind chips, title, description, an Attach diagnostics
  switch (on by default) with a preview of exactly what is included, an optional screenshot.
- List grouped by status, with an unread badge when support replies.
- Detail shows the conversation thread; the creator or a manager can mark it resolved after a
  confirmation. Tapping a row opens the detail and never changes its status.
- **Help.** Offline-cached help articles; configurable shortcuts to call or message support; the
  app version and shop code to quote.
- **Offline.** Items are queued with a Will send when online note and sent automatically.

### 9.4 Business rules

1. The diagnostics bundle contains versions, queue counts and the last 50 error events without
   payloads. A scrubbing test proves it contains no names, phone numbers or amounts.
2. Sending is idempotent so retries never create duplicates.
3. The support route is reachable by every role (main section 3).
4. Resolved items close automatically after 30 days.
5. The list updates live when replies arrive.

### 9.5 Backend

Create an item, list items and messages since a cursor, post a message, mark resolved, upload an
attachment, and notify the app through the live channel. Role scoping is enforced on the server.

### 9.6 Tests

- Offline creation then send; retry after failure without duplicates.
- Live list update and thread ordering; unread badge logic.
- Diagnostics scrubbing with sample sensitive strings; attachment size limits.
- Role visibility for all three roles; resolve confirmation.
- Contract tests and widget tests at 320 dp.

### 9.7 Acceptance criteria

A cashier files a problem offline with diagnostics attached; it sends when online; the support
reply appears in the thread with a badge; the cashier cannot see other staff members' items.

## 10. Import, export and Google Sheets

### 10.1 Goal and users

Imports that can be previewed and undone, exports that are complete and correctly scoped, and a
Sheets integration that never skips or duplicate rows. Managers and the owner; exporting needs the
export_data permission.

### 10.2 Data model

Table `import_runs`: id, uuid, started_at, staff_id, file_name, kind (inventory, barcodes,
customers, suppliers), mode (preview or apply), totals (rows, created, updated, skipped,
problems), status.

Table `import_problems` (existing, extended): run_id, row_number, the full original row, severity,
reason code, resolved, resolved_by.

Table `import_changes`: id, run_id, entity, entity_id, before values, after values. Enables Undo.

Table `sheets_sync_state`: stream (inventory, barcodes, sales), cursor, last_success_at,
last_error.

### 10.3 Screens and flows

**Import wizard.**

1. Choose a file (spreadsheet or CSV) or download the template, which is localised, contains
   example rows and carries a version marker.
2. Map columns: headers are detected automatically and can be changed.
3. Preview (dry run): counts of products to create, update and skip, and a problem list with row
   numbers. Duplicates are detected: the same barcode twice in the file, a barcode already used by
   another product, the same name with a different size.
4. Choose update rules: match by barcode first, then name and size; never match an inactive
   product by name unless the manager chooses to reactivate; choose which fields may be
   overwritten (price, cost, category; stock is off by default).
5. Apply in batches inside transactions. A summary shows results; Undo is available for 24 hours.
6. Problem rows open an editor that keeps every field from the original row, including barcode,
   size, half and quarter prices and tax class, and shows a specific error if saving fails.

**Export.** Inventory, customers, sales for a period, VAT summary, expenses, stock movements.

**R-01 implementation note (2026-10-25).** Expenses and till movements are implemented as
offline-first, append/audit-safe records. Cashier payouts above the owner-configured threshold
require manager/owner PIN approval, the approver remains on the expense row, receipt photos are
stored as local relative paths, inactive categories cannot receive new entries, expense reports
cover 7 days, 30 days, or one year with category shares, and shift close shows the cash-sales,
refund, repayment, expense, and movement components. KRA/eTIMS state remains independent of this
local cash-control ledger.

**R-02 implementation note (2026-10-25).** Discounts and price overrides are implemented
offline-first: seeded reasons and owner settings control enablement, role limits and reason
requirements; cashier over-limit changes escalate to manager approval; line and order discounts
are stored with original prices and approver metadata; order shares use deterministic
largest-remainder allocation; VAT, receipts, eTIMS payload data and returns use the discounted
stored values; and below-cost discounts are blocked unless the owner explicitly allows them.

**R-03 implementation note (2026-10-25).** Held sales are durable offline carts with customer,
portion, variant, pack, discount, and price snapshots. Expiry cleanup, a ten-cart limit, current
stock validation, explicit changed-price confirmation, and held-sale warnings during sign-out and
shift close are implemented; resuming a cart returns it to the same offline checkout path.

**R-04 implementation note (2026-10-25).** Cash drawer control is implemented end to end: owner
settings persist enablement, cash-sale opening, connector pin, and safe pulse timings; the ESC/POS
encoder emits the configured pulse; completed cash sales never fail when the printer is unavailable;
and append-only offline drawer events retain sale, staff, approval, and success metadata for sync and
reporting. Manual no-sale openings are permission-gated, require manager approval for cashiers, and
are audited with their reason. Verified by focused receipt/database tests 138/138, affected
analyzer, full serial Flutter suite 1,608/1,608, backend build/lint, and Vitest 120/120.

**R-05 implementation note (2026-10-25).** Stocktake is offline-first and transactional: counts
capture expected stock and variants, support blind entry and recounts, freeze only lines already
counted, and calculate each variance from the line's count time so later sales or deliveries are
not misclassified as shrinkage. Applying a count writes non-zero count movements and updates stock
atomically with manager/owner attribution; uncounted lines are left unchanged and the movement
queue remains compatible with multi-till sync. Verified focused database/migration tests 155/155,
affected analyzer, and full serial Flutter suite 1,610/1,610.

**R-06 implementation note (2026-10-25).** Packs and cartons are integrated with the existing
catalogue, sell, receiving, return, held-sale, and sync paths. A pack may target a product or one of
its variants; barcode resolution returns the correct target; receiving converts pack quantities to
base units and records the derived unit cost; and sales snapshot pack id/quantity for audit and
returns. Verified focused database/migration tests 156/156, affected analyzer, and full serial
Flutter suite 1,611/1,611.

**R-07 implementation note (2026-10-25).** Barcode labels use the internal EAN-13 generator and
the existing printer connector. Assignments are persisted through the barcode ledger; label jobs
are stored locally, printed in bounded chunks, and resumed from the last confirmed chunk after a
printer failure. The encoder is covered at both 58 mm and 80 mm paper budgets. Verified focused
label/database/migration tests 193/193, affected analyzer, and full serial Flutter suite
 1,613/1,613.

**R-08 implementation note (2026-10-25).** Expiry tracking is offline-first and transactional:
received batches retain variant, batch-code, cost, and lifecycle metadata; enabling tracking
backfills existing countable stock as an unknown-expiry batch; sales allocate dated stock
oldest-first for products and variants and refuse expired stock; returns restore their original
batch while expired returns remain write-offs; and manager write-offs update the batch, product or
variant count, and stock ledger atomically. Receipt sync carries the expiry date, batch code, and
variant identity so another till can reproduce the same batch boundary. Analytics separates
expiring and expired products so owners can review write-offs. Measured/tank products remain
outside expiry tracking for v1.
Focused expiry/variant/analytics tests pass 70/70; the affected analyzer and full serial Flutter
suite pass 1,615/1,615 with the runner terminating cleanly.
Spreadsheet or CSV; date range; no hidden row limit (streamed or paged); shift exports are bounded
to that shift and staff. Files are clearly labelled Not encrypted.

**Google Sheets.** Link an account, choose or create a spreadsheet, switch streams on or off, Sync
now, and see the last success. Sales are appended oldest first in batches; progress is saved after
each successful batch and each row carries its receipt number so a retry cannot duplicate it.
Inventory writes clear stale rows; the barcode sheet clears its tail when barcodes are removed.
The sheet is a one-way mirror unless the owner explicitly runs Import from sheet. Unlinking
revokes access.

### 10.4 Business rules

1. Stock quantities from an import are recorded as ledger movements with reason import, never
   silent overwrites.
2. A problem row is marked resolved only after its write succeeds, and is never dropped.
3. Importing the same file twice makes no further changes.
4. Limits: warning above 5,000 rows, hard limit 20,000 rows per run.
5. Numbers with thousands separators, spreadsheet dates and byte-order marks are handled; barcodes
   and phone numbers are normalised on the way in.

### 10.5 Tests

- Dry run results equal apply results; duplicate and inactive-match rules; the problem editor
  preserves all fields; Undo restores previous values.
- Export row counts equal database counts with 50,000 sales; shift export boundaries.
- Sheets: a backlog of 1,200 sales appended oldest first with no gaps; a failure midway then retry
  creates no duplicates; barcode removal clears rows.
- Template round trip; encoding cases; 20,000-row import under 30 seconds; widget tests.

### 10.6 Acceptance criteria

A manager previews an import of 800 rows, sees 12 problems with row numbers, fixes them without
losing barcodes, applies the import, and can undo it within a day; a Sheets sync after a long
offline spell uploads every sale exactly once.

## 11. Transactions and Reports upgrades

### 11.1 Goal and users

Find any sale quickly, scope what each role can see correctly, and make reports accurate and fast
on large histories. Cashiers use Transactions; managers and the owner also use Reports.

### 11.2 Data model

No new tables. New indexes: sales by receipt number, by customer, by staff and time; payments by
reference. Settings: how many days of history a cashier may see (default 3) and the default report
period.

### 11.3 Screens and flows

**Transactions.**

- Filter bar: period (today, yesterday, 7 days, custom), search (receipt number, KRA number,
  customer name or phone, M-Pesa code, product), payment chips, status chips (eTIMS pending,
  rejected, returned, unverified, on account), and a staff filter for managers.
- The list is paged (50 at a time) with pull to refresh.
- Detail screen (see main section 5.4): lines, payments, eTIMS status, returns, the audit trail
  for this sale, and the actions Reprint, Share and Return.
- **Scoping.** A cashier sees only sales recorded under their own staff id, within the allowed
  number of days. If the person's identity cannot be resolved they see nothing, never everything.
  Customer phone numbers are masked in lists for cashiers.

**Reports.**

- The same period control as analytics.
- Sections: sales by day, by staff for the chosen period, by payment, VAT, and Shifts (paged) with
  a shift detail screen.
- Aggregation happens in the database, not in memory.
- A shift with no staff id appears as Unattributed with a warning and is never shown as shop-wide
  totals.
- Each section exports only its own period or shift, has an error state with retry, and guards
  against out-of-order responses.

### 11.4 Business rules

1. Period boundaries are local midnight; all comparisons use the same time convention as storage.
2. Staff scoping always uses the staff id, not the display name.
3. Searching by customer needs the manage_customers permission for managers; cashiers can search
   only their own sales.

### 11.5 Tests

- A cashier can never see another staff member's sale, including through search; missing identity
  shows nothing.
- Each search key finds its sale; paging 100,000 sales stays under 200 ms per page.
- Period boundaries at midnight and month ends; exports bounded to period or shift.
- Shift variance matches the shift screen; rapid period switching shows the last choice.
- Widget and accessibility checks at 320 dp and text scale 2.0.

### 11.6 Acceptance criteria

A cashier finds a customer's receipt in seconds by typing the last digits of the M-Pesa code; a
manager exports one shift and gets exactly that shift's sales.

## 12. Audit log and multi-shop portfolio

### 12.1 Goal and users

A trustworthy audit trail that lasts long enough to matter, and cross-shop views that never
disturb the live database. Used by the owner (and managers for their shop).

### 12.2 Data model

Audit log fields (existing table, extended): id, created_at, actor id and name snapshot, approver
id, action, entity, entity id, summary, before and after values (structured), severity (routine,
important, critical), device id.

Retention classes. Routine rows (for example each recorded sale) are kept 90 days, then compacted
into one daily summary row. Important and critical rows (price and cost changes, stock
adjustments, returns, discounts, permission and PIN changes, staff changes, deletions, backups and
restores) are kept at least three years, or longer if the legal retention period requires.

### 12.3 Screens and flows

- **Activity.** Filters for period, severity, action type, staff and shop; search; a detail view
  with before and after; an owner-only export; a note such as Log complete since 12 Jan.
- **Multi-shop (owner).** A shop tab strip reading other shops through separate read-only
  connections. The active shop never changes while browsing.
- **Portfolio.** Period selector, comparison table and chart across shops, drill into a shop
  (read-only), a stale-data marker when offline, and protection against out-of-order responses.

### 12.4 Business rules

1. The audit log is append-only. The only deletions are the retention job and account deletion.
2. Compaction never removes important or critical rows.
3. Cross-shop reads use their own read-only handles; the single active database handle is never
   swapped for browsing. Switching the active shop waits for in-flight queries, then reopens.
4. Registry updates (shop list, names, tenant links) are serialised, and renaming a shop updates
   the switcher.
5. The money units returned by the portfolio endpoint are fixed by a contract test.

### 12.5 Tests

- Compaction keeps important rows and daily totals; an attempt to edit or delete a row fails.
- Browsing another shop while a sale is being recorded leaves both shops intact (concurrency
  test); read-only handles cannot write.
- Portfolio response ordering and units; Activity list over 100,000 rows paged within budget.
- Role gating for all three roles.

### 12.6 Acceptance criteria

An owner reviews a price change from eight months ago with who made it and who approved it, and
can compare three shops without any of them being interrupted.

## 13. UI hardening and visual system

### 13.1 Goal and users

A consistent, phone-first, accessible interface with no overflowing text, no dead ends and one set
of layout rules. Applies to every screen and every role.

### 13.2 Standards

**Layout.** Phone page padding 8 dp, card padding 12 dp, gaps 12 dp; tablets 16 dp. Provided as
shared helpers so no screen hard-codes a number.

**Product tile.** Sized from its content, not a fixed ratio. The photo is at most 56 dp in tiles;
the name takes two lines; the price and stock follow. Fractional stock shows one decimal (for
example 0.4) instead of rounding to zero. At large text sizes the grid falls back to fewer
columns. The no-photo placeholder is a neutral box icon or the product initial, never an
image-not-supported icon. Photos are resolved once, decoded at the device pixel ratio, and do not
flicker on rebuilds.

**Text.** Every text that shows user data (names, shop names, notes) has a defined overflow rule.
Shared widgets exist for money (scales down to a minimum size, full value for screen readers),
names (two lines then ellipsis) and labels. Text scale up to 2.0 is supported with no fixed-height
containers around text.

**Colour.** Tokens only: the few literals in the theme file move to the primitives file. Chart and
brand colours get dark-theme variants that reach 3:1 against the surface. Meaning is never
conveyed by colour alone.

**Dead ends.** The database error screen gains Try again, Share diagnostics, Restore from backup
and Contact support. Every error state in the app offers an action.

**Dialogs and sheets.** One shared confirmation helper; buttons always close their own route.
Guidelines say when to use a dialog and when a sheet.

**Empty and loading states.** Each list defines an empty state with a next action and a skeleton
with a short delay; one reusable offline notice.

**Accessibility.** Screen-reader labels are localised; no duplicate activation hints; sensible
focus order; reduced motion respected.

**Brand.** The app name comes from one constant.

### 13.3 Tests

- Golden suite: key screens at 320, 360 and 412 dp, light and dark, text scale 1.0, 1.3 and 2.0.
- Overflow detection: no layout overflow errors in any golden scenario, including products with
  photos and 40-character names.
- Contrast test computed from the token values (4.5:1 for text, 3:1 for graphical objects) for
  both themes.
- Lint checks for hard-coded colours and strings.
- Rebuild test proves photos are not reloaded on each rebuild.
- Dialog tests inside the real tab navigator; manual screen-reader script on a real device.

### 13.4 Acceptance criteria

On a 360 dp phone at the largest text size, the till, dashboard and inventory screens show every
name, price and total without clipping or overflow, and every error screen offers a way forward.

## 14. Data lifecycle: account deletion, data export and retention

### 14.1 Goal and users

Honour deletion and privacy requests properly while keeping tax records lawfully. Used by the
owner (shop level) and managers (customer level).

### 14.2 Data model

Table `deletion_requests`: id, created_at, stage (local erased, remote pending, remote done,
failed), attempts, last_error. The owner's email needed to complete the remote step is kept in
secure storage until the remote step succeeds, then removed.

Erase-set registry. One maintained list classifies every table, column and file folder as erase,
anonymise-and-keep, keep-for-legal-retention, or contains-no-personal-data. A test fails the build
when a new table or column is not classified.

Retention policy (to be confirmed with an accountant): sales and tax documents for the legal
period (commonly five years); audit log per section 12; support items two years; operational logs
30 days; backups are under the owner's control.

### 14.3 Screens and flows

- **Delete my shop data** (owner, with email code or PIN). A summary lists what will be removed,
  with counts. A choice is offered where the law requires it: delete everything, or delete
  personal data and keep anonymised tax records for the legal period.
- **Export my data first:** a complete machine-readable bundle plus a readable summary, never
  containing secrets.
- **Typed confirmation** of the shop name.
- **Order of work.** The backend deletion is attempted first when online. If offline, the request
  is recorded as Remote pending and finishes automatically when connectivity returns, with
  retries and a visible status in Settings; the local erase proceeds without losing the ability to
  complete the remote step.
- **Erase customer (manager):** anonymises name, phone and TIN while keeping ledger totals;
  blocked while a balance is outstanding unless it is written off.
- After completion the app returns to the welcome screen.

### 14.4 Business rules

1. Erasure covers the database, photos (owner avatar, product and receipt photos), local backups,
   held carts, caches, tokens and pending queues.
2. An interrupted deletion resumes where it stopped.
3. Exports and backups made earlier by the owner are outside the app's control; the screen says
   so.
4. Anonymised tax documents keep totals and tax figures but no names or phone numbers.

### 14.5 Tests

- Classification test: every table and column is in the registry.
- Marker test: insert recognisable personal values everywhere, run deletion, and assert none
  remain in the database, files or caches.
- Offline deletion then online completion; retry and backoff; interrupted deletion resumes.
- Export bundle contents and absence of secrets; erase-customer keeps ledger sums; retention-mode
  deletion keeps anonymised tax documents.
- Widget and accessibility checks.

### 14.6 Acceptance criteria

An owner who deletes their shop while offline sees a Remote pending status; when the phone
reconnects the online account is deleted, and a scan of the phone's app files finds none of the
owner's personal data.

## 15. Placement in the roadmap

The main specification's phases (28.1) apply. This addendum slots in as follows.

| Addendum item | Phase | Notes |
| --- | --- | --- |
| Defect register, blocking items (X-1 to X-6, X-15, X-16, X-18 to X-21, X-36, X-37, X-40, X-41, X-44, X-46) | 0 | small independent fixes with regression tests |
| Defect register, remaining items | 1 | delivered with the section named in each row |
| 3 Shop verification and cloud linking | 0 to 1 | needed before eTIMS can go live |
| 4 eTIMS enablement and buyer details | 1 | with returns and credit notes |
| 5 Printing subsystem | 1 | layout fixes in Phase 0 |
| 6 Scanning subsystem | 1 | used by receiving, stocktake and labels |
| 7 In-app updates and safe rollback | 1 | must ship before any schema-changing release |
| 8 Authentication and PIN hardening | 2 | lockout and idle fixes in Phase 0 |
| 9 Support and feedback | 2 | |
| 10 Import, export and Sheets | 1 and 3 | correctness in Phase 1; wizard and undo in Phase 3 |
| 11 Transactions and Reports | 1 and 2 | transaction detail in Phase 1 because returns need it |
| 12 Audit log and multi-shop | 2 | read-only handles before any cross-shop use |
| 13 UI hardening | 1 and ongoing | tile overflow and padding first |
| 14 Data lifecycle | 1 and 2 | erase-set classification test in Phase 1 because new personal-data tables arrive then |

### 15.1 Additional open questions

1. Whether KRA requires item registration and classification codes per product (adds fields to
   section 4.2).
2. Whether the store policy for the chosen distribution channel permits the self-update path, or
   whether it must be limited to sideloaded installs only.
3. The exact legal retention period for tax records, and how it interacts with the right to
   erasure.

## 16. Staff, product and business analytics: KPI catalogue, drill-down and visibility

This section extends main section 26 and addendum section 11. It defines every KPI once, adds
staff analytics and per-product analysis with full drill-down, says where each piece lives in the
app, and says who sees what. KPI sets differ by business profile; the profile-specific sets are in
the Business Profiles Specification.

### 16.1 Goal and users

Give owners and managers a complete, trustworthy picture of the business by shop, by staff member
and by product, with every number tappable down to the receipts behind it. Give cashiers a simple
view of their own day. Nothing about cost, profit or other people's performance leaks to people
who should not see it.

### 16.2 Principles

1. **One KPI dictionary.** Each KPI has one definition and is computed by one piece of logic used
   by every screen, export and notification, so the dashboard, analytics, reports and Z report can
   never disagree.
2. **Everything drills down.** Every figure opens the list of records that make it up, and that
   list adds up to the figure.
3. **Computed from stored values.** Prices, costs, tax and discounts are read from the sale as
   recorded, never recomputed from today's settings.
4. **Net and honest.** Sales are net of returns and discounts. Profit is calculated on revenue
   excluding VAT.
5. **Fair and explainable.** Staff metrics always show context (hours worked, mix, sample size)
   and a plain explanation of how they are calculated.
6. **Visibility by role and permission.** Defaults are in 16.8 and can be changed with the
   permission model (main section 23).

**Definition defects found while specifying**

| ID | Defect | Required outcome |
| --- | --- | --- |
| X-47 | The profit stored on each sale is the sum of (unit price minus unit cost) times quantity, using VAT-inclusive prices. For a VAT-registered shop this counts the VAT collected as profit | Profit uses the VAT-exclusive line amount (main section 4.3 provides the stored VAT). A regression test with mixed tax classes proves it |
| X-48 | Products with no cost recorded show 100 percent margin and inflate profit and margin | A cost coverage KPI and a visible warning list of products missing a cost |
| X-49 | Profit is visible to cashiers on the dashboard | Cost-derived figures follow view_profit and view_cost (main section 26.3) |

### 16.3 KPI dictionary

Visibility key: O owner, M manager, C own a cashier sees only their own figure. Permission names
are from main section 2.2 and section 16.8.

**Sales**

| KPI | Definition | Default visibility | Drills down to |
| --- | --- | --- | --- |
| Gross sales | Sum of line totals before discounts and returns (VAT-inclusive) | O, M, C own | Transactions |
| Discounts | Line and order discounts given | O, M, C own | Discounted sales |
| Returns | Value of credit notes in the period | O, M, C own (count) | Returns list |
| Net sales | Gross sales minus discounts minus returns | O, M, C own | Transactions |
| Net sales excluding VAT | Net sales minus VAT collected | O, M | VAT summary |
| Transactions | Count of completed sales | O, M, C own | Transactions |
| Average basket | Net sales divided by transactions | O, M, C own | Transactions sorted by value |
| Items per basket | Units sold divided by transactions | O, M, C own | Basket analysis |
| Sales growth | Like-for-like change against the previous period | O, M, C own | Trend chart |
| Sales per shift hour | Net sales divided by hours in shifts | O, M, C own after close | Shift list |
| Target attainment | Net sales divided by the target | O, M, C own target | Targets |
| Busiest times | Transactions by weekday and hour | O, M | Hour detail |

**Profit and margin** (all need view_profit unless stated)

| KPI | Definition | Default visibility | Drills down to |
| --- | --- | --- | --- |
| Cost of goods sold | Unit cost at sale time times quantity, net of restocked returns | O, M (view_cost) | Product margin table |
| Gross profit | Net sales excluding VAT minus cost of goods sold | O, M | Product and category |
| Gross margin percent | Gross profit divided by net sales excluding VAT | O, M | Product and category |
| Markup percent | Gross profit divided by cost of goods sold | O, M | Product |
| Net profit | Gross profit minus expenses | O (M if view_profit) | Expenses |
| Margin leakage | Profit lost to discounts, below-cost sales, returns, waste and shortages | O, M | Leakage breakdown |
| Cost coverage | Share of sales value on products that have a cost | O, M | Products missing a cost |

**Cash and payments**

| KPI | Definition | Default visibility | Drills down to |
| --- | --- | --- | --- |
| Cash variance | Counted minus expected cash per shift; total and absolute | O, M, C own after close | Shift detail |
| Shifts short or over | Shifts outside the tolerance | O, M | Shift list |
| Payment mix | Share of cash, M-Pesa and on account | O, M, C own | Payments |
| Unverified M-Pesa | Count, value and oldest age | O, M, C own | Reconcile list |
| Unclaimed incoming payments | Count and value | O, M | Incoming payments |
| Expenses | By category and paid-from | O, M, C own paid-outs | Expenses list |
| Paid-outs and drops | Cash taken from the till | O, M, C own | Till movements |

**Credit (madeni)**

| KPI | Definition | Default visibility | Drills down to |
| --- | --- | --- | --- |
| Receivables | Sum of positive customer balances | O, M (manage_customers) | Customers |
| Overdue receivables | Balances older than the shop's terms | O, M | Ageing |
| Collections | Repayments received in the period | O, M, C own | Payments |
| Collection rate | Collections divided by opening receivables plus new credit | O, M | Credit trend |
| Average days to collect | Weighted age at repayment | O, M | Ageing |
| Concentration | Share of receivables held by the top five customers | O | Customers |
| Bad debt | Amounts written off | O, M | Write-off list |

**Stock**

| KPI | Definition | Default visibility | Drills down to |
| --- | --- | --- | --- |
| Stock value | At cost and at retail | O, M (view_stock_value) | Valuation table |
| Stock cover days | On hand divided by average daily units | O, M | Product list |
| Inventory turnover | Cost of goods sold divided by average stock value | O | Category |
| Out of stock and low stock | Counts and lists | O, M, C names only | Stock list |
| Lost-sales estimate | Days at zero stock times average daily units times price | O, M | Product list |
| Dead stock | No sale in the chosen days, value at cost | O, M | Product list |
| Shrinkage | Count variances plus waste plus write-offs, value and percent of sales | O, M (view_cost) | Stock movements |
| Purchases | Spend by supplier and category | O, M | Receipts |
| Supplier price changes | Cost movement per product | O, M | Cost history |

**Tax and compliance**

| KPI | Definition | Default visibility | Drills down to |
| --- | --- | --- | --- |
| eTIMS issue rate | Issued divided by eligible sales; median time to issue | O, M | Sync Center |
| Pending age and rejected count | Oldest unissued receipt; rejected receipts | O, M | Sync Center |
| VAT collected by class | Taxable, exempt, zero-rated | O, M (view_reports) | VAT summary |
| Credit notes | Count and value | O, M | Returns |
| Business-customer share | Sales carrying a buyer PIN | O, M | Transactions |

**Customers**

| KPI | Definition | Default visibility | Drills down to |
| --- | --- | --- | --- |
| Active and new customers | With a purchase in the period; first purchase in the period | O, M (manage_customers) | Customers |
| Repeat rate | Customers with two or more purchases | O, M | Customers |
| Top customers | By spend and by balance | O, M | Customer detail |

### 16.4 Staff analytics

Per staff member, for any period:

| Metric | Definition | Notes |
| --- | --- | --- |
| Net sales and transactions | As in 16.3, for sales this person rang up | by staff id, not name |
| Average basket and items per basket | As in 16.3 | |
| Sales per shift hour | Net sales divided by their shift hours | shows hours alongside |
| Average time per sale | From the first item added to completion | needs the sale start time (16.10) |
| Discounts given | Count, value, share of their sales | compared with the shop median |
| Price overrides | Count and value | |
| Returns processed | Count, value, share of their transactions | |
| Cart clears and line removals | Baskets emptied after items were added; items removed after scanning | context, not accusation |
| No-sale drawer openings | Count per day | |
| Cash variance | Per shift and total; shifts short or over | variance belongs to the shift owner |
| Credit sales and collections | Value sold on account; repayments collected | |
| Unverified M-Pesa | Count and age | |
| Stock adjustments | Count and value of adjustments they made | |
| Expenses recorded | Count and value | |
| Approvals given | Manager approvals by type | managers only |
| Product mix | Category and top products sold | |
| Hourly pattern | Transactions by hour | |
| Target attainment | Against their target | |

Exception flags are neutral indicators shown to managers and the owner, with thresholds the owner
can edit. Defaults: cash variance on a shift above KSh 200 or 1 percent of cash sales; discount
share more than twice the shop median and above 3 percent; returns above 5 percent of
transactions; more than 3 no-sale openings in a day; line removals above twice the shop median. A
flag links to the records behind it and never states a conclusion.

### 16.5 Product analytics and drill-down

**Product list (Analytics, Products).** One row per product for the chosen period.

| Column | Meaning |
| --- | --- |
| Units and net sales | Sold and revenue after discounts and returns |
| Share of sales and rank | Position among all products |
| Gross profit and margin percent | Needs view_profit |
| Trend | Change against the previous like-for-like period |
| On hand and cover days | From the stock ledger |
| Days since last sale | |
| Return and discount rate | |
| ABC class | A for the products making the first 80 percent of revenue, B the next 15, C the rest |

Filters: category, supplier, tax class, ABC class, status (selling, slow, dead, out of stock),
profile-specific filters. Sort by any column. Quick lenses: Top sellers, Fast movers, Slow movers,
Dead stock, Highest margin, Lowest margin, Margin leaks, Out of stock but selling, Missing cost.

**Product detail analysis (tap any row).** Sections in this order:

1. Header: name, photo, category, current price and cost, stock, status.
2. Key figures for the period with change against the previous period.
3. Trend chart with a metric switch (units, sales, profit) and a toggle to overlay price and cost
   changes.
4. When it sells: weekday and hour pattern.
5. Who sells and who buys: by staff, by payment method, and top customers.
6. How it sells: by selling option (for example bottle, tot, cup; full, half, quarter; weight
   steps; by amount) and by variant (size and colour where used).
7. Bought together: the five products most often in the same basket, with the share of baskets.
8. Margin leakage: discounts, returns, waste, shortages and below-cost sales, each with value.
9. Stock timeline: the ledger of movements (sales, receipts, adjustments, counts, write-offs) with
   running balance, and batches and expiry where tracked.
10. Purchasing: supplier and purchase history, cost history, last cost versus average cost,
    reorder suggestion and days of stock left.
11. Records: the transactions containing this product, opening the usual transaction detail.

Every section respects 16.8: cost, margin, supplier and purchase sections need the permissions
shown there, and cashiers never see this screen.

Category and supplier analysis use the same layout one level up, and drill into their products.

### 16.6 Drill-down model

**Levels.** Shop, then staff list or product list or category list, then a staff or product
detail, then a shift (for staff) or the transactions list, then a single transaction. A breadcrumb
is always shown; Back goes up one level; the period and filters carry down.

**Drill contract.** Every tappable figure is defined by a metric and a set of filters (period,
staff, product, category, payment, customer, status). The destination is the Transactions screen
or the relevant list pre-filtered with exactly those filters, and its total equals the figure that
was tapped. A test enforces this for every KPI.

**Explain this number.** A long-press or an info button on any figure opens a sheet with its
definition, what is included and excluded, the period, and when it was last updated.

**Compare.** Any list can compare two periods, or a staff member or product against the shop
median.

### 16.7 Where each piece is added

| Place | What it contains | Who it is for |
| --- | --- | --- |
| Dashboard | Role-specific cards. Managers and owners: sales with like-for-like trend, payment split, receivables, returns, attention items and an Exceptions card (flags from 16.4). Cashiers: My day (below) | all roles, different cards |
| My day (cashier home card and screen) | My sales, my transactions, my average basket and items per basket, my target progress, my discounts and returns counts, my unverified M-Pesa list, my collections. After closing a shift: my cash variance | cashiers |
| Analytics hub (new section chips: Overview, Sales, Products, Staff, Customers and credit, Stock, Cash and payments, Tax) | The charts and tables of 16.3, each tappable | manager, owner |
| Analytics, Staff | Staff list (sortable table; on phones a card list) with chosen metrics, flags and a compare-to-median toggle; tap a row for the staff detail | manager, owner |
| Staff detail (also reachable from Settings, Staff) | Header with hours and shifts; key figures; trend chart with metric switch; product mix; hourly pattern; shifts list with variance; exceptions timeline with links; approvals given | manager, owner; the person themselves in My day form |
| Analytics, Products | Product list with lenses; product detail analysis from 16.5 | manager, owner |
| Shift screen and shift detail | Reconciliation, sales, movements, discounts and returns for one shift | cashier (own), manager, owner |
| Transaction detail | The last level of every drill-down | per scoping rules (addendum 11) |
| Customers | Per-customer spend, repeat purchases, balance and ageing | manage_customers |
| Inventory | A Stock health tab: valuation, cover days, dead stock, lost-sales estimate, shrinkage | stock managers |
| Reports | Formal period reports and exports (VAT, shifts, staff takings) built from the same dictionary | manager, owner |
| Sync Center | System health KPIs (backlog, backup age, printer failures, offline time) | manager, owner |
| Notifications | Threshold alerts for flags and targets, aggregated and PII-free (main section 24) | owner, manager |
| Settings, Targets and thresholds | Sales targets per shop or staff; flag thresholds; minimum sample sizes | owner |

**Navigation.** Managers and owners get an Analytics entry in the main navigation. Cashiers do
not; they see only My day. Deep links to analytics screens are checked against the permission
model, so a cashier cannot reach another person's detail by any route.

### 16.8 Who sees what

New permission keys: view_staff_performance (with a scope of own, cashiers, or all),
view_own_performance, view_stock_value, view_cost and view_profit (both already named),
view_customer_data, set_targets.

| Area | Owner | Manager (default) | Cashier (default) | Controlled by |
| --- | --- | --- | --- | --- |
| Shop sales KPIs (net sales, transactions, basket) | yes | yes | own only | role |
| Profit, margin, cost of goods, margin leakage | yes | yes | never | view_profit, view_cost |
| Net profit after expenses | yes | no unless granted | never | view_profit |
| Stock value and shrinkage value | yes | yes | no | view_stock_value, view_cost |
| Staff list and all staff detail | all staff | cashiers and self | no | view_staff_performance scope |
| Own performance | yes | yes | yes, neutral wording | view_own_performance |
| Exception flags | all | cashiers and self | own, as plain information (can be hidden by setting) | view_staff_performance |
| Product analysis, cost and supplier sections | yes | yes | no | view_profit, view_reports |
| Product list (sales only, no cost) | yes | yes | no | view_reports |
| Receivables lists and customer spend | yes | yes | only the customer being served | view_customer_data |
| eTIMS and VAT KPIs | yes | yes | a pending badge on own sales | view_reports |
| Expected cash before counting | yes | yes | hidden until the count is entered (blind close, on by default) | setting |
| Targets: set | yes | no | no | set_targets |
| Targets: view | all | all | own | role |
| Export of any analytics | yes | no | no | export_data |
| Cross-shop staff and product comparison | yes | no | no | role |

Managers cannot see the owner's own figures and cannot grant themselves more access; changes to
these permissions need owner verification and are audited.

### 16.9 Privacy and fairness guardrails

1. **Context and sample size.** Ratios (average basket, discount share, return rate) are hidden
   when there are fewer than 20 transactions or 3 shifts in the period, and show Not enough data
   yet.
2. **No public ranking.** Leaderboards are off by default. Cashiers see their own figures against
   the shop median, never against named colleagues.
3. **Transparency.** Staff see a plain screen, What the shop can see about your work, listing the
   figures above. It appears when an account is created and in Profile.
4. **Purpose limitation.** Staff metrics are for running the business; exporting them is
   owner-only and audited.
5. **Flags are not findings.** Wording is neutral and every flag links to the records.
6. **Departed staff** appear as Former staff with figures kept for the business's records and the
   personal name removed on request.
7. **Customer data** in analytics is masked for anyone without view_customer_data.

### 16.10 Data model additions

| Table or field | Purpose |
| --- | --- |
| sales.started_at | When the first item was added; enables average time per sale |
| sales.device_id | Which till; used by consolidated reporting (main section 22) |
| cart_events | id, staff_id, at, event (cart cleared, line removed, price edited, discount applied, held, resumed), value_minor; kept 90 days; feeds exception flags |
| daily_kpis | date, scope type (shop, staff, category, product), scope id, metric key, value, dictionary version; rebuilt nightly and updated incrementally; makes month and year views fast and survives audit compaction |
| targets | id, scope (shop or staff), metric, period (day, week, month), value, active |
| Settings | variance tolerance, flag thresholds, minimum sample sizes, blind close, leaderboard on or off |
| Dictionary version | Each metric definition carries a version so changes are explicit and stored snapshots stay interpretable |

### 16.11 Business rules

1. A sale belongs to the staff member signed in when it was recorded. Sales with no staff id appear
   as Unattributed and are never merged into anyone's figures or into shop totals without being
   labelled.
2. Cash variance belongs to the shift owner. When several people sell during one shift, sales are
   shown per seller but the variance is shown at shift level with a note.
3. A shift that crosses midnight assigns each sale to its own calendar day.
4. Per-hour metrics use recorded shift hours only.
5. Like-for-like comparisons follow main section 26.4.
6. The nightly rebuild is compared with live queries; a mismatch raises a diagnostics warning.
7. Cashier-visible figures never include cost-derived values, even indirectly (for example profit
   per item, or a margin colour).

### 16.12 Tests

- Dictionary conformance: every KPI is produced by one function; screens, exports and
  notifications are tested to call it; a fixture with three staff and known totals checks every
  KPI.
- Visibility matrix: every area by every role by permission overrides and scope values; deep links
  to another person's detail are refused.
- Drill contract: for every tappable figure the destination list's total equals the figure.
- VAT-exclusive profit: mixed tax classes, discounts and returns produce the expected profit (the
  X-47 regression).
- Cost coverage warning appears and clears as costs are added.
- Sample-size suppression at 19 and 20 transactions and at 2 and 3 shifts.
- Flag thresholds at, just under and just over each limit.
- Unattributed and former-staff handling; shared-till shifts; midnight crossing.
- Daily summary equals live queries across 100,000 sales; performance under 500 ms for any period.
- Product analysis: ABC classes; bought-together results on a known basket set; section visibility
  by role; selling-option and variant breakdowns add up to the product total.
- Blind close: the cashier cannot see the expected cash before submitting the count.
- Widget and accessibility checks: tables become card lists on phones at 320 dp and text scale
  2.0; charts have text alternatives.

### 16.13 Acceptance criteria

- A manager opens Analytics, Staff, sees four cashiers with flags, opens one, taps Discounts, and
  lands on the filtered Transactions whose total equals the figure.
- A manager opens Analytics, Products, sorts by margin, opens a product, and sees its trend, who
  sells and buys it, what it is bought with, where margin leaks, and its stock timeline; a cashier
  cannot reach any of this.
- A cashier sees My day with their own figures and no cost or profit anywhere, and cannot open
  another person's detail.
- The dashboard, analytics, Z report and exports show identical net sales for the same period.

### 16.14 Placement in the roadmap

| Stage | Contents | Phase |
| --- | --- | --- |
| A | KPI dictionary; VAT-exclusive profit fix; cost coverage; profit gating by permission; blind close | 1 |
| B | My day; staff list and detail from existing data (sales, shifts, returns once available); product list and product detail analysis | 2 |
| C | Full KPI set, targets, flags and notifications, cart events, drill contract tests, daily summary table, category and supplier analysis | 3 |

### 16.15 Additional open questions

1. Whether managers should see each other's performance, or only their own and the cashiers'.
2. Whether staff commission or incentive calculations are wanted (this section reports performance
   but does not compute pay).
3. Default sales target units: per shift, per day or per month.
