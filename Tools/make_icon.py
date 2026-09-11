#!/usr/bin/env python3
"""Installs the LensBeacon brand icon into the Xcode asset catalogs and derives the
in-app mark.

The canonical artwork is the Apple Fellow brand kit, vendored in `Icon_Source/`:

    Icon_Source/LensBeacon_iOS_iPadOS_1024.png   iOS / iPadOS master, 1024x1024
    Icon_Source/LensBeacon_watchOS_1088.png      watchOS master, 1088x1088
    Icon_Source/LensBeacon_Master_1024.svg       editable master (arcs + optical centre)
    Icon_Source/IconComposer_Background.svg      layered-icon background (navy gradient)
    Icon_Source/IconComposer_Foreground.svg      layered-icon foreground (the mark)

This script does NOT redraw the mark. It:
  1. copies the iOS master into `LensBeacon/Resources/Assets.xcassets/AppIcon.appiconset`
  2. proportionally scales the watchOS master to 1024 for
     `LensBeaconWatch/Assets.xcassets/AppIcon.appiconset`
  3. renders the transparent in-app glyph (`Mark.imageset`) from the same arc/lens
     geometry as the SVG master, flat Beacon Blue, for onboarding / About.

The layered Icon Composer `.icon` is the intended final form on Xcode 26; producing
it needs the Icon Composer GUI (File ▸ New ▸ Icon, drop in the two IconComposer
SVGs). Until then the flat master below is App Store-valid and preserves the mark
exactly.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Icon_Source"

IOS_MASTER = SRC / "LensBeacon_iOS_iPadOS_1024.png"
WATCH_MASTER = SRC / "LensBeacon_watchOS_1088.png"

IOS_APPICON = ROOT / "LensBeacon/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
WATCH_APPICON = ROOT / "LensBeaconWatch/Assets.xcassets/AppIcon.appiconset/watch-icon-1024.png"
MARK = ROOT / "LensBeacon/Resources/Assets.xcassets/Mark.imageset/mark.png"

BEACON_BLUE = (59, 130, 246, 255)  # #3B82F6 — matches Palette.accent / brand token


def install_app_icons() -> None:
    IOS_APPICON.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(IOS_MASTER, IOS_APPICON)
    print(f"iOS   <- {IOS_MASTER.name} (1024)")

    WATCH_APPICON.parent.mkdir(parents=True, exist_ok=True)
    watch = Image.open(WATCH_MASTER).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    watch.save(WATCH_APPICON)
    print(f"watch <- {WATCH_MASTER.name} scaled 1088->1024")


def _cubic(p0, p1, p2, p3, steps=400):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0]
        y = u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1]
        pts.append((x, y))
    return pts


def render_mark(size=1024, supersample=4) -> None:
    """The same two arcs + optical centre as LensBeacon_Master_1024.svg, flat colour,
    on a transparent field. Used as a template image in the app.

    Each arc is stamped as a run of filled discs (radius = half the SVG stroke
    width) along the sampled bezier — this gives an artefact-free round-capped
    stroke that PIL's wide `line()` cannot."""
    k = supersample
    S = size * k
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = 39 * k  # SVG stroke-width 78 -> radius 39

    def arc(seg):
        line = _cubic(seg[0], seg[1], seg[2], seg[3])[:-1] + _cubic(seg[3], seg[4], seg[5], seg[6])
        for x, y in line:
            cx, cy = x * k, y * k
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BEACON_BLUE)

    # Upper arc: M145 478 C 275 270,430 194,512 194 C 594 194,749 270,879 478
    arc([(145, 478), (275, 270), (430, 194), (512, 194), (594, 194), (749, 270), (879, 478)])
    # Lower arc: M145 546 C 275 754,430 830,512 830 C 594 830,749 754,879 546
    arc([(145, 546), (275, 754), (430, 830), (512, 830), (594, 830), (749, 754), (879, 546)])

    # Optical centre: solid disc with a negative-space pupil, so the glyph still
    # reads when tinted a single colour.
    c = 512 * k
    d.ellipse([c - 132 * k, c - 132 * k, c + 132 * k, c + 132 * k], fill=BEACON_BLUE)
    d.ellipse([c - 52 * k, c - 52 * k, c + 52 * k, c + 52 * k], fill=(0, 0, 0, 0))

    img.resize((size, size), Image.LANCZOS).save(MARK)
    print(f"mark  <- rendered from arc geometry ({size})")


if __name__ == "__main__":
    install_app_icons()
    render_mark()
    print("done. run `xcodegen generate` if the watch appiconset is new.")
