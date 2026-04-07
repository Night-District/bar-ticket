#!/usr/bin/env python3
"""
Generates the Bar Ticket DMG background image.
Subtle black-gray gradient with soft pink orb accents.
Output: dmg-background.png (660x400 px)

Usage:
  pip3 install Pillow
  python3 generate-background.py
"""

import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUTPUT_PATH = os.path.join(os.path.dirname(__file__), "dmg-background.png")
W, H = 660, 400

PINK = (255, 0, 249)
PINK_LIGHT = (255, 128, 252)
PURPLE = (153, 0, 204)


def draw_gradient(img):
    """Draw a subtle vertical dark gradient from near-black to dark gray."""
    draw = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        r = int(12 + t * 10)
        g = int(12 + t * 8)
        b = int(16 + t * 10)
        draw.line([(0, y), (W, y)], fill=(r, g, b))


def draw_glow(canvas, cx, cy, radius, color_rgb, opacity):
    """Draw a soft radial glow."""
    glow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    r = color_rgb
    gd.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        fill=(r[0], r[1], r[2], int(255 * opacity))
    )
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=radius * 0.7))
    canvas.alpha_composite(glow_layer)


def draw_dashed_arrow(draw, x0, x1, y, color, opacity):
    """Draw a dashed horizontal arrow."""
    c = (*color, int(255 * opacity))
    x = x0
    while x < x1 - 12:
        end_x = min(x + 8, x1 - 12)
        draw.line([(x, y), (end_x, y)], fill=c, width=2)
        x += 14
    draw.polygon([(x1, y), (x1 - 10, y - 5), (x1 - 10, y + 5)], fill=c)


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
    img = Image.new("RGBA", (W, H), (12, 12, 16, 255))

    # Gradient base
    draw_gradient(img)

    # Subtle pink/purple orb glows
    draw_glow(img, 560, 60, 200, PINK, 0.06)
    draw_glow(img, 100, 340, 160, PURPLE, 0.05)
    draw_glow(img, 330, 200, 250, PINK, 0.02)

    draw = ImageDraw.Draw(img)

    # Dashed arrow between icon zones (y=170, centered vertically in icon area)
    draw_dashed_arrow(draw, 235, 425, 170, PINK_LIGHT, 0.50)

    # "drag to install" label below arrow
    mono_font = get_font("SFMono-Regular", 12)
    label = "drag to install"
    bbox = draw.textbbox((0, 0), label, font=mono_font)
    label_w = bbox[2] - bbox[0]
    draw.text(
        (330 - label_w // 2, 192),
        label,
        fill=(255, 255, 255, 140),
        font=mono_font
    )

    # Convert to RGB
    final = img.convert("RGB")
    final.save(OUTPUT_PATH, "PNG", optimize=True)
    print(f"Saved: {OUTPUT_PATH} ({W}x{H})")


if __name__ == "__main__":
    main()
