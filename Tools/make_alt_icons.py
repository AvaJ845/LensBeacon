#!/usr/bin/env python3
"""Derives the two alternate app icons from the approved 1024 master.

This does NOT redraw the mark (the brand spec forbids that). It applies a colour
grade to `Icon_Source/LensBeacon_iOS_iPadOS_1024.png` — the same arcs, lens and
optical centre, recoloured:

  Midnight — the mark on a near-black field, cooled and dimmed. Moodier.
  Mono     — a single-hue treatment: navy shadows lifting to Lens Cyan highlights.

Outputs land in the asset catalog as AppIcon-Midnight / AppIcon-Mono icon sets.
"""
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageEnhance, ImageOps

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "Icon_Source" / "LensBeacon_iOS_iPadOS_1024.png"
ASSETS = ROOT / "LensBeacon" / "Resources" / "Assets.xcassets"

CONTENTS = """{
  "images" : [
    { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""


def _write_set(name: str, img: Image.Image) -> None:
    d = ASSETS / f"{name}.appiconset"
    d.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(d / "icon-1024.png")
    (d / "Contents.json").write_text(CONTENTS)
    print(f"  {name}.appiconset")


def midnight(master: Image.Image) -> Image.Image:
    # The mark on a near-black field: blend the navy background toward black, keep the
    # beacon arcs bright so the silhouette still reads at 40 pt.
    black = Image.new("RGB", master.size, (4, 10, 18))
    out = Image.blend(master.convert("RGB"), black, 0.5)
    out = ImageEnhance.Contrast(out).enhance(1.18)   # push arcs/lens away from the field
    out = ImageEnhance.Brightness(out).enhance(0.9)
    r, g, b = out.split()
    return Image.merge("RGB", (r, g, ImageEnhance.Brightness(b).enhance(1.1)))


def mono(master: Image.Image) -> Image.Image:
    # High-contrast two-tone: the navy field stays dark, the mark lifts to one bright
    # Lens Cyan. A hard-ish contrast curve keeps it from muddying at small size.
    lum = ImageOps.grayscale(master.convert("RGB"))
    lum = ImageOps.autocontrast(lum, cutoff=2)
    lum = ImageEnhance.Contrast(lum).enhance(1.6)
    return ImageOps.colorize(lum, black=(11, 31, 51), white=(126, 206, 244))


def main() -> None:
    if not MASTER.exists():
        raise SystemExit(f"missing {MASTER}")
    master = Image.open(MASTER)
    print("Alternate icons from", MASTER.name)
    _write_set("AppIcon-Midnight", midnight(master))
    _write_set("AppIcon-Mono", mono(master))
    print("\n⚠  Review both on a real Home Screen at 40 pt before shipping — the brand")
    print("   spec gates on 29–40 pt legibility. If either loses the arc/lens read,")
    print("   hand-tune the mark rather than the colour grade.")


if __name__ == "__main__":
    main()
