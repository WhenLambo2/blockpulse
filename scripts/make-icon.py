#!/usr/bin/env python3
"""Generate App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png (opaque, 1024x1024)."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

S = 1024
out = Path(sys.argv[1] if len(sys.argv) > 1 else "App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
img = Image.new("RGB", (S, S), (18, 18, 22))
d = ImageDraw.Draw(img)
# vertical gradient
for y in range(S):
    t = y / S
    d.line([(0, y), (S, y)], fill=(int(18 + 20 * t), int(18 + 10 * t), int(22 - 6 * t)))
orange = (247, 147, 26)
# three stacked blocks (left), slightly offset like a chain
for i, (x, y) in enumerate([(180, 560), (330, 410), (480, 260)]):
    shade = tuple(int(c * (0.75 + 0.125 * i)) for c in orange)
    d.rounded_rectangle([x, y, x + 260, y + 260], radius=48, fill=shade)
# pulse line across
pts = [(90, 760), (330, 760), (400, 620), (470, 880), (560, 520), (640, 760), (934, 760)]
d.line(pts, fill=(255, 255, 255), width=44, joint="curve")
out.parent.mkdir(parents=True, exist_ok=True)
img.save(out, "PNG")
print(out)
