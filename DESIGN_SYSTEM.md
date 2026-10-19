# Duka POS design system

> The values below are the ones the app renders with. Every colour, size and
> spacing step here is read out of `duka_pos_app/lib/theme/`, and every one of
> them is asserted in `duka_pos_app/test/theme/`. A number in this file that
> the code does not hold is a bug in this file.

## 1. Product direction

- **Product**: Duka POS (SimpleSales)
- **Surface**: offline-first mobile/native point-of-sale app
- **Platforms**: Android and iOS
- **Users**: shop owners and cashiers working quickly at a counter, on budget
  phones, often one-handed and often in a hurry
- **Main goal**: make selling feel immediate, and make inventory and reporting
  feel trustworthy
- **Design concept**: **the counter ledger** — warm paper-like surfaces, ink-dark
  information, a botanical-green action spine, and compact transaction rows that
  make every change feel deliberate and easy to verify
- **Surface profile** (the ui-ux-kit routing vocabulary): **mobile / native**,
  with a dashboard and an analytics surface in the app. Every screen is judged
  against a thumb on a 320dp phone at 200% text before anything else.

## 2. Brand and voice

- Style: warm, practical, calm, high-clarity
- Voice: plain and reassuring; direct verbs — "Add product", "Adjust stock",
  "Charge KSh 1,240"
- Errors: say what happened **and what the person can do next**; never expose
  exception text. An error that repeats the field's own label says nothing the
  person did not already know.
- Empty states: explain the next useful action, not just "No data"
- Success states: confirm the completed action and the amount or reference
- A dead end is a missing feature. Every failure screen offers a way forward:
  a retry, or a way to get the diagnostics to whoever can help.

## 3. Colour tokens

Tier 1 (`lib/theme/primitives.dart`) is the **only** file in `lib/` allowed a
colour literal. Tier 2 (`lib/theme/app_colors.dart`) is the semantic tier;
widgets read it through the asserting `AppColors.of(context)`.

| Role | Token | Light | Dark | Use |
|---|---|---:|---:|---|
| Canvas | `canvas` | `#FAF6F0` | `#1A1816` | The page behind the cards |
| Surface | `surface` | `#FFFFFF` | `#242220` | Cards, forms, navigation |
| Sunken | `surfaceSunken` | `#F3EDE6` | `#0F0E0D` | Wells, chips, table stripes |
| Ink | `onSurface` | `#2D2A26` | `#F5F0EB` | Body text. **Also the launcher icon plate** |
| Secondary ink | `onSurfaceVariant` | `#4A433C` | `#D4CAC0` | Supporting text |
| Muted ink | `onSurfaceMuted` | `#6B635A` | `#AA9F97` | Metadata |
| Accent | `accent` | `#1B6B3A` | `#4ADE7E` | The action spine. **Also the brand ink** |
| On accent | `onAccent` | `#FFFFFF` | `#2D2A26` | Text on the accent |
| Accent container | `accentContainer` | `#E8F5EC` | `#244A30` | Selected states |
| Success | `success` | `#1A7A3A` | `#5CE68A` | Status text, with a word and a glyph |
| Warning | `warning` | `#8A6508` | `#FFB84D` | Low stock, attention |
| Danger | `danger` | `#C0392B` | `#FF6B5B` | Errors, destructive actions |
| Info | `info` | `#1A6BAA` | `#6AB0F5` | Neutral information |
| Outline | `outline` | `#E8E0D6` | `#4A4541` | Hairlines. Decorative, below 3:1 |
| Meaningful boundary | `outlineStrong` | `#8A8075` | `#7A736D` | Input edges. Clears 3:1 |

**Payment identities** (somebody else's brand, used only for the payment-mix
ring, which is a *graphical object* and so is held to 3:1, not 4.5:1):

| Tender | Light | Dark |
|---|---:|---:|
| M-Pesa | `#009C4E` | `#00A651` |
| Airtel | `#EC1C24` | `#EC1C24` |
| Equitel | `#0066CC` | `#3E90E8` |
| Cash | `#6B635A` | `#8A8075` |

Each identity has a value per appearance, because a provider's logo colour is
not the colour that survives a dark surface. The legend names every slice, so
colour is never the only channel — and that is not a licence to draw a slice
the eye cannot find.

**Rules**: colour is never the only status signal — pair it with a word, a
count, an icon or a shape. Dark is designed, not inverted. Body and supporting
text clears 4.5:1; graphical objects and meaningful boundaries clear 3:1.
Every pair is measured in `test/theme/contrast_test.dart`.

## 4. Typography

Plus Jakarta Sans, bundled as a variable font (never `google_fonts`, never a
network fetch). Tabular figures are on **every** role, so a number can appear
anywhere without someone remembering to opt in.

| Role | Size / line / weight | Use |
|---|---|---|
| `displaySmall` | 28 / 1.15 / 800 | The one number a screen is about |
| `headlineMedium` | 26 / 1.2 / 700 | Screen titles |
| `headlineSmall` | 22 / 1.2 / 700 | Totals, dialog titles |
| `titleLarge` | 18 / 1.25 / 700 | Section headings |
| `titleMedium` | 15 / 1.3 / 700 | Card and list headings |
| `titleSmall` | 13 / 1.3 / 600 | Row headings, the product name in a tile |
| `bodyLarge` | 15 / 1.45 / 400 | Important copy |
| `bodyMedium` | 14 / 1.45 / 400 | Standard labels and rows |
| `bodySmall` | 12 / 1.4 / 400 | Secondary metadata |
| `labelLarge` | 14 / 1.2 / 700 | Button labels |
| `labelMedium` | 13 / 1.2 / 600 | Chips, small captions |
| `labelSmall` | 11 / 1.2 / 600 | The stock count, axis labels |

Every size is a token: a `fontSize: 14` in a feature file is a bug.

**Text must survive 200% scaling.** No fixed heights on anything that holds
text; no `maxLines` without an `overflow`; no `FittedBox` or clamped text
scaling to make a label fit. A `Text` with an ellipsis and no `maxLines` still
wraps — `maxLines` is what stops it.

## 5. Spacing, shape and layout

- **Spacing scale** (`AppSpacing`): `xs 2 · sm 4 · md 8 · lg 12 · xl 16 ·
  xxl 24 · section 20`. Tighter than a marketing layout — this is an Operate
  surface, and the steps are spent on data rows.
- **Tap target floor**: 44dp, on every interactive element.
- **Row height**: 44dp as a **minimum**, never a fixed height.
- **Radii**: 4 badge · 6 well · 8 control · 12 card (the cap) · pill for chips.
- **Page gutter** (`PageGutter`): a phone gets 12dp of page padding and 8dp
  inside a card; a tablet gets 16 and 16. The depth of a page is the sum of
  the page's padding, the card's border and the card's padding — 33dp of
  nothing before the first word is a tenth of a 360dp screen.
- **Navigation**: one bottom `NavigationBar` on a phone, a `NavigationRail` on a
  tablet. The breakpoint comes from `WindowSizeClass` — the same vocabulary for
  every screen — never from a device check.
- **Motion**: short and functional, and collapsed to nothing under reduced
  motion.

### The till page

The catalogue and the cart, and how they sit together:

- **Wide** (a tablet, a landscape till): side by side. The cashier looks at one
  and touches the other.
- **Phone**: stacked, catalogue above, cart below — the thumb reaches the
  bottom of the screen, and the bottom of the screen is where the money is.
- The pane layout **divides a height**, so it must be given a bounded one. A
  `Column` hands its non-flexible children an *unbounded* height; put the pane
  layout in an `Expanded`. An unbounded height in a grid is a grid with an
  infinite scroll extent, which is a crash in the sliver's index arithmetic.
- The search field and the scanner share **one row** — two rows of controls
  before a single product is a fifth of the screen spent.

### Grids size their cells from the content

A cell's height is computed from the text it holds, at the text scale in force.
A ratio of the width is a *guess* about how much text a cell holds, and a guess
is wrong the moment the text scale moves — in the direction that breaks the
layout. The price and the stock count are **measured**, not assumed: a price
that wraps to two lines at 150% text needs two lines of room, and a price is
never truncated to make it fit.

## 6. Components

- Buttons: Material 3, 44dp minimum target, `MaterialTapTargetSize.padded`
- Inputs: filled fields, 8dp radius, explicit labels, correct keyboard types
- Cards: a warm surface, a hairline, a 1px shadow — separated by depth, not by
  a wall of borders
- Status: label + icon + count, never colour alone
- Icon-only controls: always a tooltip and a semantic label
- Money: always `formatMoney()` from `lib/utils/money.dart`, always tabular
- Every data view has all three states: loading, empty, error — and the error
  is recoverable
- One node for a thing a person reads as one thing: a product tile is a single
  semantics node ("Kenyatta bread, KSh 60, 12 in stock, adds it to the cart"),
  not four

## 7. Accessibility baseline

WCAG 2.2 AA. The matrix that proves it is `test/support/harness.dart`:
320 / 360 / 412 / 800 wide, text at 1.0 / 1.3 / 2.0, light and dark, bold
text, RTL, reduced motion. A screen that overflows at any of those is a
screen that clips for a real person.

- Every interactive target is at least 44dp.
- A user's own text — a product, staff or shop name — is bounded with
  `maxLines` and an ellipsis, and the full value is carried by the semantics
  label.
- Semantics hints say what the tap **does**, not how to perform it. "Double tap
  to add" repeats what the platform already announces and says nothing about
  what the tap is for.
- Payment and sale outcomes are visible and announced.

## 8. Implementation source of truth

| Thing | File |
|---|---|
| Raw values (the only colour literals) | `duka_pos_app/lib/theme/primitives.dart` |
| Semantic colours | `duka_pos_app/lib/theme/app_colors.dart` |
| Type, spacing, shape | `duka_pos_app/lib/theme/typography.dart`, `app_spacing.dart`, `app_shapes.dart` |
| Theme assembly | `duka_pos_app/lib/theme/app_theme.dart` |
| Shared components | `duka_pos_app/lib/ui/components/` |
| Page layout and the gutter | `duka_pos_app/lib/ui/layout/page.dart` |
| The till page | `duka_pos_app/lib/widgets/sell_page.dart`, `product_tile.dart` |
| The shell | `duka_pos_app/lib/routing/home_shell.dart` |
| Money | `duka_pos_app/lib/utils/money.dart` |
| The contrast and token proofs | `duka_pos_app/test/theme/` |
| The layout matrix | `duka_pos_app/test/support/harness.dart` |
