from pathlib import Path

from PIL import Image

from app.compose import compose_strip


def test_compose_is_exact_4x6(tmp_path, three_images):
    paths = []
    for i, data in enumerate(three_images):
        p = tmp_path / f"{i}.jpg"
        p.write_bytes(data)
        paths.append(p)
    out = tmp_path / "strip.jpg"
    compose_strip(paths, out, title="Kate & Jack", date="14 Nov 2026")
    with Image.open(out) as im:
        assert im.size == (1200, 1800)
        assert im.info.get("dpi") == (300, 300)
    assert out.stat().st_size > 10_000


def test_compose_requires_three(tmp_path, three_images):
    p = tmp_path / "one.jpg"
    p.write_bytes(three_images[0])
    try:
        compose_strip([p], tmp_path / "x.jpg", title="x", date="y")
    except ValueError as exc:
        assert "exactly 3" in str(exc)
    else:
        raise AssertionError("expected ValueError")


def test_cover_applies_all_exif_orientations(tmp_path):
    from PIL import ImageDraw, ImageOps

    from app.compose import _cover

    for orientation in range(1, 9):
        raw = Image.new("RGB", (120, 180), "white")
        draw = ImageDraw.Draw(raw)
        draw.rectangle((0, 0, 39, 59), fill="red")
        draw.rectangle((80, 120, 119, 179), fill="blue")
        exif = Image.Exif()
        exif[274] = orientation
        path = tmp_path / f"orientation_{orientation}.jpg"
        raw.save(path, "JPEG", quality=95, exif=exif)

        with Image.open(path) as opened:
            expected = ImageOps.exif_transpose(opened).convert("RGB")
        actual = _cover(path, expected.size)
        assert actual.size == expected.size, f"orientation {orientation}"
        assert actual.tobytes() == expected.tobytes(), f"orientation {orientation}"
