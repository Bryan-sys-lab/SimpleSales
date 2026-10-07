#!/usr/bin/env python3
"""Generate every Simple POS launcher icon from the geometric S mark.

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
from PIL import Image, ImageChops, ImageDraw

# ---------------------------------------------------------------------------
# Palette — mirrors DukaColors in lib/theme/app_theme.dart
# ---------------------------------------------------------------------------
INK = (0x25, 0x1A, 0x1D, 0xFF)       # DukaColors.ink        #251A1D
PAPER = (0xFF, 0xFF, 0xFF, 0xFF)      # DukaColors.onPrimary  #FFFFFF
WINE = (0x6E, 0x26, 0x38, 0xFF)       # DukaColors.primary    #6E2638

# ---------------------------------------------------------------------------
# The mark: the geometric "S" — a single continuous white curve with a wine
# accent dot. The source PNG is exported from the design tool's SVG and
# rendered on a solid ink background; this script strips that background so
# the mark can composited onto whatever surface the platform provides.
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

_GEOMETRIC_S_SOURCE = os.path.join(
    BRANDING, "stitch_simple_pos_launcher_icon",
    "simple_pos_geometric_s_icon", "screen.png",
)


def _load_s_source() -> Image.Image:
    """Load the geometric S source PNG and return it centred in a square canvas.

    The source may be 512x520 (taller than wide) with a solid ink background.
    We centre-crop to a square, upscale for supersampling, and strip the ink
    background to transparency using fast C-level `ImageChops` operations so the
    mark can be composited onto any platform-supplied background.
    """
    src = Image.open(_GEOMETRIC_S_SOURCE).convert("RGBA")
    # Centre-crop to square.
    min_dim = min(src.size)
    left = (src.size[0] - min_dim) // 2
    top = (src.size[1] - min_dim) // 2
    src = src.crop((left, top, left + min_dim, top + min_dim))
    s = min_dim * SUPERSAMPLE
    src = src.resize((s, s), Image.LANCZOS)

    # Build a mask: pixels close to ink become transparent, everything else is kept.
    ink_bg = Image.new("RGB", (s, s), INK[:3])
    diff = ImageChops.difference(src.convert("RGB"), ink_bg)
    diff_gray = diff.convert("L")
    # Threshold: anything that differs from ink by >10 is part of the mark.
    mask = diff_gray.point(lambda v: 255 if v > 10 else 0, mode="L")

    result = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    result.paste(src, (0, 0), mask)
    return result


def render_mark(size: int, scale: float) -> Image.Image:
    """The full-colour geometric S mark on transparency.

    The wine dot is preserved: it is solid wine on white, which reads as its
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

    No wine, no bezel: the launcher tints this one colour and supplies its own
    background, so the entire mark (S stroke and wine dot) is collapsed to a
    single white silhouette.
    """
    mark = render_mark(size, scale)
    alpha = mark.split()[-1]  # alpha channel
    result = Image.new("RGBA", (size, size), PAPER)
    result.putalpha(alpha)
    return result


def render_legacy(size: int) -> Image.Image:
    """Pre-API-26 launcher icon: rounded ink square, S centred on it."""
    s = size * SUPERSAMPLE
    base = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(base).rounded_rectangle(
        (0, 0, s - 1, s - 1),
        radius=LEGACY_BG_RADIUS * s,
        fill=INK,
    )
    # Render the mark at supersampled resolution, then downsample the base.
    mark = _load_s_source()
    mark_size = int(size * SCALE_LEGACY * SUPERSAMPLE)
    mark = mark.resize((mark_size, mark_size), Image.LANCZOS)
    offset = (s - mark_size) // 2
    base.alpha_composite(mark, (offset, offset))
    return base.resize((size, size), Image.LANCZOS)


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
