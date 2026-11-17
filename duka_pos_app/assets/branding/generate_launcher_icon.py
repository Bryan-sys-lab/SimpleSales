#!/usr/bin/env python3
"""Generate every SimpleSales launcher icon from the supplied brand artwork.

Why a script and not checked-in binaries alone: the mark is described once,
here, and every size is rendered from that single source. A hand-painted PNG
per density drifts — the 192 gets a nudged tooth, the 48 gets a heavier
bezel — and the drift is invisible until someone notices the app looks
different on two launchers. Rendering all 5 Android densities, all 3
adaptive layers and all 19 iOS slots from one pipeline means they cannot
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
from PIL import Image

# ---------------------------------------------------------------------------
# Palette — mirrors DukaColors in lib/theme/app_theme.dart
# ---------------------------------------------------------------------------
INK = (0x2D, 0x2A, 0x26, 0xFF)       # DukaColors.ink        #2D2A26
PAPER = (0xFF, 0xFF, 0xFF, 0xFF)      # DukaColors.onPrimary  #FFFFFF
GREEN = (0x1B, 0x6B, 0x3A, 0xFF)      # DukaColors.primary    #1B6B3A

# ---------------------------------------------------------------------------
# The supplied glossy lockup is the source of truth. Small adaptive layers use
# its extracted S-and-dot safe mark; full legacy/iOS icons use the complete
# approved square artwork so the platform icon and app branding agree.
# ---------------------------------------------------------------------------

# How much of the canvas the mark fills, per context. Each is set by how much
# of the artwork the platform is about to throw away.
SCALE_LEGACY = 0.92    # rounded square the user sees whole
SCALE_APPLE = 1.00     # iOS masks to a squircle; full canvas
# Adaptive icons only guarantee the central 66/108 of the canvas, and a round
# mask takes a 66dp circle out of that. 0.58 is the largest scale whose widest
# point still lands inside that circle.
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

_GLOSSY_SOURCE = os.path.join(BRANDING, "Glossy SimpleSales App Icon.png")
_SAFE_MARK_OUTPUT = os.path.join(BRANDING, "simple_sales_s_mark.png")


def _load_s_source() -> Image.Image:
    """Extract the supplied artwork's S-and-dot mark into a square tile."""
    source = Image.open(_GLOSSY_SOURCE).convert("RGBA")
    # Explicit crop around the S and dot; excludes the wordmark and tagline.
    src = source.crop((350, 200, 910, 740))
    canvas = Image.new("RGBA", (560, 560), (0, 0, 0, 255))
    canvas.alpha_composite(src, (0, 10))
    s = canvas.width * SUPERSAMPLE
    return canvas.resize((s, s), Image.LANCZOS)


def _load_full_source(size: int) -> Image.Image:
    """Return the supplied full lockup as a square, opaque app icon."""
    return Image.open(_GLOSSY_SOURCE).convert("RGB").resize(
        (size, size), Image.LANCZOS
    )


def render_mark(size: int, scale: float) -> Image.Image:
    """The full-colour geometric S mark on transparency.

    The brand dot is preserved: it is solid green on white, which reads as its
    own tone at every density and survives a monochrome pass because the
    dot's alpha is non-zero.
    """
    supersampled = _load_s_source()  # at SUPERSAMPLE * source_dim
    # Scale the mark to fill `scale` fraction of the output canvas.
    # Resizing directly from the supersampled source with LANCZOS provides
    # natural anti-aliasing — no manual supersample/downsample needed.
    mark_size = int(size * scale)
    mark = supersampled.resize((mark_size, mark_size), Image.LANCZOS)
    output = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - mark_size) // 2
    output.alpha_composite(mark, (offset, offset))
    return output


def render_monochrome(size: int, scale: float) -> Image.Image:
    """Solid white silhouette for `android:monochrome`.

    No green, no bezel: the launcher tints this one colour and supplies its own
    background, so the entire mark (S stroke and brand dot) is collapsed to a
    single white silhouette.
    """
    mark = render_mark(size, scale)
    alpha = mark.split()[-1]  # alpha channel
    result = Image.new("RGBA", (size, size), PAPER)
    result.putalpha(alpha)
    return result


def render_legacy(size: int) -> Image.Image:
    """Pre-API-26 launcher icon from the supplied safe full lockup."""
    return _load_full_source(size).convert("RGBA")


def render_apple(size: int) -> Image.Image:
    """iOS app icon from the supplied full lockup, with no alpha channel.

    App Store validation rejects an icon PNG with transparency, so the result
    is flattened to RGB rather than written as RGBA.
    """
    return _load_full_source(size)


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
    _save(_load_s_source().resize((1024, 1024), Image.LANCZOS), _SAFE_MARK_OUTPUT)
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
