# Duka POS — Path to Production-Ready

What exists today is a working codebase that demonstrates the app's behavior correctly. "Production-ready" means something stricter: a shop can hand this to real staff, trust it with real money and real stock, for months, without a developer standing by. This document is the gap between those two, organized so nothing gets missed by accident.

**Status update:** the items marked ✅ below have since been implemented in the codebase (see the updated zip) — the rest of this document is unchanged and still describes genuine remaining gaps.

Each item is tagged:
- **🔴 Must-fix** — do not launch without this; either a legal exposure, a data-loss risk, or the app is unusable without it.
- **🟡 Should-fix** — launch is survivable without it, but it will cause real friction or risk within the first few months.
- **🟢 Nice-to-have** — genuinely optional; backlog for v2.

---

## 1. Making the code itself production-grade

### 1.1 Get it compiling and running on a real device 🔴
The current code has never been run. Before anything else: `flutter pub get`, fix whatever package-version mismatches surface, and get it launching on an actual budget Android phone (not just an emulator — emulators are more forgiving on memory and don't reflect a shop's real hardware).

### 1.2 Input validation, everywhere 🔴 ✅ partially done
Product form now validates negative prices/stock, empty names, and non-numeric input with inline error messages, and warns (rather than silently allowing) a sell price below cost. Still open: duplicate-name warning, and validation on the staff-PIN and owner-setup forms beyond the 4-digit regex check already in place.

Nothing in the current code stops a cashier from entering a negative price, a product with an empty name, a stock quantity of -50, or two products with the identical name. Every form needs explicit validation with a clear error message, not just a silent no-op. This includes:
- Prices and stock can't be negative.
- Product name required, and a duplicate-name warning (not a hard block — some shops do carry near-duplicates like two bottle sizes with similar names, but they should be told).
- PIN fields reject anything but 4 digits.
- Numeric fields reject non-numeric paste (a cashier pasting "3,500" instead of "3500" is a real failure mode with Kenyan number formatting).

### 1.3 Concurrent-edit and race-condition handling 🔴
Two things happen "at once" more than you'd think on a single till: a cashier double-tapping "complete sale," or a stock adjustment landing mid-checkout. The current SQLite transaction in `recordSale` covers the core case, but needs:
- A UI-level guard against double-submit (disable the checkout button the instant it's tapped, re-enable only on success or failure).
- Explicit handling for the "someone adjusted stock while this cart was open" case — re-check stock immediately before committing, not just when the item was added to the cart.

### 1.4 Error handling that a non-technical cashier can act on 🔴
Right now, most failures either crash silently or show a generic message. Every error state needs a message written for someone with no technical background: not "SqliteException: constraint failed" but "Couldn't save — try again, and tell the owner if this keeps happening." This covers: DB write failures, file-picker cancellations, Google sign-in failures, out-of-storage-space on the device, and a corrupted database file on launch (see 2.3).

### 1.5 Proper PIN security 🔴 ✅ done
Salt is now random per install, stored via `flutter_secure_storage` (OS keystore/keychain), not a source constant. Lockout added: 5 wrong attempts locks that user out for 30 seconds. Auto-lock added: 4 minutes of no touches anywhere in the app signs the till out back to the lock screen. Tune the exact timeout/attempt numbers with real staff feedback — these are reasonable starting defaults, not tested against real usage yet.

The current PIN salt is a hardcoded constant in the source code — meaning every install of the app shares the same salt, which defeats much of the point of salting. Before launch:
- Generate a random salt per install, store it via `flutter_secure_storage` (backed by Android Keystore / iOS Keychain), not as a source constant.
- Add a lockout after repeated wrong PIN attempts (e.g. 5 tries, then a 30-second cooldown) to make PIN guessing impractical for someone who picks up an unlocked-but-signed-out till.
- Add an auto-lock timeout: if the till sits idle for a few minutes, sign out automatically, so a phone left on the counter doesn't stay logged in as whoever last used it.

### 1.6 Database migrations 🟡 ✅ scaffolding done
`onUpgrade` is now wired up with a documented pattern and an explicit `_schemaVersion` constant. No real migration has been needed yet (schema hasn't changed since launch), so the branch is currently empty with an example left in a comment — but the infrastructure is in place so the *next* schema change doesn't require retrofitting this.

The schema will change after launch — a new column, a new table — and the app needs `onUpgrade` migration logic in `database_helper.dart` from day one, even if v1 only has one migration path ever written. Shipping v1 without this means the *second* release requires every shop to lose their data or requires a manual migration script run by hand on each phone — neither is acceptable.

### 1.7 Corrupted-database recovery 🟡
If the SQLite file gets corrupted (a crash mid-write, a bad SD card, a botched OS-level backup restore), the app currently just fails to open. Add a detection check on launch and a recovery path: offer to restore from the most recent local backup, or at minimum fail with a clear explanation and next step rather than a blank crash screen.

### 1.8 Currency, date, and locale correctness 🟡
- Confirm all monetary values format as `KSh 12,500` consistently (thousands separator, no decimals unless genuinely needed) across every screen — dashboard, receipts, reports, exports.
- Confirm the device's system date/time is what "today" means for shift summaries and daily totals — if a phone's clock is wrong (common on cheap devices), the dashboard will silently show the wrong day's numbers. Consider a subtle "device time: [X]" note somewhere diagnostic, or a warning if the clock looks implausible.
- Swahili labels for the handful of actions staff will use constantly (sell, restock, total) are worth adding even in a v1 — check with actual shop staff which words they'd actually want.

### 1.9 App branding assets 🟡
Real app icon (not the Flutter default), splash screen, and a consistent color scheme applied to native Android/iOS chrome (status bar color, etc.) — currently only the in-app theme is set.

---

## 2. Data integrity & backup

### 2.1 Automatic backup reminders 🔴 ✅ done
A dismissible banner now appears on the dashboard if it's been more than 30 hours since the last export/share, with a one-tap "Back up now" action. Dismissing just hides it for that session — it isn't a hard block.

Manual export exists, but relies on the owner remembering. Add a soft, non-blocking prompt — e.g. once a day, or after N sales since the last backup — reminding the owner to export. Don't make it a hard block; a forgotten backup shouldn't stop someone from selling.

### 2.2 Backup file protection 🟡
An exported Excel/JSON backup contains the shop's full sales history, cost prices, and margins — sensitive business data. If it's shared over WhatsApp or email (as the current design assumes), anyone who intercepts it can read it in plain text. Consider a password-protected export option, or at minimum, tell the owner clearly in the UI that the export file is unencrypted and should be handled like cash.

### 2.3 Protecting against phone loss 🟡
If the owner's phone is lost, stolen, or dies, and no recent backup exists — the shop's entire sales history and inventory is gone, permanently, with no cloud recovery (that's the tradeoff of being genuinely offline). This needs to be communicated clearly at setup time, not discovered the hard way: prompt for a first backup immediately after owner account creation, before the app is used for a single sale.

### 2.4 Android auto-backup conflicts 🟢
Android's built-in app backup (to the user's Google account) may try to back up the SQLite file automatically in ways that conflict with a restore-in-progress, or restore a stale copy after a reinstall. Explicitly configure the app's Android manifest backup rules to exclude or correctly handle the database file rather than leaving it to Android's default behavior.

---

## 3. Testing & QA

None of this exists yet. For a POS app handling real money, this is not optional polish — it's the difference between "this shop trusts the till" and "this shop goes back to a notebook after the first bad night."

### 3.1 Automated tests 🔴 ✅ core coverage added
`test/database_helper_test.dart` now covers product CRUD, and — the highest-value case — the checkout transaction: a normal sale, selling more than available stock (confirms it throws and changes nothing), and a multi-item cart where only one line is short on stock (confirms the *whole* cart rolls back, not just the short item). Stock adjustments are covered too. Still missing: widget tests for the actual screens (PIN login/lockout, checkout UI, form validation) — the database layer was prioritized since it's where silent data corruption would do the most damage.

- **Unit tests** for `database_helper.dart`: every CRUD method, and specifically the `recordSale` transaction — including the case where stock runs out mid-transaction and the whole thing correctly rolls back.
- **Unit tests** for margin calculations, low-stock detection, and the hybrid sync fallback logic (`sync_service.dart`) — mock both the "online" and "offline" paths.
- **Widget tests** for the checkout flow, PIN login (correct PIN, wrong PIN, lockout), and product form validation.

### 3.2 Manual QA pass, written down as a checklist 🔴
Before every release, someone runs through (and checks off) a fixed list of real scenarios, not just "does it open." At minimum:
- Complete a sale with 1 item, with 5 items, with an item that has only 1 in stock.
- Try to sell more of an item than is in stock.
- Kill the app mid-checkout (force-close) and confirm stock and sales stay consistent on relaunch.
- Sign in as owner, as staff; confirm staff cannot see owner-only screens.
- Export and re-import a backup; confirm data matches.
- Turn off Wi-Fi/data, hit "Sync now," confirm it falls back to Excel cleanly.
- Enter a negative price, an empty product name, letters in a stock field.
- Rotate the phone / use it in landscape (if not explicitly locked to portrait — decide and document which).

### 3.3 Real-device testing 🔴
Test on at least one genuinely low-end/budget Android phone (2GB RAM class), not just a developer's high-end phone or an emulator — this is the realistic hardware a small shop will actually use, and performance or storage issues that don't show up on better hardware are exactly what will show up in the field.

### 3.4 Crash reporting 🔴 ✅ wired, needs a Firebase project to activate
`main.dart` now has the Crashlytics error-capture hooks in place, guarded behind a `firebaseConfigured` flag currently set to `false`. Turning it on requires the one-time account step of creating a Firebase project and running `flutterfire configure` (generates `firebase_options.dart`) — see the updated README Part 3. Until that's done, the app runs normally with crash reporting simply off.

Wire up Firebase Crashlytics or Sentry before the first real shop uses this. Without it, if the app crashes in a shop 200km away, you will never know it happened unless the owner happens to mention it — and by then they may have already given up and gone back to a notebook.

### 3.5 Pilot with one real shop before wider rollout 🟡
Run this in a single friendly shop for at least a couple of weeks before calling it done. Real usage surfaces things a checklist won't: a screen a cashier finds confusing under time pressure with a queue of customers, a workflow that's technically correct but annoying at 7pm on a Friday.

### 3.6 Load/scale testing 🟢
Confirm performance holds up with a year+ of sales history (a few thousand rows is trivial for SQLite, but confirm report screens paginate or stay fast rather than loading everything into memory as history grows) and a large product catalog (100+ SKUs).

---

## 4. Kenya-specific compliance — read this section carefully

### 4.1 KRA eTIMS — the single biggest compliance question 🔴
Since 2023, KRA requires **VAT-registered businesses** in Kenya to issue electronic tax invoices through eTIMS (electronic Tax Invoice Management System), either via KRA-approved hardware/software or their free eTIMS mobile/web app. If this shop is VAT-registered, receipts generated by this app are **not currently compliant** — the receipt is a plain text summary, not an eTIMS-registered invoice, and the app has no integration with KRA's systems.

Before treating this app as the shop's real point of sale:
- **Confirm whether the shop is VAT-registered.** Many very small retail shops are below the VAT registration threshold and this may not apply — but wines & spirits retail can cross that threshold faster than other small retail given price points, so don't assume.
- If VAT-registered, either (a) integrate with KRA's eTIMS API for invoice generation — a real, separate technical project with its own registration and certification process — or (b) run this app for internal inventory/sales tracking only, and issue compliant invoices through KRA's own free eTIMS app in parallel, treating this app as the shop's internal system of record rather than its tax-facing point of sale.
- This is worth a direct conversation with the shop owner's accountant or a KRA-registered tax agent before launch, not a decision to make purely in code.

### 4.2 Alcohol licensing record-keeping 🟡
The excise stamp batch field exists as a record-keeping convenience but does **not** verify stamp authenticity — that requires KRA's own verification systems and is out of scope here. Make sure the shop understands this app helps them keep organized records, but doesn't replace their obligation to only stock and sell properly stamped product.

### 4.3 Data Protection Act, 2019 (Kenya) 🟡
The app stores staff names and (hashed) PINs — personal data under Kenyan law. If the shop has more than a handful of staff or the owner wants to be fully correct, the shop (as the "data controller") may need to register with the Office of the Data Protection Commissioner (ODPC), and the app should have a short, plain-language notice for staff about what data is collected and why (name + PIN, for attributing sales — nothing else, no location tracking, no external sharing except the owner's own opt-in Google Sheets sync). This is a low-burden compliance step but worth doing properly rather than skipping.

### 4.4 Play Store / App Store alcohol-related content policy 🟡
Both Google Play and Apple's App Store have restrictions on apps related to alcohol (age-gating requirements, sometimes regional restrictions on alcohol *sales* apps specifically, though a shop's *internal inventory tool* is a different category than a consumer-facing alcohol delivery app). Before submitting to either store, read their current alcohol content policies directly — this is exactly the kind of thing that changes over time and needs checking at submission time, not assumed from general knowledge. See section 5.1 for why sideloading may be the simpler path regardless.

---

## 5. Distribution: getting it onto real phones, repeatedly

### 5.1 Store listing vs. sideloading — decide this deliberately 🟡
This is an **internal business tool for one shop's staff**, not a consumer app. That changes the calculus:
- **Sideloading** (distributing the `.apk` directly, installed via "allow unknown sources") avoids app store review entirely, avoids the alcohol-content policy question in 4.4, and avoids Apple's $99/year developer program for a single shop's iPhones (if they even use iPhones — Android is far more common for this context). The tradeoff is manual update distribution (5.2) and a slightly less polished install experience.
- **Play Store** (even as an "unlisted" or internal-testing-track app, not publicly searchable) gives automatic updates and a more familiar install flow, at the cost of a one-time $25 developer registration and whatever review friction the alcohol policy creates.
- **Recommendation for a single shop:** sideload. It's simpler, faster, and sidesteps policy questions that don't really apply to an internal tool. Revisit the Play Store (as an unlisted/internal release) only if this grows into a product sold to multiple shops.

### 5.2 Update distribution without a store 🔴 (if sideloading)
If not using an app store, there's no automatic update mechanism. Without a plan, "fixing a bug" means physically walking to the shop with a new APK on a USB stick or sending it over WhatsApp and talking the owner through reinstalling — for every single fix. Before launch, decide and build a lightweight in-app "check for update" flow: the app checks a known URL (e.g. a file on GitHub Releases, which is already in this project's allowed toolchain) for a version number, and if newer, prompts the owner to download and install the new APK directly. This is a small feature that prevents a very real ongoing support headache.

### 5.3 Signing key management 🔴
Whoever builds the release APK generates a signing keystore. **That keystore must be backed up somewhere safe and never lost or regenerated** — if it's lost, every future update must be a fresh install (losing all local data, since Android treats a differently-signed APK as a different app). Document who holds this key and where it's backed up, before the first real release.

---

## 6. Ongoing maintenance & support

### 6.1 A real support channel 🔴
When (not if) something goes wrong in the shop, who does the owner contact, and how fast can they expect a response? Even a simple WhatsApp number or email, with an honest expected response time, is better than the owner discovering there's no one to call.

### 6.2 CI/CD pipeline 🟡
Codemagic (already recommended for the first build) should be configured to build automatically on every code change pushed to the main branch, so releases are consistent and repeatable rather than a manual process prone to "works on my machine."

### 6.3 Versioned changelog 🟢
A simple running log of what changed in each release — useful both for your own sanity debugging "which version is this shop running" and for being transparent with the owner about what a given update actually does.

### 6.4 Staff offboarding process 🟢
When a staff member leaves the shop, someone needs to remember to deactivate their PIN. Consider a gentle nudge — e.g. flagging staff who haven't logged a sale in 30+ days — rather than relying purely on the owner remembering.

---

## 7. UX polish for real-world shop conditions

### 7.1 Interruption handling 🟡
A phone call, a low-battery shutdown warning, or the app being backgrounded mid-sale are everyday events on a shared shop phone, not edge cases. Confirm the cart state survives being backgrounded and restored, and that a checkout in progress can't be left in a half-completed state by an interruption.

### 7.2 Search and filter as the catalog grows 🟡
The current inventory and product-selector lists are flat lists. Once a shop has 80–150 SKUs (realistic for wines & spirits), a cashier scrolling to find "Chrome Vodka 250ml" under time pressure is a real usability problem. Add search-as-you-type to both the inventory screen and the product picker on the Sell screen before launch, not after complaints.

### 7.3 Accessibility basics 🟢
Respect the device's system font-scaling setting rather than fixed font sizes (some staff may need larger text), and confirm color contrast is sufficient for the low-stock red / in-stock green indicators to be readable in bright daylight (a very real condition for a phone used near a shop's open doorway).

### 7.4 Barcode scanning 🟢
Not in the current scope, but worth flagging as the single most-requested feature once a shop has used this for a few weeks with a growing product list — using the phone's own camera (no extra hardware) via a package like `mobile_scanner` is a realistic v2 addition.

### 7.5 Receipt customization 🟢
Shop name and address on the receipt header, maybe a short footer message ("Asante — karibu tena" is already there as a placeholder) — small but makes the app feel like it belongs to that specific shop rather than a generic template.

---

## 8. Business & operational readiness (not code)

### 8.1 A short staff training document 🔴
Even a one-page printed sheet: how to sign in, how to sell, what to do if a sale won't go through, who to call if something breaks. Staff turnover in retail is high; this shouldn't depend on the owner re-explaining the app to every new hire from memory.

### 8.2 A recovery plan the owner actually knows about 🔴
Make sure the owner genuinely understands, in plain terms, what happens if their phone is lost (2.3) — and has actually done a practice backup-and-restore once, not just been told it's possible.

### 8.3 Decide the multi-shop question now, even if the answer is "not yet" 🟢
If this owner has (or plans to have) more than one shop location, that's a meaningfully different product shape than what's built (this assumes one shop per install). Worth a direct conversation now so it's a deliberate "out of scope for v1" decision rather than a surprise later.

---

## 9. New: backend, multi-tenancy, and M-Pesa (added this round)

A real backend now exists (`duka_pos_backend/`, Supabase-based) implementing what was asked for: Row Level Security for tenant isolation (each shop's data is invisible to every other shop, enforced by Postgres itself, not app-level filtering), role-based access control (owner vs. staff permissions enforced by RLS policies, not just hidden UI), and M-Pesa payments via PayHero. This is real, deployable code — not a mockup — but it has never touched a live Supabase project or a real PayHero account, so it inherits the same "needs a real first run" caveat as the Flutter app, plus a few gaps specific to this addition:

### 9.1 Deploy and test against real accounts 🔴
Nothing here has run against an actual Supabase project or PayHero merchant account. This is the direct equivalent of item 1.1 for the new backend half of the system — see the go-live checklist's new step 3.5.

### 9.2 Product/stock sync drift between phone and backend 🔴
Enabling M-Pesa creates a second stock ledger (Postgres, via the backend) alongside the phone's local SQLite ledger. They're synced on demand (when M-Pesa is enabled, and on "Sync now"), not continuously — so there's a real window where a product added or restocked locally isn't yet sellable via M-Pesa, or where the backend's view of stock is briefly stale. This is the single most important thing to understand before relying on M-Pesa for a busy shop; see the backend README for the full explanation and what a tighter fix would look like (real-time sync, or making the backend authoritative once M-Pesa is on).

### 9.3 PayHero webhook trust model 🟡
Because PayHero's exact webhook signing/authentication scheme wasn't verifiable from their public docs, `payhero-callback` treats the webhook purely as a trigger to re-confirm status directly with PayHero's own API — never trusting the webhook body's claims about payment success. This is the right conservative default, but confirm PayHero's current signing options directly (their dashboard or support) and tighten this if a proper signature-verification mechanism exists — belt-and-suspenders is better than belt-alone for anything touching money.

### 9.4 Per-staff backend identity 🟢
Right now one Supabase login exists per till device (created when the owner first enables M-Pesa), not one per staff member — the actual cashier is recorded as plain text for reporting, while the backend-level identity is the device/owner's. This is a deliberate scope decision, documented in the schema, not an oversight — revisit only if backend-side per-staff audit trails become genuinely necessary.

### 9.5 eTIMS toggle is intent-only, not integration 🔴
Restating this from section 4.1 because it's easy to miss now that there's a Settings switch that *looks* like a feature: flipping "eTIMS record-keeping" to Included does not talk to KRA in any way. Don't let its existence in the UI be read as the compliance question having been resolved.

### 9.6 Multi-till LAN sync is still separate and still unbuilt 🟡
Worth restating clearly: this backend solves sync *for M-Pesa payments specifically*. It does not give two physical tills in the same shop a shared, real-time view of stock for cash sales — that's the LAN host/client design from the original dev spec's Section 2, and it remains a distinct, unbuilt piece of work.

## Priority summary

| Must-fix before any real shop relies on this (🔴) | Should-fix soon after (🟡) | Backlog (🟢) |
|---|---|---|
| Compile & run on real device | DB migrations ✅ scaffolded | Android auto-backup config |
| Input validation ✅ mostly done | Corrupted-DB recovery | Barcode scanning |
| Concurrent-edit handling | Locale/date correctness | Receipt customization |
| Actionable error messages | Backup file protection | Accessibility polish |
| Real PIN security ✅ done | Phone-loss communication | Staff offboarding nudges |
| Automated tests ✅ core coverage added | Alcohol-licensing record clarity | Changelog |
| Manual QA checklist, run every release | Data Protection Act notice | Multi-shop decision |
| Real low-end device testing | Store vs. sideload decision | |
| Crash reporting ✅ wired, needs Firebase project | Support channel | |
| **KRA eTIMS determination** | CI/CD automation | |
| Automatic backup reminders ✅ done | Search/filter as catalog grows | |
| Update distribution mechanism (if sideloading) | Interruption handling | |
| Signing key backed up & documented | | |
| Staff training document | | |
| Owner backup/recovery understanding confirmed | | |

**What's still genuinely open from the 🔴 list:** compiling and running on a real device (nothing here has been tested against an actual compiler), concurrent-edit UI guards, friendlier error messages throughout, the manual QA checklist itself (a process, not code), real low-end device testing, the KRA eTIMS legal determination, sideload update distribution, signing key handling, and the two non-code items (staff training doc, confirming the owner has actually practiced a restore). Everything else in the 🔴 column now has real code behind it.

The eTIMS question (4.1) is flagged in both the compliance section and here deliberately — it's the one item on this list that isn't a technical risk but a legal one, and it needs a real answer from the shop's own tax situation before this app can be trusted as their actual point of sale rather than a parallel record-keeping tool.
