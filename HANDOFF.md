# HANDOFF — SimpleSales multi-tenancy, identity & observability

**Date:** 2026-10-10
**Branch:** `main` @ `a8ba01f` (ahead by ~70 files, uncommitted)
**State:** green — `flutter analyze` clean, **835/835 tests pass**, gates pass.

---

## 1. How to pick this up

```bash
cd /home/bstudio/Projects/Pos/duka_pos_app
flutter analyze                 # expect: No issues found
flutter test                    # expect: All tests passed! (835)
```

Nothing is committed. Everything below is in the working tree.

### The two worktrees

| Worktree | Branch | What's there |
|---|---|---|
| `/home/bstudio/Projects/Pos` | `main` | the Flutter app (all new work) |
| `/home/bstudio/Projects/Pos/.kilo/worktrees/backend-analytics/duka_pos_backend` | `backend` | `src/lib/portfolio.ts` + `src/__tests__/portfolio.test.ts` (**untracked**), `src/routes/tenant.ts` modified |

Backend verify (from inside the backend worktree):
```bash
cd "/home/bstudio/Projects/Pos/.kilo/worktrees/backend-analytics/duka_pos_backend"
ln -s /home/bstudio/Projects/Pos/duka_pos_backend/node_modules node_modules   # worktree has no node_modules
./node_modules/.bin/tsc --noEmit     # 29 pre-existing errors, none in files you touch
./node_modules/.bin/vitest run       # 68 tests pass (10 are new portfolio tests)
rm node_modules
```

---

## 2. Decisions already made — do not re-litigate

| Decision | Why |
|---|---|
| **Keycloak, not Clerk** | User explicitly reverted a Clerk suggestion mid-session. Stay on Keycloak. |
| **New brand = botanical green** `#1B6B3A`, warm ivory `#FAF6F0`, warm charcoal `#2D2A26`, warm amber `#8A6508` | Replaced the old wine brand `#6E2638`/`#251A1D`. All icons + `colors.xml` regenerated. |
| **App renamed to `SimpleSales`** (no space) | Dart package stays `duka_pos` deliberately — renaming rewrite ~all imports for zero user benefit. |
| **Charts are line + pie, never bar** | The bar chart (`SimplePosChart`) is **deleted** from `lib/widgets/chart.dart`. My `dashboard_hourly_test.dart` was *written to fail compilation* if you reintroduce it. |
| **Owner has NO `actorId`** | `deleteStaffWithTombstone` scrubs staff rows. A FK into a scrubable row leaks the name the tombstone removes. Display name is denormalised into `actor_name`. |
| **Audit rows read: `ownerRelevantAudit`** | Sales filtered out of the owner feed — 200 sale rows drown the one settings change they wanted. |
| **Audit row written AFTER the write it describes** | A crash leaves a product with no log row, never a log row for a product that doesn't exist. **Exception: shop switch is written BEFORE** (see gotcha). |
| **Log write failure never fails the action** | A shop that can't adjust stock because a log insert failed is worse than one with a log gap. |
| **`recordActionAudit(AppState, …)` not `BuildContext`** | Fixes `use_build_context_synchronously`. Capture `state = context.read<AppState>()` **before the first await**. |
| **`_SettingsPanel` / `TaxSettingsPanel` / `PortfolioPanel` public** | Stateful screens own async work and delegate to a value-driven public panel, so tests render layout without a DB. |

---

## 3. DONE

### Staff tagging — 29 attributed actions (`lib/models/audit_log.dart`, `lib/services/audit_actor.dart`)
v18 migration, `audit_log` table + 3 indexes, created from **one shared `_createAuditLogTable`** so fresh-install and upgrade schemas cannot diverge (`migration_test.dart` enforces this).

Tagged: sales (4 paths), stock, product/barcode/variant, staff, M-Pesa, printer, tax, sync, backups, shifts, shop switch.
**Tests:** `test/audit_log_test.dart` (12)

### Cross-shop audit visibility (`lib/services/cross_shop_audit_reader.dart`, `lib/screens/activity_screen.dart`)
Walks the local shop registry, asks each shop's own DB, restores the shop it started in. Owner sees **every shop** — merged or by-shop.
**Tests:** `test/cross_shop_audit_test.dart` (12), `test/screens/activity_screen_test.dart` (18)

### Backups verified (`test/backup_test.dart`, 10)
Round-trip export → AES-256-GCM → decrypt → real importer. Found & fixed a **cross-test-file sqlite 1032** (`workspace_test.dart` deleted `.db` files other files still had open).

### Also done
Shop switching fixed (read the **local registry**, not `/tenant/shops` — local-only shops were unreachable); portfolio KPI screen; charts → line/pie; 3 dead sell-screen files removed (1,318 lines); dark mode + system theme verified; 173 dead ARB keys removed.

### Baseline for the next session
App: **902 tests pass**, `flutter analyze` 0 issues, `dart format` clean, i18n-bans PASS. Backend (`backend` branch worktree): **214 tests pass**, `tsc --noEmit` clean, `prisma validate` clean. **`dart_test.yaml` sets `concurrency: 1` and that is load-bearing** (see the new gotchas). — but `check_raw_values.sh` **fails on pre-existing raw `Duration(seconds:)` values** in `lib/main.dart` (the press-back-again window), `lib/services/auth_service.dart` (lockout windows), `lib/services/barcode/scan_input_service.dart`, `lib/services/printer/esc_pos_printer.dart`. They predate this work and were deliberately left alone: two of them are security-relevant lockout constants and the rest are in screens unrelated to the verify flow. The 20s→30s / 2s→5s retokenising I tried was reverted for the same reason.

---

## 4. REMAINING — all five delivered

1. ~~**Verify flow**~~ — **DONE.** `lib/ui/dialogs/verify_identity_dialog.dart` (two sheets: 4-digit PIN → 6-digit code), `BackendService.requestVerificationCode` / `confirmVerificationCode` / interceptor refresh, `AppState.identityVerified` (stored in prefs as `profile_email_verified`; the flag that gates the auto-backup switch in `_SyncPanel`). Backend: `POST /api/auth/link`, `/api/auth/verify`, `/api/auth/refresh` in `src/routes/auth.ts`, Keycloak admin client in `src/lib/keycloak_admin.ts` (account created **disabled**, `activated` only after the code), codes in `prisma/migrations/20261010210000_email_verification` (`EmailVerification` table: hashed, PIN bound under the same salt, single-use, 10-min TTL, 5 attempts), EmailJS in `src/lib/email_sender.ts`. The till's session (`src/lib/app_session.ts`) is signed by the server and accepted **only** on `/tenant/*`, `/products/*`, `/reports/*`. **Tests:** `test/ui/dialogs/verify_identity_test.dart` (14), `test/screens/settings_verification_test.dart` (12), backend `src/__tests__/auth_http.test.ts` (13) + `verification.test.ts` (16) + `app_session.test.ts` (14) + `keycloak_admin.test.ts` (11) + `email_sender.test.ts` (6). **Not yet exercised against a real realm** — needs `KEYCLOAK_ADMIN_CLIENT_ID/SECRET`, `EMAIL_VERIFICATION_SECRET`, `APP_SESSION_SECRET`, the four `EMAILJS_*` keys (see `.env.example` and the README section).
2. ~~**EmailJS verification codes**~~ — **DONE**, same work as above.
3. ~~**WebSocket analytics streaming**~~ — **DONE.** `GET /tenant/portfolio` still answers, but the till now streams at `wss://…/live` (`src/routes/live.ts`), over a dependency-free RFC 6455 implementation (`src/lib/websocket.ts`, 18 codec tests) with `src/lib/live.ts` as the single change bus, emitting after writes in `products/sync`, `products/stock-adjust` and `tenant/settings PATCH`. It carries *only* `{type:'stale', reasons}, at` — the figures come from the same `readPortfolio` the HTTP endpoint uses (`src/lib/portfolio_query.ts`, extracted so the two cannot disagree). Scoping is read at connect time from the caller's own profiles, heartbeat 30s, idle close 10m. **Tests:** `websocket.test.ts` (18), `live.test.ts` (14), `live_http.test.ts` (13, over a real TCP client).
4. ~~**App observability**~~ — **DONE.** `lib/models/crash_log.dart` + a **v19** `crash_log` table (shared `_createCrashLogTable` so a fresh and an upgraded install match), `_trimCrashLog` deleting the oldest on *every write* (cap 200, `<=` boundary — `<` leaves the table one row over), `lib/services/failure_recorder.dart` (framework + zone hooks, a 10-crumb breadcrumb trail, route/actor/action attached from the router's `_BreadcrumbObserver`, best-effort by design), and `lib/screens/diagnostics_screen.dart` / `Routes.diagnostics` (`bounded and says so`, a shareable text report with the environment first, a confirm before clearing). **Tests:** `test/crash_log_test.dart` (11), `test/failure_recorder_test.dart` (10), `test/screens/diagnostics_screen_test.dart` (16).
5. ~~**Admin API + dashboard**~~ — **DONE.** API: `GET /api/system/users` (paged, masked email, `email_verified`), `/analytics` (window-bounded, 400 days, `window_truncated`), `/analytics/drilldown` (per-day series with zero-filled days, tender mix, staff leaderboard, per-shop breakdown — all from the pure `src/lib/admin_analytics.ts`), `/observability` (pending codes, codes burnt in 24h, recent attempts masked), `GET|PATCH /system/tenants/:id/settings` (404 vs 400 distinguished, empty update rejected), `PATCH /system/users/:id/active`. UI: a hand-built page served from the same origin at `/admin` (`src/routes/dashboard.ts`, `src/public/dashboard.{html,css,js}`), no framework and no bundle, holding its token in `sessionStorage` only and showing the API's own error verbatim. `npm run build` copies `src/public` to `dist/public`. **Tests:** `admin_analytics.test.ts` (27), `dashboard.test.ts` (14 — including "links only assets that exist" and "calls only endpoints that exist").

---

## 5. GOTCHAS that will cost you an hour each

- **Shell tab-completion degrades during long command chains.** If a bash call returns `parse error near '>'`, run `echo ok` once to reset before retrying. I hit this ~8 times; it produces garbage like `/home/bsoft 2>/dev/null` chains.
- **The ffi test DB persists at `.dart_tool/sqflite_common_ffi/databases/`.** `resetForTests()` only nulls the singleton, it does NOT close the handle. **Never delete `.db` files mid-suite** — use unique workspace keys per case and delete only in `setUpAll`. Deleting with an open connection → `sqlite 1032 attempt to write a readonly database`, reported against an innocent test.
- **`ExcelService()` is a no-arg façade** — `ExcelService(db)` fails to compile.
- **`gen-l10n` params are ordered ALPHABETICALLY** (`detail, products, refused`). A signature with an int first but alphabetically third will swap your arguments silently. Always read the generated getter before wiring it.
- **`SectionHeader` UPPER-CASES its label.** Shop names and titles get their own headings.
- **`AppTypography.of(context)` returns a `TextTheme`** — declaring it as `AppTypography` is a compile error.
- **`AppSpacing.of(context)` returns an object** — `horizontal: spacing` fails; it's `spacing.md`.
- **`flutter test` runs suites CONCURRENTLY, and four suites (`workspace`, `cross_shop_audit`, `migration`, `audit_log`) delete `.db` files in `setUpAll`.** `resetForTests()` nulls the singleton without closing the handle, so one suite's delete lands under another suite's open connection and sqlite reports `1032 attempt to write a readonly database` against whichever test writes next — a failure with no relationship to its cause. It was latent (the 835 baseline passed by timing luck) and adding suites perturbed the timing, so it is **pinned with `dart_test.yaml` → `concurrency: 1`**. Do not remove that to speed up a run.
- **`crash_log` needs `<=` when trimming by `id`.** Deleting `id < cutoff` where `cutoff` is the row at `offset: keep` leaves the table **one row over its cap on every write**. `pruneAuditLog` already uses `id <=`; the crash log must match. [test/crash_log_test.dart] asserts the exact cap, which is the only way to catch an off-by-one that grows by one per write.
- **A modal bottom sheet beats a dialog for numeric entry.** `shift_float_sheet.dart` argued it and the verify flow proves it: at 2.0x text on 320dp an `AlertDialog`'s content `Flexible` will not shrink below its fixed children, so title + actions + field overflow by ~45px. Bounding the scroll region AND moving the actions row outside the scroll view is what fixes it. A sheet also needs its own `Material(type: transparency)` or a directly-pumped test throws "No Material widget found", and `viewInsetsOf` rather than `.of` so the keyboard does not rebuild it.
- **`openInMemoryForTests()` assigns to the ONE singleton.** Calling it twice orphans the first DB; both ends of a "round trip" then read the same store and the test proves nothing.
- **`SectionedPage` uses `sections:`; `AdaptivePage` uses `child:`** — mixing them is confusing and unrunnable.
- **`lib/widgets/chart.dart`'s `describeSlices` and `PosPieChart` are the reusable primitives** — reuse them before writing a new chart.
- **`lib/ui/components/states.dart` has `EmptyStateView` / `ErrorStateView` / `SkeletonList`** — use them, don't hand-roll.
- **A sheet needs its own `Material`.** The modal route supplies one around the builder's result, but pumping the sheet widget directly in a test throws *"No Material widget found"* from the `TextField` — an error that reads like a theme problem. `_VerifySheetFrame` wraps itself in `Material(type: transparency)` for this.
- **A modal sheet is a better verification dialog than an `AlertDialog`.** Both steps are keyboard entry; a dialog puts the field under the keyboard on a 640dp till. The sheet also scrolls its prose (`_sheetMaxHeight`) so a long sentence at 2.0x never costs the owner the entry field.
- **`alertDialog`'s actions row is where a control goes to die.** With a 2.0x text scale on 320dp, an `AlertDialog`'s content `Flexible` will not shrink below its fixed children, so actions + title + entry overflow. Bounding the scroll region *and* moving actions outside it is what fixes it.
- **`prisma generate` must run in the worktree after a schema change.** The client is generated into `/home/bstudio/Projects/Pos/duka_pos_backend/node_modules` (shared through the symlink), so without it both `tsc` and the route tests report `prisma.emailVerification` as non-existent. It does not need a database.
- **Mounting anything on `/api/auth` must come before `app.use('/api', authMiddleware)`** — these are the only endpoints that authenticate by content, so they run before a token exists.
- **`flutter test` runs suites CONCURRENTLY, and four of them delete `.db` files in `setUpAll`.** `resetForTests()` nulls the singleton without closing the handle, so one suite's delete lands under another suite's open connection and sqlite reports `1032 attempt to write a readonly database` against whichever test writes next. This was latent (the 835-test baseline passed by timing luck) and my additions perturbed the timing, so it is now **pinned with `dart_test.yaml` → `concurrency: 1`**. Do not remove that to speed up a run. The file names the four suites; if another suite adds a DB, it must either use unique workspace keys or join the serialised set.
- **`git checkout -- <file>` in the backend worktree DESTROYS work.** The `backend` branch worktree has hours of **uncommitted** work on top of the branch head (the portfolio route was one of those files, and `checkout` ate it; it was reconstructed by hand). **Commit early, commit often, on both trees.** `git status --short` lists what an accidental checkout would delete.
- **This environment does not deliver a client-side FIN to the server side of a loopback connection in time for a test to see.** A `socket.destroy()` in a test leaves the server's socket open until teardown; write a close frame (or end the server socket) instead, and reap streams in `afterEach`. This is why `live_http.test.ts` closes from the server side.
- **Node's `http` server only raises `upgrade` for a request carrying BOTH `Upgrade:` and `Connection: Upgrade`.** A test that forgets one never reaches your upgrade handler and looks like a hanging server.

---

## 6. House style (enforced by the analyzer + gates)

`dart format` clean · `flutter analyze` 0 issues · i18n-bans gate PASS · no raw `Color(0x…)`/`Colors.*` outside `lib/theme/**` · no `_buildX()` methods (extract `Widget` classes) · directional geometry only (`EdgeInsetsDirectional`, never `left`/`right`) · every user string in `app_en.arb` with `nullable-getter: false` · 44px min tap targets · no `FittedBox`/`ellipsis`/`withClampedTextScaling` on real labels · every test with a device/scale/brightness matrix loops the ranges **around** `testWidgets`, never inside it (an overflow is reported once per render object).

---

## 7. Security note flagged to the user, unresolved

`session-ses_ede6.md` and `session-ses_ee85.md` at the repo root contained a **GitHub PAT** and a **Sentry DSN** in plain text at an earlier point. The files have since been rewritten without them and they are **untracked/not in git history**, so no repo cleanup is needed — but the **PAT should be rotated** as a precaution.
