import io
import sys
from pathlib import Path

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def make_jpeg(color=(200, 80, 120), size=(900, 1200)) -> bytes:
    im = Image.new("RGB", size, color)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=90)
    return buf.getvalue()


@pytest.fixture
def three_images():
    return [make_jpeg((220, 60, 90)), make_jpeg((60, 160, 120)), make_jpeg((80, 100, 220))]
