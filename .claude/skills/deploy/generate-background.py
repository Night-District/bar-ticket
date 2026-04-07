#!/usr/bin/env python3
"""
Generates the Bar Ticket DMG background image.
Night District dark branding: #0a0a0f base, pink/purple accents, grid overlay.
Output: dmg-background.png (660x400 px)

Usage:
  pip3 install Pillow
  python3 generate-background.py
"""

import os
import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUTPUT_PATH = os.path.join(os.path.dirname(__file__), "dmg-background.png")
W, H = 660, 400

# ─── Colors ───────────────────────────────────────────────────────────────
BG         = (10, 10, 15)
PINK       = (255, 0, 249)
PINK_LIGHT = (255, 128, 252)
PURPLE     = (153, 0, 204)
WHITE      = (255, 255, 255)


def draw_glow(canvas, cx, cy, radius, color_rgb, opacity):
    """Draw a soft radial glow using a blurred filled ellipse on a temp layer."""
    glow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    r = color_rgb
    gd.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        fill=(r[0], r[1], r[2], int(255 * opacity))
    )
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=radius * 0.6))
    canvas.alpha_composite(glow_layer)


def draw_grid(canvas):
    gd = ImageDraw.Draw(canvas)
    step = 60
    line_color = (255, 255, 255, 8)
    for x in range(0, W, step):
        gd.line([(x, 0), (x, H)], fill=line_color, width=1)
    for y in range(0, H, step):
        gd.line([(0, y), (W, y)], fill=line_color, width=1)


def draw_corner_brackets(draw, margin=20, arm=20, stroke=2):
    """Draw 4 corner bracket decorations in pink at 40% opacity."""
    color = (255, 0, 249, 102)  # 40% opacity

    def bracket(x, y, dx, dy):
        draw.line([(x, y), (x + dx * arm, y)], fill=color, width=stroke)
        draw.line([(x, y), (x, y + dy * arm)], fill=color, width=stroke)

    bracket(margin, margin, +1, +1)           # top-left
    bracket(W - margin, margin, -1, +1)        # top-right
    bracket(margin, H - margin, +1, -1)        # bottom-left
    bracket(W - margin, H - margin, -1, -1)    # bottom-right


def draw_dashed_arrow(draw, x0, x1, y, color, opacity):
    """Draw a dashed horizontal arrow from x0 to x1 at height y."""
    dash_on = 8
    dash_off = 6
    stroke = 2
    c = (*color, int(255 * opacity))

    x = x0
    while x < x1 - 12:
        end_x = min(x + dash_on, x1 - 12)
        draw.line([(x, y), (end_x, y)], fill=c, width=stroke)
        x += dash_on + dash_off

    # Arrowhead
    ax = x1
    draw.polygon([(ax, y), (ax - 12, y - 6), (ax - 12, y + 6)], fill=c)


def get_font(name, size):
    """Try to load a system font, fall back to default."""
    font_paths = [
        f"/System/Library/Fonts/Supplemental/{name}.ttf",
        f"/System/Library/Fonts/{name}.ttf",
        f"/Library/Fonts/{name}.ttf",
    ]
    for path in font_paths:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    try:
        return ImageFont.load_default(size=size)
    except Exception:
        return ImageFont.load_default()


def main():
    # Base canvas (RGBA for compositing)
    img = Image.new("RGBA", (W, H), (*BG, 255))

    # Grid
    draw_grid(img)

    # Glow orbs
    draw_glow(img, 580, 40, 180, PINK, 0.15)
    draw_glow(img, 80, 360, 140, PURPLE, 0.12)

    # Bottom bar tint
    bar_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bar_layer)
    bd.rectangle([(0, 340), (W, H)], fill=(255, 0, 249, 15))   # ~6% pink
    bd.line([(0, 340), (W, 340)], fill=(255, 0, 249, 77), width=1)  # 30% pink line
    img.alpha_composite(bar_layer)

    draw = ImageDraw.Draw(img)

    # Corner brackets
    draw_corner_brackets(draw)

    # Dashed arrow (x: 240→420, y: 175)
    draw_dashed_arrow(draw, 240, 420, 175, PINK, 0.70)

    # "drag to install" label
    mono_font = get_font("SFMono-Regular", 11)
    label = "drag to install"
    bbox = draw.textbbox((0, 0), label, font=mono_font)
    label_w = bbox[2] - bbox[0]
    draw.text((330 - label_w // 2, 200), label, fill=(*PINK_LIGHT, 204), font=mono_font)

    # App name label
    sans_font = get_font("Avenir-Heavy", 13)
    bt_label = "Bar Ticket"
    bbox = draw.textbbox((0, 0), bt_label, font=sans_font)
    draw.text((165 - (bbox[2] - bbox[0]) // 2, 235), bt_label, fill=(*WHITE, 230), font=sans_font)

    # Applications label
    app_label = "Applications"
    bbox = draw.textbbox((0, 0), app_label, font=sans_font)
    draw.text((495 - (bbox[2] - bbox[0]) // 2, 235), app_label, fill=(*WHITE, 230), font=sans_font)

    # Bottom tagline
    tagline = "> bar-ticket --watch ~/Developer"
    bbox = draw.textbbox((0, 0), tagline, font=mono_font)
    draw.text((330 - (bbox[2] - bbox[0]) // 2, 362), tagline, fill=(*PINK_LIGHT, 191), font=mono_font)

    # Convert to RGB for PNG output
    final = img.convert("RGB")
    final.save(OUTPUT_PATH, "PNG", optimize=True)
    print(f"Saved: {OUTPUT_PATH} ({W}x{H})")


if __name__ == "__main__":
    main()
