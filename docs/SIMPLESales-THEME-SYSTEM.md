# SimpleSales Theme System & Human Interface Design Plan

Status: active implementation source of truth

This document records the theme/UI plan supplied for the current implementation goal. The complete pasted specification remains the governing brief; this index makes its implementation contract discoverable from the repository.

## Scope

Implement one shared Flutter design system for Drinks, Duka, Fashion and Open while preserving the existing architecture, navigation, business logic, database and working features.

## Required architecture

- `duka_pos_app/lib/theme/primitives.dart`: the only location for literal color values.
- `duka_pos_app/lib/theme/app_colors.dart`: semantic `AppColors` `ThemeExtension`, with `copyWith`, `lerp`, light/dark registration and `AppColors.of(context)` access.
- `duka_pos_app/lib/theme/app_theme.dart`: deliberately authored light and dark themes, including `ThemeData`, `ColorScheme`, typography and component defaults. Do not use `ColorScheme.fromSeed`.
- `duka_pos_app/lib/theme/app_spacing.dart`: shared 4/8-point spacing rhythm and reusable dimensions.
- Existing shared components: common buttons, fields and controls; do not create profile-specific copies.

## Non-negotiable interaction standards

- Prefer 48 x 48 logical-pixel Android touch targets; never reduce below the 44-pixel baseline without a compelling layout reason.
- Standard primary buttons target 48 pixels high with 16 pixels of horizontal padding.
- Standard single-line fields target a 56-pixel minimum and must grow for text scaling, multiline content and validation messages.
- Use 16-pixel mobile gutters, 24-pixel larger-screen gutters and approximately 560–640 pixels as a wide form content maximum.
- Respect system text scaling; do not clamp it or clip content.
- Communicate status with labels/icons/text as well as color. Payment-provider identity is separate from transaction status.
- Preserve authoritative payment success/failure semantics and provide recoverable processing/error states.
- Use restrained, purposeful motion and respect reduced-motion settings.

## Theme and accessibility requirements

- Provide authored light and dark palettes with readable semantic foreground/container pairs.
- Centralize semantic surfaces, text, outlines, brand, status, media, overlay and payment-provider roles.
- Meet 4.5:1 normal-text and 3:1 large-text contrast targets where applicable.
- Test narrow layouts around 320 logical pixels, typical phone/tablet widths, enlarged text including a feasible 200% scenario, and both themes.
- Check clipping, overflow, keyboard obstruction, focus order, semantics labels, selected states and touch targets on representative transaction paths.
- Apply the same tokens and shared components to all four profiles.

## Implementation order

1. Audit the existing theme, shared components, screens and tests.
2. Complete/verify shared tokens and both theme builders.
3. Centralize component defaults.
4. Migrate shared and high-frequency POS screens incrementally.
5. Add focused theme/contrast/accessibility/responsive tests.
6. Review light/dark rendered layouts and transaction paths.

## Current evidence

- Shared spacing and interaction dimensions are implemented and covered by the
  the theme token tests; the authored light/dark palette and semantic contrast
  gate pass 95 theme tests, including the preferred 48px Android target.
- Shared support/search controls and the sell transaction surface use the
  semantic theme and preferred Android touch targets.
- Sell-page responsive tests pass at 320, 360 and 412 logical pixels in both
  themes from 1.0x through 2.0x text scaling (29 focused tests).
- Profile editing exposes name/email autofill purposes and passes its focused
  200% layout/input-purpose coverage (5 tests).
- Receiving stock uses responsive narrow-screen actions and expanded dropdowns;
  its focused UI/domain flow passes (26 tests).
- Expense and till-control sheets use expandable financial-entry dropdowns and
  remain covered by analyzer validation; their shared sheet frame already
  scrolls around the keyboard and enlarged text.
- Shared page gutters now consume the explicit 16px mobile / 24px larger-screen
  dimension tokens rather than profile- or screen-specific values.
- Information status now has authored foreground, container and
  on-container semantic tokens in both themes, with WCAG contrast coverage.
- Dashboard hourly sales now stacks its peak badge on narrow/enlarged layouts;
  the focused chart suite passes 14 tests, including 320px and 200% text in
  both light and dark themes.
- Shared line and bar charts expose screen-reader increment/decrement actions
  in addition to touch selection; chart accessibility and rendering checks pass
  (51 focused tests).
- The four-profile capability/acceptance, profile model and shared selling
  surface checks pass (47 tests), including Fashion acceptance and shared
  profile-driven behaviour.
- Entry screens pass the 320/360px, 1x/2x, light/dark layout matrix (47 tests);
  the splash uses shared mobile gutters and its progress state is static under
  reduced motion.
- The central sell navigation action is a semantic, keyboard/switch-accessible
  control, and the inventory product row now uses the shared 56px dimension;
  navigation and inventory-related checks pass.
- Portfolio rows retain zero-activity shops in the accessible chart legend and
  ranked list; dashboard attention, shift, profile-photo and credit-sheet
  responsive checks pass after the latest narrow/enlarged-layout fixes.
- The new pre-account profile tour is covered by focused responsive tests at
  320/360px and 200% text scaling. Its Kenyan shop photography is bundled
  rather than network-dependent, and the onboarding cards use clean cropped
  photographic surfaces with native Flutter copy instead of embedding the
  reference-grid artwork in the images.
- The end-of-section full Flutter gate passed on the current production
  worktree with 1,687 tests. The follow-up onboarding accessibility additions
  now pass in the focused suite as well (7 onboarding tests), covering semantics
  labels and the first-page touch-target floor,
  including the onboarding flow, shared profile checks, payment-mix legend,
  identity-dialog actions and system-back coverage.
- The legacy post-account demo/import route now renders the optional
  permissions step instead; newly created accounts mark the retired
  walkthrough complete before entering permissions.
- Flutter analyzer reports no issues for the current app.
- The first full section gate exposed four responsive/shared-surface failures;
  the affected payment-mix legend and identity-dialog action layouts are now
  responsive, and the focused payment-mix, identity-dialog and system-back
  checks pass. The final full gate is green. A Flutter-rendered light and dark
  onboarding review has been inspected at the small-device size; the image,
  card surface, typography and bottom actions render without overflow. A host
  Android/device capture is unavailable in this workspace, so the rendered
  evidence is widget-level rather than a physical-device sign-off.

## Acceptance gate

The work is complete only when the shared two-tier theme is in use, both themes provide every required semantic role, dimensions and typography scale correctly, status/error/transaction feedback is clear, all four profiles use the shared rules, existing functionality remains intact, and the relevant tests plus rendered review pass.

Related expansion source of truth: [`../simplepos_expansion_plan.md`](../simplepos_expansion_plan.md).
