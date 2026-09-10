#!/usr/bin/env python3
"""Generates LensBeacon's app icon and the in-app mark.

Design brief: calm, privacy-first, editorial. A single "beacon lens" — a lens
aperture at the centre with three concentric detection rings opening to the
upper-right, the way a real scan fans out from a point. Warm cream on a deep teal
field, no gloss, no siren colours. Rendered at 4x and downsampled for clean edges.
"""

from PIL import Image, ImageDraw
import math

S = 1024
SS = 4  # supersample factor
W = S * SS

TEAL_TOP = (18, 78, 78)
TEAL_BOT = (10, 48, 50)
CREAM = (244, 240, 230)
CREAM_DIM = (244, 240, 230, 90)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def background():
    img = Image.new("RGB", (W, W))
    px = img.load()
    for y in range(W):
        row = lerp(TEAL_TOP, TEAL_BOT, y / (W - 1))
        for x in range(W):
            px[x, y] = row
    return img


def draw_mark(img, inset_ratio=0.0):
    d = ImageDraw.Draw(img, "RGBA")
    cx = cy = W / 2
    # Optical centre sits a touch low-left so the rings have room to open up-right.
    cx -= W * 0.06
    cy += W * 0.06

    # Concentric detection rings, opening toward the upper-right quadrant.
    ring_widths = [W * 0.028, W * 0.030, W * 0.032]
    radii = [W * 0.20, W * 0.30, W * 0.40]
    for r, lw, alpha in zip(radii, ring_widths, (255, 180, 120)):
        bbox = [cx - r, cy - r, cx + r, cy + r]
        d.arc(bbox, start=-78, end=12, fill=CREAM[:3] + (alpha,), width=round(lw))

    # The lens: an outer ring and a filled iris with a small catch-light notch.
    lr = W * 0.125
    d.ellipse([cx - lr, cy - lr, cx + lr, cy + lr], outline=CREAM, width=round(W * 0.030))
    ir = W * 0.070
    d.ellipse([cx - ir, cy - ir, cx + ir, cy + ir], fill=CREAM)
    # Negative-space aperture blades hint (simple triangle cut).
    hole = W * 0.026
    d.ellipse([cx - hole, cy - hole, cx + hole, cy + hole], fill=(12, 55, 56, 255))


def rounded(img, radius_ratio=0.2237):
    # iOS applies its own mask, but round here too so the standalone PNG looks right.
    r = round(W * radius_ratio)
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W, W], radius=r, fill=255)
    out = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def main():
    img = background().convert("RGBA")
    draw_mark(img)
    icon = rounded(img).resize((S, S), Image.LANCZOS)
    icon.convert("RGB").save("LensBeacon/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

    # A transparent glyph for in-app use (onboarding, About).
    glyph = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_mark_glyph(glyph)
    glyph.resize((S, S), Image.LANCZOS).save("LensBeacon/Resources/Assets.xcassets/Mark.imageset/mark.png")


def draw_mark_glyph(img):
    d = ImageDraw.Draw(img, "RGBA")
    cx, cy = W / 2 - W * 0.04, W / 2 + W * 0.04
    for r, lw, alpha in zip((W * 0.20, W * 0.30, W * 0.40),
                            (W * 0.028, W * 0.030, W * 0.032),
                            (255, 170, 110)):
        d.arc([cx - r, cy - r, cx + r, cy + r], start=-78, end=12,
              fill=(20, 90, 90, alpha), width=round(lw))
    lr = W * 0.125
    d.ellipse([cx - lr, cy - lr, cx + lr, cy + lr], outline=(20, 90, 90, 255), width=round(W * 0.030))
    ir = W * 0.070
    d.ellipse([cx - ir, cy - ir, cx + ir, cy + ir], fill=(20, 90, 90, 255))


if __name__ == "__main__":
    main()
