#!/usr/bin/env python3
"""Composite captioned App Store / marketing screenshot frames from raw
simulator/device captures, at exact target pixel sizes, headlessly (no browser,
no manual screenshot-of-a-webpage step). Renders straight to the sizes App
Store Connect actually accepts, so the output uploads as-is.

Brand: LensBeacon (Apple Fellow brand kit) — Deep Navy canvas, Lens Cyan
accent, off-white ink. Visually matches Tools/screenshot-frames.html (the
manual/browser fallback this supersedes for the real upload set).

Usage: see Tools/build_appstore_screenshots.py for the actual frame list and
caption copy — this module is just the renderer.
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

NAVY = (11, 31, 51)        # #0B1F33
NAVY2 = (27, 58, 87)       # #1b3a57
CYAN = (99, 199, 242)      # #63C7F2
INK = (234, 242, 251)      # #eaf2fb

FONT_DIR = "/System/Library/Fonts/Supplemental"
BOLD = os.path.join(FONT_DIR, "Arial Bold.ttf")


def radial_gradient(w, h, center_frac=(0.78, 0.0), inner=NAVY2, outer=NAVY, outer_frac=0.85):
    """Approximates the CSS radial-gradient(130% 90% at 78% 0%, navy2, navy 58%)."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = center_frac[0] * w, center_frac[1] * h
    rx, ry = w * 1.05, h * 0.75
    d = np.sqrt(((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2)
    t = np.clip(d / outer_frac, 0, 1)[..., None]
    inner_a, outer_a = np.array(inner, dtype=np.float32), np.array(outer, dtype=np.float32)
    rgb = (inner_a * (1 - t) + outer_a * t).astype(np.uint8)
    return Image.fromarray(rgb, mode="RGB")


def wrap_text(draw, text, font, max_width):
    words = text.split()
    lines, cur = [], ""
    for word in words:
        trial = (cur + " " + word).strip()
        if draw.textlength(trial, font=font) <= max_width or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def rounded_mask(size, radii):
    """radii = (top_left, top_right, bottom_right, bottom_left)."""
    w, h = size
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    tl, tr, br, bl = radii
    d.rectangle([tl, 0, w - tr, h], fill=255)
    d.rectangle([0, tl, w, h - bl], fill=255)
    d.pieslice([0, 0, tl * 2, tl * 2], 180, 270, fill=255)
    d.pieslice([w - tr * 2, 0, w, tr * 2], 270, 360, fill=255)
    d.pieslice([w - br * 2, h - br * 2, w, h], 0, 90, fill=255)
    d.pieslice([0, h - bl * 2, bl * 2, h], 90, 180, fill=255)
    return mask


def render_frame(raw_path, headline, subhead, out_path, out_size,
                  shot_width_frac=0.86, top_pad_frac=0.075, side_pad_frac=0.09,
                  headline_size_frac=0.052, sub_size_frac=0.030, gap_above_shot_frac=0.03):
    """One iPhone/iPad frame: gradient card, headline + subhead, the raw
    screenshot inset at its own native aspect ratio (never force-cropped —
    a distorted or cropped screenshot would be its own small dishonesty)."""
    W, H = out_size
    canvas = radial_gradient(W, H)
    draw = ImageDraw.Draw(canvas)

    side_pad = int(W * side_pad_frac)
    max_text_w = W - 2 * side_pad
    headline_font = ImageFont.truetype(BOLD, int(W * headline_size_frac))
    sub_font = ImageFont.truetype(BOLD, int(W * sub_size_frac))

    y = int(H * top_pad_frac)
    for line in wrap_text(draw, headline, headline_font, max_text_w):
        tw = draw.textlength(line, font=headline_font)
        draw.text(((W - tw) / 2, y), line, font=headline_font, fill=INK)
        y += int(headline_font.size * 1.16)

    y += int(H * 0.012)
    for line in wrap_text(draw, subhead, sub_font, max_text_w):
        tw = draw.textlength(line, font=sub_font)
        draw.text(((W - tw) / 2, y), line, font=sub_font, fill=CYAN)
        y += int(sub_font.size * 1.25)

    text_bottom = y + int(H * gap_above_shot_frac)

    raw = Image.open(raw_path).convert("RGB")
    rw, rh = raw.size
    shot_w = int(W * shot_width_frac)
    shot_h = int(shot_w * rh / rw)
    max_shot_h = H - text_bottom
    if shot_h > max_shot_h:
        shot_h = max_shot_h
        shot_w = int(shot_h * rw / rh)

    shot = raw.resize((shot_w, shot_h), Image.LANCZOS)
    radius = int(shot_w * 0.075)
    mask = rounded_mask((shot_w, shot_h), (radius, radius, 0, 0))

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow_layer = Image.new("L", (shot_w, shot_h), 0)
    ImageDraw.Draw(shadow_layer).rounded_rectangle([0, 0, shot_w, shot_h], radius=radius, fill=90)
    sx, sy = (W - shot_w) // 2, H - shot_h
    shadow.paste((0, 0, 0, 255), (sx, sy + int(H * 0.02)), shadow_layer)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=int(W * 0.02)))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")

    canvas.paste(shot, (sx, sy), mask)
    ImageDraw.Draw(canvas).rounded_rectangle(
        [sx, sy, sx + shot_w, sy + shot_h + radius], radius=radius,
        outline=(255, 255, 255, 40), width=2)

    canvas.save(out_path)
    print("wrote", out_path, canvas.size)


def render_watch_frame(raw_path, headline, out_path, out_size):
    """A Watch frame: flat navy (no gradient — too small a canvas for one to
    read), one headline, the raw screenshot filling the rest at native aspect."""
    W, H = out_size
    canvas = Image.new("RGB", (W, H), NAVY)
    draw = ImageDraw.Draw(canvas)
    max_text_w = W - 2 * int(W * 0.09)
    headline_font = ImageFont.truetype(BOLD, int(W * 0.082))
    y = int(H * 0.07)
    for line in wrap_text(draw, headline, headline_font, max_text_w):
        tw = draw.textlength(line, font=headline_font)
        draw.text(((W - tw) / 2, y), line, font=headline_font, fill=INK)
        y += int(headline_font.size * 1.18)

    raw = Image.open(raw_path).convert("RGB")
    rw, rh = raw.size
    shot_w = int(W * 0.86)
    shot_h = int(shot_w * rh / rw)
    max_shot_h = H - y - int(H * 0.03)
    if shot_h > max_shot_h:
        shot_h = max_shot_h
        shot_w = int(shot_h * rw / rh)
    shot = raw.resize((shot_w, shot_h), Image.LANCZOS)
    radius = int(shot_w * 0.12)
    mask = rounded_mask((shot_w, shot_h), (radius, radius, 0, 0))
    sx, sy = (W - shot_w) // 2, H - shot_h
    canvas.paste(shot, (sx, sy), mask)
    canvas.save(out_path)
    print("wrote", out_path, canvas.size)
