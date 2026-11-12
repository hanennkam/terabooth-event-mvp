from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Mapping

from PIL import Image, ImageDraw, ImageOps

from .atomic import replace_with_retry

from .compose import _font
from .templates import SlotSpec, TemplateSpec


def _rgb(value: int) -> tuple[int, int, int]:
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def _rgba(value: int) -> tuple[int, int, int, int]:
    return ((value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def _open_rgb(path: Path) -> Image.Image:
    with Image.open(path) as im:
        return ImageOps.exif_transpose(im).convert("RGB")


def _draw_contain(
    canvas: Image.Image, image: Image.Image, dest: tuple[int, int, int, int]
) -> None:
    x, y, w, h = dest
    scale = min(w / image.width, h / image.height)
    iw = max(1, round(image.width * scale))
    ih = max(1, round(image.height * scale))
    resized = image.resize((iw, ih), Image.Resampling.LANCZOS)
    canvas.paste(resized, (x + (w - iw) // 2, y + (h - ih) // 2))


def _draw_crop(
    canvas: Image.Image,
    image: Image.Image,
    dest: tuple[int, int, int, int],
    rect: Mapping[str, float],
) -> None:
    sx = float(rect["x"]) * image.width
    sy = float(rect["y"]) * image.height
    sw = float(rect["w"]) * image.width
    sh = float(rect["h"]) * image.height
    src = (round(sx), round(sy), round(sx + sw), round(sy + sh))
    region = image.crop(src)
    x, y, w, h = dest
    canvas.paste(region.resize((w, h), Image.Resampling.LANCZOS), (x, y))


def _hex_rgb(value: str) -> tuple[int, int, int]:
    text = value.lstrip("#")
    if len(text) != 6:
        return (17, 17, 17)
    try:
        return tuple(int(text[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]
    except ValueError:
        return (17, 17, 17)


def _draw_branding(
    canvas: Image.Image,
    branding: Mapping[str, Any],
    offset_x: float,
    *,
    event_title: str,
    font_path: str | None,
) -> None:
    color = _hex_rgb(str(branding.get("color_hex") or "#111111"))
    top = branding.get("placement") == "top"
    title_y = 132 if top else 1680
    tagline_y = title_y + 34
    logo_path = branding.get("logo_path")
    if logo_path:
        try:
            with Image.open(logo_path) as logo:
                logo = ImageOps.exif_transpose(logo).convert("RGB")
                max_w, max_h = 130, 72
                scale = min(max_w / logo.width, max_h / logo.height)
                size = (max(1, round(logo.width * scale)), max(1, round(logo.height * scale)))
                resized = logo.resize(size, Image.Resampling.LANCZOS)
                x = round(offset_x + 54)
                y = 52 if top else 1640
                canvas.paste(resized, (x, y))
        except Exception:
            pass
    title = str(branding.get("title") or event_title or "").strip()
    tagline = str(branding.get("tagline") or "").strip()
    center_x = round(offset_x + 600)
    draw = ImageDraw.Draw(canvas)
    if title:
        draw.text(
            (center_x, title_y), title, fill=color,
            font=_font(27, font_path), anchor="mm",
        )
    if tagline:
        draw.text(
            (center_x, tagline_y), tagline, fill=(74, 70, 64),
            font=_font(17, font_path), anchor="mm",
        )


def compose_template(
    image_paths: Mapping[str, Path],
    out_path: Path,
    template: TemplateSpec,
    *,
    title: str,
    date: str,
    crops: Mapping[str, Mapping[str, Any]] | None = None,
    font_path: str | None = None,
    branding: Mapping[str, Any] | None = None,
) -> Path:
    """Canonical template renderer used by the bridge.

    `crops` is keyed by slot id and contains the normalized crop contract.
    A missing crop or a `fit` crop preserves the complete source image.
    """
    crops = crops or {}
    canvas = Image.new("RGB", (template.canvas_width, template.canvas_height), _rgb(template.background_color))
    images: dict[str, Image.Image] = {}
    try:
        for slot in template.slots:
            # Resolve the image by ordered image index; the API has already
            # mapped IDs to stored paths, never client-supplied paths.
            keys = list(image_paths.keys())
            if slot.image_index >= len(keys):
                raise ValueError(f"template slot {slot.id} has no image")
            image_id = keys[slot.image_index]
            if image_id not in images:
                images[image_id] = _open_rgb(image_paths[image_id])

        for repeat in range(template.repeat_x):
            offset_x = repeat * template.panel_width
            if template.divider_y > 0:
                draw = ImageDraw.Draw(canvas)
                draw.line(
                    (offset_x + 24, template.divider_y, offset_x + template.panel_width - 24, template.divider_y),
                    fill=_rgb(template.divider_color),
                    width=2,
                )
            for slot in template.slots:
                keys = list(image_paths.keys())
                image = images[keys[slot.image_index]]
                dest = (
                    round(offset_x + slot.x),
                    round(slot.y),
                    round(slot.width),
                    round(slot.height),
                )
                crop = crops.get(slot.id)
                if crop is None or crop.get("mode") == "fit":
                    _draw_contain(canvas, image, dest)
                else:
                    _draw_crop(canvas, image, dest, crop["rect"])
                if slot.border_width > 0:
                    draw = ImageDraw.Draw(canvas)
                    draw.rectangle(
                        (dest[0], dest[1], dest[0] + dest[2] - 1, dest[1] + dest[3] - 1),
                        outline=_rgb(slot.border_color),
                        width=max(1, round(slot.border_width)),
                    )

            for text in template.texts:
                value = {
                    "event_title": title,
                    "event_date": date,
                    "literal": text.text,
                }.get(text.kind, "")
                if not value:
                    continue
                draw = ImageDraw.Draw(canvas)
                draw.text(
                    (offset_x + text.x, text.y),
                    value,
                    fill=_rgb(text.color),
                    font=_font(round(text.font_size), font_path),
                    anchor="mm",
                )
            if branding and branding.get("enabled"):
                _draw_branding(
                    canvas, branding, offset_x,
                    event_title=title, font_path=font_path,
                )
    finally:
        for image in images.values():
            image.close()

    out_path.parent.mkdir(parents=True, exist_ok=True)
    temp = out_path.with_name(f".{out_path.name}.{os.getpid()}.part")
    try:
        canvas.save(temp, "JPEG", quality=95, dpi=(template.dpi, template.dpi), optimize=True)
        replace_with_retry(temp, out_path)
    except Exception:
        try:
            temp.unlink(missing_ok=True)
        except OSError:
            pass
        raise
    finally:
        canvas.close()
    return out_path
