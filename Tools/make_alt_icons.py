#!/usr/bin/env python3
"""Renders the two alternate app icons from the *same arc/lens geometry* as the
approved master — only the colour is changed, never the mark (the brand spec
forbids redrawing it).

The master's exact path data lives in `Icon_Source/LensBeacon_Master_1024.svg`.
This script substitutes the gradient/fill definitions, renders each variant to PNG
with macOS Quick Look, flattens the alpha, and writes the icon sets.

  Midnight — the mark on a near-black field, arcs cooled to a single cyan.
  Mono     — one hue: Lens Cyan mark on a flat Deep Navy field.

Run:  python3 Tools/make_alt_icons.py
"""
from __future__ import annotations
import subprocess, tempfile
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MASTER_SVG = ROOT / "Icon_Source" / "LensBeacon_Master_1024.svg"
ASSETS = ROOT / "LensBeacon" / "Resources" / "Assets.xcassets"

CONTENTS = """{
  "images" : [
    { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""

# Same <defs> block shape as the master; only stop colours differ.
MIDNIGHT_DEFS = """<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0%" stop-color="#050A12"/>
    <stop offset="100%" stop-color="#0B1F33"/>
  </linearGradient>
  <linearGradient id="arc" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#63C7F2"/>
    <stop offset="100%" stop-color="#3B82F6"/>
  </linearGradient>
  <radialGradient id="lens" cx="45%" cy="38%" r="65%">
    <stop offset="0%" stop-color="#AEE6FB"/>
    <stop offset="45%" stop-color="#3B82F6"/>
    <stop offset="100%" stop-color="#0B1F33"/>
  </radialGradient>
</defs>"""

MONO_DEFS = """<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0%" stop-color="#0B1F33"/>
    <stop offset="100%" stop-color="#0B1F33"/>
  </linearGradient>
  <linearGradient id="arc" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#7ECEF4"/>
    <stop offset="100%" stop-color="#7ECEF4"/>
  </linearGradient>
  <radialGradient id="lens" cx="45%" cy="38%" r="65%">
    <stop offset="0%" stop-color="#0B1F33"/>
    <stop offset="100%" stop-color="#0B1F33"/>
  </radialGradient>
</defs>"""

# Mono needs a ring on the optical centre so the lens still reads on a flat field.
MONO_EXTRA = '<circle cx="512" cy="512" r="132" fill="none" stroke="#7ECEF4" stroke-width="16"/>'


def _svg_variant(defs: str, extra: str = "") -> str:
    src = MASTER_SVG.read_text()
    head, _, tail = src.partition("<defs>")
    _, _, after_defs = tail.partition("</defs>")
    body = after_defs
    if extra:
        body = body.replace("<circle cx=\"512\" cy=\"512\" r=\"132\" fill=\"url(#lens)\"/>",
                            f'<circle cx="512" cy="512" r="132" fill="url(#lens)"/>\n{extra}')
    return head + defs + body


def _render(svg_text: str, name: str) -> Image.Image:
    with tempfile.TemporaryDirectory() as td:
        svg = Path(td) / f"{name}.svg"
        svg.write_text(svg_text)
        subprocess.run(["qlmanage", "-t", "-s", "1024", "-o", td, str(svg)],
                       check=True, capture_output=True)
        png = Path(td) / f"{name}.svg.png"
        img = Image.open(png).convert("RGBA")
        flat = Image.new("RGB", img.size, (11, 31, 51))
        flat.paste(img, mask=img.split()[3])
        return flat


def _write(name: str, img: Image.Image) -> None:
    d = ASSETS / f"{name}.appiconset"
    d.mkdir(parents=True, exist_ok=True)
    img.save(d / "icon-1024.png")
    (d / "Contents.json").write_text(CONTENTS)
    print(f"  {name}.appiconset")


def main() -> None:
    if not MASTER_SVG.exists():
        raise SystemExit(f"missing {MASTER_SVG}")
    print("Alternate icons from", MASTER_SVG.name)
    _write("AppIcon-Midnight", _render(_svg_variant(MIDNIGHT_DEFS), "midnight"))
    _write("AppIcon-Mono", _render(_svg_variant(MONO_DEFS, MONO_EXTRA), "mono"))
    print("\nReview both on a Home Screen at 40 pt before shipping (brand spec).")


if __name__ == "__main__":
    main()
