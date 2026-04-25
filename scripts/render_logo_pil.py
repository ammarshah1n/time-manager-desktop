#!/usr/bin/env python3
"""Render the Timed app icon at all required macOS sizes.

Design (v2 — iWork-style typographic mark):
- Apple-icon squircle (corner radius 22.4% of width)
- Solid Apple system blue background
- Bold geometric white "T" centered, sized for 16x16 legibility
- One color, one shape — confident and Apple-native (Pages/Numbers/Keynote vocabulary)
"""
from __future__ import annotations

import os
import sys
from PIL import Image, ImageDraw

OUT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "Assets.xcassets", "AppIcon.appiconset"
)

SPECS = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

# Squircle (Apple icon shape)
CORNER_RADIUS = 0.2244

# T geometry — proportions chosen so the T fills the canvas confidently and
# survives the downsample to 16x16 without losing the crossbar.
T_BAR_WIDTH = 0.580   # horizontal bar width
T_BAR_HEIGHT = 0.130  # horizontal bar thickness
T_STEM_WIDTH = 0.150  # vertical stem thickness
T_TOTAL_HEIGHT = 0.520
T_BAR_TOP_OFFSET = 0.245  # top edge of horizontal bar from icon top

BG = (0, 122, 255, 255)   # Apple system blue
FG = (255, 255, 255, 255)


def render(side: int) -> Image.Image:
    # Render at 4x and downsample for clean edges at small sizes.
    scale = 4
    s = side * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    radius = int(CORNER_RADIUS * s)
    draw.rounded_rectangle([(0, 0), (s - 1, s - 1)], radius=radius, fill=BG)

    # Unified T as a single 8-vertex polygon — joint at the stem/bar
    # intersection is perfectly seamless.
    bar_w = T_BAR_WIDTH * s
    bar_h = T_BAR_HEIGHT * s
    stem_w = T_STEM_WIDTH * s
    bar_top = T_BAR_TOP_OFFSET * s
    total_h = T_TOTAL_HEIGHT * s
    cx = s / 2

    bar_left = cx - bar_w / 2
    bar_right = cx + bar_w / 2
    stem_left = cx - stem_w / 2
    stem_right = cx + stem_w / 2
    bar_bottom = bar_top + bar_h
    stem_bottom = bar_top + total_h

    polygon = [
        (bar_left, bar_top),
        (bar_right, bar_top),
        (bar_right, bar_bottom),
        (stem_right, bar_bottom),
        (stem_right, stem_bottom),
        (stem_left, stem_bottom),
        (stem_left, bar_bottom),
        (bar_left, bar_bottom),
    ]
    draw.polygon(polygon, fill=FG)

    return img.resize((side, side), Image.LANCZOS)


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    for filename, side in SPECS:
        out = os.path.join(OUT_DIR, filename)
        render(side).save(out, "PNG")
    print(f"Rendered {len(SPECS)} icons → {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
