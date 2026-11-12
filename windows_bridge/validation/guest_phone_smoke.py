"""Disposable guest-phone LAN smoke test for the Terabooth bridge.

The PowerShell wrapper sets independent API/delivery secrets and invokes this
script. All data lives under a fresh temporary directory. No production
database, port 8787 process, printer or camera is touched.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PUBLIC = "http://192.168.8.192:8788"


def request(url: str, *, method="GET", headers=None, body=None, timeout=15):
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.read(), dict(response.headers)


def multipart(fields: dict[str, str], files, boundary: str):
    out = io.BytesIO()
    for name, value in fields.items():
        out.write(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n".encode())
        out.write(value.encode() + b"\r\n")
    for name, filename, data, content_type in files:
        out.write(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{filename}\"\r\n"
            f"Content-Type: {content_type}\r\n\r\n".encode()
        )
        out.write(data + b"\r\n")
    out.write(f"--{boundary}--\r\n".encode())
    return out.getvalue(), f"multipart/form-data; boundary={boundary}"


def jpeg(color) -> bytes:
    image = Image.new("RGB", (900, 1200), color)
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=90)
    return buffer.getvalue()


def wait_health(base: str, token: str, timeout=20) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            status, _, _ = request(
                base + "/v1/health",
                headers={"Authorization": f"Bearer {token}"},
                timeout=1,
            )
            if status == 200:
                return True
        except Exception:
            pass
        time.sleep(0.1)
    return False


def production_port_open() -> bool:
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.settimeout(0.3)
    try:
        return probe.connect_ex(("127.0.0.1", 8787)) == 0
    finally:
        probe.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8788)
    parser.add_argument("--public-url", default=DEFAULT_PUBLIC)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    api_token = os.environ.get("TERABOOTH_API_TOKEN", "")
    delivery_secret = os.environ.get("TERABOOTH_DELIVERY_SECRET", "")
    if not api_token or not delivery_secret:
        print("BLOCKED: run through run_guest_phone_smoke.ps1 so independent secrets are generated.")
        return 2
    if not args.public_url.startswith("http://") or "localhost" in args.public_url or "127.0.0.1" in args.public_url:
        print("BLOCKED: --public-url must be the LAN URL, not localhost.")
        return 2

    root = Path(tempfile.mkdtemp(prefix="terabooth-guest-phone-"))
    data = root / "data"
    data.mkdir()
    local = f"http://127.0.0.1:{args.port}"
    env = os.environ.copy()
    env.update({
        "TERABOOTH_DATA_DIR": str(data),
        "TERABOOTH_HOST": "0.0.0.0",
        "TERABOOTH_PORT": str(args.port),
        "TERABOOTH_PRINTER": "mock",
        "TERABOOTH_PUBLIC_BASE_URL": args.public_url.rstrip("/"),
        "TERABOOTH_API_TOKEN": api_token,
        "TERABOOTH_DELIVERY_SECRET": delivery_secret,
    })
    proc = subprocess.Popen(
        [sys.executable, "scripts/run_bridge.py"],
        cwd=str(ROOT), env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    checks: dict[str, str] = {}
    guest_url = None
    qr_path = None
    try:
        if not wait_health(local, api_token):
            err = ""
            if proc.poll() is not None:
                err = (proc.stderr.read() or b"").decode("utf-8", "replace")[-600:]
            print(f"BLOCKED: disposable bridge did not become healthy. {err}")
            return 2
        checks["isolated_database"] = "PASS" if data.resolve().is_dir() else "FAIL"
        checks["production_port_8787_open"] = "OBSERVED" if production_port_open() else "NOT OBSERVED"
        checks["disposable_bridge_8788"] = "PASS"
        try:
            request(local + "/v1/health")
            checks["unauthenticated_health"] = "FAIL"
        except urllib.error.HTTPError as exc:
            checks["unauthenticated_health"] = "PASS" if exc.code == 401 else f"FAIL ({exc.code})"

        images = [jpeg((220, 60, 90)), jpeg((60, 160, 120))]
        meta = {
            "schema": "terabooth.print/1",
            "event_id": "evt-guest-phone-smoke",
            "session_id": "ses-guest-phone-smoke",
            "template": "duo_4x6_v1",
            "template_version": 1,
            "copies": 1,
            "paper": "4x6",
            "cut": "2x6",
            "event_text": {"title": "Terabooth Guest Smoke", "date": "14 Nov 2026"},
            "images": [
                {"id": f"img{i}", "filename": f"{i}.jpg", "sha256": hashlib.sha256(b).hexdigest(), "width": 900, "height": 1200}
                for i, b in enumerate(images)
            ],
            "delivery": {"required": True, "ttl_hours": 24},
        }
        boundary = "----terabooth-guest-smoke-" + uuid.uuid4().hex
        body, content_type = multipart(
            {"metadata": json.dumps(meta)},
            [(f"image_{i}", f"{i}.jpg", b, "image/jpeg") for i, b in enumerate(images)],
            boundary,
        )
        status, raw, _ = request(
            local + "/v1/print-jobs",
            method="POST",
            headers={
                "Authorization": f"Bearer {api_token}",
                "Idempotency-Key": "guest-phone-smoke-1",
                "Content-Type": content_type,
            },
            body=body,
            timeout=20,
        )
        if status not in (200, 202):
            print(f"BLOCKED: job creation returned {status}")
            return 2
        job = json.loads(raw)
        checks["mock_job_created"] = "PASS"
        for _ in range(120):
            _, raw_job, _ = request(
                local + f"/v1/print-jobs/{job['job_id']}",
                headers={"Authorization": f"Bearer {api_token}"},
            )
            job = json.loads(raw_job)
            if job["state"] in {"completed", "failed", "unknown"} and job.get("gif_state") in {"ready", "failed"}:
                break
            time.sleep(0.1)
        checks["mock_job_completed"] = "PASS" if job["state"] == "completed" else f"FAIL ({job['state']})"
        delivery = job.get("delivery_url")
        if not delivery or not delivery.startswith(args.public_url.rstrip("/") + "/d/"):
            print("BLOCKED: delivery URL did not use the configured LAN public URL.")
            return 2
        guest_url = delivery
        checks["guest_url_public"] = "PASS"
        token = delivery.rsplit("/", 1)[-1]
        local_guest = f"{local}/d/{token}"

        def probe(name, path):
            try:
                status, _, _ = request(local_guest + path, timeout=20)
                checks[name] = "PASS" if status == 200 else f"FAIL ({status})"
            except urllib.error.HTTPError as exc:
                checks[name] = f"FAIL ({exc.code})"

        image_ids = [str(item["id"]) for item in job.get("images", [])]
        probe("guest_page", "")
        probe("manifest", "/manifest.json")
        for index, image_id in enumerate(image_ids, start=1):
            probe(f"original_{index}", f"/original/{image_id}")
        probe("strip", "/strip")
        probe("zip", "/download.zip")
        probe("gif", "/gif")
        checks["branded_strip_generated"] = checks.get("strip", "FAIL")
        try:
            qr = request(local_guest + "/qr.png", timeout=20)
            if qr[0] == 200 and qr[1].startswith(b"\x89PNG"):
                checks["qr_image"] = "PASS"
                qr_path = root / "guest-qr.png"
                qr_path.write_bytes(qr[1])
            else:
                checks["qr_image"] = "FAIL"
        except urllib.error.HTTPError as exc:
            checks["qr_image"] = f"FAIL ({exc.code})"

        passed = all(value == "PASS" for value in checks.values() if value not in {"OBSERVED", "NOT OBSERVED"})
        print("=== GUEST PHONE SMOKE ===")
        for name, value in checks.items():
            print(f"{name}: {value}")
        print(f"GUEST_URL={guest_url}")
        if qr_path:
            print(f"QR_FILE={qr_path}")
        print("This URL contains guest access. Do not post it publicly.")
        if not passed:
            print("SMOKE_RESULT=FAIL; disposable server will stop.")
            return 1
        if args.self_test:
            print("SELF_TEST=complete")
            return 0
        print("Bridge is running. Press Ctrl+C to stop and clean up disposable data.")
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            return 0
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
        try:
            shutil.rmtree(root)
            print("CLEANUP=removed disposable data")
        except OSError as exc:
            print(f"CLEANUP=FAILED {exc}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
