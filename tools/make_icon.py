"""Draws the Shot Guide app icon: a sun over layered mountains, 1024x1024."""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main(out_dir: str) -> None:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    top, bottom = (14, 42, 58), (232, 118, 58)
    for y in range(SIZE):
        draw.line([(0, y), (SIZE, y)], fill=lerp(top, bottom, (y / SIZE) ** 1.6))
    # Sun
    draw.ellipse([590, 250, 830, 490], fill=(255, 196, 92))
    # Back range
    draw.polygon([(0, 760), (180, 520), (330, 640), (520, 420), (720, 640), (860, 540), (1024, 700), (1024, 1024), (0, 1024)],
                 fill=(38, 74, 88))
    # Front range
    draw.polygon([(0, 860), (240, 600), (400, 760), (560, 620), (780, 860), (1024, 760), (1024, 1024), (0, 1024)],
                 fill=(16, 36, 46))
    # Snow cap on the front peak
    draw.polygon([(240, 600), (200, 644), (230, 640), (252, 660), (278, 640), (290, 650)], fill=(236, 240, 242))
    # Viewfinder corners
    c, w, m = (255, 255, 255), 22, 120
    for (x, y, dx, dy) in [(m, m, 1, 1), (SIZE - m, m, -1, 1), (m, SIZE - m, 1, -1), (SIZE - m, SIZE - m, -1, -1)]:
        draw.line([(x, y), (x + dx * 110, y)], fill=c, width=w)
        draw.line([(x, y), (x, y + dy * 110)], fill=c, width=w)
    img.save(out / "AppIcon.png")
    contents = {
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }
    (out / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    catalog = out.parent
    (catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    print("icon written to", out)


if __name__ == "__main__":
    main(sys.argv[1])
