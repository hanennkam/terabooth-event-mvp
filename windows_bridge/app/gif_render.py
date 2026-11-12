from __future__ import annotations

import os
from pathlib import Path
from typing import Sequence

from PIL import Image, ImageOps

from .atomic import replace_with_retry

GIF_WIDTH = 360
GIF_HEIGHT = 540
FRAME_DURATION_MS = 1800
FRAME_COUNT = 3  # legacy three-up default
MIN_FRAMES = 1
MAX_FRAMES = 4
BACKGROUND = (16, 17, 20)


class GifGenerationError(RuntimeError):
    pass


def _frame(path: Path) -> Image.Image:
    try:
        with Image.open(path) as source:
            oriented = ImageOps.exif_transpose(source).convert("RGB")
            contained = ImageOps.contain(
                oriented,
                (GIF_WIDTH, GIF_HEIGHT),
                method=Image.Resampling.LANCZOS,
            )
            frame = Image.new("RGB", (GIF_WIDTH, GIF_HEIGHT), BACKGROUND)
            frame.paste(
                contained,
                ((GIF_WIDTH - contained.width) // 2,
                 (GIF_HEIGHT - contained.height) // 2),
            )
            return frame
    except Exception as exc:
        raise GifGenerationError(f"source image could not be decoded: {path.name}: {exc}") from exc


def cleanup_gif_temp_files(jobs_dir: Path) -> int:
    removed = 0
    if not jobs_dir.exists():
        return 0
    for job_dir in jobs_dir.iterdir():
        if not job_dir.is_dir():
            continue
        for candidate in job_dir.glob(".guest.gif.*.part"):
            try:
                candidate.unlink()
                removed += 1
            except OSError:
                continue
    return removed


def inspect_gif(path: Path, expected_frames: int | None = None) -> dict[str, object]:
    with Image.open(path) as gif:
        if getattr(gif, "format", None) != "GIF":
            raise GifGenerationError("output is not a GIF")
        if gif.size != (GIF_WIDTH, GIF_HEIGHT):
            raise GifGenerationError(f"unexpected GIF size {gif.size}")
        count = int(getattr(gif, "n_frames", 1))
        expected = expected_frames if expected_frames is not None else FRAME_COUNT
        if expected < MIN_FRAMES or expected > MAX_FRAMES:
            raise GifGenerationError(f"unsupported expected frame count {expected}")
        if count != expected:
            raise GifGenerationError(
                f"expected {expected} GIF frames, got {count}"
            )
        loop = int(gif.info.get("loop", -1))
        if loop != 0:
            raise GifGenerationError(f"GIF loop must be infinite (loop=0), got {loop}")
        durations: list[int] = []
        for index in range(count):
            gif.seek(index)
            durations.append(int(gif.info.get("duration", 0)))
        if any(duration != FRAME_DURATION_MS for duration in durations):
            raise GifGenerationError(f"unexpected frame durations {durations}")
        with open(path, "rb") as handle:
            header = handle.read(6)
        if header != b"GIF89a":
            raise GifGenerationError(f"expected GIF89a, got {header!r}")
        return {
            "format": "GIF",
            "width": GIF_WIDTH,
            "height": GIF_HEIGHT,
            "frames": count,
            "durations_ms": durations,
            "loop": loop,
            "bytes": path.stat().st_size,
        }


def generate_gif(image_paths: Sequence[Path], out_path: Path) -> dict[str, object]:
    frame_count = len(image_paths)
    if frame_count < MIN_FRAMES or frame_count > MAX_FRAMES:
        raise GifGenerationError(
            f"1 to 4 source images are required, got {frame_count}"
        )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    temp = out_path.with_name(f".{out_path.name}.{os.getpid()}.part")
    frames: list[Image.Image] = []
    try:
        for path in image_paths:
            if not path.exists():
                raise GifGenerationError(f"source image is missing: {path.name}")
            frames.append(_frame(path))
        # Let Pillow use a consistent adaptive palette for photographic frames.
        palette_frames = [
            frame.convert("P", palette=Image.Palette.ADAPTIVE, colors=256)
            for frame in frames
        ]
        palette_frames[0].save(
            temp,
            format="GIF",
            save_all=True,
            append_images=palette_frames[1:],
            duration=FRAME_DURATION_MS,
            loop=0,
            optimize=True,
            disposal=2,
        )
        try:
            os.chmod(temp, 0o600)
        except OSError:
            pass
        metadata = inspect_gif(temp, expected_frames=frame_count)
        replace_with_retry(temp, out_path)
        return metadata
    except GifGenerationError:
        try:
            temp.unlink(missing_ok=True)
        except OSError:
            pass
        raise
    except Exception as exc:
        try:
            temp.unlink(missing_ok=True)
        except OSError:
            pass
        raise GifGenerationError(str(exc)) from exc
    finally:
        for frame in frames:
            frame.close()
