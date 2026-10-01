#!/usr/bin/env python3
"""Builds the menu-bar mark from Stone's 1024px app icon.

Stone desktop's own tray PNG is the sketch scaled straight down, which leaves sub-pixel strokes
that render faint and small. This thickens the ink before scaling and fills an 18pt canvas.

Usage: Scripts/make-menu-bar-mark.py [path/to/icon.png]   (default: ../stone/build/icon.png)
"""
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "stone/build/icon.png"
OUT = ROOT / "Stone/Infrastructure/App/Assets.xcassets/StoneMark.imageset"

CANVAS_PT = 18      # the menu bar's standard template height
GLYPH_PT = 16       # glyph box inside it, leaving a 1pt margin
STROKE_PT = float(__import__("os").environ.get("STROKE_PT", "1.1"))  # target stroke weight once scaled down
SOURCE_STROKE = 12  # pen width in the 1024px artwork, in source pixels

icon = Image.open(SOURCE).convert("RGBA")
# Flatten onto white first: the squircle's soft transparent edge is dark underneath, and would
# otherwise count as ink and stretch the crop to the whole background instead of the cube.
flat = Image.alpha_composite(Image.new("RGBA", icon.size, (255, 255, 255, 255)), icon).convert("L")
ink = ImageChops.invert(flat).point(lambda v: 255 if v > 150 else 0)
box = ink.getbbox()
glyph = ink.crop(box)

scale_to_point = GLYPH_PT / max(glyph.size)
grow = round((STROKE_PT / scale_to_point - SOURCE_STROKE) / 2)
padded = Image.new("L", (glyph.width + 2 * grow, glyph.height + 2 * grow), 0)
padded.paste(glyph, (grow, grow))
thick = padded.filter(ImageFilter.MaxFilter(2 * grow + 1))

for factor, name in ((1, "stoneMark.png"), (2, "stoneMark@2x.png"), (3, "stoneMark@3x.png")):
    canvas = CANVAS_PT * factor
    side = GLYPH_PT * factor
    ratio = side / max(thick.size)
    size = (max(1, round(thick.width * ratio)), max(1, round(thick.height * ratio)))
    alpha = thick.resize(size, Image.LANCZOS)
    mark = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    black = Image.new("RGBA", size, (0, 0, 0, 255))
    black.putalpha(alpha)
    mark.paste(black, ((canvas - size[0]) // 2, (canvas - size[1]) // 2), black)
    mark.save(OUT / name)
    print(f"{name}: {canvas}px, glyph {size[0]}x{size[1]}")
