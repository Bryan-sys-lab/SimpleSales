# SimpleSales / Duka POS — Dashboard Redesign Implementation Patches (v79)

**Purpose:** an implementation handoff for the existing Flutter codebase in `duka_pos_app_source_v79.zip`. This is a structural dashboard redesign, not a colour-only theme pass. The four profile dashboards must reproduce the hierarchy and daily-operational feel of the generated Duka, Fashion, Drinks and Open references while retaining every existing business function, permission check, route, data scope, refresh path and offline behaviour.

**Do not treat generated mockup figures as real data.** The sample screenshots are visual references only.

---

## 0. Non-negotiable implementation rules

1. Do not replace, mock, seed or hardcode operational data to make a dashboard look populated.
2. Do not delete routes, navigation destinations, actions, permissions, database writes or workflows. A dashboard shortcut may move into the hero/action area, but the destination remains reachable through its existing route/navigation.
3. Preserve role and staff scope. A cashier must not see owner/manager totals or customer-wide balances merely because the new KPI layout has space.
4. Keep the current `RefreshIndicator` pull-to-refresh. Remove only the fake/duplicate refresh-looking business-switch affordance; the switch itself remains.
5. Remove the hardcoded “12.8% compared with previous day” badge. Do not show percentage trends until an actual previous-period comparison is calculated from the same date window, refund rules and staff scope.
6. Never label held/parked sales as “open tabs”. The existing Drinks analytics field called `openTabs` counts `held_carts` with `status='held'`; present it as **Held carts** or **Parked sales**.
7. Never call Open’s cumulative `cashInMinor - cashOutMinor` a till/cash-on-hand balance. Label it **Net cash movement** unless a real reconciled cash-position query is implemented.
8. Open’s current job-completion revenue is all-time. Add a date-bounded daily query before calling it “today”. Label it **Completed job revenue today**, not “cash collected today”.
9. Do not display a cost-pool utilisation percentage unless the application has a real per-job/per-pool budget and actual-cost denominator. Existing cost groups and job costs alone do not justify a percentage.
10. Do not use `FittedBox`, text shrinking, fixed-height KPI cards, clipped text or `maxLines: 1` ellipsising for important names/labels as a workaround for large system fonts.
11. Do not redesign `ShellNavBar`, `HomeShellTabs`, route visibility or role-based destination lists in this patch. The hero and quick actions are shortcuts, not replacements for navigation.
12. Keep financial semantic colours constant across profiles: success = paid/profit, danger = expenses/negative/refund/over-budget, warning = pending/credit/unsettled. Profile accent colours are only an additional identity layer.

## 1. Source map and current implementation to change

The relevant existing source files are:

- `lib/screens/dashboard_screen.dart` — shared retail-profile loading, `DashboardReady`, profile router, staff scoping and session-load guards.
- `lib/screens/dashboard_shared.dart` — `CompactBusinessHeader`, `FinancialHero`, `SupportingMetrics`, `QuickAction`, greeting helper.
- `lib/screens/dashboard_sections.dart` — `DashboardPanel`, `DashboardTopProducts`, `DashboardLowStockList`, shift, credit, hourly-sales and no-sales panels.
- `lib/screens/duka_dashboard_screen.dart` — Duka dashboard, `_DukaStockOverview`, `_DukaDashboardQuickActions`.
- `lib/screens/fashion_dashboard_screen.dart` — Fashion dashboard, `_FashionLowStockVariants`, `_FashionReservesOverview`, fashion quick actions.
- `lib/screens/drinks_dashboard_screen.dart` — Drinks-specific hero, stats, shift/stock/tank panels and actions.
- `lib/screens/open_dashboard_screen.dart` — independent Open loader, `_OpenBusinessHeader`, `_OpenFinancialHero`, operational overview and `_OpenQuickActions`.
- `lib/services/analytics.dart` — `DailyTotals`, `PaymentMixRow`, `DrinksAnalyticsSnapshot`.
- `lib/db/database_helper.dart` — `salesTotalsFor`, `salesByPaymentMethod`, `drinksAnalytics`, `getFinancialSums`, laybys and financial event queries.
- `lib/profile/shop_profile.dart` — `ShopProfile` enum. Reuse it; do not create a second profile enum.
- `lib/theme/app_colors.dart`, `lib/theme/app_spacing.dart`, `lib/theme/typography.dart`, `lib/ui/components/surface.dart` — existing theme and surface primitives. Extend dashboard-only styling without mutating global theme semantics.
- `lib/l10n/app_en.arb` and `lib/l10n/app_sw.arb` — source localisations. Do not edit generated localisation Dart manually.

### Current layout that must be replaced

- Duka and Fashion currently render `CompactBusinessHeader` → `FinancialHero` → `SupportingMetrics` → quick actions and operational modules. The hero is currently a sunken/light surface, not the forest-green hero in the reference.
- Drinks has a separate `_DrinksSalesHero` and `_DrinksStatsGrid` which duplicate the common hero/stats pattern, and the page’s action arrangement differs from the other profiles.
- Open uses `_OpenFinancialHero` with four money tiles in one `IntrinsicHeight(Row(...))`; this is unsafe on narrow screens and at large text scale.
- Retail headers display a time-based greeting and shop greeting sentence. Those strings consume space without helping the cashier decide what to do.
- Duka/Fashion/Drinks put the backup reminder before the main dashboard metrics. Keep the reminder, but do not let it displace the daily money summary.
- Duka’s `_DukaStockOverview` repeats stock value already suitable for a KPI; after moving stock value into the KPI grid, retain the total/low/out-of-stock counts in a stock-status panel so no information disappears.

---

## 2. PATCH 01 — Add a dashboard-only profile palette

**Create:** `lib/theme/dashboard_profile_palette.dart`

Do not change `AppColors` global primary/success/danger/warning values. Do not let switching a profile recolour the rest of the app, POS checkout, receipts or navigation. This palette is for dashboard profile markers and the thin top accent on profile-specific operational cards only.

Implement an immutable value object with these properties:

```dart
import 'package:flutter/material.dart';
import '../profile/shop_profile.dart';

@immutable
class DashboardProfilePalette {
  const DashboardProfilePalette({
    required this.accent,
    required this.tint,
    required this.ink,
  });

  final Color accent;
  final Color tint;
  final Color ink;

  static DashboardProfilePalette forProfile(
    ShopProfile profile, {
    required Brightness brightness,
  }) {
    final bool dark = brightness == Brightness.dark;
    return switch (profile) {
      ShopProfile.duka => DashboardProfilePalette(
          accent: Color(dark ? 0xFFF59E0B : 0xFFD97706),
          tint: Color(dark ? 0xFF3A2A12 : 0xFFFEF3C7),
          ink: Color(dark ? 0xFFFCDFA0 : 0xFF92400E),
        ),
      ShopProfile.fashion => DashboardProfilePalette(
          accent: Color(dark ? 0xFFE08E75 : 0xFFC26D53),
          tint: Color(dark ? 0xFF38241F : 0xFFFAF0EC),
          ink: Color(dark ? 0xFFFFC1AD : 0xFF7C3F2C),
        ),
      ShopProfile.drinks => DashboardProfilePalette(
          accent: Color(dark ? 0xFFFB923C : 0xFFEA580C),
          tint: Color(dark ? 0xFF3B2719 : 0xFFFFEDD5),
          ink: Color(dark ? 0xFFFFC18A : 0xFF9A3412),
        ),
      ShopProfile.open => DashboardProfilePalette(
          accent: Color(dark ? 0xFF38BDF8 : 0xFF0284C7),
          tint: Color(dark ? 0xFF142F3B : 0xFFE0F2FE),
          ink: Color(dark ? 0xFFA7E2FF : 0xFF075985),
        ),
    };
  }
}
```

Use `Theme.of(context).brightness` when creating the palette. Do not use the profile accent to colour profit/expense/credit semantics.

**Visual application:**
- Profile pill in the business header: `tint` background, `ink` text, profile icon, short localised profile name.
- Profile-specific operational cards: a 3dp-high `accent` strip at the top edge.
- Optional profile status indicators: `accent` only; do not recolour every icon, chart or button.
- Hero always remains forest green regardless of profile.

---

## 3. PATCH 02 — Add shared responsive dashboard layout helpers

**Add to:** `lib/screens/dashboard_shared.dart` (or a small new `lib/screens/dashboard_layout.dart` if you prefer to keep it isolated; do not duplicate helper logic per profile).

Use local `LayoutBuilder` constraints, not `MediaQuery.sizeOf(context).width` from the whole phone, for card grids. `PageGutter` and `AdaptivePage` already own outer page spacing; do not add a second global gutter.

Implement:

```dart
double dashboardTextScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.5).toDouble();

int dashboardGridColumns({
  required double availableWidth,
  required double textScale,
  required double minCellWidth,
  int maxColumns = 4,
  double gap = 12,
}) {
  final double requiredCellWidth = minCellWidth * textScale;
  final int count = ((availableWidth + gap) / (requiredCellWidth + gap)).floor();
  return count.clamp(1, maxColumns).toInt();
}

bool dashboardCanUseTwoColumns({
  required double availableWidth,
  required double textScale,
}) => availableWidth >= 840 && textScale <= 1.25;
```

KPI cards: `minCellWidth: 150`, `maxColumns: 4`. Quick action tiles: `minCellWidth: 150`, `maxColumns: 3`. Compact paired operational cards: `minCellWidth: 168`, `maxColumns: 2` so the Fashion/Drinks/Open reference layouts can use two compact panels on a normal phone; at text scale >1.25 those panels naturally become one column. Content-heavy Duka low-stock lists may remain full width instead of forcing a cramped half-width list. For a full dashboard two-column desktop split, use `dashboardCanUseTwoColumns` from a `LayoutBuilder` that wraps the dashboard body. At a large text scale, always fall back to one full-width column.

Use `Wrap` with computed child widths or a `GridView` with `shrinkWrap: true`, `NeverScrollableScrollPhysics`, and the calculated column count. The dashboard itself remains the single vertical scroll owner.

No fixed-height cards. Use natural `Column(mainAxisSize: MainAxisSize.min)` sizing and `minHeight` only where a tap target requires it. Important text must wrap.

---

## 4. PATCH 03 — Replace the dashboard header; remove greetings, keep scope and shift truth

**Modify:** `lib/screens/dashboard_shared.dart`.

Replace `CompactBusinessHeader` with a compact `DashboardBusinessHeader` (or change the existing class in place if that minimises imports). New constructor contract:

```dart
const DashboardBusinessHeader({
  required this.shopName,
  required this.profile,
  required this.shift,
  this.onSwitchBusiness,
  super.key,
});
```

The header must display, in a compact responsive `Wrap`:

- Shop name as the primary identity.
- Profile pill using `DashboardProfilePalette` (DUKA / FASHION / DRINKS / OPEN).
- Existing authoritative shift state from `Shift?`.
- Current date in a secondary text style.
- Business switch action if present, with `Icons.swap_horiz` or `Icons.storefront_outlined` — **not `Icons.refresh`**.

Remove the redundant “Current business” label row and time-of-day greeting. Do not remove `onSwitchBusiness`; it must still route to `Routes.profile`.

Remove `eyebrow` and greeting `subtitle` from the header API. In all three retail dashboards, replace:

```dart
CompactBusinessHeader(
  shopName: ...,
  eyebrow: timeOfDayWord(...),
  subtitle: data.greeting,
  ...
)
```

with the new header passing `profile: appState.shopProfile` and `shift: data.openShift`.

For Open, remove `_OpenBusinessHeader` and use the same header with `profile: ShopProfile.open` and the current shift only if the Open screen has an authoritative shift object. Do not invent one; otherwise render no shift chip.

Remove the unused `timeOfDayWord()` helper from `dashboard_shared.dart` and the duplicate local copy in `open_dashboard_screen.dart` only after confirming no remaining references.

Remove `DashboardReady.greeting`, `_greeting(...)`, its local `l10n`/staff-name reads and all constructor/copy-through arguments in `dashboard_screen.dart`. Preserve `scopeLabel`, `ownOnly`, session generation, `_loadSerial`, `_current(...)`, `ownStaffId(...)`, and staff-scoped queries. Greeting removal is a UI clean-up, **not** permission/scope simplification.

---

## 5. PATCH 04 — Create one shared forest-green money-first hero

**Add to:** `lib/screens/dashboard_shared.dart`.

Create `DashboardMoneyHero` and use it in Duka, Fashion, Drinks and Open. Its API should be profile-agnostic:

```dart
class DashboardMoneyHero extends StatelessWidget {
  const DashboardMoneyHero({
    required this.label,
    required this.amount,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    this.secondaryLine,
    this.scopeLabel,
    this.paymentMix = const <PaymentMixRow>[],
    this.onTransactions,
    super.key,
  });

  final String label;
  final Money amount;
  final String primaryActionLabel;
  final VoidCallback onPrimaryAction;
  final String? secondaryLine;
  final String? scopeLabel;
  final List<PaymentMixRow> paymentMix;
  final VoidCallback? onTransactions;
}
```

**Appearance:**
- Rounded 16–20dp forest-green surface, gradient `#0F3D2E` → `#16523E`.
- Main label in light mint/sage; primary amount in white, tabular figures, bold.
- Optional scope/transactions line below; it must be a truthful count/label, never a fake trend.
- Optional tender chips, only when the actual confirmed tender data exists. Render as translucent white pills; wrap to another line on narrow phones.
- High contrast white primary action button with forest-green label. Put it beside the amount at wide widths; stack it below at phone widths or text scale >1.25.
- No fixed height. Keep the amount text allowed to wrap rather than clipping.
- Use `PageGutter.card(context)` and existing `AppShapes`/`AppSpacing` primitives.

Remove the old hardcoded trend row from `FinancialHero` and `_DrinksSalesHero`. Do not replace it with a static `+14.2%`, sample percentage, green arrow or arbitrary comparison label.

### Hero content by profile

| Profile | Main label / value | Hero primary action |
|---|---|---|
| Duka | Net sales today / `data.totals.total` | New sale → existing `onOpenSell` |
| Fashion | Net sales today / `data.totals.total` | New sale → existing `onOpenSell` |
| Drinks | Net sales today / `data.totals.total` | New sale → existing `onOpenSell` |
| Open | Completed job revenue today / new date-bounded `job_completion` revenue | New job → `Routes.openJobNew` |

For Duka/Fashion/Drinks, include transactions count as a secondary line (the existing `DailyTotals.transactions` is receipt count, not item count). Include `scopeLabel` so a cashier can see that their displayed total is their own scope. For Open, do not display “cash collected” unless the selected financial event definition actually measures money received.

---

## 6. PATCH 05 — Add a common four-card KPI system

**Add to:** `lib/screens/dashboard_shared.dart`.

Create:

- `DashboardKpiTone` enum: `neutral`, `positive`, `expense`, `pending`, `info`.
- `DashboardKpiData`: `label`, `value`, `icon`, `tone`, optional `onTap`, optional accessibility label.
- `DashboardKpiGrid`: responsive grid using `dashboardGridColumns`.
- `DashboardKpiCard`: 36dp rounded icon badge plus label and value.

Tone mapping must use global semantic tokens from `AppColors.of(context)`:

| Tone | Text/icon | Badge background | Meaning |
|---|---|---|---|
| positive | `success` | `success` tint | paid / gross profit / positive movement |
| expense | `danger` | `danger` tint | expenses / outflow / negative value |
| pending | `warning` | `warning` tint | credit owed / layby / unsettled |
| info | existing info/blue semantic token | matching tint | stock / operation counts |
| neutral | `onSurface` | surface-muted tint | other measures |

Do not add a different success/warning/danger mapping for each profile. Values must use `formatMoney(Money.fromMinor(...))` for money; use plain counts with localised labels for counts.

Each KPI surface: white/theme surface, subtle border `#E2E8F0` in light mode, 12–16dp radius, 36dp icon badge, natural height, 12–16dp padding. Do not make cards clickable unless the supplied `onTap` leads to the correct existing feature. If a card is clickable, semantics must announce label and value.

Use 4 KPIs per profile at normal width. When text scale expands, reflow to 2 or 1 column; never shrink the amount to preserve four columns.

---

## 7. PATCH 06 — Add profile accent strips to shared operational cards

**Modify:** `lib/screens/dashboard_sections.dart`.

Add optional `Color? topAccent` to `DashboardPanel`. If null, render exactly as today. If non-null, add a 3dp high `ColoredBox(color: topAccent)` as the first child inside the clipped card, above the header. Ensure the card stays clipped to its existing rounded corners. Do not change default callers.

Add optional `Color? topAccent` to `DashboardTopProducts` and `DashboardLowStockList`, forwarding to `DashboardPanel`. This lets the profile's most important operational panels receive the profile accent without making every universal section coloured.

Text safety in `DashboardTopProducts`, `DashboardLowStockList` and their row widgets:
- Remove `maxLines: 1` + ellipsis from product names/variant labels where it truncates meaningful identity.
- Use a `Column` or `Wrap` at narrow width / large text scale so product name, SKU/variant and quantity can occupy separate lines.
- Preserve all row tap handlers and `View all` buttons.
- Keep the existing panel-header stack behaviour at width <360 or text scale >1.3.

---

## 8. PATCH 07 — Make the hero and KPIs the first operational content

Apply the same top-level sequence in the retail dashboards:

1. `DashboardBusinessHeader`
2. Existing `DashboardAttentionCard` (only when actionable; do not hide ETIMS/payment/import errors)
3. `DashboardMoneyHero`
4. `DashboardKpiGrid`
5. Backup reminder banner (only when due; still prominent, but after the money summary)
6. Profile-specific quick actions (no duplicate “New sale” because that is the hero CTA)
7. Profile-specific operational two-card row on wide screens; stacked on phones
8. Existing charts, stock/tank/shift/credit/recent sections not already represented by a KPI or operational card

The ordering is intentional: users should understand today’s money and start the most common workflow without scrolling. Operational information must remain in the page below. Do not hide lower sections behind a “More” accordion or remove them merely to shorten the screen.

At widths where the content can genuinely support it and text scale ≤1.25, place two operational cards side by side. At narrow phones or larger text, stack them.

---

## 9. PATCH 08 — Duka dashboard composition

**Modify:** `lib/screens/duka_dashboard_screen.dart`.

### KPI order

1. **Gross profit** — `data.totals.profitMinor`, positive tone. Label it “Gross profit” because `DailyTotals.profitMinor` is before operating expenses.
2. **Expenses** — `data.totals.expensesMinor`, expense tone.
3. **Stock value** — `data.stockValue`, info tone. Preserve its existing on-tap route to Inventory if the KPI is clickable.
4. **Credit owed** — `data.creditOwedMinor`, pending tone, only for owner/manager; navigate to the existing customer/credit ledger. For staff who cannot see customer-wide balances, replace this fourth tile with **Transactions** (`data.totals.transactions`) rather than showing a zero credit figure.

### Composition

- Hero: `DashboardMoneyHero`, label `dashboardNetSalesToday`, value `data.totals.total`, transaction count and scope, button `New sale`.
- KPI grid follows hero.
- Remove the Sell tile from `_DukaDashboardQuickActions`; the hero is the primary New sale entry. Keep Add product, Receive stock and Stocktake with their existing capability/permission gates and existing callbacks.
- First operational pair: `DashboardLowStockList` (amber top accent) + `DashboardTopProducts` (amber top accent). Keep `View all` → Inventory and row tap → Product detail. Use exact current `data.lowStock`, `data.lowStockCount` and `data.topProducts` data.
- Keep `_DukaStockOverview`, but remove its duplicate Stock Value tile because stock value is now a KPI. It must continue to show **Total products**, **Low stock**, and **Out of stock** counts. This is not redundant: it tells the owner how broad the inventory issue is. Keep its Inventory link.
- Keep the hourly sales chart, loose-goods/tank cards, shift card, credit/customer route where not duplicated, attention card, backup action and all existing callbacks.
- If the fourth KPI is Credit owed for owner/manager, do not also show a second identical credit summary card lower on the page. If the lower card includes useful information beyond amount/count, retain that additional information without repeating the same total twice.

### Responsive arrangement

- On large screens, use a left content column for hero/KPIs/actions and an operational area with low stock/top products side by side; preserve shift and other panels in the right/secondary stack.
- On phones and when `textScale > 1.25`, stack everything in the order above.
- Do not base the decision only on `MediaQuery.sizeOf(context).width`; use local `LayoutBuilder` constraints.

---

## 10. PATCH 09 — Fashion dashboard composition

**Modify:** `lib/screens/fashion_dashboard_screen.dart`.

### KPI order

1. **Gross profit** — `data.totals.profitMinor`, positive tone.
2. **Expenses** — `data.totals.expensesMinor`, expense tone.
3. **Transactions** — `data.totals.transactions` (receipt count; do not label as units/items sold).
4. **Low-stock variants** — `data.lowStockVariants.length`, warning tone; tap through to the existing Inventory/Catalogue route if there is an authorised destination.

Do not claim “best-selling sizes” unless there is an actual aggregation of sale quantities grouped by variant size. Existing `topProducts` may be product-level sales; title it **Top-selling styles** or **Top products** according to the returned data, not “Best-selling sizes”.

### Composition

- Hero: shared forest-green `DashboardMoneyHero`, Net sales today and New sale.
- KPI grid directly below hero.
- Keep `_FashionDashboardQuickActions` but remove its duplicate Sell tile. Keep New Layby, Catalogue, Add product/style, Receive stock and all existing route/permission checks.
- Operational pair: `_FashionReservesOverview` with fashion accent + `_FashionLowStockVariants` with fashion accent. These are the two panels the owner needs to act on first: uncollected/reserved stock and size/colour variants that are running out.
- In `_FashionReservesOverview`, add the sum of outstanding balance for `LaybyStatus.open` records already fetched by `_load()` (`sum += layby.balance.minorUnits` only for open laybys). Display it as **Layby balance** inside that panel; do not add a second query or add a duplicate layby KPI. Keep counts for open, awaiting payment and ready for collection. Existing route to `Routes.laybys` remains.
- Keep ordinary product low-stock list, hourly-sales chart, top-selling products, shift panel, manager/owner credit visibility and attention/backup functions.
- In `_FashionLowStockVariants` and `_VariantRow`, remove ellipsis/truncation of style, colour and size. Use a vertical row layout if required. Do not reduce text scale.

### Access control

Do not expose layby balances or the customer-wide credit panel to unauthorised staff if those are owner/manager scoped. If existing layby route has its own restrictions, preserve them; do not assume a hidden card is a permission check.

---

## 11. PATCH 10 — Drinks data and dashboard composition

**Modify:** `lib/screens/dashboard_screen.dart`, `lib/screens/dashboard_shared.dart`, `lib/screens/drinks_dashboard_screen.dart`, and `lib/services/analytics.dart` only as required.

### Load existing Drinks analytics into `DashboardReady`

`DrinksAnalyticsSnapshot` already exists and includes measured litres, pour sales/cost, measured lines, held carts, tank levels, waste litres/value and dip variance. Add to `DashboardReady`:

```dart
this.drinksAnalytics = DrinksAnalyticsSnapshot.empty,
this.paymentMix = const <PaymentMixRow>[],

final DrinksAnalyticsSnapshot drinksAnalytics;
final List<PaymentMixRow> paymentMix;
```

In `_DashboardScreenState._load()` call `db.drinksAnalytics(since: dayStart, until: tomorrow, staffId: staffId)` only when `appState.shopProfile == ShopProfile.drinks`; otherwise use `DrinksAnalyticsSnapshot.empty`. Put the call in the same awaited load batch as other dashboard aggregates, or execute it concurrently with the existing `Future.wait`. Preserve the `sessionGeneration`, `_loadSerial` and `_current(...)` checks before committing the result.

Important: the current early branch for `products.isEmpty && !totalsAll.hasSales` must not skip this profile-specific query. Either remove the special fast-return branch and allow the normal batch to load its empty-but-real aggregates, or explicitly load the profile-specific aggregates in that branch too. Do not leave a Drinks dashboard unable to show held carts/tank state just because no completed sale has happened yet.

### Drinks KPI order

1. **Gross profit** — `data.totals.profitMinor`.
2. **Expenses** — `data.totals.expensesMinor`.
3. **Measured volume sold** — `data.drinksAnalytics.litresSold` with an appropriate litres formatter.
4. **Waste value** — `data.drinksAnalytics.wasteValueMinor` (only when waste tracking is populated; if no waste records exist, render a factual zero or a neutral “No waste recorded” state, never a sample value).

Do not show `data.drinksAnalytics.openTabs` as “Open tabs”. It is held/parked carts. Do not call `pourSalesMinor - pourCostMinor` “gross profit” because global `DailyTotals.profitMinor` is the reconciled gross profit and other sales types may be included. If you show the pour-only difference, label it **Measured-pour contribution** and derive it from those same two fields.

### Composition

- Replace `_DrinksSalesHero` with shared `DashboardMoneyHero`, New sale action.
- Replace `_DrinksStatsGrid` with shared `DashboardKpiGrid`.
- Create a Drinks operational card titled **Held carts** / **Parked sales** using the actual snapshot count. Link only if the target screen actually opens/loads the held cart list; otherwise render a non-clickable count and retain the existing Sell entry point.
- Pair it with **Tank & beverage stock** using current `data.tanks`, `data.tankSales`, `_TankCards` and existing product stock panels. Do not invent tabs, table numbers, poured drinks or happy-hour features.
- Keep the serving/pour action (`Routes.servings`), add beverage/product action with its profile/permission gate, close-shift route, ordinary reorder, hourly sales, top products, tanks, credit and attention. Move the duplicate New sale action into the hero; retain the existing route from the Sell navigation destination.
- Use Drinks orange accent only on Held carts and Tank/stock panel top strips.

---

## 12. PATCH 11 — Make tender chips accurate (not based on the wrong aggregate)

The existing `salesByPaymentMethod()` groups `sales.payment_method`. This is insufficient for the reference’s Cash + M-Pesa split because a sale with split tender has `payment_method = 'split'` and its actual component amounts are in `sale_payments`.

**Add to `DatabaseHelper` in `lib/db/database_helper.dart`:**

```dart
Future<List<PaymentMixRow>> salesTenderMix({
  required DateTime since,
  DateTime? until,
  int? staffId,
}) async {
  final where = <String>[
    's.created_at >= ?',
    "sp.status = 'confirmed'",
    's.payment_verified = 1',
  ];
  final args = <Object?>[since.toIso8601String()];
  if (until != null) {
    where.add('s.created_at < ?');
    args.add(until.toIso8601String());
  }
  if (staffId != null) {
    where.add('s.staff_id = ?');
    args.add(staffId);
  }
  final rows = await (await database).rawQuery('''
    SELECT sp.method AS method,
           CAST(COALESCE(SUM(sp.amount_minor), 0) AS INTEGER) AS sales_minor,
           COUNT(DISTINCT s.id) AS transactions
      FROM sale_payments sp
      JOIN sales s ON s.id = sp.sale_id
     WHERE ${where.join(' AND ')}
     GROUP BY sp.method
     ORDER BY sales_minor DESC, sp.method ASC
  ''', args);
  return rows.map((row) => PaymentMixRow(
    method: row['method'] as String? ?? 'cash',
    salesMinor: (row['sales_minor'] as num?)?.toInt() ?? 0,
    transactions: (row['transactions'] as num?)?.toInt() ?? 0,
  )).toList();
}
```

Confirm actual `sales.payment_verified` and `sale_payments.status` schema before finalising the query. The existing migrations populate `sale_payments` for old records and mark unverified legacy tender as `unverified`; use confirmed tender rows only. Verify that split and non-split sales both have sale-payment rows after migrations. If any supported old database can still lack rows, implement a fallback for sales with no `sale_payments` child rows using `sales.payment_method`/`sales.total` and exclude those sale IDs from the tender subquery to avoid double counting.

Add `salesTenderMix(since: dayStart, until: tomorrow, staffId: staffId)` to the retail dashboard load and store the result in `DashboardReady.paymentMix`. Pass it into `DashboardMoneyHero` and render chips only for actual returned rows. Do not render fixed Cash/M-Pesa chips when a method has no amount.

**Important display rule:** these chips represent confirmed tender mix. Since refunds are subtracted from `DailyTotals.total`, chip totals may not equal net sales after refunds. Label them “Payments received” or “Tender mix”, not “Net sales split”. Do not assert that they sum to the hero value.

Add database tests for:
- Cash-only sale.
- M-Pesa-only sale.
- Split cash + M-Pesa sale.
- Unverified/pending payment excluded.
- Staff ID filter applied.
- Date `since` inclusive and `until` exclusive.
- Sale with no `sale_payments` row handled via fallback if the codebase supports that legacy state.

---

## 13. PATCH 12 — Open profile: correct financial definitions and rebuild the hero

**Modify:** `lib/screens/open_dashboard_screen.dart` and `lib/db/database_helper.dart`.

### Date-bounded financial event sums

Extend `getFinancialSums` without breaking existing callers:

```dart
Future<({int revenueMinor, int cashInMinor, int cashOutMinor})>
    getFinancialSums({
  String? eventType,
  DateTime? sinceUtc,
  DateTime? untilUtc,
}) async {
  final where = <String>[];
  final args = <Object?>[];
  if (eventType != null) {
    where.add('event_type = ?');
    args.add(eventType);
  }
  if (sinceUtc != null) {
    where.add('occurred_at_utc >= ?');
    args.add(sinceUtc.toUtc().toIso8601String());
  }
  if (untilUtc != null) {
    where.add('occurred_at_utc < ?');
    args.add(untilUtc.toUtc().toIso8601String());
  }
  final rows = await (await database).rawQuery(
    'SELECT COALESCE(SUM(revenue_minor), 0) AS revenue, '
    'COALESCE(SUM(cash_in_minor), 0) AS cash_in, '
    'COALESCE(SUM(cash_out_minor), 0) AS cash_out '
    'FROM financial_events'
    '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}',
    args.isEmpty ? null : args,
  );
  ... // preserve the existing return record construction
}
```

Use existing column `occurred_at_utc` and existing UTC normalisation convention used by `getFinancialEvents`; do not use a local timestamp column. Check the schema field exists and tests cover UTC boundaries.

In `_OpenDashboardScreenState._load()` compute local day start and next day, then call:

- All-time `job_completion` sums for existing revenue-to-date reporting.
- Today’s `job_completion` sums with `sinceUtc: dayStart.toUtc()` and `untilUtc: tomorrow.toUtc()` for the hero.
- Preserve current completed-job cost/profit logic, credit summary and job/pool status queries.

Do not change the existing meaning of `_revenueMinor` without checking all downstream labels; introduce a separate `_revenueTodayMinor` and clear it in `clearForSession()`.

### Open hero and KPI cards

- Replace `_OpenFinancialHero` with shared `DashboardMoneyHero` using label **Completed job revenue today**, amount `_revenueTodayMinor`, and action **New job** → `Routes.openJobNew`.
- Follow with KPI grid (only when `canSeeShopMoney` is true):
  1. Revenue to date — existing `_revenueMinor`.
  2. Net profit to date — existing `_netProfitMinor`; preserve its current calculation semantics and label it accordingly.
  3. Net cash movement — existing `_cashPositionMinor = cashIn - cashOut`; rename everywhere from “Cash position”/“Till balance” so users do not read it as money physically in a drawer.
  4. Receivables — `_receivablesMinor`.
- Preserve `canSeeShopMoney = owner || manager`; cashiers must not see this grid or hero money fields if those figures are not staff-scoped.
- Keep the operational overview with Active jobs, Awaiting payment, Overdue jobs and Cost groups. Keep existing status routes. Do not imply cost-pool health/utilisation in percent when there is no stored budget denominator.
- Rename the recent activity title to **Recent jobs** if the rows remain `_recentJobs`; do not imply the list contains all system activity.
- Keep New Job, Record Payment, Record Sale, Add Job Cost, New Cost Group and Add Item actions under their existing permissions.
- Add `required bool canRecordOwnerFinance` to `_OpenQuickActions`; include Owner finance only when `appState.isOwnerSession`. Keep the guard inside `_recordOwnerTransaction` as a second line of defence. Currently the button is included for everyone and only fails after tap; fix the discoverability/permission presentation without removing the action for owners.
- Do not force a cashier to see a blank green financial hero. If `canSeeShopMoney` is false, show the header, operational job cards and permitted actions at the top of the page.

### Open responsive layout

Replace `_OpenFinancialHero`’s four-way `IntrinsicHeight(Row(...))` layout. Shared hero + adaptive KPI grid must wrap 4 → 2 → 1 columns based on actual constraints and text scaler. Do not use a horizontal scroll list for core money metrics.

---

## 14. PATCH 13 — Remove duplicate/obsolete components only after their data is relocated

After all four dashboards use the shared hero and KPI grid:

- Remove `FinancialHero` and `SupportingMetrics` from `dashboard_shared.dart` only after grep confirms no callers remain.
- Remove `_DrinksSalesHero` and `_DrinksStatsGrid` only after the Drinks screen uses shared components.
- Remove `_OpenFinancialHero` and `_OpenBusinessHeader` only after Open uses shared components.
- Remove `timeOfDayWord` helpers only after no references remain.
- Keep `QuickAction` if still used; do not delete blindly.
- Keep `DashboardReady.scopeLabel`, `openShift`, `expectedTill`, all attention fields and stock/tank/credit fields.
- Do not remove `_DukaStockOverview` until `totalProducts`, low-stock and out-of-stock counts have an explicit new destination. The required new destination is the stock-status panel (not the money KPI grid).

The user explicitly requires that moved features remain findable. If any widget is retired, add its data to the intended destination and update tests before deleting the original.

---

## 15. PATCH 14 — Dashboard information architecture (exact daily-use order)

### Duka

1. Header: shop name + Duka pill + shift state + business switch.
2. Actionable attention (ETIMS/import/payment) if present.
3. Forest-green Net sales today hero + New sale.
4. Four KPIs: Gross profit, Expenses, Stock value, Credit owed (or Transactions for roles without credit-balance access).
5. Backup reminder if due.
6. Quick actions: Add product, Receive stock, Stocktake (each existing permission-gated); no duplicate Sell action.
7. Two operational cards: Stock needing attention + Top-selling items.
8. Stock status (total products, low stock, out of stock; no duplicated stock value).
9. Hourly sales, loose-goods/tank items, shift and any remaining useful credit detail.

### Fashion

1. Header: shop name + Fashion pill + shift state + switch.
2. Actionable attention.
3. Net sales today hero + New sale.
4. KPIs: Gross profit, Expenses, Transactions, Low-stock variants.
5. Backup reminder if due.
6. Quick actions: New layby, Catalogue, Add product/style, Receive stock (existing gates); no duplicate Sell.
7. Two operational cards: Laybys/reserves + Low-stock variants.
8. Ordinary stock, Top-selling styles/products (accurately named), hourly sales, shift and permitted credit details.

### Drinks

1. Header: shop name + Drinks pill + shift state + switch.
2. Actionable attention.
3. Net sales today hero + New sale.
4. KPIs: Gross profit, Expenses, Measured volume sold, Waste value.
5. Backup reminder if due.
6. Quick actions: Record pour/serving, Add beverage/product (existing capability/permission), Close shift (existing route); no duplicate Sell.
7. Two operational cards: Held carts/Parked sales + Tank & beverage stock.
8. Beverage stock, tanks, hourly sales, Top products, shift and permitted credit.

### Open

1. Header: shop name + Open pill + business switch.
2. Actionable attention/errors.
3. If owner/manager: Completed job revenue today hero + New job.
4. If owner/manager: four KPIs Revenue to date, Net profit to date, Net cash movement, Receivables.
5. Operational cards: Jobs requiring attention + Cost groups (no fake budget percentage).
6. Quick actions per existing permissions, including Owner finance only for owner.
7. Recent jobs.
8. Backup reminder if due, in a visible location below the primary information.

At small screen sizes the cards become a single vertical stack, preserving this order.

---

## 16. PATCH 15 — Accessibility and large-font hardening

Apply these checks to every new/modified dashboard widget:

- Use `LayoutBuilder` at the widget’s own available width.
- Use the shared text-scale-aware column helper.
- Let labels and values wrap. Long product names, layby/customer names, style names, job titles and button labels must remain visible.
- No hardcoded width for labels. No `Row` with two unbounded text children. Use `Expanded` only when the sibling can wrap and the text can occupy multiple lines; otherwise switch to `Column`/`Wrap`.
- Do not use fixed card heights. Do not clip the hero amount. Use natural height and responsive hero action stacking.
- Keep minimum interactive target at least `AppSpacing.minTapTarget` (44–48dp per existing theme convention).
- Add `Semantics` for KPI label + value and action labels. Do not let a decorative icon be announced separately if the card already has a combined label.
- Test text scale at 1.0, 1.3, 1.5 and 2.0. Test widths 320, 360, 390, 600, 840 and 1200 logical pixels.
- Test both light and dark themes. Dark theme uses the same profile identity but the dark tint/ink values from `DashboardProfilePalette`; the forest hero retains high contrast.
- Keep text selection / copy behaviour wherever the existing widget supports it.

---

## 17. PATCH 16 — Localisation

Add any new visible strings to both `lib/l10n/app_en.arb` and `lib/l10n/app_sw.arb`. At minimum audit/add keys for:

- `dashboardProfileDuka`, `dashboardProfileFashion`, `dashboardProfileDrinks`, `dashboardProfileOpen` (reuse existing profile translations if they already exist; do not create duplicate keys unnecessarily).
- `dashboardNewSale`, `dashboardNewJob` (reuse existing localized sale/job action labels where exact semantics match).
- `dashboardGrossProfit`, `dashboardExpenses`, `dashboardTransactions`, `dashboardStockStatus`, `dashboardHeldCarts`, `dashboardParkedSales`, `dashboardMeasuredVolume`, `dashboardWasteValue`, `dashboardLaybyBalance`, `dashboardNetCashMovement`, `dashboardRevenueToDate`, `dashboardCompletedJobRevenueToday`, `dashboardRecentJobs`, `dashboardPaymentsReceived`.
- Any new semantics for “Low-stock variants”, “Top-selling styles”, “Awaiting payment”, “Ready for collection”.

Do not hardcode English strings in new widgets. Run the project’s localisation generation command (`flutter gen-l10n` or repository wrapper) and include generated Dart changes if generation is part of the repo workflow. Do not manually edit generated localisations.

Remove or deprecate `dashboardVersusPreviousDay` only after grep confirms no widget uses it. Its current English and Swahili values are hardcoded `12.8% compared with previous day`; do not leave it displayed.

---

## 18. PATCH 17 — Tests and regression gates

Add/update widget tests under `test/screens/` (create `dashboard_profile_layout_test.dart` and `dashboard_text_scale_test.dart` if no suitable existing file exists) and database tests under `test/`.

### Widget/visual tests

For each profile, render the dashboard at 320/360/390/600/840/1200 widths and text scales 1.0/1.3/1.5/2.0, in both light and dark themes. Assert:

- Header displays shop name, correct profile pill, authoritative shift if present and working switch callback.
- Hero is the first financial surface, uses the forest-green gradient, displays the actual metric label/value and primary action.
- No static `12.8%` or fake trend badge appears.
- KPI cards reflow rather than overflow; no `RenderFlex overflow` exceptions.
- Operational cards stack at large font scale and retain their contents and routes.
- Action labels remain visible and wrap; action callbacks still fire.
- No greeting/refresh-looking switch icon appears.
- Profile accent differs by profile, while profit/expense/pending semantic tones remain the same across all profiles.

### Role/scope tests

- Cashier sees only staff-scoped totals and no whole-shop credit/financial KPIs.
- Manager/owner sees permitted business-wide KPIs.
- Profile switching still opens existing profile screen.
- Owner finance quick action only appears in owner session; underlying function still checks owner session.
- Inventory/stock/receiving/stocktake actions continue to honour their existing permission keys.
- Session changes during dashboard loading cannot leave old-session figures on the screen. Preserve and test the existing `_loadSerial`, `sessionGeneration` and `_current` guard.

### Database/data tests

- Tender mix correctly counts split-tender cash and M-Pesa amounts, excludes unverified tender and respects staff/date scope.
- Drinks snapshot query remains date and staff scoped for measured volume; held carts are labelled as held carts, not tabs.
- Open `getFinancialSums` with `sinceUtc`/`untilUtc` returns correct UTC-bounded totals and existing callers without dates remain unchanged.
- Open daily job-completion revenue is distinct from all-time revenue and does not get labelled as cash collected.
- Fashion layby sum equals the sum of outstanding balances of open laybys only; closed/completed/cancelled laybys are excluded.

### Existing regression suites

Run the full existing Flutter test suite, especially:
- `test/screens/dashboard_attention_e2e_test.dart`
- `test/ui/dashboard_hourly_test.dart`
- `test/analytics_test.dart`
- `test/database_helper_test.dart`
- shift/session/permission tests.

Then run `dart format` on changed Dart files, `flutter analyze`, generated localisation checks, and the project’s normal Android build/test command. Do not claim completion if any command was not run; report unavailable tooling explicitly.

---

## 19. Acceptance checklist — do not mark complete until all are true

- [ ] The four dashboards look like a coherent product family but have four genuinely different operational content arrangements.
- [ ] The green money-first hero exists on all four profiles; Open hero’s daily revenue is date-bounded job-completion revenue.
- [ ] Profile badge/accent is Duka amber, Fashion terracotta, Drinks orange, Open blue.
- [ ] Financial semantic colours remain unchanged across profiles.
- [ ] Four adaptive KPI cards appear per profile when the user has permission to see those figures.
- [ ] No hardcoded “12.8% compared with previous day” remains visible.
- [ ] Payment mix chips, if present, use confirmed amounts from `sale_payments` and account for split tender.
- [ ] Held carts are not called open tabs.
- [ ] Cash-in-minus-cash-out is not called cash position/till balance.
- [ ] No fabricated cost-pool budget utilisation percentage exists.
- [ ] Backup reminder remains reachable and pull-to-refresh still works.
- [ ] No dashboard action, route, stock metric, chart, shift, credit workflow, job workflow or role check has silently disappeared.
- [ ] Owner-only financial metrics and Owner Finance remain correctly gated.
- [ ] The app has no layout overflow at 320dp width / 200% font scale.
- [ ] All widget/database tests and analysis/build checks are run and reported.

## 20. Required agent delivery report

After implementation, report:

1. Every file changed and the reason.
2. Every widget moved/retired and where its data/action now appears.
3. Any item that could not be implemented because the data model does not support it.
4. Tests run and exact pass/fail results.
5. Any permission/session/data-scope behaviour intentionally left unchanged.
6. Screenshots of each of the four profiles at 390dp / 100% and 390dp / 200% text scale, plus one wide-screen view.

**Important:** Do not return only a redesigned screenshot. The deliverable is the working Flutter implementation in the actual v79 source.
