#!/usr/bin/env python3
"""Generate every Simple POS launcher icon from one vector-ish definition.

Why a script and not checked-in binaries alone: the mark is described once,
here, as geometry, and every size is rendered from that single description. A
hand-painted PNG per density drifts — the 192 gets a nudged tooth, the 48 gets
a heavier bezel — and the drift is invisible until someone notices the app
looks different on two launchers. Rendering all 5 Android densities, all 3
adaptive layers and all 19 iOS slots from one function means they cannot
disagree.

Colours are read from lib/theme/app_theme.dart (DukaColors) and are NOT chosen
here. Editing a colour in this file makes the icon drift away from the app, so
change it in the theme and re-run instead.

Usage:  python3 assets/branding/generate_launcher_icon.py
Requires: Pillow.
"""

from __future__ import annotations

import json
import os
from PIL import Image, ImageDraw

# ---------------------------------------------------------------------------
# Palette — mirrors DukaColors in lib/theme/app_theme.dart
# ---------------------------------------------------------------------------
INK = (0x25, 0x1A, 0x1D, 0xFF)  # DukaColors.ink        #251A1D
PAPER = (0xFF, 0xFF, 0xFF, 0xFF)  # DukaColors.onPrimary #FFFFFF
WINE = (0x6E, 0x26, 0x38, 0xFF)  # DukaColors.primary   #6E2638

# ---------------------------------------------------------------------------
# The mark: a receipt with a torn bottom edge rising out of a POS terminal.
#
# Coordinates are fractions of the canvas, origin top-left. Every shape is a
# solid fill on purpose:
#
#  * No thin strokes and no interior hairlines. At 48x48 a 2px line is either
#    gone or a smudge, and the mark has to survive being shrunk, tinted and
#    masked by three different launchers.
#  * The only interior colour is the wine screen inside the terminal body, and
#    it is a solid block rather than a line. Monochrome icons discard it
#    entirely and still read, because each shape is independently identifiable.
#  * PAPER on INK is ~17:1 contrast. WINE on INK is ~1.6:1, which is why the
#    wine is only ever used *inside* a white shape (WINE on PAPER is ~10:1).
# ---------------------------------------------------------------------------
RECEIPT = (0.335, 0.130, 0.665, 0.600)  # left, top, right, bottom
RECEIPT_RADIUS = 0.024
TEETH = 4  # torn edge: 4 points and 3 notches
NOTCH_INSET = 0.012  # keeps the notches clear of the rounded corners
NOTCH_APEX = 0.540  # how far each notch cuts back up into the paper

TERMINAL = (0.150, 0.660, 0.850, 0.868)
TERMINAL_RADIUS = 0.046
# The wine screen sits flush with the terminal's top edge and is inset from its
# sides, so the white terminal reads as a bezel around it and the strip of white
# below it reads as the keypad. The screen takes the larger share on purpose: at
# 48x48 the whole terminal is only 10px tall, and a screen/keypad split that is
# too even collapses into one grey bar.
SCREEN = (0.200, 0.660, 0.800, 0.790)
SCREEN_RADIUS = 0.020

# How much of the canvas the mark fills, per context. Each is set by how much
# of the artwork the platform is about to throw away.
SCALE_LEGACY = 0.92  # rounded square the user sees whole
SCALE_APPLE = 1.00  # iOS masks to a squircle; this mark already has margins
# Adaptive icons only guarantee the central 66/108 of the canvas, and a round
# mask takes a 66dp circle out of that. 0.58 is the largest scale whose widest
# corner (the terminal's bottom-left) still lands inside that circle.
SCALE_ADAPTIVE = 0.58
LEGACY_BG_RADIUS = 0.225  # the legacy square's own corner radius

SUPERSAMPLE = 4  # render large, downsample: edges stay clean at 20px

ANDROID_DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
# The adaptive canvas is 108dp and the <foreground>/<monochrome> layers are
# also 108dp, so they render at 4x the legacy density factor.
ANDROID_ADAPTIVE = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ANDROID_RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
APPICONSET = os.path.join(
    ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset"
)
BRANDING = os.path.join(ROOT, "assets", "branding")


def _px(value: float, size: int, scale: float) -> float:
    """Map a mark coordinate onto the output canvas, honouring the scale."""
    return (0.5 + (value - 0.5) * scale) * size


def _radii(value: float, size: int, scale: float) -> float:
    return value * scale * size


def paper_mask(size: int, scale: float) -> Image.Image:
    """The white silhouette: receipt (with torn edge) plus terminal body.

    Returned as an 8-bit mask so the notches are real transparency rather than
    a flood-fill of the background colour, which is what makes the same code
    usable for the transparent adaptive and monochrome layers.
    """
    s = size * SUPERSAMPLE
    mask = Image.new("L", (s, s), 0)
    draw = ImageDraw.Draw(mask)

    draw.rounded_rectangle(
        tuple(_px(v, s, scale) for v in RECEIPT),
        radius=_radii(RECEIPT_RADIUS, s, scale),
        fill=255,
    )
    left, _, right, bottom = RECEIPT
    segment = (right - left) / TEETH
    for index in range(TEETH - 1):
        start = left + index * segment + NOTCH_INSET
        end = left + (index + 1) * segment - NOTCH_INSET
        draw.polygon(
            [
                (_px(start, s, scale), _px(bottom, s, scale)),
                (_px(end, s, scale), _px(bottom, s, scale)),
                (_px((start + end) / 2, s, scale), _px(NOTCH_APEX, s, scale)),
            ],
            fill=0,
        )

    draw.rounded_rectangle(
        tuple(_px(v, s, scale) for v in TERMINAL),
        radius=_radii(TERMINAL_RADIUS, s, scale),
        fill=255,
    )
    return mask


def screen_mask(size: int, scale: float) -> Image.Image:
    """The wine screen punched into the terminal body."""
    s = size * SUPERSAMPLE
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        tuple(_px(v, s, scale) for v in SCREEN),
        radius=_radii(SCREEN_RADIUS, s, scale),
        fill=255,
    )
    return mask


def _coloured(mask: Image.Image, rgba: tuple[int, int, int, int]) -> Image.Image:
    layer = Image.new("RGBA", mask.size, rgba[:3] + (0,))
    layer.putalpha(mask)
    return layer


def _flatten(mask: Image.Image, size: int) -> Image.Image:
    """Downsample the supersampled mask to `size` with a clean edge."""
    return mask.resize((size, size), Image.LANCZOS)


def render_mark(size: int, scale: float) -> Image.Image:
    """The full-colour mark on transparency, supersampled down to `size`.

    The screen is composited *over* the paper, not under it: it is a cut-out
    window in the white terminal body, so painting it first and the terminal
    second hides it completely.
    """
    paper = _flatten(paper_mask(size, scale), size)
    screen = _flatten(screen_mask(size, scale), size)
    mark = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mark.alpha_composite(_coloured(paper, PAPER))
    mark.alpha_composite(_coloured(screen, WINE))
    return mark


def render_monochrome(size: int, scale: float) -> Image.Image:
    """Solid silhouette for `android:monochrome`.

    No wine, no bezel: the launcher tints this one colour and supplies its own
    background, so anything that survives as a separate tone would collapse.
    """
    paper = _flatten(paper_mask(size, scale), size)
    return _coloured(paper, PAPER)


def render_legacy(size: int) -> Image.Image:
    """Pre-API-26 launcher icon: rounded ink square, mark centred on it."""
    s = size * SUPERSAMPLE
    base = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(base).rounded_rectangle(
        (0, 0, s - 1, s - 1),
        radius=LEGACY_BG_RADIUS * s,
        fill=INK,
    )
    mark = render_mark(size, SCALE_LEGACY)
    base = base.resize((size, size), Image.LANCZOS)
    base.alpha_composite(mark)
    return base


def render_apple(size: int) -> Image.Image:
    """iOS app icon: full-bleed ink square, no alpha channel.

    App Store validation rejects an icon PNG with transparency, so the result
    is flattened to RGB rather than written as RGBA.
    """
    canvas = Image.new("RGB", (size, size), INK[:3])
    mark = render_mark(size, SCALE_APPLE)
    canvas.paste(mark, (0, 0), mark)
    return canvas


def _save(image: Image.Image, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, format="PNG", optimize=True)
    print(f"  {os.path.relpath(path, ROOT):<62} {image.size[0]}x{image.size[1]}")


def main() -> None:
    print("Android legacy ic_launcher.png")
    for folder, size in ANDROID_DENSITIES.items():
        _save(render_legacy(size), os.path.join(ANDROID_RES, folder, "ic_launcher.png"))

    print("Android adaptive foreground")
    for folder, size in ANDROID_ADAPTIVE.items():
        _save(
            render_mark(size, SCALE_ADAPTIVE),
            os.path.join(ANDROID_RES, folder, "ic_launcher_foreground.png"),
        )

    print("Android adaptive monochrome")
    for folder, size in ANDROID_ADAPTIVE.items():
        _save(
            render_monochrome(size, SCALE_ADAPTIVE),
            os.path.join(ANDROID_RES, folder, "ic_launcher_monochrome.png"),
        )

    print("iOS AppIcon.appiconset")
    with open(os.path.join(APPICONSET, "Contents.json"), encoding="utf-8") as handle:
        contents = json.load(handle)
    for entry in contents["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        points = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        _save(render_apple(round(points * scale)), os.path.join(APPICONSET, filename))

    print("Brand masters")
    _save(render_apple(1024), os.path.join(BRANDING, "simple_pos_icon_1024.png"))
    _save(render_apple(512), os.path.join(BRANDING, "simple_pos_icon_512.png"))
    _save(
        render_monochrome(512, 1.0),
        os.path.join(BRANDING, "simple_pos_icon_monochrome_512.png"),
    )
    _save(
        render_mark(512, SCALE_ADAPTIVE),
        os.path.join(BRANDING, "simple_pos_foreground_512.png"),
    )


if __name__ == "__main__":
    main()
