# Branding assets

Source artwork for the Simple POS launcher icon. Everything here is
**generated** — the PNGs are build output, not the master.

```sh
python3 assets/branding/generate_launcher_icon.py   # requires Pillow
```

## Why a generator

The mark is defined once, as geometry, in `generate_launcher_icon.py`. All five
Android densities, the adaptive foreground and monochrome layers, all nineteen
iOS slots and the masters in this folder come out of that one function.

Hand-tuning each PNG does not work: nudge the tooth spacing in the 192 and it
stops matching the 48, and nothing catches that until a shopkeeper notices the
app looks different on two handsets. Re-run the script instead.

`test/app_brand_test.dart` checks every generated file exists, is a valid PNG
and is the declared pixel size, so a partially-regenerated set fails CI.

## The mark

A receipt with a torn bottom edge, rising out of a POS terminal.

Flat fills only — no gradients, no strokes, no hairlines. Three reasons, all of
them about the 48x48 case:

- A stroke thin enough to look right at 192 is gone at 48, and one thick enough
  to survive 48 is a blob at 192.
- Android 13+ themed icons take the alpha channel and repaint it in the user's
  wallpaper colours. Anything that depends on being two distinct colours stops
  working the moment it is tinted, so `ic_launcher_monochrome.png` is generated
  as its own flat silhouette with the wine screen dropped.
- iOS renders the icon at 20pt on a Spotlight row. Detail that survives the
  home screen does not survive that.

Geometry is in fractions of the canvas and each context picks its own scale,
because each platform throws away a different amount of the artwork:

| Context | Scale | Why |
| --- | --- | --- |
| Legacy Android | 0.92 | The user sees the rounded square whole. |
| iOS | 1.00 | iOS masks to a squircle; the mark already carries its own margins. |
| Android adaptive | 0.58 | Adaptive icons only guarantee the central 66/108, and a round mask takes a 66dp circle out of that. 0.58 is the largest scale whose widest corner still lands inside the circle. |

## Colours

Taken from `DukaColors` in `lib/theme/app_theme.dart`. Not chosen here.

| Token | Hex | Role |
| --- | --- | --- |
| `ink` | `#251A1D` | Background, and the Android splash window. |
| `onPrimary` | `#FFFFFF` | The receipt and terminal body. |
| `primary` | `#6E2638` | The terminal's screen. |

`primary` on `ink` is only about 1.6:1 — unusable as a mark on that
background, which is why the wine appears *inside* a white shape (about 10:1)
rather than on the background. Anything new added to this mark has the same
constraint: pick its pair against what it actually sits on.

Android needs these as resources too, so the values are duplicated in
`android/app/src/main/res/values/colors.xml`. That is the one place the
palette is written down twice; change the theme, then re-run this script.

## What is generated where

- `android/.../mipmap-*/ic_launcher.png` — legacy, pre-API-26
- `android/.../mipmap-*/ic_launcher_foreground.png` — adaptive foreground, 108dp
- `android/.../mipmap-*/ic_launcher_monochrome.png` — themed icon silhouette
- `android/.../mipmap-anydpi-v26/ic_launcher.xml` — the layer stack (hand-written)
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/` — 19 slots, no alpha channel
- `simple_pos_icon_1024.png` / `_512.png` — opaque masters, for print and docs
- `simple_pos_icon_monochrome_512.png` — flat silhouette
- `simple_pos_foreground_512.png` — adaptive foreground on transparency

iOS icons are written as RGB rather than RGBA because App Store validation
rejects an app icon PNG with an alpha channel.
