#!/usr/bin/env python3
"""Generate print-calibration assets (no printer required).

- data/test-4x6-calibration.jpg : 1200x1800 (4x6 @ 300 dpi), two 600x1800 panels
- data/test-2x6-strip.jpg       : 600x1800 (2x6 @ 300 dpi)

The sheet includes rulers, orientation arrows, colour patches and a centre cut line.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1200, 1800
STRIP = 600
DPI = 300


def font(size: int):
    for p in [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "C:/Windows/Fonts/arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()


def panel(draw: ImageDraw.ImageDraw, x0: int, label: str) -> None:
    d = font(34)
    s = font(22)
    draw.rectangle((x0 + 10, 10, x0 + STRIP - 10, H - 10), outline="black", width=2)
    draw.text((x0 + STRIP // 2, 55), label, fill="black", font=d, anchor="mm")
    draw.text((x0 + STRIP // 2, H - 45), "TOP = camera up  |  BOTTOM = cut edge", fill="black", font=s, anchor="mm")

    # ruler ticks every 0.25 inch (75 px) along the left edge
    for i in range(0, 24):
        y = 120 + i * 75
        if y > H - 120:
            break
        length = 40 if i % 4 == 0 else 20
        draw.line((x0 + 20, y, x0 + 20 + length, y), fill="black", width=2)
        if i % 4 == 0:
            draw.text((x0 + 70, y), f"{i // 4}in", fill="black", font=s, anchor="lm")

    # colour patches
    colors = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (0, 0, 0), (255, 255, 255), (128, 128, 128)]
    for i, c in enumerate(colors):
        draw.rectangle((x0 + 300 + (i % 3) * 80, 120 + (i // 3) * 80,
                        x0 + 370 + (i % 3) * 80, 190 + (i // 3) * 80), fill=c, outline="black")
    draw.text((x0 + STRIP // 2, 300), "ARROW →", fill="black", font=d, anchor="mm")
    draw.line((x0 + 160, 330, x0 + 440, 330), fill="black", width=3)
    draw.polygon([(x0 + 440, 330), (x0 + 420, 318), (x0 + 420, 342)], fill="black")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default="data")
    args = ap.parse_args()
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    canvas = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(canvas)
    panel(draw, 0, "LEFT 2x6")
    panel(draw, STRIP, "RIGHT 2x6")
    draw.line((STRIP, 0, STRIP, H), fill="red", width=2)
    draw.text((STRIP, 900), "CUT", fill="red", font=font(28), anchor="mm")
    four = out / "test-4x6-calibration.jpg"
    canvas.save(four, "JPEG", quality=95, dpi=(DPI, DPI))

    strip = canvas.crop((0, 0, STRIP, H))
    two = out / "test-2x6-strip.jpg"
    strip.save(two, "JPEG", quality=95, dpi=(DPI, DPI))

    for p in (four, two):
        with Image.open(p) as im:
            print(f"{p}: {im.size[0]}x{im.size[1]} @ {im.info.get('dpi')}")
    print("Print the 4x6 sheet on DNP media with 2-inch cut; measure both strips.")


if __name__ == "__main__":
    main()
