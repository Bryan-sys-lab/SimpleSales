# Flutter accessibility audit

**Date:** 2026-09-29  
**WCAG target:** 2.2 AA  
**Platforms:** Android and iOS  
**Scope:** Flutter application source audit; device-level TalkBack, VoiceOver, Accessibility Inspector, and Accessibility Scanner runs remain required.

## Summary

| Severity | Open findings | Addressed in this pass |
|---|---:|---:|
| CRITICAL | 0 confirmed from source | 0 |
| MAJOR | 4 | 4 addressed; device verification pending |
| MINOR | 5 | 3 addressed; 1 advisory; device verification pending |

## Findings

### 1. Primary sale and payment outcomes are not announced as status changes

- **Files:** `duka_pos_app/lib/screens/sell_screen.dart` around checkout handlers
- **WCAG:** 4.1.3 Status Messages (Level A, WCAG 2.1)
- **Platforms:** Android, iOS
- **Severity:** MAJOR
- **Issue:** Cash and M-Pesa outcomes must be exposed as a live semantic status in addition to visual feedback.
- **Status:** Addressed in `sell_screen.dart` with a visible live semantic region and `SemanticsService.announce()`.

### 2. Structured personal-data fields lack autofill hints across the app

- **Files:** owner setup, settings/Auth0 dialogs, staff dialogs, M-Pesa form
- **WCAG:** 1.3.5 Identify Input Purpose (Level AA, WCAG 2.1)
- **Platforms:** Android, iOS
- **Severity:** MAJOR
- **Issue:** Email, password, name, and phone fields need consistent `autofillHints` and correct input semantics.
- **Status:** Addressed for owner setup, Auth0/M-Pesa setup, settings, staff PINs, and checkout forms. Device verification remains.

### 3. Forms are not consistently protected against large text reflow

- **Files:** owner setup, backend setup, inventory editor, settings dialogs
- **WCAG:** 1.4.4 Resize Text (Level AA, WCAG 2.0)
- **Platforms:** Android, iOS
- **Severity:** MAJOR
- **Issue:** Several forms use non-scrolling `Column` layouts and inline fixed-size progress indicators. At Android 2x or iOS 3x text size, controls can become unreachable or overflow.
- **Fix:** Wrap long forms in `SingleChildScrollView`, avoid fixed-height text containers, and test at the platform scale limits.

### 4. Hardcoded status colors are scattered outside the theme

- **Files:** dashboard, inventory, settings, backup banner, error utility
- **WCAG:** 1.4.3 Contrast (Minimum) (Level AA, WCAG 2.0) and 1.4.1 Use of Color (Level A, WCAG 2.0)
- **Platforms:** Android, iOS
- **Severity:** MAJOR
- **Issue:** Raw status colors make contrast verification and dark/high-contrast adaptation difficult. Statuses must also retain text or icon context.
- **Status:** Addressed in the application source by routing status colors through `DukaColors`/`ColorScheme`; rendered contrast still requires device verification.

### 5. Inventory remove-staff icon button has no explicit tooltip

- **File:** `duka_pos_app/lib/screens/settings_screen.dart`
- **WCAG:** 4.1.2 Name, Role, Value (Level A, WCAG 2.0)
- **Platforms:** Android, iOS
- **Severity:** MINOR
- **Issue:** The icon-only remove action relies on its visual icon and has no explicit accessible name in source.
- **Fix:** Add `tooltip: 'Remove ${s.name}'` and retain the confirmation dialog.

### 6. Product and cart controls need stronger semantic grouping

- **File:** `duka_pos_app/lib/screens/sell_screen.dart`
- **WCAG:** 1.3.1 Info and Relationships (Level A, WCAG 2.0)
- **Platforms:** Android, iOS
- **Severity:** MINOR
- **Issue:** Product cards visually combine name, price, stock, and cart count, but the semantic reading order is not explicitly grouped.
- **Fix:** Provide one concise product semantic label and keep quantity controls separately labeled. Product card labels were added in this pass.

### 7. Screen-level headings are inconsistent

- **Files:** dashboard, inventory, reports, settings, login/setup screens
- **WCAG:** 2.4.6 Headings and Labels (Level AA, WCAG 2.0)
- **Platforms:** iOS (VoiceOver rotor), Android (TalkBack)
- **Severity:** MINOR
- **Issue:** Some screens have visual headings but no `Semantics(header: true)` marker.
- **Fix:** Mark the primary screen/section headings as semantic headers. Shell title, dashboard Low stock, and Sell Cart were updated in this pass.

### 8. Reduced-motion behavior is not explicitly gated

- **Files:** app-wide; current source has no central motion policy
- **WCAG:** 2.3.3 Animation from Interactions (Level AAA, not scored at AA)
- **Platforms:** Android, iOS
- **Severity:** MINOR / advisory
- **Issue:** No custom animations are currently present, but future transitions could bypass Reduce Motion.
- **Fix:** Keep animations implicit and gate any future `AnimationController`, `Hero`, or custom route transition on `MediaQuery.disableAnimations`.

### 9. Device-level validation is still required

- **Scope:** runtime behavior
- **WCAG:** 2.5.8 Target Size (Minimum) (Level AA, WCAG 2.2), 2.4.11 Focus Not Obscured (Level AA, WCAG 2.2)
- **Platforms:** Android, iOS
- **Severity:** MINOR / verification required
- **Issue:** Source-level defaults now target 48dp, but actual hit regions, keyboard overlap, Switch Access, and VoiceOver focus order require simulator/device validation.
- **Fix:** Run Flutter semantics tests plus Android Accessibility Scanner and Xcode Accessibility Inspector on representative small and large devices.

## Passed or improved checks

- Primary navigation uses one consistent bottom `NavigationBar` with icon and label.
- No bare `GestureDetector` tap targets were found in the application source.
- M-Pesa phone input now uses phone keyboard and telephone autofill semantics.
- Cart icon actions now have explicit tooltips.
- Product actions now expose concise semantic labels.
- Shared theme controls and buttons use accessible-size defaults.

## Out of scope

- WCAG AAA-only criteria, including enhanced contrast and zero animation.
- Web bypass blocks and hover behavior; this is a native Android/iOS app.
- Final contrast readings on physical displays; the next pass should verify rendered theme pairs with Flutter tests and device tools.
