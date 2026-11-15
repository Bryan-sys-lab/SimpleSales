# SimpleSales / Duka POS v79 — Agent Implementation & Navigation Preservation Contract

**Purpose:** Give the coding agent an exact execution contract for applying the dashboard redesign patches in `DASHBOARD_REDESIGN_IMPLEMENTATION_PATCHES_V79.md` without breaking the existing application. This is a structural dashboard redesign, but the rest of the product must remain functionally intact: every supported feature, route, shortcut, permission, data scope, back path, and task flow must continue to work.

**Source of truth:** `duka_pos_app_source_v79.zip`, extracted project root `duka_pos_app/`.

**Required companion specification:** `DASHBOARD_REDESIGN_IMPLEMENTATION_PATCHES_V79.md` contains the 17 detailed UI/data patches. Read that file first. This contract adds the execution order, navigation graph, feature-entrypoint matrix, existing route discrepancies, and regression requirements. Where the two documents conflict, this contract takes precedence for route and flow preservation.

**Do not use** `duka_pos_dashboard_redesign_v79_patched.zip` as the source of truth. It is not the complete authoritative source and must not replace the original v79 project.

---

## 1. The task in one sentence

Rebuild the four dashboard screens so their real daily-operation layout matches the generated Duka, Fashion, Drinks and Open reference designs — forest-green money hero, useful KPI arrangement, profile-specific operational panels and clear primary actions — while preserving the app's existing business engines and the complete, permission-aware navigation graph.

This is **not** permission to simplify the rest of the app, remove secondary functions, replace the router, or change how sales, stock, laybys, drinks, jobs, finance, shifts, reports, settings or support work.

## 2. Absolute invariants — do not violate these

1. **No route deletion or renaming.** Do not delete, rename, re-parent, merge, or change the path of a route in `lib/routing/routes.dart` or `lib/routing/app_router.dart` as part of the dashboard redesign.
2. **No feature deletion.** Do not remove any existing dashboard panel, menu item, quick action, overflow action, sheet, dialog, report, feature screen, or workflow just because it is not visible in the generated reference. Reposition it or keep its existing entry point.
3. **No hiding to make the dashboard look cleaner.** Do not put existing features behind newly introduced accordions, collapsed sections, tabs, carousels, or an extra menu unless the feature was already accessed that way. Use the dashboard's normal vertical scroll for secondary content.
4. **No new permission grants.** Do not make a cashier, manager, or profile able to reach a route or see data that the existing role/profile policy disallows. A shortcut must have the same permission conditions as its destination.
5. **No permission regressions.** Do not remove route guards, `PermissionKey` checks, `canManageStock`, `canViewReports`, `isAdmin`, profile capability checks, staff-only data scoping, workspace scoping, or tenant isolation.
6. **No navigation rewrite.** Do not replace `GoRouter`, `StatefulShellRoute.indexedStack`, `HomeShellTabs`, `visibleDestinations`, `ShellNavBar`, the rail, drawer, or `More` sheet with a new navigation system.
7. **No guessed route strings.** Use `Routes.*` constants and helper constructors. Do not hand-concatenate route strings at call sites.
8. **No accidental route-index arithmetic.** Use `HomeShellTabs.goTo(AppDestination...)` for shell destinations. Never use a visible-list index as a branch index. `More` is an action with no branch, not a `/more` route.
9. **Preserve push/back semantics.** Existing detail flows use `context.push` and root-navigator child routes so Back returns to the prior dashboard/list with its state. Do not replace these with `context.go`, `Navigator.push`, or a new stack unless the existing code already uses that exact behavior.
10. **Preserve route identity.** Record IDs belong in path parameters for deep links. Do not replace `:productId`, `:tankId`, `:jobId`, or `:poolId` with `state.extra`.
11. **Preserve intentional `extra` payloads.** Some flows intentionally pass a live `ScanSession`, a product ID for stocktake, a job ID, or the `{ 'quickSale': true }` map. Do not strip, rename or transform these payloads.
12. **No fabricated dashboard data.** The generated mockup amounts, counts, percentages, labels and trend figures are visual examples only. Render real values or truthful empty states.
13. **No fake “refresh” action.** Keep the current pull-to-refresh mechanism. A business switch must open the business-profile selector, not look like a refresh button.
14. **Preserve offline behavior.** Do not make local business-profile switching or existing local POS functions depend on a successful backend call.
15. **Preserve text accessibility.** Never shrink important text to force a card into one row. No fixed-height KPI cards, clipped primary amounts, or `FittedBox` workarounds.
16. **Do not restyle the entire POS.** Dashboard profile accents apply to dashboard identity and dashboard operational modules only. Checkout, receipts, stock forms, reports and the global navigation retain their established semantic colours unless a separate approved task says otherwise.
17. **Keep localisation.** Add/update source ARB strings in both English and Swahili. Do not hand-edit generated localisation Dart files.
18. **Keep existing audit events.** Do not bypass the existing profile-change audit, financial audit, or operation result handling.
19. **Keep loading/session safeguards.** Preserve `_loadSerial`, session-generation checks, `_current(...)`, `mounted`, `LiveRefresh`, `SessionRefresh`, `TickerMode` visibility checks and staff-scope query arguments.
20. **Never call a route “reachable” merely because `appRedirect` returns null.** The route must also be registered, its route builder must render the correct feature for that profile, the user must have permission, and a real UI action must lead to it.

---

## 3. Important correction to the earlier patch notes: business switching is not `Routes.profile`

This is a critical distinction in the current source and must be handled correctly.

- `Routes.profile` is `/settings/profile`. It opens `ProfileScreenOpen`, the account/shop-owner profile screen.
- Actual **business profile switching** is implemented in `_MoreSheet` in `lib/routing/home_shell.dart`. Its “Switch business profile” item opens the profile-selection dialog and changes the shop profile.
- Existing dashboard `onSwitchBusiness` callbacks in Duka, Fashion and Drinks currently call `context.push(Routes.profile)`. That does **not** open the business-profile picker; it opens the account profile. Do not repeat this mistake in the redesigned header.
- The previous dashboard patch specification's line saying the new business switch must continue to route to `Routes.profile` is superseded by this contract.

### Required implementation

1. Extract the existing profile-picker operation from `_MoreSheet` into one reusable shell-owned callback/controller method, or expose an equivalent method on `HomeShellTabs`.
2. Reuse the exact existing profile-change sequence:
   - show the existing profile chooser/dialog;
   - call `DatabaseHelper.instance.setShopProfile(selected)`;
   - call `AppState.setShopProfile(selected)`;
   - call `BackendService.setBusinessProfile(selected)` as best-effort sync, retaining its offline-safe catch behavior;
   - call `recordActionAudit` with `AuditAction.profileChanged` and `AuditEntity.workspace`;
   - allow the existing session/profile listeners to rebuild and reload the correct dashboard.
3. Make both the dashboard hero/header business switch and `More → Switch business profile` invoke that single implementation. Do not create two divergent profile-change flows.
4. Do not route the business switch to `/settings/profile`, `/dashboard`, or an invented `/switch-profile` URL.
5. Test that switching Duka → Fashion → Drinks → Open changes dashboard composition and profile capabilities without signing out, losing the shell, corrupting the current workspace, or bypassing the audit event.

### Account profile is separate

The shell app-bar person/account button also calls `Routes.profile`. Keep that meaning distinct from business switching. The current redirect guard blocks all `/settings/...` routes for non-admin roles, while the person/account button is currently constructed without an admin condition. Verify this affordance against the product's intended staff policy:

- If this is an owner-only account screen, render the account button only for roles allowed to open it (currently the Settings guard is admin-only).
- If non-admin staff are meant to have a personal profile screen, implement a staff-safe route and screen with an explicit authorization rule; do not open the owner's private account editor to all staff.
- Do **not** weaken the Settings guard for all settings routes merely to fix the person button.
- Add tests proving the visible account action never points to a route that redirects the same user away.

---

## 4. Existing navigation model — preserve this structure

### 4.1 Primary shell destinations

`AppDestination` lives in `lib/routing/routes.dart`. The shell owns navigation and role filtering. The dashboard redesign must not implement a parallel tab system.

| Session/profile | Primary destinations | Notes |
|---|---|---|
| Duka owner/manager with stock permission | Dashboard, Inventory, Sell, Analytics, More; Support remains available through the wider shell affordance / More | Settings is not a primary tab. |
| Fashion owner/manager with stock permission | Dashboard, Inventory (Fashion Catalogue), Sell, Analytics, More; Support remains available | Laybys and Exchanges remain additional Fashion workflows. |
| Drinks owner/manager with stock permission | Dashboard, Inventory, Sell, Analytics, More; Support remains available | Servings and tank workflows remain Drinks-specific. |
| Retail cashier | Dashboard, Sell, Analytics, More; Support remains available | No Inventory destination. Analytics must remain scoped to the cashier's own sales. |
| Open owner/manager | Dashboard, Open Business, Sell, Analytics, More; Support remains available | No Inventory tab. `/inventory` redirects to Portfolio. |

The exact list comes from `visibleDestinations(AppState)` in `lib/routing/home_shell.dart`. Do not hardcode a role/profile destination list in any dashboard screen.

**Responsive shell behavior:** on compact screens, `ShellNavBar` is used and `Support` is removed from the visible bottom-bar cells; it remains available from More. On larger screens, the rail/drawer uses the full destination list. Keep the current central Sell affordance, active-branch semantics, branch stacks, rail/drawer behavior and status strip. Do not copy a bottom navigation row from the generated mockups over the real app shell.

### 4.2 More is an action sheet, not a route

`AppDestination.more` has `branchIndex == -1`. `HomeShellTabs.goTo(AppDestination.more)` opens the existing `_MoreSheet`; do not use `context.go('/more')` or add a fake route.

Preserve these current More-sheet entries and their existing conditions/actions:

| More item | Existing action / condition |
|---|---|
| Switch business profile | Opens the profile picker and performs the audited local/backend profile change. |
| Fashion reserves / laybys | Only when `state.shopProfile.navigation.showLayby`; opens `Routes.laybys`. |
| Exchanges | Fashion-only UI item; opens `Routes.exchangeScreen`. |
| Reports / exports | Only when `state.canViewReports`; opens `Routes.reports`. |
| Settings | Only when `state.isAdmin`; opens `Routes.settings`. |
| Help | Opens `Routes.help`. |
| Support | Switches to `AppDestination.support`. |
| Notifications | Opens the existing notification sheet; selected notification destination is pushed unchanged. |
| Business tools marketplace | Opens `Routes.marketplace`. |
| Open business record | Keep current profile/capability behavior; Open already has its own primary branch. Do not invent a new destination. |

Do not remove More items because their feature is not part of the daily dashboard. Do not show an action to a role/profile that cannot successfully open it.

### 4.3 Shell app-bar actions

Preserve the existing top-level actions in `_ShellScaffold` / `_ShellAppBar`:

- Expense / Pay Out action, shown only when `PermissionKey.recordExpense` is granted; it opens the existing expense sheet.
- Customer credit shortcut, shown only for owner/manager; it opens `Routes.customers`.
- Account/profile action, subject to the explicit role/access alignment in Section 3.
- Sign-out confirmation and local-first sign-out behavior.
- Till status strip, which belongs to the shell and must not be moved into the dashboard or obscured by dashboard scrolling.

---

## 5. Complete route inventory — do not drop any of these

The route constants are defined in `lib/routing/routes.dart`; concrete registration and builders are in `lib/routing/app_router.dart`. This list is the route-regression inventory for the agent.

### 5.1 Session / onboarding doors

| Route constant | Path | Purpose |
|---|---|---|
| `Routes.splash` / `Routes.initial` | `/splash` | Initial boot gate. |
| `Routes.recovery` | `/recovery` | Database recovery. |
| `Routes.welcome` | `/welcome` | Welcome / account chooser. |
| `Routes.login` | `/login` | Owner login. |
| `Routes.staffLogin` | `/staff-login` | Staff PIN login. |
| `Routes.setup` | `/setup` | Owner/shop setup. |
| `Routes.onboarding` | `/onboarding` | Legacy onboarding/deep-link path. |
| `Routes.permissions` | `/permissions` | Optional device permissions step. |

Do not change the boot/session redirect order in `appRedirect` as part of a dashboard pass.

### 5.2 Root-level shared routes

| Constant | Path | Purpose |
|---|---|---|
| `Routes.marketplace` | `/marketplace` | Business tools marketplace. |
| `Routes.help` | `/help` | Help. |

These are registered at the root navigator, outside the shell branches. Preserve their root-level presentation and return behavior.

### 5.3 Dashboard branch and dashboard details

| Constant | Path | Expected entry / use |
|---|---|---|
| `Routes.dashboard` | `/dashboard` | Active profile dashboard. |
| `Routes.transactions` | `/dashboard/transactions` | Dashboard transaction count / transaction summary. |
| `Routes.customers` | `/dashboard/customers` | Customer balances / credit. |
| `Routes.laybys` | `/dashboard/laybys` | Fashion laybys; route builder checks profile capability. |

Keep details pushed over the shell on the root navigator, so Back returns to the dashboard context rather than resetting the branch.

### 5.4 Sell branch

| Constant | Path | Expected entry / use |
|---|---|---|
| `Routes.sell` | `/sell` | Main POS sale flow; supports current `extra` payloads. |
| `Routes.cameraScan` | `/sell/scan` | Scanner; preserves an optional `ScanSession` handoff. |

Do not change the cart lifecycle, sale completion, held-cart behavior, split-tender logic, receipt, printer, barcode, or scan-session handoff while redesigning dashboard buttons.

### 5.5 Inventory branch and product details

| Constant/helper | Path | Profile/permission rule |
|---|---|---|
| `Routes.inventory` | `/inventory` | Requires stock permission and a profile with inventory; Open redirects to Portfolio. |
| `Routes.product(id)` | `/inventory/product/:productId` | Product route with ID in path; preserve deep-link behavior. |
| `Routes.productDetail(id)` | `/inventory/product-detail/:productId` | Product detail by ID; keep distinct from the product route. |
| `Routes.servings` | `/inventory/servings` | Drinks measured serving service only. |
| `Routes.tankRegister` | `/inventory/tank-register` | Drinks tank register only. |
| `Routes.tankDetail(id)` | `/inventory/tank/:tankId` | Drinks tank detail by path ID. |
| `Routes.stocktake` | `/inventory/stocktake` | Stocktake; preserve optional product ID `extra`. |
| `Routes.fashionProductForm` / `fashionProductNew()` | `/inventory/fashion-product/new` | Fashion style/variant creation; verify Drinks variant policy as noted below. |
| `Routes.fashionProduct(id)` | `/inventory/fashion-product/:productId` | Style/variant detail with path ID. |
| `Routes.fashionProductEdit(id)` | `/inventory/fashion-product/:productId/edit` | Style/variant edit with path ID. |

The redesigned Duka/Fashion/Drinks dashboards may add shortcuts into these routes, but must not add duplicate inventory writers or bypass the existing forms/repositories.

### 5.6 Analytics branch and details

| Constant | Path | Rule |
|---|---|---|
| `Routes.analytics` | `/analytics` | Visible to all roles; cashier figures remain staff-scoped. |
| `Routes.reports` | `/analytics/reports` | Requires `canViewReports`. |
| `Routes.shift` | `/analytics/shift` | Shift detail; intentionally reachable by cashiers for their own shift. |
| `Routes.expenses` | `/analytics/expenses` | Expense/finance detail. |
| `Routes.portfolio` | `/analytics/portfolio` | Cross-shop portfolio; admin/owner only. |

Reports are a view within Analytics, not a new bottom tab. Do not move them into a new route or make them visible to roles that cannot view reports.

### 5.7 Settings branch and settings details

| Constant | Path | Purpose / access |
|---|---|---|
| `Routes.settings` | `/settings` | Settings; current route guard is admin-only. |
| `Routes.taxSettings` | `/settings/tax` | Tax / eTIMS settings. |
| `Routes.activity` | `/settings/activity` | Cross-shop activity. |
| `Routes.diagnostics` | `/settings/diagnostics` | Diagnostics; owner-only ledger repair is separately controlled. |
| `Routes.incomingPayments` | `/settings/incoming-payments` | Incoming payment review. |
| `Routes.syncCenter` | `/settings/sync-center` | Sync status/conflict center. |
| `Routes.permissionsMatrix` | `/settings/permissions` | Permission matrix. |
| `Routes.profile` | `/settings/profile` | Owner/shop account profile, **not** business-profile switching. |
| `Routes.imports` | `/settings/imports` | Import review/problems. |

Keep the broad Settings guard intact unless a specific route is deliberately split out with a tested authorization policy. Do not make all settings accessible merely to make one dashboard card or account shortcut work.

### 5.8 Open profile routes

All are under `/open-business` and must remain Open-profile-only:

| Constant/helper | Path | Purpose |
|---|---|---|
| `Routes.openBusiness` | `/open-business` | Open Business primary branch / job list. |
| `Routes.openJobs` | `/open-business/jobs` | All jobs. |
| `Routes.openJobNew` | `/open-business/jobs/new` | New job. |
| `Routes.openJobEdit(id)` | `/open-business/jobs/:jobId/edit` | Edit a job. |
| `Routes.openJobDetail(id)` | `/open-business/jobs/:jobId` | Job detail. |
| `Routes.openJobAddCost(id)` | `/open-business/jobs/:jobId/cost` | Add direct job cost. |
| `Routes.openCostGroups` | `/open-business/cost-groups` | Cost pools/groups. |
| `Routes.openCostGroupNew` | `/open-business/cost-groups/new` | New cost group. |
| `Routes.openCostGroupDetail(id)` | `/open-business/cost-groups/:poolId` | Cost group detail. |
| `Routes.openReceivables` | `/open-business/receivables` | Open-business receivables/payment history. |

Preserve the `jobId`/`poolId` in the path. Do not make Open profile inventory a tab: `Routes.inventory` must continue to redirect to `Routes.portfolio` under Open.

### 5.9 Fashion exchange route

| Constant | Path | Purpose |
|---|---|---|
| `Routes.exchangeScreen` | `/fashion/exchange` | Fashion exchange flow; app-router comment and page builder currently declare it Fashion-only. |

Do not make this a Drinks action unless the product owner explicitly changes the feature policy and the screen/data flow is implemented for Drinks.

---

## 6. Existing route-policy discrepancies the agent must resolve, not ignore

A redirect test alone does not guarantee that the final route page can be built. Audit all three layers together: `appRedirect`, `app_router.dart` route page builder, and the profile capability / visible-entry-point rules.

### 6.1 Fashion exchange: redirect guard currently disagrees with the route builder

- `appRedirect` currently groups `Routes.exchangeScreen` with Fashion product routes and permits both Fashion and Drinks.
- `app_router.dart` registers the exchange page as Fashion-only (`ShopProfile.fashion ? ExchangeScreen() : NotFoundScreen(...)`).
- The router comment says the exchange is Fashion-only.
- `test/routing/profile_route_matrix_test.dart` currently expects the exchange redirect check to allow Drinks.

**Required resolution:** treat Exchanges as Fashion-only unless a separate implemented Drinks exchange workflow is found. Align the redirect guard and route matrix test with the route builder and the feature's existing comment. Do not expose a Drinks exchange shortcut that lands on `NotFoundScreen`.

### 6.2 Fashion product/variant routes: route guard, tests and page builder disagree for Drinks

- `ProfileDefinition` sets `variants: true` for both Fashion and Drinks.
- `appRedirect` permits `/inventory/fashion-product/...` under Fashion and Drinks.
- `profile_route_matrix_test.dart` expects these paths to be allowed for Drinks.
- The current route page builders for `fashion-product/new`, `fashion-product/:productId` and edit check `ShopProfile.fashion` only.

**Required resolution:** inspect `FashionProductFormScreen`, `FashionProductDetailScreen`, Drinks product creation (`ProfileProductForms`), existing acceptance tests and stored variant data. Establish whether Drinks is intended to use these particular Fashion product routes or whether Drinks variants are managed through a different UI. Then make all three layers agree:

- If these are truly Fashion-only screens, tighten `appRedirect` and its tests so Drinks is redirected away; retain Drinks' own supported variant/product workflow.
- If Drinks is intended to use these routes, implement a Drinks-compatible route presentation and route-builder capability check; do not blindly show Fashion labels/terminology or reuse an incompatible writer.

Do not mark the patch complete while redirect, builder, capability and visible entry point disagree.

### 6.3 Account icon and profile route

The top app-bar account action opens `Routes.profile`, but the blanket Settings redirect is admin-only. Align the affordance with the permission contract as described in Section 3. A visible button must not send a role to a route that immediately redirects away.

### 6.4 Dashboard “Switch business” callback

The Duka/Fashion/Drinks dashboard switch callback currently opens `Routes.profile`, which is the wrong destination. It must invoke the shared business-profile picker behavior from `More → Switch business profile`. Preserve the account profile route as a separate feature.

Record all discrepancy decisions in the final implementation report and add tests for each resolution.

---

## 7. Dashboard redesign execution order

Apply the companion 17 patches in this order. Do not make all four dashboards separately before the shared system is stable.

### Phase 0 — establish a baseline before editing

1. Extract `duka_pos_app_source_v79.zip` into a clean working directory.
2. Record the original commit/hash or archive checksum; create a feature branch.
3. Run baseline commands:

   ```bash
   flutter pub get
   dart format --output=none --set-exit-if-changed lib test
   flutter analyze
   flutter test
   ```

   If a baseline command fails, record the failing test/error before modifying anything. Do not silently attribute a pre-existing failure to the dashboard changes.
4. Capture baseline screenshots of Duka, Fashion, Drinks and Open at 320dp, 360dp and a normal phone size, including an accessibility text scale of 2.0.
5. Save a navigation manifest of all `Routes` paths, registered route builders, `visibleDestinations` output by role/profile, and all dashboard callback destinations.
6. Run and record these existing navigation/scope suites before editing:

   ```bash
   flutter test test/routing/profile_route_matrix_test.dart
   flutter test test/routing/redirect_test.dart
   flutter test test/screens/home_shell_navigation_test.dart
   flutter test test/screens/home_shell_profile_switch_test.dart
   flutter test test/ui/shell_nav_bar_test.dart
   flutter test test/cashier_analytics_scope_test.dart
   ```

### Phase 1 — shared dashboard foundation

Apply companion patches 01–03 and relevant parts of 15–16:

- Add dashboard-only profile palette; do not mutate global `AppColors` semantics.
- Add responsive layout helpers based on local `LayoutBuilder` constraints and `MediaQuery.textScalerOf(context)`.
- Replace greeting-first header with compact shop identity, profile pill, truthful shift state, date, and an explicitly named **Switch business** action that uses the actual profile picker flow.
- Keep the business switch and account profile as separate actions.
- Keep `RefreshIndicator`, error/retry states, backup reminder, till status strip and session behavior.

### Phase 2 — shared money hero and KPI components

Apply patches 04–07 and 11:

- Build the shared forest-green hero with current real figures, transaction count, accurate tender split chips and primary action.
- Remove the fake hardcoded percentage trend entirely unless a real comparison query is implemented and tested.
- Build shared responsive KPI cards.
- Ensure amount labels state the actual measure (net sales, gross profit, expenses, outstanding credit, completed job revenue, net cash movement etc.).
- Keep paid/profit, expenses/negative and pending/credit semantics consistent across profiles.
- Put the hero and primary business actions before less urgent panels; do not remove alerts, shift or backup functionality.

### Phase 3 — implement one profile at a time

Implement and test each profile before moving on:

1. Duka (`duka_dashboard_screen.dart`): hero → 4 money/stock KPIs → stock needing attention / top products → shift, credit, hourly sales, alerts, backup and all existing product/stock actions.
2. Fashion (`fashion_dashboard_screen.dart`): hero → layby balance, gross profit, items sold, low-stock variants → laybys needing attention / fast-moving variants → catalogue, new layby, exchange, inventory, shift, credit and existing alerts/actions.
3. Drinks (`drinks_dashboard_screen.dart`): hero → profit, held carts, measured volume, pour variance (only when true data exists) → open/held sale workflow and tank/stock watch → servings, tank detail/register, packaged stock, inventory, shift, credit and existing actions. Never call held carts “open tabs”.
4. Open (`open_dashboard_screen.dart`): hero → net profit, net cash movement, receivables, active jobs → jobs requiring attention / cost groups or genuinely measured budget health → New job, record payment, add cost, record sale, receivables, cost groups and job drilldowns. Do not invent a budget utilisation percentage.

### Phase 4 — reconnect every action

For every card, icon, row, button, “View all”, overflow item and hero CTA:

1. Identify its existing callback and route target before moving it.
2. Preserve the route constant, payload, permission condition and push/go semantics.
3. If an item has no current route (for example a purely informational KPI), do not make it look tappable.
4. If a new shortcut is introduced, use it only as an additional entry point to an existing feature. It must not replace the existing primary navigation or the More-sheet entry.
5. Test its destination by tapping the control in a widget/integration test. Static code search is not sufficient.

### Phase 5 — responsive and accessibility hardening

- Keep one primary vertical scroll owner per dashboard; do not nest independent vertical scrolling lists without a deliberate, tested reason.
- Reflow card rows using local constraints; at high text scale cards become full-width columns.
- Wrap payment chips, profile pills and action rows.
- Allow hero action to stack below the amount when needed.
- Do not clip names, currency, balances, warning labels, units, buttons or navigation labels.
- Keep tap targets at least 48 logical pixels.
- Use semantic labels for icon-only buttons and maintain logical reading order.
- Keep keyboard, screen-reader and Back behavior intact.

### Phase 6 — final regression, report and review

Run every baseline test plus new route/flow tests, analyzer, formatter, build and screenshot comparison. See Sections 10–12.

---

## 8. Dashboard feature-entrypoint matrix — every existing workflow must remain reachable

This matrix is not a request to make every feature visible to every role. Preserve the existing role/profile access rules. “Reachable” means a user who is already entitled to a feature still has a clear, working way to reach it.

### 8.1 Shared across retail dashboards (Duka, Fashion, Drinks)

| UI element / user intent | Destination / callback | Preservation rule |
|---|---|---|
| New sale / Start sale | Existing `onOpenSell` → `/sell` | Keep current cart/sale entry flow; do not create a second POS implementation. |
| Sales count / transactions | `Routes.transactions` | Keep date/context and Back behavior. |
| Credit owed / customer balance | `Routes.customers` | Keep only where `canManageCredit` / existing role condition permits. |
| Shift status / Open Shift | Existing `onOpenShift` → `Routes.shift` | Must work for cashier's own shift; preserve expected till read and shift controls. |
| Low-stock product row | Existing `onOpenProduct` → `Routes.product(id)` | Preserve path ID; only interactive when user can manage stock. |
| View all stock | Existing `onOpenInventory` → `Routes.inventory` | Preserve role and profile capability gates. |
| eTIMS attention | Existing retry / tax settings callbacks | Rejected receipt fix remains permission-gated; do not convert all alerts to blind retry. |
| Backup reminder | Existing `onBackupNow` callback | Keep backup action, confirmation and result state; move visually below hero/KPIs if needed. |
| Pull to refresh | Existing `onRefresh` callback via `RefreshIndicator` | Keep it as a gesture; do not create a refresh button in the header. |
| Switch business | Shared existing profile picker extracted from More | Must not route to `Routes.profile`. |

### 8.2 Duka

Keep all Duka-specific paths/actions already implemented:

- New sale → `/sell`.
- Add product → existing profile-aware product form / product creation path.
- Receive stock → existing `ReceiveStockSheet`/inventory path; do not replace it with a generic add-product form.
- Stocktake → `/inventory/stocktake`, retaining optional product ID `extra`.
- Open a product → `/inventory/product/:productId` as currently wired from the dashboard.
- View all products/stock → `/inventory` (permission-gated).
- Stock alerts, total product count, low-stock count and out-of-stock count must remain available after stock value moves into a KPI. Moving stock value into a KPI does not justify deleting the stock-status counts.
- Keep top-selling items, sales-by-hour/no-sales state, shift, customer credit and eTIMS/import attention cards.

### 8.3 Fashion

Keep these Fashion operations and their existing routes:

- New sale → `/sell`.
- New style/product → `/inventory/fashion-product/new`.
- Open style/variant detail → `/inventory/fashion-product/:productId`.
- Edit style/variant → `/inventory/fashion-product/:productId/edit`.
- Fashion catalogue → existing `/inventory` profile route (`FashionCatalogueScreen`).
- Laybys / reserves → `/dashboard/laybys`.
- Exchange → `/fashion/exchange`, Fashion-only unless explicitly re-scoped later.
- Low-stock size/colour variant row → existing variant/product drilldown callback; preserve the target ID and permission check.
- Keep layby payments/balances and due dates, fast-moving variants, stock alerts, shift, credit, hourly sales, top products and eTIMS/import attention.

A card showing “layby balance” is not a substitute for the Layby list. The balance KPI and the existing customer-level layby workflow must both remain reachable.

### 8.4 Drinks

Keep these Drinks operations and routes:

- Start sale → `/sell`.
- Add drink/product → existing `ProfileProductForms.showForm(profile: ShopProfile.drinks)` flow and its existing save path.
- Measured servings → `/inventory/servings`.
- Tank register → `/inventory/tank-register`.
- Tank detail → `/inventory/tank/:tankId`.
- Packaged stock → `/inventory`.
- Stocktake → `/inventory/stocktake` where current permission/capability permits.
- Keep tank cards, tank sales, beverage stock preview, low stock, held-cart/parked-sale awareness, shift, credit, sales by hour, top products and eTIMS/import attention.
- Keep any existing pour/serving confirmation and stock-decrement logic. Do not create a dashboard-only write path.

**Terminology/data rule:** `DrinksAnalyticsSnapshot.openTabs` currently counts held carts (`held_carts.status='held'`). Display it as “Held carts” or “Parked sales”, not “Open tabs”. Do not create a new table-tab abstraction as a cosmetic substitute.

### 8.5 Open

Keep these Open operations and routes:

- New job → `/open-business/jobs/new`.
- All jobs → `/open-business/jobs`.
- Job row → `/open-business/jobs/:jobId`.
- Edit job → `/open-business/jobs/:jobId/edit`.
- Add job cost → `/open-business/jobs/:jobId/cost`.
- Record payment → preserve the existing `_pickJob` selection then open the selected job detail/payment workflow.
- New cost group/pool → `/open-business/cost-groups/new`.
- Cost groups list → `/open-business/cost-groups`.
- Cost group detail → `/open-business/cost-groups/:poolId`.
- Receivables → `/open-business/receivables`.
- Quick/linked sale → `/sell` with the existing job ID or `{ 'quickSale': true }` payload, exactly as appropriate for the current action. Do not discard the job association.
- Keep active jobs, awaiting-payment jobs, overdue jobs, recent jobs, cost group count, receivables, recent activity and all current job status indicators.

**Terminology/data rule:** `_cashPositionMinor` is `all.cashInMinor - all.cashOutMinor`, a cumulative net cash movement. It is not a live till float/cash-on-hand balance. Label it “Net cash movement” unless the app adds a separately reconciled cash-position calculation.

**Revenue rule:** the existing `job_completion` financial sum is all-time. Do not label it “today” until a real local-day-bounded query is added and tested. Do not call completed job revenue “cash collected” unless the exact event represents cash received.

**Cost rule:** do not render a percentage budget utilisation card unless a real budget denominator and actual-cost numerator exist for the displayed cost pool/job. Never calculate utilisation as a made-up ratio from aggregate totals.

---

## 9. Data, session and business logic that the dashboard must not break

### 9.1 Shared retail loader

In `lib/screens/dashboard_screen.dart`, preserve:

- `DashboardState` loading / failed / ready states and retry UI;
- profile dispatch into Drinks, Duka and Fashion dashboard screens;
- Open's independent `OpenDashboardScreen` loader;
- `_loadSerial` and `_current(serial, session, appState)` protection against stale reads;
- `sessionGeneration` checks;
- cashier `ownOnly` filtering and `staffId` arguments passed to sales, top-products and other staff-scoped queries;
- shift lookup by current staff ID;
- `LiveRefresh` and `SessionRefresh` behavior;
- current backup reminder and attention dismissal state;
- pull-to-refresh.

Removing the greeting must not remove a field or query that also carries the staff identity/scope. Remove only the greeting presentation/data plumbing once all remaining uses are checked.

### 9.2 Payment mix

Do not derive accurate tender totals solely from `sales.payment_method`. The app can have split tender in `sale_payments`; the new tender chips must aggregate actual tender rows by the current date window and the same staff/shop scope as the hero. Refund, void, reversed and unconfirmed payment handling must match the existing analytics definitions. If a verified tender split is not available, omit the chips rather than inventing one.

### 9.3 Profile and workspace

- Reuse `ShopProfile` and `ProfileDefinition` in `lib/profile/`; do not create a second profile enum or duplicated boolean matrix.
- Keep profile capabilities as the authority for inventory, measured goods, variants, drink service, layby, jobs, pooled costs and analytics.
- Do not use the profile accent to change business logic or global success/danger/warning colours.
- Preserve `DatabaseHelper` workspace selection and row-scope boundaries.
- Preserve best-effort backend sync and local usability if backend profile update fails.

### 9.4 Open loader

Open's `LiveRefresh` currently declares no live reasons. Do not pretend a refresh stream is wired if it is not. Preserve `SessionRefresh`, explicit retry/refresh and error state. If adding live reasons, connect them to actual events and add tests; do not change its timing semantics accidentally.

---

## 10. Required automated test plan

### 10.1 Keep all existing tests

Do not delete, skip, weaken or rewrite existing tests just to pass a new layout. Run at minimum:

```bash
flutter test test/routing/profile_route_matrix_test.dart
flutter test test/routing/redirect_test.dart
flutter test test/screens/home_shell_navigation_test.dart
flutter test test/screens/home_shell_profile_switch_test.dart
flutter test test/ui/shell_nav_bar_test.dart
flutter test test/cashier_analytics_scope_test.dart
flutter test test/profile_test.dart
flutter test test/profile_change_preview_test.dart
flutter test test/fashion_acceptance_test.dart
flutter test test/shift_cash_job_payments_test.dart
flutter test test/shift_ledger_test.dart
flutter test test/row_scope_test.dart
flutter test test/session_scope_test.dart
```

Also run the complete `flutter test` suite.

### 10.2 Route registration and link tests

Add or extend tests so **every route in Section 5** is tested at both redirect and route-builder level.

For each route, test:

1. A signed-in user with the appropriate role/profile reaches the intended screen (not `NotFoundScreen`).
2. A user without the required role/profile is redirected or denied exactly as intended.
3. The route path parameters rebuild the screen after a cold/deep link without relying on `state.extra`.
4. Back returns to the correct previous screen and preserves the tab's state/scroll position where that is the existing behavior.
5. A shortcut's callback navigates to the exact intended route, not merely any screen that appears similar.

Build a route coverage assertion that enumerates every route path in a central test manifest. It should fail when a `Routes` constant is added without a matching registered route test (except documented helpers/door routes tested separately).

### 10.3 Role/profile matrix

At minimum test these combinations:

- Profiles: Duka, Fashion, Drinks, Open.
- Roles: owner/admin, manager, cashier.
- Stock permission: true/false where test harness supports it.
- Report permission: true/false.
- Cost/expense permission: true/false.

Assert visible destinations from `visibleDestinations`, More-sheet item conditions, dashboard action visibility, route redirects and resulting screen builders agree. Do not assume manager permissions equal admin permissions.

### 10.4 Dashboard UI tests

For each of the four dashboards, test:

- Hero shows the correct real metric label/value source and primary action.
- No static/fake trend percentage is displayed.
- Every KPI is sourced from a valid query/field; null or unavailable data uses a truthful empty/loading state.
- Operational cards contain real profile-specific data.
- Each tappable card/button opens its expected destination.
- Existing panels that were moved still exist and remain visible in the same page scroll (unless role/profile policy legitimately excludes them).
- Pull-to-refresh still triggers the loader.
- Backup, shift, eTIMS/import, customer-credit and profile-specific actions remain functional.

### 10.5 Large-font / responsive tests

Run widget/golden tests at:

- Widths: 320dp, 360dp, 375dp, 393dp, 430dp, 600dp, 840dp and 1200dp.
- Text scales: 1.0, 1.15, 1.3, 1.5, 1.8 and 2.0.
- Light and dark theme.
- English and Swahili.

Assert:

- No `RenderFlex` overflow exceptions.
- No horizontal dashboard scrolling unless the feature is inherently a horizontal carousel/table and already behaves that way.
- Hero amount, label, profile pill, tender chips and CTA remain visible.
- Cards change from multi-column to one column when width/text scale requires it.
- No text overlap, clipping, hidden CTA, inaccessible tooltip-only action, or tap target below 48dp.
- The page can scroll from header to the last existing panel and bottom nav does not cover the last action.

### 10.6 Profile switch regression

Test all directed changes between the four profiles (12 transitions):

- Picker opens from More.
- Picker opens from the redesigned dashboard switch action.
- Selected profile persists to the local database.
- AppState updates.
- Backend update failure leaves the app usable offline.
- Audit event is recorded once.
- Dashboard body, profile pill, profile accent, primary actions and navigation destinations update.
- A previous profile's detail screen cannot remain visible under the new profile if its route is no longer allowed.
- No stale async dashboard load overwrites the new profile's figures.

---

## 11. Manual smoke tests — real daily-operation flows

Perform these with seeded test data on a phone-sized device. Test owner and cashier separately where relevant.

### Duka smoke path

1. Open Duka dashboard; verify today's net sales, tender split and transaction count.
2. Tap New sale; add an item, change quantity, choose payment, complete sale, confirm receipt/result.
3. Return to dashboard; verify totals update after returning/refreshing.
4. Tap a low-stock item; verify correct product detail.
5. Receive stock; verify on-hand and stock ledger update.
6. Run stocktake; verify count variance and save path.
7. Open transaction list and customer balances; return with Back and confirm dashboard state.
8. Open shift detail; confirm current staff shift and cash/till actions are correct.

### Fashion smoke path

1. Open Fashion dashboard; verify layby and variant metrics.
2. Create a style with colour/size variants; open detail; edit a variant.
3. Open catalogue; confirm new style appears.
4. Start sale and choose the correct variant.
5. Create/open a layby, record deposit/payment and verify outstanding balance.
6. Open Exchanges and complete a valid exchange path; verify atomic return/replacement behavior.
7. Open a low-stock size/colour row and ensure it opens the correct product/variant.
8. Confirm Back from every detail returns to the expected list/dashboard.

### Drinks smoke path

1. Open Drinks dashboard; confirm hero sales and operational metrics.
2. Add a drink via the Drinks product form; verify unit/bottle/price fields and saved data.
3. Start a sale for packaged stock and complete payment.
4. Record a measured serving; verify units and stock decrement.
5. Open tank register, open a tank detail and confirm the same tank ID/data.
6. Use held-cart/parked-sale flow; verify it is still reachable and correctly labelled.
7. Confirm sales/shift/stock panels refresh and Back restores the correct dashboard.

### Open smoke path

1. Open Open dashboard; create a new job.
2. Open job details; edit the job; add a cost; verify the job's cost history.
3. Create a cost group; open details; associate it with job flows as currently supported.
4. Record a payment for a selected job; verify the right job receives the payment.
5. Create a linked sale using the job ID extra; verify the association is preserved.
6. Open receivables; open the correct customer/payment history.
7. Complete a job and verify completed-job revenue uses the defined date window.
8. Confirm net cash movement is not described as till float and no fake budget utilisation appears.

### Cross-profile and navigation smoke path

1. From each profile, use the header Switch business control; verify it opens the profile chooser rather than the owner account screen.
2. Switch profile through More as a second path; confirm both use the same underlying operation.
3. Navigate between Dashboard, Sell, Inventory/Open Business and Analytics; ensure each branch retains its existing stack.
4. Open More and test Help, Support, Marketplace, Notifications, Reports (where permitted), Settings (admin only), Laybys (Fashion only), and profile switching.
5. Use system Back from all pushed detail routes.
6. Cold-start the app on one parameterised product/tank/job/cost-group URL and confirm it reconstructs the correct detail without relying on `extra`.
7. Sign in as cashier; ensure Inventory/Settings/Reports/Portfolio restrictions hold and own-only Analytics remains own-only.

---

## 12. Commands and delivery gates

Run, in order:

```bash
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

If a command cannot run because of missing SDK/platform tooling, report the exact blocker and leave that gate marked **not run**. Do not say “all tests passed” when only a subset ran.

Before delivery, provide:

1. A list of every file changed and why.
2. A one-to-one checklist showing each companion patch number implemented, partially implemented, or not implemented.
3. A route manifest diff: route path, screen builder, profile gate, role gate, and test covering it.
4. A dashboard action matrix: visible control → callback → `Routes.*` destination/payload → access condition.
5. A list of preserved workflows verified manually for each profile.
6. A list of route-policy discrepancies found and how each was resolved.
7. Test command output/results, including all not-run items.
8. Screenshots of all four dashboards at 1.0 and 2.0 text scale, normal phone width and narrow 320dp width.
9. Any known remaining issue, with exact file/symbol and impact.
10. Confirmation that no route, menu item, feature screen, permission, migration, schema, offline path or business writer was removed or silently changed.

### Definition of done

The dashboard redesign is complete only when:

- all four profile dashboards visually follow the generated references in hierarchy and daily-use arrangement;
- all existing functions and all entitled routes remain reachable;
- every visible navigation control leads to a working, authorized destination;
- route guard, route registration, route builder, feature capability and UI shortcut agree;
- push/back, deep links, shell branch state and profile switching still work;
- sales, payment, stock, layby, pour, tank, job, cost, receivable and shift flows pass the smoke tests;
- data scope and permissions are unchanged;
- 200% text-scale layouts remain usable without clipping or overflow;
- all existing tests still pass and new regression tests pass;
- the delivery report is complete and honest about anything not run.

**Do not stop after the four screenshots look right. The app is only finished when the links behind those screenshots still take the user through the same correct business flows.**
