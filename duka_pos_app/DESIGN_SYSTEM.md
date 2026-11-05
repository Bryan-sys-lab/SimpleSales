# DESIGN_SYSTEM.md

> The official design reference for SimpleSales — Drinks profile. Every future
> page, section, component, and UI update must follow this file so the design
> stays consistent across the drinks profile views.

---

## 1. Project overview

- **Product name:** SimpleSales
- **Surface profile:** App/Product UI — Mobile/Native (Flutter)
- **Platform:** Android (Flutter mobile app)
- **Target users:** Bar owners, bartenders, till operators running a drinks-first business
- **Main design goal:** Money first, then actions, then stock — a calm, practical interface where the one number a till operator lands on (today's sales) is the largest thing on the screen, and every tap target is easy to hit fast behind a bar.

---

## 2. Brand direction

- **Visual style:** Apple-inspired — clean, calm, practical. Bottled emerald green as the single accent; cool neutral ramp; generous corner radii (16px cards, 999px pills).
- **Mood & tone:** Confident but unflashy. A tool for working, not a marketing page.
- **Design personality:** Corporate-clean / practical-instrument. The UI reads like a behind-bar dashboard: legible at a glance, fast to tap, no decoration that doesn't earn its place.
- **Design concept (one sentence):** A till dashboard that feels like precision instrumentation behind a bar — emerald accent on a cool neutral ramp, tabular figures everywhere, one dominant number (today's sales) and a clear path to the next action (start a sale).
- **Adversarial-review verdict:** Cover the brand name — could this be any POS? The emerald accent + cool neutral ramp + 16px card radius combination is distinctive enough that it doesn't read as generic Material. The one weakness found was the hero split (left text / right image), which was avoided by using a full-width green-gradient hero card instead.
- **Reference style used:** The SimpleSales profile mockups (SimpleSales Drinks Profile UI Mockups.png / simple_sales_profile_mockups.html) — the specific moves adapted: green-gradient hero with eyebrow label, two-stat grid below hero, shift overview as a mini-list of icon-badge rows, circular icon badges on every list row, full-width primary action button at the bottom of each screen's content, bottom nav pill with one active state.
- **Voice & UX copy:** Plain, verb-first CTAs ("+ Start a sale", "Record measurement", "Receive stock"). Empty states explain the next action; errors say what happened + how to fix. Real or honestly-marked mock data only — no "Acme / John Doe / Lorem ipsum".

---

## 3. Color system

Map every color to its role. Use only these values across the drinks profile.

| Role | Color | Hex | Usage |
|---|---|---|---|
| 60% — Dominant | canvas | #F2F4F7 | Page backgrounds, large surfaces |
| 30% — Secondary | surface | #FFFFFF | Cards, sheets, raised sections |
| 10% — Accent | accent / botanical38 | #1B6B3A | Buttons, hero gradient, highlights, focus rings |
| — | accentContainer | #E4F3E9 | Low-chroma accent fill, selection |
| — | onAccent | #FFFFFF | Text/icons on accent fill |
| — | success | #1A7A3A | Active shift, healthy tank |
| — | warning | #8A6508 | Low stock, needs attention |
| — | danger | #C0392B | Empty tank, out of stock |

**Usage rules:**
- Backgrounds: canvas (#F2F4F7) is the page base; surface (#FFFFFF) for cards
- Text: onSurface (#2D2A26) for body; onSurfaceVariant (#414954) for supporting lines; onSurfaceMuted (#5C6673) for tertiary/captions — all clear 4.5:1 on canvas
- Buttons: Filled buttons use accent (#1B6B3A) fill with white text; outlined buttons use surface with accent border
- Cards: surface (#FFFFFF) with outline (#DCE1E8) hairline, 16px radius
- Highlights / focus: accentContainer (#E4F3E9) for selection chips
- Separation: background contrast + shadow only — **never borders as primary elevation**
- **Dark mode:** canvas #0B0F14, surface #151A21, accent #4ADE7E (bright emerald at night); surfaces raised by +lightness; accent chroma lowered; every text pair re-verified for AA in dark

---

## 4. Typography system

- **Brand personality:** Corporate-clean / practical-instrument
- **Font family / pairing:** Plus Jakarta Sans (bundled variable font, 200–800 axis), fallback Roboto / Noto Sans
- **Why these fonts fit the personality:** Plus Jakarta Sans is a modern grotesque with tabular figures — numbers align vertically, which is essential for prices and counts behind a till
- **Type scale (named steps + exact values):**
  - displaySmall: 28px, w800, letterSpacing -0.8 (today's sales figure)
  - headlineSmall: 22px, w700, letterSpacing -0.4
  - titleLarge: 18px, w700, letterSpacing -0.2 (section titles)
  - titleMedium: 15px, w700 (card titles)
  - bodyLarge: 15px, w400, height 1.45 (body text — never below 14px effective)
  - bodyMedium: 14px, w400, height 1.45
  - bodySmall: 12px, w400, muted color (captions, timestamps)
  - labelLarge: 14px, w700 (buttons)
  - labelMedium: 13px, w600 (form labels)
  - labelSmall: 11px, w600, letterSpacing 0.2 (chips, small labels)
- **Body text:** Never below 14px effective on mobile; line-height ~1.45; line length ~60–75ch
- **Button text style:** labelLarge (14px, w700), all buttons primary style reuse same text size
- **Responsive rules:** Headings scale down on mobile via scale tokens; never clip hero text; never truncate on mobile; tabular figures on every number

---

## 5. Layout system

- **Container widths:** Max content width 1200px on desktop; full width on mobile with 16px gutters
- **Section spacing:** 32px (xl) between major sections; 24px (lg) between blocks; 16px (md) inside cards
- **Grid rules:** Two-column layout at >= 840px (3:2 flex split, primary content left, supporting right); single column below
- **Page anatomy / section order:** Brand header → hero (today's sales) → two-stat grid → shift overview → primary action → supporting sections (sales, top products, beverage stock, shift card, credit, low stock)
- **Conversion / CTA flow:** Primary CTA is "+ Start a sale" — full-width filled button, repeated once per screen at the bottom of the action zone
- **Surface-specific flows:** Drinks → dashboard (money first) → sell (product grid + cart) → beverage inventory (tank list) → tank detail (centered header + progress bar + stats) → measured servings (list + save form) → shift (centered shift panel + stats + count/close)
- **Hero composition:** Full-width green-gradient hero card (not split). Eyebrow label ("TODAY'S SALES") above display-size figure with comparison underneath. Fits within viewport, centered vertically, nothing clipped at laptop heights (~700–800px).
- **Full-screen sections:** Each major section uses min-height, fills viewport width, centers content vertically + horizontally where appropriate, safe padding, nothing clipped or overflowing — verified at widths 375/768/1280
- **Horizontal card rails:** None in drinks profile — vertical lists with icon badges instead
- **Mobile-first behavior:** Single column, full-width buttons, 48px min tap targets, bottom nav pill
- **Breakpoints:** Mobile (~375px), tablet (~768px), desktop (~1280px+)
- **Alignment rules:** CrossAxisAlignment.stretch for cards; center alignment for tank identity headers and shift panels; start alignment for lists and stats

---

## 6. Component system

- **Component base / library:** Flutter Material + custom ThemeExtension tokens (AppColors, AppSpacing, AppShapes, AppTypography). One base per project, re-themed to tokens (never library default look)
- **Buttons:** Filled (accent fill, white text, 48px height, 16px horizontal padding), Outlined (surface fill, accent border), TextButton (text only, for secondary actions). All states: default / hover / focus-visible / active-pressed (scale 0.97) / disabled
- **Cards:** SurfaceCard — surface fill (#FFFFFF), outline hairline (#DCE1E8), 16px radius, 16px padding default. No nested cards.
- **Badges:** StatusChip — pill (999px radius), filled with status color (success green / warning amber / danger red), 11px w600 text
- **Navbar:** Bottom pill nav — four items (Home, Sell, Stock, More), one active with filled background and white icon/text, others muted
- **Forms:** TextFormField with floating labels, validation on interaction (AutovalidateMode.onUserInteraction), errors inline below field, helper text
- **Inputs:** 48px min height, 12px radius, surfaceSunken fill for icon badges
- **Feature sections:** DashboardPanel — titled section card with optional trailing action, two-column stat grid, mini-list of icon-badge rows
- **CTA sections:** Full-width FilledButton with icon + label, "+ Start a sale" pattern

---

## 7. Card & section style

- **Chosen style:** Borderless cards with outline hairline + soft ink shadow (not grey)
- **Radius:** 16px cards (lg), 24px sheets/dialogs (xl), 12px controls/buttons (md), 8px table cells (sm), 4px chips (xs), 999px pills
- **Shadow / elevation:** Ink-hued shadow (#1A0A0E13 at 10%), blur 2, offset (0,1) for resting; blur 12, offset (0,4) for floating layers
- **Gradients:** Green gradient hero (botanical38 #1B6B3A → accentContainer #E4F3E9), 135deg, used only on hero cards
- **Glassmorphism:** None used
- **Rule:** No nested card-heavy layouts; one elevation hierarchy only (page base → raised card → floating sheet)

---

## 8. Icon system

- **Icon library:** Material Icons (bundled with Flutter)
- **Icon size:** 18–20px for list rows, 14px for small badges, 32px for circular art badges
- **Icon color:** onSurfaceVariant (#414954) for decorative icons, onSurfaceMuted (#5C6673) for secondary
- **Usage rules:** Icon-only controls have accessible Semantics labels; icon badges are circular with surfaceSunken fill

---

## 9. Image & asset rules

- **Logo:** Text wordmark "SimpleSales" with "Work. Sell. Grow." tagline; brand mark is a square logo (▥) in green circle
- **Product art:** Circular icon badges (64px) for tank identity; product grid art (68px) for sell screen
- **Visual treatment:** No photographs in drinks profile — icon-based visual language throughout

---

## 10. Animation & interaction system

- **Animation library:** Flutter implicit animations (AnimatedContainer, etc.) via theme tokens; no external animation library
- **Hover states:** Subtle surface lift on interactive cards; scale(0.97) on press for buttons
- **Section reveal behavior:** Sections stagger 40ms apart, 8px up, 220ms ease-out on first paint (AnalyticsScaffold Reveal pattern)
- **Button interaction:** Filled buttons scale to 0.97 on active; 160ms ease-out transition
- **Cursor pointer rules:** Pointer cursor on all interactive elements (handled by Material ink responses)
- **Interaction states:** default / hover / focus-visible / active-pressed / disabled — every interactive element ships full state set
- **Async feedback:** Loading skeleton (SkeletonList) during load; ErrorStateView with retry; EmptyStateView with action; RefreshIndicator for pull-to-refresh
- **Toast / inline message system:** showAppSnackBar for confirmations; PersistentBanner for dismissible messages; never color alone — paired with icon + label
- **Form feedback:** Inline validation on interaction; errors below field; visible required markers; helper text; submit disabled with visible reason
- **Data view states:** Empty (branded, with action), loading (skeleton), error (recoverable + retry) for every data view
- **Reduced-motion support:** Theme changes snapped to zero duration (themeAnimationStyle: AnimationStyle.noAnimation); stagger collapses to zero under reduced motion
- **Performance:** Animate only transform/opacity; tabular figures to prevent layout shift; lazy lists; dispose controllers; one ThemeExtension per token tier

---

## 11. Accessibility rules

- **Contrast rules:** Body/supporting text ≥ 4.5:1; large text/UI ≥ 3:1; computed not eyeballed; onSurfaceMuted (#5C6673) still clears 4.5:1 on canvas (#F2F4F7)
- **Focus states:** Visible focus-visible on every interactive element; never removed without replacement
- **Keyboard navigation:** Full operation; tab order = visual order; skip-to-content via Semantics sort keys
- **Semantics & ARIA:** Semantics widgets on all interactive elements; semanticLabel on cards/rows read as one phrase; button roles on InkWell/IconButton
- **System adaptation:** respects MediaQuery.boldTextOf; text scaling via boldTextFor; RTL-ready with EdgeInsetsDirectional / AlignmentDirectional
- **Text readability:** Never rely on color alone — StatusChip pairs color with word; every pill has text

---

## 12. Anti-AI-slop rules

- **Approved palette (the only colors allowed):** #F2F4F7 (canvas), #FFFFFF (surface), #1B6B3A (accent), #E4F3E9 (accentContainer), #FFFFFF (onAccent), #2D2A26 (onSurface), #414954 (onSurfaceVariant), #5C6673 (onSurfaceMuted), #DCE1E8 (outline), #6B7480 (outlineStrong), #1A7A3A (success), #8A6508 (warning), #C0392B (danger)
- **Pure #000/#fff used?** No by default — canvas is #F2F4F7 (tinted near-white), body ink is #2D2A26 (brand ink, not pure black)
- **Concept-test verdict:** Cover "SimpleSales" — still distinctive? Yes, emerald + cool neutral + 16px cards is not a generic POS template. Weakness found and fixed: hero split avoided; full-width gradient hero used instead.
- **Project-specific exceptions to the gate:** None — drinks profile follows all gate rules; bottom nav pill is the standard pattern across all profiles

---

## 13. Future page instructions

Every future page must reuse the same colors, typography, spacing, components, icons, cards, animation rules, and image style documented above. Do not introduce a new visual style unless this file is explicitly updated.

---

## 14. Update policy

If colors, typography, components, animations, cards, icons, or image style change later, update this file immediately so it never drifts from the live UI.
