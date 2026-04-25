#!/usr/bin/env python3
"""Render the Timed app icon at all required sizes from a single design spec.

The design follows the project's design system rules:
- White Apple-icon squircle (corner radius = 22.4% of width)
- One thin black ring (the clock-dial motif)
- One Apple system blue dot at 12 o'clock (BucketDot signature, single accent)
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

# Design ratios (relative to icon side length)
CORNER_RADIUS = 0.2244
RING_RADIUS = 0.332
RING_STROKE = 0.0547
DOT_RADIUS = 0.0683
DOT_OFFSET_Y = -0.332

BG = (255, 255, 255, 255)
RING = (26, 26, 26, 255)
ACCENT = (0, 122, 255, 255)


def render(side: int) -> Image.Image:
    # Render at 4x then downsample for smoother edges at small sizes.
    scale = 4
    s = side * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    radius = int(CORNER_RADIUS * s)
    draw.rounded_rectangle([(0, 0), (s - 1, s - 1)], radius=radius, fill=BG)

    cx, cy = s / 2, s / 2
    ring_r = RING_RADIUS * s
    ring_stroke = max(1, int(round(RING_STROKE * s)))
    draw.ellipse(
        [(cx - ring_r, cy - ring_r), (cx + ring_r, cy + ring_r)],
        outline=RING,
        width=ring_stroke,
    )

    dot_r = DOT_RADIUS * s
    dot_cx = cx
    dot_cy = cy + DOT_OFFSET_Y * s
    draw.ellipse(
        [(dot_cx - dot_r, dot_cy - dot_r), (dot_cx + dot_r, dot_cy + dot_r)],
        fill=ACCENT,
    )

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
