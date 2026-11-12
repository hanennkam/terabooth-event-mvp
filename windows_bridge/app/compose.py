from __future__ import annotations

import os
from pathlib import Path
from typing import Sequence

from PIL import Image, ImageDraw, ImageFont, ImageOps

from .atomic import replace_with_retry

STRIP_W, STRIP_H = 600, 1800
CANVAS_W, CANVAS_H = 1200, 1800
DPI = 300
MARGIN = 24
HEADER_H = 90
FOOTER_H = 60


def _font(size: int, font_path: str | None = None) -> ImageFont.ImageFont:
    candidates = [
        font_path,
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for c in candidates:
        if not c:
            continue
        try:
            return ImageFont.truetype(c, size)
        except Exception:
            continue
    return ImageFont.load_default()


def _cover(path: Path, size: tuple[int, int]) -> Image.Image:
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im).convert("RGB")
        return ImageOps.fit(im, size, method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))


def compose_strip(image_paths: Sequence[Path], out_path: Path, *, title: str, date: str,
                  font_path: str | None = None) -> Path:
    """Compose two identical 2x6 strips side-by-side on a 4x6 canvas.

    The printed sheet is 1200x1800 at 300 dpi (4x6 in). Each panel is 600x1800
    (2x6 in). The DNP 2-inch cut separates the panels.
    """
    if len(image_paths) != 3:
        raise ValueError("this MVP template requires exactly 3 images")
    canvas = Image.new("RGB", (CANVAS_W, CANVAS_H), "white")
    strip = Image.new("RGB", (STRIP_W, STRIP_H), "white")
    draw = ImageDraw.Draw(strip)

    # Header
    draw.text((STRIP_W // 2, 28), title, fill="black", font=_font(30, font_path), anchor="mm")
    draw.text((STRIP_W // 2, 66), date, fill="black", font=_font(20, font_path), anchor="mm")
    draw.line((MARGIN, HEADER_H - 8, STRIP_W - MARGIN, HEADER_H - 8), fill="black", width=2)

    # 3 photo slots
    gap = 18
    top = HEADER_H + 10
    bottom = STRIP_H - FOOTER_H - 10
    slot_h = (bottom - top - 2 * gap) // 3
    slot_w = STRIP_W - 2 * MARGIN
    for i, p in enumerate(image_paths):
        y = top + i * (slot_h + gap)
        photo = _cover(p, (slot_w, slot_h))
        strip.paste(photo, (MARGIN, y))
        draw.rectangle((MARGIN, y, MARGIN + slot_w - 1, y + slot_h - 1), outline="black", width=2)

    draw.text((STRIP_W // 2, STRIP_H - 30), "TERABOOTH", fill="black",
              font=_font(18, font_path), anchor="mm")

    canvas.paste(strip, (0, 0))
    canvas.paste(strip, (STRIP_W, 0))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    temp = out_path.with_name(f".{out_path.name}.{os.getpid()}.part")
    try:
        canvas.save(temp, "JPEG", quality=95, dpi=(DPI, DPI), optimize=True)
        replace_with_retry(temp, out_path)
    except Exception:
        try:
            temp.unlink(missing_ok=True)
        except OSError:
            pass
        raise
    return out_path


def compose_from_paths(paths: Sequence[str], out_path: str, title: str, date: str,
                       font_path: str | None = None) -> str:
    return str(compose_strip([Path(p) for p in paths], Path(out_path),
                             title=title, date=date, font_path=font_path))
