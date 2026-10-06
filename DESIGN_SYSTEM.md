# Duka POS design system

## 1. Product direction

- Product: Duka POS
- Surface: offline-first mobile/native point-of-sale app
- Platforms: Android and iOS
- Users: shop owners and cashiers working quickly at a counter, often on budget phones
- Main goal: make selling feel immediate and inventory/reporting feel trustworthy
- Design concept: **the counter ledger** — warm paper-like surfaces, ink-dark information, a maroon action spine, and compact transaction rows that make every change feel deliberate and easy to verify.

## 2. Brand and voice

- Style: warm, practical, calm, high-clarity
- Voice: plain and reassuring; use direct verbs such as “Add product”, “Adjust stock”, “Complete sale”
- Errors: say what happened and what the cashier can do next; never expose exception text
- Empty states: explain the next useful action, not just “No data”
- Success states: confirm the completed action and the amount/reference where relevant

References used:

- [Material 3 accessible design](https://m3.material.io/foundations/accessible-design/overview) — platform-native touch sizes, clear state, and contrast discipline.
- [Apple accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility) — VoiceOver, Dynamic Type, and platform adaptation.
- [Flutter accessibility guide](https://docs.flutter.dev/ui/accessibility) — semantics and assistive-technology implementation.

## 3. Color tokens

| Role | Token | Hex | Use |
|---|---|---:|---|
| Dominant canvas | `canvas` | `#F8F5F1` | App background and breathing room |
| Raised surface | `surface` | `#FFFFFF` | Cards, forms, navigation |
| Warm secondary | `surfaceWarm` | `#F1EAE5` | Selected navigation and subtle emphasis |
| Primary accent | `primary` | `#6E2638` | App bar, primary actions, focus |
| Primary deep | `primaryDark` | `#4B1725` | Pressed/emphasis states |
| Ink | `ink` | `#251A1D` | Main text |
| Muted ink | `mutedInk` | `#66575B` | Supporting text |
| Success | `success` | `#176B4D` | Positive status with text/icon |
| Warning | `warning` | `#9A5B00` | Low stock and attention states |
| Danger | `danger` | `#B3261E` | Errors and destructive actions |
| Outline | `outline` | `#D6C9C4` | Input edges and sparse dividers |

Color is never the only status signal: pair it with a label, count, icon, or message.

## 4. Typography

Use the platform sans-serif through Flutter’s `TextTheme`; do not introduce a second font until a real brand asset is available.

- `headlineSmall`: 24sp / 1.2 / 700 — totals and primary screen titles
- `titleLarge`: 20sp / 1.25 / 700 — section headings
- `titleMedium`: 16sp / 1.3 / 700 — card and list headings
- `bodyLarge`: 16sp / 1.45 — important supporting copy
- `bodyMedium`: 14sp / 1.4 — standard labels and rows
- `bodySmall`: 12sp / 1.35 — secondary metadata only
- Minimum body size: 14sp for dense POS metadata, 16sp for instructions and form help

All text must survive Android 2x and iOS 3x accessibility text scaling without fixed-height clipping.

## 5. Layout and interaction

- Base spacing: 4 / 8 / 12 / 16 / 24 / 32dp
- Corner radius: 14dp controls, 16dp cards, 12dp snackbars
- Minimum target: 48dp Android and 44pt iOS; use Flutter’s 48dp controls consistently
- Navigation: one bottom `NavigationBar`; maximum five destinations; icon plus label
- POS layout: split catalog/cart on tablets and wide phones; stacked catalog/cart on narrow phones
- Primary action: one clear action per screen; destructive actions stay in overflow or confirmation dialogs
- Modality: use dialogs only for focused confirmation/payment input; preserve visible Cancel/Close actions
- Motion: short, functional transitions only; respect `MediaQuery.disableAnimations`

## 6. Components

- Buttons: Material 3 `FilledButton`/`ElevatedButton` with the shared 48dp minimum height
- Inputs: filled white fields, 14dp radius, maroon 2dp focus outline, explicit labels and keyboard types
- Cards: borderless white surfaces; use spacing and elevation sparingly
- Status: label + icon/count, never color alone
- Icon-only controls: always include `tooltip` and a semantic label
- Money: always use `formatMoney()` from `lib/utils/money.dart`
- Loading/error/empty: every data view gets all three states

## 7. Accessibility baseline

Target WCAG 2.2 AA on Android and iOS. Test TalkBack and VoiceOver, 2x Android text scale, 3x iOS Dynamic Type, contrast, focus order, keyboard/switch access, and reduced motion. Async payment/sale outcomes must be visible and announced.

## 8. Implementation source of truth

- Theme tokens: `duka_pos_app/lib/theme/app_theme.dart`
- Money formatting: `duka_pos_app/lib/utils/money.dart`
- Shared shell: `duka_pos_app/lib/screens/home_shell.dart`
- High-frequency workflow: `duka_pos_app/lib/screens/sell_screen.dart`
