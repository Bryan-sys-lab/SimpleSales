# Artwork brief — Simple POS icon set

Three artifacts, in the same shape as the reference set in
`stitch_simple_mobile_app/`, but built from **this app's existing brand** rather
than a new one.

| Artifact | Folder | Output | Size |
| --- | --- | --- | --- |
| App icon | `simple_app_icon/` | `screen.png` | 1024 x 1024 |
| Vector icon symbol | `simple_vector_icon_symbol/` | `code.html` + `screen.png` | 512 x 512 |
| Launch / brand hero | `launch_artwork_and_brand_hero_graphic_for_a_modern_mobile_product_named_simple_pos/` | `screen.png` | 1376 x 768 |

Every number below is load-bearing. The colours come from `DukaColors` in
`lib/theme/app_theme.dart` and the geometry from
`generate_launcher_icon.py`; the two must not drift apart.

---

## Prompt 0 — the shared brand system

Paste this first. Prompts 1–3 all build on it, so if your tool takes a single
turn, concatenate this block with one of the three below.

```text
You are producing the icon set for "Simple POS", a point-of-sale app that runs on
a shop counter. Build a coherent set of three assets from one visual system.

BRAND PALETTE — use these exact hex values and no others:
- #251A1D  near-black warm ink  — the icon's squircle background
- #FFFFFF  white                — the receipt and the terminal body
- #6E2638  wine red             — the terminal's screen
- #4B1725  deeper wine          — shadow tone, if any depth is wanted
- #66575B  muted ink            — secondary text
- #F1EAE5  warm off-white       — light background tint
- #F8F5F1  warm paper canvas    — lightest background

The palette is warm and dark: ink and wine, no blue, no cool greys.

THE MARK — a paper receipt with a torn bottom edge, rising out of a POS
terminal. The terminal is a white rounded rectangle; inside its upper portion
is a wine-red screen (the till's display), and the strip of white below it is
the keypad. The receipt emerges from behind the terminal's top edge, so the
terminal overlaps and sits in front of the receipt.

Geometry on a 512 x 512 grid, origin top-left, as fractions of the canvas so it
scales to any size:
- Background squircle: full canvas, corner radius 0.227. Fill #251A1D.
- Receipt: left 0.335, top 0.130, right 0.665, bottom 0.600. Corner radius
  0.024. Fill #FFFFFF.
- Torn bottom edge: 4 points and 3 notches across the receipt's width. Each
  notch is a triangle cutting up into the paper with its apex at y 0.540, inset
  0.012 from each side of its segment so notches stay clear of the rounded
  corners.
- Terminal body: left 0.150, top 0.660, right 0.850, bottom 0.868. Corner
  radius 0.046. Fill #FFFFFF.
- Terminal screen: left 0.200, top 0.660, right 0.800, bottom 0.790. Corner
  radius 0.020. Fill #6E2638. Flush with the terminal's top edge and inset from
  its sides, so the white terminal reads as a bezel around it.
- The screen takes the larger share of the terminal's height on purpose. At
  48 x 48 the whole terminal is only about 10px tall, and an even screen/keypad
  split collapses into a single grey bar.

HARD CONSTRAINTS — these apply to every asset:
- Flat solid fills. No gradients, no shadows, no bevels, no 3D, no glow, no
  inner hairlines, no reflections.
- The mark reads as one flat silhouette. Nothing may depend on being two
  distinct tones.
- No text, no letters, no numbers, no barcode, no currency symbol inside the
  mark.
- #6E2638 on #251A1D is only about 1.6:1 contrast and is unusable as a mark on
  the ink background. Wine only ever appears INSIDE a white shape, where it is
  roughly 10:1.
```

---

## Prompt 1 — app icon

```text
Produce an app launcher icon for Simple POS. 1024 x 1024, opaque, PNG, no
alpha channel.

Draw the brand mark centred on a full-bleed squircle filled #251A1D with corner
radius 0.227 of the canvas. The mark itself uses the geometry and palette given
above, unmodified.

The composition sits slightly low and centred: the receipt's top reaches roughly
a quarter of the way down the canvas, and the terminal's base sits at about 0.87.
Leave generous even margin on all four sides.

The mark must fit entirely inside a circle of 66/108 of the canvas width,
centred — Android crops adaptive icons to a circle, a squircle or a pill and only
guarantees the central 66/108. Scaling the mark to 0.58 of the canvas and
centring it satisfies this.

It must stay legible at 48 x 48 and at 20pt, so: no stroke thin enough to vanish
at 48px, no detail that dissolves when tinted to a single colour, no interior
hairlines.

Output one file: screen.png
```

---

## Prompt 2 — vector icon symbol

```text
Produce the Simple POS mark as a standalone vector asset, for use as an app
icon foreground and as a logo.

Deliver TWO files:

(a) code.html — a single self-contained SVG, and nothing else in the file. Use
    viewBox="0 0 512 512" with explicit width and height of 512. No <text>, no
    <image>, no external references, no embedded raster. Use <rect> and <path>
    only, with fills. Keep the geometry and palette given above exactly.

(b) screen.png — a 512 x 512 raster preview of that SVG, transparent background
    where the squircle is not drawn.

For the SVG deliverable the mark must NOT include the #251A1D squircle: an
adaptive icon foreground layer needs the mark alone on transparency, because the
launcher supplies the background and may crop to any shape.

So export the mark twice from the same geometry:
  - one version WITH the ink squircle, for the legacy icon and for iOS
  - one version WITHOUT the squircle, fully transparent behind the mark, for the
    adaptive foreground

Also note which layer may not carry interior colour: Android 13+ themed icons
take the alpha channel and repaint it in the user's wallpaper palette, so a
monochrome variant of this mark must exist as its own flat silhouette — receipt
and terminal in solid #FFFFFF with the wine screen dropped — not as a recolour
of the foreground. If your tool can emit it, save it alongside as
simple_pos_icon_monochrome_512.png.
```

---

## Prompt 3 — launch artwork / brand hero

```text
Produce the launch and brand hero artwork for Simple POS. 1376 x 768 landscape,
opaque, PNG.

Composition, centred:
- The brand mark — a paper receipt with a torn bottom edge rising out of a POS
  terminal, white and wine-red on ink — presented as a solid tile: the mark on a
  #251A1D squircle with corner radius 0.227, sized to about 22% of the canvas
  height, sitting above centre.
- Below it the wordmark "Simple POS" set in a clean geometric sans, sentence case
  or all caps with generous letterspacing, in #FFFFFF, about 9% of the canvas
  height. Do not add a tagline, a period, or any other punctuation.
- Below the wordmark, one line of supporting text in #66575B at about 40% of the
  wordmark's size, reading "Point of sale, built for the till it runs on".

Background: a deep warm-ink field. Use #251A1D as the base with an extremely
subtle radial lift toward #4B1725 behind the mark, so the tile separates from the
background without a visible edge or a hard vignette. No visible grid, no rays, no
particles, no lens flare, no coloured glow.

The mood is a shop counter after closing: warm, dark, calm, expensive. Nothing in
it should suggest neon, nightlife or a nightclub — this is a tool a shopkeeper
uses all day.

Critical: the mark must stay legible and the wordmark must stay crisp. A hero
graphic gets scaled down to a phone screen and to a presentation slide, so avoid
fine detail, avoid text smaller than the supporting line, and do not let any
lighting effect cross over the wordmark.

Output one file: screen.png
```

---

## Wiring the output into the app

Save the four PNGs into `assets/branding/`:

| Source | Destination |
| --- | --- |
| Prompt 1, deliverable (a) | `simple_pos_icon_1024.png` |
| Prompt 2, `screen.png` with squircle | `simple_pos_icon_512.png` |
| Prompt 2, transparent version | `simple_pos_foreground_512.png` |
| Prompt 2, monochrome silhouette | `simple_pos_icon_monochrome_512.png` |

Then:

```sh
python3 assets/branding/generate_launcher_icon.py   # requires Pillow
```

That renders all 5 Android densities, the adaptive foreground and monochrome
layers at each, and all 19 iOS slots from those four files. Do **not** hand-place
per-density PNGs: nudge the notch spacing in the 192 and it stops matching the
48, and nothing catches it until a shopkeeper sees two different icons on two
handsets.

`test/app_brand_test.dart` checks every generated file exists, is a valid PNG of
the declared pixel size, and that the iOS slots carry no alpha channel — App
Store validation rejects an icon PNG with transparency. A partially-regenerated
set fails CI.

## Two things to change by hand

- `android/app/src/main/res/values/colors.xml` — `brand_ink` and
  `ic_launcher_background` must both be `#251A1D`. The native splash uses
  `brand_ink`, deliberately the same colour as the icon so the app does not
  visibly re-tint between the launcher and startup.
- `lib/screens/splash_screen.dart` — `SimplePosMark` is a `CustomPainter`, not an
  image, and it is the in-app logo drawn in `DukaColors`. Keep it that way: the
  splash is the first frame on a cold boot, and an image that has not decoded yet
  renders as nothing on some devices. `Prompt 3`'s hero is for the Play listing
  and print, not for the in-app splash.