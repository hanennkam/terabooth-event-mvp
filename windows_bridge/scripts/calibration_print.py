"""One-shot DNP calibration print client.

Generates a synthetic 1200x1800 JPEG, submits exactly ONE authenticated print
job, and never retries. Intended only for an explicit operator-authorized
physical calibration. Requires --confirm-one-print.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import time
import uuid
from pathlib import Path

import httpx
from PIL import Image, ImageDraw, ImageFont

TEMPLATE = "solo_4x6_v1"


def _token() -> str | None:
    value = os.getenv("TERABOOTH_API_TOKEN")
    if value:
        return value.strip()
    env = Path(".env")
    if env.exists():
        for line in env.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if line.startswith("TERABOOTH_API_TOKEN="):
                return line.split("=", 1)[1].strip()
    return None


def _font(size: int) -> ImageFont.ImageFont:
    for path in (
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            pass
    return ImageFont.load_default()


def _make_image() -> bytes:
    width, height = 1200, 1800
    image = Image.new("RGB", (width, height), (18, 20, 26))
    draw = ImageDraw.Draw(image)
    bars = [
        ("RED", (220, 40, 40)), ("GREEN", (40, 190, 80)),
        ("BLUE", (40, 100, 230)), ("CYAN", (40, 200, 220)),
        ("MAGENTA", (210, 50, 180)), ("YELLOW", (240, 210, 40)),
        ("WHITE", (245, 245, 245)), ("BLACK", (5, 5, 5)),
    ]
    bar_h = 120
    top = 170
    for i, (label, color) in enumerate(bars):
        y = top + i * bar_h
        draw.rectangle((100, y, width - 100, y + bar_h - 8), fill=color)
        draw.text((115, y + 10), label, font=_font(28), fill=(0, 0, 0) if label in {"WHITE", "YELLOW"} else (255, 255, 255))
    # border and corner registration marks
    draw.rectangle((49, 49, width - 50, height - 50), outline=(245, 245, 245), width=4)
    for x, y in ((60, 60), (width - 160, 60), (60, height - 160), (width - 160, height - 160)):
        draw.rectangle((x, y, x + 100, y + 100), outline=(245, 245, 245), width=3)
        draw.line((x, y, x + 100, y + 100), fill=(245, 245, 245), width=2)
        draw.line((x + 100, y, x, y + 100), fill=(245, 245, 245), width=2)
    draw.text((100, 70), "TERABOOTH 4x6 CALIBRATION", font=_font(48), fill=(255, 255, 255))
    draw.text((100, 1300), "1200 x 1800 px  |  300 dpi  |  PORTRAIT", font=_font(30), fill=(255, 255, 255))
    draw.text((100, 1360), "STANDARD CUT  |  COLOR / ALIGNMENT / BORDER", font=_font(26), fill=(255, 255, 255))
    draw.text((100, 1420), "SYNTHETIC TEST IMAGE - NOT A CUSTOMER", font=_font(24), fill=(200, 200, 200))
    buf = io.BytesIO()
    image.save(buf, "JPEG", quality=95, dpi=(300, 300))
    return buf.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8788")
    parser.add_argument("--confirm-one-print", action="store_true")
    args = parser.parse_args()
    if not args.confirm_one_print:
        print("Refusing to print without --confirm-one-print")
        return 2
    token = _token()
    if not token:
        print("TERABOOTH_API_TOKEN is not configured")
        return 2
    image_bytes = _make_image()
    digest = hashlib.sha256(image_bytes).hexdigest()
    suffix = uuid.uuid4().hex[:12]
    metadata = {
        "schema": "terabooth.print/1",
        "event_id": f"evt_calibration_{suffix}",
        "session_id": f"ses_calibration_{suffix}",
        "template": TEMPLATE,
        "template_version": 1,
        "copies": 1,
        "paper": "4x6",
        "cut": "4x6",
        "event_text": {"title": "TERABOOTH CALIBRATION", "date": time.strftime("%d %b %Y")},
        "images": [{
            "id": "calibration_image", "filename": "calibration.jpg",
            "sha256": digest, "width": 1200, "height": 1800,
        }],
        "delivery": {"required": False, "ttl_hours": 1},
    }
    headers = {"Authorization": f"Bearer {token}", "Idempotency-Key": f"calibration-{suffix}"}
    timeout = httpx.Timeout(30.0, connect=10.0)
    try:
        with httpx.Client(timeout=timeout) as client:
            response = client.post(
                f"{args.url.rstrip('/')}/v1/print-jobs",
                headers=headers,
                data={"metadata": json.dumps(metadata)},
                files={"image_0": ("calibration.jpg", image_bytes, "image/jpeg")},
            )
            print(f"HTTP {response.status_code}")
            if response.status_code not in (200, 202):
                print(f"Submit failed: {response.text[:500]}")
                return 1
            job = response.json()
            job_id = job["job_id"]
            print(f"job_id={job_id} initial_state={job.get('state')} idempotency={headers['Idempotency-Key']}")
            deadline = time.time() + 150
            while time.time() < deadline:
                status = client.get(f"{args.url.rstrip('/')}/v1/print-jobs/{job_id}", headers={"Authorization": f"Bearer {token}"})
                if status.status_code != 200:
                    print(f"Status failed: HTTP {status.status_code} {status.text[:300]}")
                    return 1
                current = status.json()
                if current.get("state") in {"completed", "failed", "unknown"}:
                    print("final=" + json.dumps({
                        "job_id": current.get("job_id"),
                        "state": current.get("state"),
                        "completion": current.get("completion"),
                        "printer_mode": current.get("printer_mode"),
                        "error": current.get("error"),
                        "images": current.get("images"),
                    }, separators=(",", ":")))
                    break
                time.sleep(2)
            else:
                print("Timed out waiting for terminal state; no retry submitted")
                return 1
            artefact = client.get(f"{args.url.rstrip('/')}/v1/print-jobs/{job_id}/artefact", headers={"Authorization": f"Bearer {token}"})
            if artefact.status_code != 200:
                print(f"Artefact retrieval failed: HTTP {artefact.status_code}; no retry submitted")
                return 1
            with Image.open(io.BytesIO(artefact.content)) as rendered:
                print(f"artefact_size={rendered.size} artefact_bytes={len(artefact.content)}")
            return 0
    except Exception as exc:  # noqa: BLE001
        print(f"Calibration request failed: {exc}; no retry submitted")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
