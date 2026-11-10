# SimpleSales Design System

The single source of truth for every SimpleSales surface: shared brand, semantic color, typography, spacing, shape, elevation, navigation, accessibility, motion, and interaction rules — plus four profile addenda (Drinks, Duka, Fashion, Open).

This document describes what the live widgets do. Do not write aspirational rules that implementation contradicts. If a rule changes, update this file in the same pull request.

---

## 1. Project overview

| Field | Value |
|---|---|
| **Product name** | SimpleSales |
| **Surface profile** | App/Product UI — Mobile/Native (Flutter) |
| **Platform** | Android (Flutter mobile app) |
| **Profiles** | Drinks, Duka, Fashion, Open |
| **Target users** | Shop owners, bar staff, till operators, field service workers |
| **Main design goal** | One SimpleSales identity. One emerald action language. Four purpose-built business experiences. Make the next correct business action obvious. |

---

## 2. Brand direction

**Visual style:** Precision instrument — calm, considered, practical. Bottled emerald as the single brand accent; cool green-neutral ramp; 16dp card radius; no decorative gradients on content cards; no glassmorphism; no persistent pulsing.

**Mood & tone:** Confident but unflashy. A tool for working, not a marketing page.

**Design personality:** Corporate-clean / practical-instrument. Legible at a glance, fast to tap, no decoration that doesn't earn its place.

**Design concept (one sentence):** A till dashboard that feels like precision instrumentation — emerald accent on a cool green-neutral ramp, tabular figures everywhere, one dominant number (today's sales or equivalent) and a clear path to the next action.

**Reference style:** SimpleSales profile mockups — green-tinted hero with eyebrow label, two-stat grid below hero, shift overview as actionable rows, icon badges with text labels, full-width primary action at the bottom of the action zone, bottom navigation with visible labels and non-color-only selected state.

**Voice & UX copy:** Plain, verb-first CTAs ("+ Start a sale", "Record measurement", "Receive stock", "New job"). Empty states explain the next action; errors say what happened + how to fix. Real or honestly-marked mock data only — no "Acme / John Doe / Lorem ipsum".

---

## 3. Color system

### 3.1 Approved semantic palette

Every color maps to a role. Use only these values. Place every literal in `lib/theme/primitives.dart`; expose them only through `AppColors` in `lib/theme/app_colors.dart`. Widgets must never import `Primitives` directly or use raw `Color(...)` literals for app UI.

#### Light appearance

| Role | Hex | Usage |
|---|---|---|
| Canvas | `#F6F8F6` | App/page background; lightly green-neutral, not cream |
| Surface | `#FFFFFF` | Cards, sheets, standard content surfaces |
| Sunken surface | `#EDF2EE` | Inputs, selected control tracks, recessed wells |
| Raised surface | `#FFFFFF` | Dialog/menu surface |
| Primary text | `#14251A` | Main headings, money, product names, primary icons |
| Secondary text | `#4E5F54` | Supporting labels, explanatory text |
| Muted text | `#607067` | Timestamps, secondary metadata only — remains AA on canvas |
| Decorative outline | `#E2E9E3` | Quiet divider/card edge where spacing establishes grouping |
| Meaningful outline | `#64766A` | Input edges, focus/selected boundaries, controls that must be found |
| Brand/action accent | `#087A45` | Primary CTA, active navigation, action emphasis |
| On accent | `#FFFFFF` | Text/icons on solid light accent |
| Accent container | `#E6F4EA` | Selected/brand-tinted low-emphasis surface |
| On accent container | `#0D3D1E` | Text/icons on accent container |
| Success | `#1A7A3A` | Verified successful/completed/healthy state |
| Success container | `#DCEFE1` | Success background — visibly distinct from accent selection |
| On success container | `#0D4D1E` | Text/icons on success container |
| Warning | `#8A6508` | Warnings and attention state |
| Warning container | `#FFF3E0` | Warning background |
| Danger | `#C0392B` | Errors, destructive actions, rejected/failed state |
| Danger container | `#FDEDEA` | Error/destructive background |
| Info | `#1A6BAA` | Neutral informational state only |
| Info container | `#E5F2FC` | Informational background |

#### Dark appearance

| Role | Hex | Usage |
|---|---|---|
| Canvas | `#0D1510` | App/page background; charcoal with subtle green undertone |
| Surface | `#17231B` | Primary card/list/dialog base |
| Sunken surface | `#111B14` | Recessed inputs and control tracks |
| Raised surface | `#202D25` | Menus, dropdowns, elevated sheets, nested overlays |
| Primary text | `#F1F7F2` | Main headings, money, product names, primary icons |
| Secondary text | `#D0DBD2` | Supporting labels, explanatory text |
| Muted text | `#B1C0B5` | Secondary metadata only |
| Decorative outline | `#314137` | Quiet divider/card edge |
| Meaningful outline | `#77877D` | Inputs, selected boundaries, focus indicators |
| Brand/action accent | `#30C879` | Primary CTA, active brand/action emphasis |
| On accent | `#062516` | Text/icons on the brighter dark-theme accent |
| Accent container | `#193C29` | Low-emphasis selected/brand surface |
| On accent container | `#B9F0D0` | Text/icons on accent container |
| Success | `#5CE68A` | Verified successful/completed/healthy state |
| Success container | `#123520` | Success background — distinct from accent container |
| On success container | `#8DE8AE` | Text/icons on success container |
| Warning | `#FFB84D` | Warnings and attention state |
| Warning container | `#3A2A0C` | Warning background |
| Danger | `#FF6B5B` | Errors, destructive actions, rejected/failed state |
| Danger container | `#3A1814` | Error/destructive background |
| Info | `#6AB0F5` | Neutral informational state only |
| Info container | `#123047` | Informational background |

#### High-contrast variants

High-contrast light/dark palettes are declared as `AppColors.highContrastLight()` and `AppColors.highContrastDark()`. They use stronger boundaries (`outlineStrong`), deeper canvas/surface separation, and clearer selected-state differentiation. Platform-driven high contrast (`MediaQuery.highContrastOf`) is applied automatically; no fourth appearance mode is added.

### 3.2 Role definitions

| Role | Meaning | Example usage |
|---|---|---|
| Brand accent | SimpleSales brand and primary action | Main Sell/Confirm action, brand mark |
| Profile identity | Which business mode is active | Profile badge, small icon surface, subtle hero tint |
| Selected state | Current tab/filter/segment | Selected row, selected chip, active destination |
| Success | Completed/healthy state | Paid, synced, saved, shift open (only when true) |
| Warning | Attention needed | Low stock, backup overdue, pending action |
| Danger | Destructive/failed state | Delete, rejected payment, critical error |
| Info | Neutral information | Tips, explanatory status |
| Provider identity | Actual payment provider | M-Pesa, Airtel Money, Equitel, cash |
| Disabled | Unavailable control | Disabled button/text/input state |
| Focus | Keyboard/switch-access focus | Focus ring and active control indication |

**Never reuse the same color treatment for two different meanings where users need to tell them apart.** Selection and success both use green-family tones — distinguish them with background tone, border, label, icon, and component structure. AccentContainer (selection) ≠ SuccessContainer (confirmation).

### 3.3 Provider identity colors

M-Pesa, Airtel Money, Equitel, and cash identity colors live in provider-specific slots only. Never reuse provider colors as generic success/info/profile accents.

---

## 4. Typography system

**Brand personality:** Corporate-clean / practical-instrument

**Font family / pairing:** Plus Jakarta Sans (bundled variable font, 200–800 axis), fallback Roboto / Noto Sans. Tabular figures on every number a user compares vertically.

**Type scale (named steps + exact values):**

| Step | Size | Weight | Usage |
|---|---|---|---|
| displaySmall | 28px | w800 | One dominant figure per screen (today's sales, total) |
| headlineSmall | 22px | w700 | Screen titles |
| titleLarge | 18px | w700 | Section/card titles |
| titleMedium | 15px | w700 | Card titles, section headings |
| bodyLarge | 15px | w400 | Body text, operational content |
| bodyMedium | 14px | w400 | Body text — never below 14px effective on mobile |
| bodySmall | 12px | w400 | Captions, timestamps, tertiary metadata only |
| labelLarge | 14px | w700 | Buttons |
| labelMedium | 13px | w600 | Navigation labels, form labels |
| labelSmall | 11px | w600 | Chips, small badges — tertiary metadata only |

**Rules:**
- Navigation labels use `labelMedium` (13px), never `labelSmall` (11px)
- Section headings use `titleMedium` (15px), sentence case — never uppercase micro-labels
- `bodySmall` (12px) and `labelSmall` (11px) only for nonessential tertiary metadata, never for the only way to understand an action or important state
- Critical stock quantity, prices, payment state, and error/status information must remain clearly legible (14px+)
- Dynamic Type/text scaler and bold-text settings must continue to work. Test 1.0x, 1.3x, 1.5x, 2.0x; allow card and row height to grow instead of clipping/truncating
- Tabular figures on all monetary totals, prices, quantities, aligned financial columns
- Never ellipsize a price, balance, outstanding amount, or stock quantity as the only visible value

---

## 5. Layout system

**Spacing rhythm:** 4/8-point scale. Avoid one-off values. Compact: 16dp page gutter, 16dp card inset. Medium/large: 20–24dp card inset. 32dp only for spacious desktop layouts where measured content width supports it.

| Component | Compact | Medium/Large | Spacious |
|---|---|---|---|
| Page gutter | 16dp | 20–24dp | up to 32dp |
| Card inset | 16dp | 20–24dp | 24–32dp |
| Primary button height | 48dp min | 48dp min | grows for content |
| Text field height | 56dp min | 56dp min | never fixed/clipped |
| Tap target | 48dp preferred | 48dp preferred | never below 44dp |
| List row | 48dp min | 56dp preferred | content may expand |
| Card radius | 16dp | 16dp | 20–24dp sheets/dialogs |

**Rules:**
- No nested cards. A card groups content; a sheet/dialog floats above.
- One elevation hierarchy: page base → raised card → floating sheet/dialog
- Remove redundant nested insets. 16dp page gutter + 16dp card inset is the normal compact composition
- Keep full-width reading layouts constrained on tablets; don't stretch short lists/forms across the entire display
- Replace fixed-ratio grids with variable-height layouts that respect all cell content
- No fixed `childAspectRatio` grids that clip text at large text scales
- Use `EdgeInsetsDirectional` for leading/trailing content; maintain safe areas

---

## 6. Component system

**Component base:** Flutter Material + custom ThemeExtension tokens (AppColors, AppSpacing, AppShapes, AppTypography, AppMotion). One base per project, re-themed to tokens — never library default look.

**Buttons:** Filled (accent fill, white text, 48dp height, 16dp horizontal padding), Outlined (surface fill, accent border), Text (text only, secondary actions). All states: default / hover / focus-visible / active-pressed (scale 0.96) / disabled.

**Cards:** SurfaceCard — surface fill, outline hairline, 16dp radius, 16dp padding default (compact). No nested cards.

**Badges:** StatusChip — pill (999dp radius), filled with status color, readable text size (not 11px for important info).

**Bottom navigation:** Four destinations (Dashboard, Sell, Inventory, More), visible icon + label, consistent hit areas. Sell may receive stronger emerald emphasis but remains a navigation destination, not a promotional element. Selection communicated by color PLUS shape (accentContainer background).

**Forms:** TextFormField with floating labels (visible, never placeholder-only), validation on interaction, errors inline below field, helper text, 56dp min height, submit disabled with visible reason.

**Sheets and dialogs:** Clear title, concise explanatory content, one primary action, explicit cancel/close action. Drag/close affordance, stable top title, content scrolls independently, action area reachable, height adapts to keyboard/small viewport.

**More sheet:** Groups secondary destinations by task (business, inventory, reports, account/support) with concise heading and simple rows. Not another dashboard or unstructured grid.

**Profile selector:** Recognizable profile icon or mark (not raw first letter), current selection shown with checkmark + text/semantics, semantic colors not `Colors.white`/`Colors.green`.

---

## 7. Card & section style

**Surface roles:** (1) page/background, (2) content grouping, (3) floating overlay. No fourth/fifth tier without real purpose.

**Cards:** Surface fill, outline hairline, 16dp radius, 16dp padding (compact). Use background/surface contrast, spacing, and typography before adding outlines or shadows. No nested full cards. No repeated card borders within card borders.

**Sheets/dialogs:** 24dp radius, raised surface, floating shadow.

**Gradients:** None on content cards. Green gradient only on hero surfaces where profile-specific design calls for it (one hero per dashboard max).

**Glassmorphism:** None used.

---

## 8. Icon system

**Icon library:** Material Icons (bundled with Flutter).

**Icon size:** 18–24dp for list rows, 14dp for small badges, 26dp for nav ball.

**Icon color:** Semantic tokens (`onSurface`, `onSurfaceMuted`, `accent`, `onAccent`) — never raw `Colors.*`.

**Usage rules:** Icon-only controls have accessible Semantics labels. Icon badges are circular with surfaceSunken fill. Color is never the only state cue — every pill/chip has text.

---

## 9. Image & asset rules

**Logo:** SimpleSales wordmark with brand mark. Bundled, never network-fetched.

**Hero images:** Stretched end-to-end across full screen width (`width: double.infinity`, `fit: BoxFit.cover`), not square pictures centered in the screen. One hero per dashboard max.

**Profile images/icons:** Properly sized (min 44dp touch target), themed for light/dark/high-contrast, never raw color literals.

**Product art:** Aspect-ratio placeholders so image loading doesn't cause tile reflow. Missing photos use consistent branded placeholder. Images faithful in dark mode — no darkening of product photography.

**Fashion:** Photography as merchandising signal — image, style name, price, variant availability lead catalogue browsing.

**Drinks/Duka/Open:** Imagery only when it improves recognition. No decorative stock photos on operational dashboards.

---

## 10. Animation & interaction system

**Animation library:** Flutter implicit animations via theme tokens (AppMotion). No external animation library.

**Motion principles:**
- Motion communicates hierarchy, feedback, storytelling, or state — never decoration
- Animate only `transform`/`opacity`
- Micro-interactions ~150–300ms; ease-out entering, ease-in exiting; avoid linear
- Reduced motion collapses to `Duration.zero` — not "gentler"
- No persistent idle animation/timer on Sell navigation or dashboard KPI components
- No auto-playing shimmer/pulse on persistent financial totals, navigation controls, low-stock rows, or status badges

**Button interaction:** Scale to 0.96 on press, 160ms ease-out.

**Toast/inline message:** `showAppSnackBar` for confirmations; never color alone — paired with icon + label.

**Form feedback:** Inline validation on interaction; errors below field; visible required markers; submit disabled with visible reason.

**Data view states:** Empty (branded, with action), loading (skeleton), error (recoverable + retry) for every data view.

---

## 11. Accessibility rules

**Contrast:** Body/supporting text ≥ 4.5:1; large text/UI ≥ 3:1; computed not eyeballed; every text pair passes AA in both light and dark.

**Focus:** Visible focus-visible on every interactive element; never removed without replacement.

**Color is never the only state cue:** Selected nav, success, warning, danger, profile, payment state all include text/icon/shape semantics.

**Touch targets:** Minimum 44dp, preferably 48dp for POS actions; no overlapping hit regions.

**Text scaling:** Respect MediaQuery textScaler; allow cards/rows to grow; never clip essential content.

**Reduced motion:** Respect MediaQuery.disableAnimationsOf; collapse animations to zero.

**RTL:** EdgeInsetsDirectional, AlignmentDirectional, TextAlign.start.

---

## 12. Navigation rules

**Mobile navigation:** Four destinations — Dashboard, Sell, Inventory, More. All four have visible icon + label and consistent hit areas.

**Selection:** Communicated by color PLUS shape (accentContainer background container behind selected icon).

**Sell entry:** Has a text label for sighted users; icon alone is insufficient.

**Nav stability:** Bottom navigation available consistently across nested routes where appropriate; selected destination reflects current route; no tab state lost unexpectedly.

**Bottom content padding:** Accounts for actual nav height + system bottom inset. Keyboard must not leave the bar floating over cart or primary form action.

**Profile switching:** Distinctive meaningful icon per profile, checkmark + "Current" semantics, AppColors not Colors.white/Colors.green.

---

## 13. Profile addenda

### Drinks

**Mental model:** Beverage sales, stock by container/tank, measured servings, packaged beverages, shifts, cash/till reconciliation.

**Dashboard priority:** Today's sales + actual shift status. Tank levels and low-stock as compact operational info, not duplicated large cards.

**Units:** Bottle/tank/serving units explicit and consistent. Never mix stock quantities and revenue in the same visual hierarchy without labels.

**Visual identity:** Beverage photography, tank/serving iconography, dashboard eyebrow, profile selector, onboarding illustration. Emerald for primary actions and shared semantics.

**Constraints:** No large green hero + second full-width Sell button + raised green Sell tab competing at once. Tank content appears exactly once per layout.

### Duka

**Mental model:** General retail, product catalogue, stock quantities, receiving goods, stocktakes, loose goods, customer credit, everyday sales.

**Dashboard priority:** Sales, stock alerts, next inventory action. Receive Stock and Stocktake easy to reach without half a screen for large cards.

**Catalogue:** Photo/placeholder, product name, unit/variant, price, stock state, one obvious tap target. Distinguish stock value, daily sales, gross profit, cash position.

**Visual identity:** Retail/product imagery, unit-aware stock rows, restock/stocktake actions.

### Fashion

**Mental model:** Styles, sizes, colors/variants, stock by variant, laybys, returns/exchanges, sales.

**Dashboard priority:** Sales summary; secondary KPI = laybys/active reservations or low-stock variants.

**Catalogue:** Real product imagery, product/style name, price, size/color availability. Product cards preserve image proportions; missing photos use branded placeholder.

**Variants:** Size/color/variant chips with visible selected shape/check (not color-only). Swatches need accessible names; size values must be text.

**Visual identity:** Product photography, variant chips, fashion-specific iconography.

### Open

**Mental model:** Jobs/services, customer details, estimates/quotes, job costs, payments/receivables, operational follow-through.

**Dashboard priority:** Jobs in progress, overdue/next jobs, outstanding receivables, revenue collected. Name every number — never label receivables as sales or costs as profit.

**Jobs:** Job-stage timelines, service imagery, job-specific iconography. Status = text label + icon/indicator.

**Visual identity:** Job-stage timelines, service imagery, job-specific iconography.

---

## 14. Anti-AI-slop rules

- **Approved palette only:** No colors outside `lib/theme/primitives.dart` exposed through `AppColors`
- **Pure #000/#fff:** Not used by default — canvas is tinted near-white, body ink is brand ink
- **No Lucide by default;** no mixed icon families; no emojis as structural icons
- **No borders as primary elevation:** Background contrast + spacing before borders
- **No nested cards:** One elevation hierarchy only
- **No persistent idle animation:** No heartbeat, glow, shimmer, pulse on nav or KPIs
- **No color-only state:** Every state includes text/icon/shape
- **No split hero (left text / right image):** Full-width hero only
- **No decorative sparkle/AI icon:** No ✨ in eyebrows/badges/pills
- **No focus ring on mouse click:** `:focus-visible` only
- **No floating element overflow:** Collision-aware positioning for tooltips/dropdowns/popovers
- **No horizontal card row with native scrollbar:** Use snap/controls/mask fade
- **No gradient text, decorative glass, or side-stripe border accents**
- **No profile-specific accent palettes:** One emerald across all four profiles

---

## 15. Future page instructions

Every future page must reuse the same colors, typography, spacing, components, icons, cards, animation rules, and image style documented above. Do not introduce a new visual style unless this file is explicitly updated.

---

## 16. Update policy

If colors, typography, components, animations, cards, icons, or image style change later, update this file immediately so it never drifts from the live UI.
