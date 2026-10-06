# Redesign brief — the shared contract

You are redesigning screens in a Flutter POS app at `/home/bstudio/Projects/Pos/duka_pos_app`.
The design system has **already been rebuilt and is frozen**. Your job is to move your
assigned screens onto it.

## Read these first, in this order

1. `lib/theme/primitives.dart` — tier 1, the ONLY file allowed a colour literal
2. `lib/theme/app_colors.dart` — tier 2, `AppColors.of(context).surface` etc.
3. `lib/theme/app_spacing.dart` — `AppSpacing.of(context).md` etc.
4. `lib/theme/app_shapes.dart` — `AppShapes.of(context).card(colors)` etc.
5. `lib/theme/app_motion.dart` — `AppMotion.of(context).fast`, `AppMotion.resolve(context, role)`
6. `lib/theme/app_haptics.dart` — `HapticTheme.of(context).fire(HapticEvent.commit)`
7. `lib/theme/typography.dart` — `AppTypography.of(context).bodyMedium`, `AppTypography.money(...)`
8. `lib/ui/components/surface.dart` — `SurfaceCard`, `SectionHeader`, `DataRow`, `StatTile`
9. `lib/ui/components/status.dart` — `StatusTone`, `StatusChip`, `CountBadge`
10. `lib/ui/components/states.dart` — `EmptyStateView`, `ErrorStateView`, `SkeletonList`
11. `lib/ui/components/controls.dart` — `MoneyText`, `ActionBar`, `SearchField`,
    `SegmentedChoice`, `ConfirmDialog`, `confirmIrreversible`, `PersistentBanner`, `showAppSnackBar`
12. `lib/ui/layout/page.dart` — `AdaptivePage`, `SectionedPage`, `AdaptiveGrid`
13. `lib/ui/layout/window_size_class.dart` — `windowSizeClassOf(context)`
14. `lib/ui/brand/simple_pos_mark.dart` — `SimplePosMark`, `SimplePosWordmark`

## Non-negotiable rules

### Tokens — a hard gate will fail your work
- **NO** raw `Color(0x…)`, `Colors.*` (except `Colors.transparent`), `Curves.*`,
  `Duration(milliseconds:|seconds:)`, literal `BorderRadius.circular(n)`, or
  `fontSize: n` in any file you edit. Read a semantic slot instead.
- The ONLY exceptions: `lib/theme/**` and `lib/ui/brand/**` (brand identity is a constant).

### Semantics — the accessibility floor, every screen
- Every interactive node: `Semantics(button: true, label: <the display label>, …)`.
  The label is the **display label**, not a sentence.
- Every `Icon`: a `semanticLabel`, or wrap in `ExcludeSemantics` when decorative.
  There is no third option.
- Author traversal with `sortKey: OrdinalSortKey(n)` where priority ≠ layout order.
- Expose state as a **value** or `liveRegion`, never as a luminance step.
- Transient results: `Semantics(liveRegion: true)` or `showAppSnackBar`.

### Targets and text scale
- Every interactive target ≥ 44×44 logical px and **single-tap**. No long-press-only
  or drag-only affordance — every gesture needs a visible, focusable fallback.
- **BANNED**: `MediaQuery.withClampedTextScaling`, `textScaleFactor`, `FittedBox`,
  and `TextOverflow.ellipsis` on a real user label. Fix the layout instead — flexible
  heights, wrapping text. A truncated price or product name is a bug.
- Use `minHeight` / `ConstrainedBox`, never a fixed `SizedBox(height: N)` on anything
  holding text.
- Never gate anything on `MediaQuery.highContrastOf` — it is always false on Android.

### Directional geometry (RTL-safe from the first commit)
- `EdgeInsetsDirectional.only(start:, end:, top:, bottom:)`, `EdgeInsetsDirectional.symmetric`,
  `AlignmentDirectional`, `TextAlign.start/end`, `MainAxisAlignment.start/end`.
- **BANNED**: `EdgeInsets.only(left:/right:)`, `Alignment.centerLeft/centerRight`,
  `Positioned(left:/right:)`, `TextAlign.left/right`.
- **`Icons.adaptive.*` DOES NOT EXIST IN FLUTTER.** It is React Native's idiom.
  I got this wrong in an earlier revision of this brief and three files inherited
  it — do not propagate it.
- **CORRECT for direction-implying glyphs: just use them.** Flutter's
  direction-implying icons (`arrow_back`, `arrow_forward`, `chevron_left`,
  `chevron_right`, `list`, `send`, `reply`, `redo`, `undo`, `login`, `logout`,
  `sort`, `help`, `label`, `first_page`, `last_page`, `trending_up`, …) are
  declared with `matchTextDirection: true`, so `Icon` mirrors them automatically
  under an RTL locale. There is nothing extra to do.
- BANNED are the icons that imply direction but are NOT flagged, where you must
  pick the directional pair yourself: `Icons.chevron_right` is fine (flagged),
  but a hand-drawn path or a `CustomPaint` arrow is not. If you need a genuinely
  non-mirroring glyph (a clock, a checkmark, media play/pause, a logo), that is
  correct — leave it.

### Colour is never the only channel
Every stateful meaning (selected, paid, low stock, blocked, over) needs ≥3 independent
channels. Use `StatusChip`/`StatusTone` — it already does glyph + word + monotonic weight,
with colour derived last.

### Motion
- Read durations from `AppMotion.of(context)` and wrap with `AppMotion.resolve(context, role)`
  so they collapse to `Duration.zero` under `MediaQuery.disableAnimationsOf(context)`.
- Never re-read the platform flag per animation; never animate `height`/`width`/`top`/`left`.
- Under the motion dial 3/10: motion only ACKNOWLEDGES a commit. Tab switches and
  screen changes are instant.
- Fire haptics through `HapticTheme.of(context).fire(HapticEvent.commit)` — once per
  committed event, on the commit frame, never in an animation listener or a per-item loop.

### Adaptive
- Branch on `windowSizeClassOf(context)` / `LayoutBuilder`, **never** `Platform.isAndroid`
  or a device check.
- Read the narrowest MediaQuery aspect: `sizeOf`, `paddingOf`, `viewInsetsOf` — not `.of`.
- Edge content in `SafeArea`; respect `viewInsetsOf(context).bottom` for the keyboard.
- Never lock orientation. Top-level regions use `Expanded`/`Flexible`/`ConstrainedBox`,
  never fixed pixel widths.

### Widget composition
- Extract **widget classes**, never `Widget _buildX()` methods. `const` where legal,
  every field `final`.
- `build()` ≤ ~80 lines. No I/O, formatting, `DateTime.now()`, or domain math in `build()`.
- Lists: `ListView.builder`/`SliverList`. Never `ListView(children: items.map(...))`
  for unbounded data.
- Callbacks resolve a **stable id**, never a captured content value.
- `StatelessWidget` by default; `StatefulWidget` only for local ephemeral state.
  Every controller/FocusNode/subscription `dispose()`d.
- Async: `await` or handle explicitly. Capture `ScaffoldMessenger`/`Navigator` **before**
  an await; guard `context.mounted` after. Never `context.go` after an await without it.

### States
Resolve exactly one of loading / empty / error / content in a **single switch** over an
`AsyncValue` or your own sealed state. Never a triple of `isLoading`/`error`/`items` bools.
- empty ≠ filtered-empty ≠ error. Use `EmptyStateView(kind: …)` and distinguish them.
- Never render `e.toString()` or a stack trace. Map to a human message.
- Refresh keeps previous content; loading is a delayed `SkeletonList` shaped like the result.
- Error state always offers a next action that preserves scroll/filters/input.

### Copy
- Button labels = verb + object ("Charge KSh 4,320"), never "OK".
- No em dashes (U+2014) anywhere. No marketing buzzwords.
- The app is "Simple POS" (already in `lib/app_brand.dart`). Do not hardcode the name.

## API changes you must respect

The app moved to `go_router`. Existing call sites that used the old tab enum must change:

```dart
// OLD (gone)
context.read<HomeShellTabs>().goTo(HomeTab.inventory);
// NEW
context.read<HomeShellTabs>().goTo(AppDestination.inventory);
// import '../routing/routes.dart';
```

- Navigate with `context.go(Routes.x)` to replace the stack, `context.push(Routes.x)` to
  stack a screen you pop back from. Import from `lib/routing/routes.dart`.
- Do NOT call `Navigator.push` / `MaterialPageRoute` any more.
- `DukaColors` / `DukaSpacing` are **gone**. Grep for them in your files and replace.
- `lib/widgets/sign_out_sheet.dart` provides `CartLineCount` via the shell — keep reading it.

## What NOT to change

- Do not edit anything in `lib/theme/**`, `lib/ui/**`, `lib/routing/**`, `lib/main.dart`,
  `lib/services/**`, `lib/db/**`, `lib/models/**`, `lib/utils/**`, `pubspec.yaml`, or
  `test/**`. Other agents own those and are editing them concurrently.
- **Preserve all business logic.** Every database call, service call, model field,
  validation rule, receipt/eTIMS/printer path, and business message must survive.
  This is a presentation rewrite, not a feature rewrite.
- If you need a new shared component, put it in **your own screen file** as a private
  widget class. Do not add files under `lib/ui/`.
- Keep each file's existing public class names and constructor signatures, EXCEPT where
  this brief tells you to add a parameter.

## Verify before you report back

Run and make clean:

```
export PATH="$HOME/.local/share/flutter/bin:$PATH"
cd /home/bstudio/Projects/Pos/duka_pos_app
dart format lib/screens/<your files>
dart analyze lib/screens/<your files>
```

Then grep your own files for banned constructs and confirm zero hits:

```bash
grep -nE "Color\(0x|Colors\.(white|black|grey|gray|red|blue|green)|Curves\.ease|Duration\(milliseconds:|Duration\(seconds:|BorderRadius\.circular\(|fontSize:|withClampedTextScaling|textScaleFactor|FittedBox|EdgeInsets\.only\((left|right)|Align(ment)?\.center(Left|Right)|TextAlign\.(left|right)" lib/screens/<your files>
```

The only permitted `TextOverflow.ellipsis` is on a value that is decorative or
already fully available to assistive tech via `semanticLabel`.

## Design intent for this app

Warm paper and one confident wine accent. Operate-mode density: packed rows, tight
numeric alignment with tabular figures, minimal decoration, generous targets. This is a
till at a counter between a customer and a sale — legibility from arm's length and
speed on a thumb beat any amount of polish.






github_pat_[REDACTED]

dsn

https://6529a0aed5ec916a608b772aeacf5563@o4512208404348928.ingest.de.sentry.io/4512208431284304