#!/usr/bin/env python3
"""Render the Nerva wordmark from the Gemini master, for every place it appears.

Why a script and not checked-in binaries alone: the logo appears in four
places in the app and on two different surfaces, and a hand-painted PNG per
place drifts — the footer's logo ends up a different size from the settings
panel's, and the light variant ends up a different blue. Rendering both
variants from one pipeline means they cannot disagree.

The source is the generated master: a chrome wordmark on black, with a light
flare under it and a tagline under that. The wordmark is what the app needs;
the flare is a light effect that has nothing to render on a flat surface, and
the tagline is unreadable at the size a footer can afford.

Two variants, because a logo has to work on both of the app's surfaces:

  * `nerva_wordmark_dark.png` — the wordmark as generated: silver letters with
    a blue "A", for the app's NIGHT surfaces, which are near-black like the
    master's own background.
  * `nerva_wordmark_light.png` — the same wordmark in the app's ink with the
    blue deepened, for the app's DAY surfaces, where silver on white would be
    unreadable.

Usage:  python3 assets/branding/generate_nerva_logo.py
Requires: Pillow.
"""

from __future__ import annotations

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)

#: The generated master. Not committed to the app bundle — only the two
#: rendered wordmarks are.
SOURCE = os.path.join(APP, 'Gemini_Generated_Image_msht6emsht6emsht.jpeg')

#: Where the rendered wordmarks land.
OUT_DIR = HERE

# ---------------------------------------------------------------------------
# The crop, MEASURED from the master rather than guessed.
# ---------------------------------------------------------------------------
# The master is 1264x843. Scanning it for bright rows gives three bands:
#
#   363..486   the NERVA letters
#   529..547   the light flare
#   565..604   the tagline
#
# Only the first is the wordmark. The flare is a light effect on black, which
# has nothing to render on a flat surface, and the tagline is unreadable at
# the height a footer can afford.
WORDMARK_BOX = (166, 363, 1097, 486)

#: A little air around the ink, so the letters' anti-aliased edges are not
#: shaved off by the crop.
PADDING = 4

# ---------------------------------------------------------------------------
# The mattes.
# ---------------------------------------------------------------------------
# The master is a light-emitting object on black: a pixel's brightness IS its
# coverage. So the matte is the brightness, and the colour is the pixel.
#
# Two thresholds, because the two variants want different mattes:
#
#   DARK  — a soft one (up to 200). The app's night surfaces are near-black,
#           so the wordmark's own metallic gradient has to survive: a dimmer
#           letter edge has to stay a DIMMER edge, not a hole.
#   LIGHT — a tight one (up to 64). On a white surface a 50%-transparent
#           letter is a washed-out letter, so the matte is nearly binary and
#           the metallic gradient is replaced by flat ink.
DARK_LO, DARK_HI = 8, 200
LIGHT_LO, LIGHT_HI = 8, 64

#: The app's ink, for the light variant's silver letters. The same value the
#: app's own wordmark is painted in, so the two sit together without one
#: looking like a different app.
INK = (0x2D, 0x2A, 0x26)

#: The blue of the "A", deepened for a white surface.
#:
#: The master's blue is (73, 124, 213), which is 2.9:1 against white — a
#: hair under the 3:1 a graphical object has to clear. (36, 96, 190) is
#: 4.7:1, and it is still visibly the same blue.
BLUE = (36, 96, 190)

#: How blue a pixel has to be before it is the "A" rather than a silver letter.
BLUE_TEST = 25


def _alpha(pixel: tuple[int, int, int], lo: int, hi: int) -> int:
    """The coverage of a pixel, from its brightness on black."""
    brightness = max(pixel)
    if brightness <= lo:
        return 0
    if brightness >= hi:
        return 255
    return int(round((brightness - lo) * 255 / (hi - lo)))


def _is_blue(pixel: tuple[int, int, int]) -> bool:
    r, g, b = pixel
    return b > r + BLUE_TEST and b > g + 10


def _crop(master: Image.Image) -> Image.Image:
    left, top, right, bottom = WORDMARK_BOX
    left = max(0, left - PADDING)
    top = max(0, top - PADDING)
    right = min(master.width, right + PADDING)
    bottom = min(master.height, bottom + PADDING)
    return master.crop((left, top, right, bottom)).convert('RGB')


def _render(wordmark: Image.Image, *, light: bool) -> Image.Image:
    """The wordmark on a transparent ground, in one of the two variants."""
    out = Image.new('RGBA', wordmark.size, (0, 0, 0, 0))
    src = wordmark.load()
    dst = out.load()
    lo, hi = (LIGHT_LO, LIGHT_HI) if light else (DARK_LO, DARK_HI)
    for y in range(wordmark.height):
        for x in range(wordmark.width):
            pixel = src[x, y]
            alpha = _alpha(pixel, lo, hi)
            if alpha == 0:
                continue
            if light:
                colour = BLUE if _is_blue(pixel) else INK
            else:
                # The master's own colour, kept: the metallic gradient IS the
                # logo, and a night surface is near enough to the master's own
                # background for it to read exactly as generated.
                colour = pixel
            dst[x, y] = (colour[0], colour[1], colour[2], alpha)
    return out


def main() -> None:
    if not os.path.exists(SOURCE):
        raise SystemExit(
            f'missing source: {SOURCE}\n'
            'The Nerva master is not committed to the app bundle. Put the '
            'generated image at assets/Gemini_Generated_Image_*.jpeg and '
            're-run.'
        )

    master = Image.open(SOURCE)
    wordmark = _crop(master)

    dark = _render(wordmark, light=False)
    dark_path = os.path.join(OUT_DIR, 'nerva_wordmark_dark.png')
    dark.save(dark_path, optimize=True)

    light = _render(wordmark, light=True)
    light_path = os.path.join(OUT_DIR, 'nerva_wordmark_light.png')
    light.save(light_path, optimize=True)

    print(f'wrote {dark_path}  {dark.size[0]}x{dark.size[1]}')
    print(f'wrote {light_path}  {light.size[0]}x{light.size[1]}')


if __name__ == '__main__':
    main()
