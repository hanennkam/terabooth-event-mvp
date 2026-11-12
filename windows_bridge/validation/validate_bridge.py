"""Disposable Windows validation for the Terabooth bridge runtime.

Run with the runtime-only .venv on the Windows laptop. It never reads or deletes
production data; all state is under a fresh temporary directory.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import io
import json
import os
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

from PIL import Image

try:
    import resource
except ImportError:
    resource = None  # type: ignore[assignment]

ROOT = Path(__file__).resolve().parent.parent
TOKEN = "validation-api-token"

_WINDOWS_VERSION_FIELDS = (
    "major",
    "minor",
    "build",
    "platform",
    "service_pack",
    "service_pack_major",
    "service_pack_minor",
    "suite_mask",
    "product_type",
)


def windows_version_info(version=None) -> dict[str, object] | None:
    """Return documented Windows version fields without relying on _asdict()."""
    if version is None:
        if not sys.platform.startswith("win"):
            return None
        version = sys.getwindowsversion()
    return {
        field: getattr(version, field)
        for field in _WINDOWS_VERSION_FIELDS
        if hasattr(version, field)
    }


def lan_ip() -> str:
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            probe.connect(("192.0.2.1", 80))
            return probe.getsockname()[0]
        finally:
            probe.close()
    except OSError:
        return "192.0.2.10"


def rss_bytes(pid: int) -> int | None:
    if sys.platform.startswith("win"):
        try:
            from ctypes import wintypes

            class Counters(ctypes.Structure):
                _fields_ = [
                    ("cb", wintypes.DWORD),
                    ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t),
                    ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t),
                    ("PeakPagefileUsage", ctypes.c_size_t),
                ]

            kernel = ctypes.windll.kernel32
            psapi = ctypes.windll.psapi
            handle = kernel.OpenProcess(0x1000 | 0x0400, False, pid)
            if not handle:
                return None
            counters = Counters()
            counters.cb = ctypes.sizeof(counters)
            ok = psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb)
            kernel.CloseHandle(handle)
            return int(counters.WorkingSetSize) if ok else None
        except Exception:
            return None
    try:
        raw = Path(f"/proc/{pid}/statm").read_text().split()[1]
        return int(raw) * os.sysconf("SC_PAGE_SIZE")
    except Exception:
        pass
    if resource is None:
        return None
    try:
        value = int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
        return value if sys.platform == "darwin" else value * 1024
    except Exception:
        return None


def request(url: str, *, method="GET", headers=None, body=None, timeout=8):
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.read(), dict(response.headers)


def multipart(fields: dict[str, str], files: list[tuple[str, str, bytes, str]]):
    boundary = "----terabooth-validation-" + uuid.uuid4().hex
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


def wait_health(base: str, timeout=15) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            status, _, _ = request(
                base + "/v1/health",
                headers={"Authorization": f"Bearer {TOKEN}"},
                timeout=1,
            )
            if status == 200:
                return True
        except Exception:
            pass
        time.sleep(0.1)
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18787)
    parser.add_argument("--keep-report", action="store_true")
    args = parser.parse_args()

    started = time.time()
    root = Path(tempfile.mkdtemp(prefix="terabooth-validation-"))
    data = root / "data with spaces"
    data.mkdir()
    report = {"status": "BLOCKED", "checks": {}, "metrics": {}, "errors": []}
    base = f"http://127.0.0.1:{args.port}"
    public = f"http://{lan_ip()}:{args.port}"
    env = os.environ.copy()
    env.update({
        "TERABOOTH_DATA_DIR": str(data),
        "TERABOOTH_HOST": "127.0.0.1",
        "TERABOOTH_PORT": str(args.port),
        "TERABOOTH_PRINTER": "mock",
        "TERABOOTH_API_TOKEN": TOKEN,
        "TERABOOTH_DELIVERY_SECRET": "validation-delivery-secret",
        "TERABOOTH_PUBLIC_BASE_URL": public,
    })
    py = sys.executable
    proc = None

    def check(name, fn):
        try:
            value = fn()
            report["checks"][name] = {"status": "PASS", "detail": value}
            return True
        except Exception as exc:
            report["checks"][name] = {"status": "FAIL", "detail": str(exc)}
            report["errors"].append(f"{name}: {exc}")
            return False

    def start():
        nonlocal proc
        proc = subprocess.Popen(
            [py, "scripts/run_bridge.py"],
            cwd=str(ROOT), env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
        if not wait_health(base):
            err = ""
            if proc.poll() is not None:
                err = (proc.stderr.read() or b"").decode("utf-8", "replace")[-800:]
            raise RuntimeError(f"bridge did not become healthy: {err}")
        return {"pid": proc.pid, "startup_seconds": round(time.time() - started, 3)}

    try:
        report["environment"] = {
            "platform": sys.platform,
            "windows": windows_version_info(),
            "python": sys.version.split()[0],
            "executable": py,
            "temp_data": str(data),
        }
        check("runtime_imports", lambda: __import__("fastapi").__version__)
        start_info = None
        check("startup_health", lambda: (globals().__setitem__("start_info", start()) or start_info))
        if report["checks"]["startup_health"]["status"] == "PASS":
            check("diagnostics", lambda: request(base + "/v1/diagnostics", headers={"Authorization": f"Bearer {TOKEN}"})[0])
            report["metrics"]["idle_rss_bytes"] = rss_bytes(proc.pid)
            images = [jpeg((220, 60, 90)), jpeg((60, 160, 120))]
            meta = {
                "schema": "terabooth.print/1",
                "event_id": "evt-validation",
                "session_id": "ses-validation",
                "template": "duo_4x6_v1",
                "template_version": 1,
                "copies": 1,
                "paper": "4x6",
                "cut": "2x6",
                "event_text": {"title": "Validation Event", "date": "14 Nov 2026"},
                "images": [
                    {"id": f"img{i}", "filename": f"{i}.jpg", "sha256": hashlib.sha256(b).hexdigest(), "width": 900, "height": 1200}
                    for i, b in enumerate(images)
                ],
                "delivery": {"required": True, "ttl_hours": 24},
            }
            body, content_type = multipart(
                {"metadata": json.dumps(meta)},
                [(f"image_{i}", f"{i}.jpg", b, "image/jpeg") for i, b in enumerate(images)],
            )
            submit_headers = {"Authorization": f"Bearer {TOKEN}", "Idempotency-Key": "validation-1", "Content-Type": content_type}
            status, raw, _ = request(base + "/v1/print-jobs", method="POST", headers=submit_headers, body=body, timeout=20)
            if status not in (200, 202):
                raise RuntimeError(f"print submit returned {status}: {raw[:200]!r}")
            job = json.loads(raw)
            for _ in range(100):
                _, raw_job, _ = request(
                    base + f"/v1/print-jobs/{job['job_id']}",
                    headers={"Authorization": f"Bearer {TOKEN}"},
                )
                job = json.loads(raw_job)
                if job["state"] in {"completed", "failed", "unknown"} and job.get("gif_state") in {"ready", "failed"}:
                    break
                time.sleep(0.1)
            report["checks"]["mock_job"] = {"status": "PASS" if job["state"] == "completed" else "PARTIAL", "detail": {"state": job["state"], "gif_state": job.get("gif_state")}}
            token = job["delivery_url"].rsplit("/", 1)[-1]
            local_url = f"{base}/d/{token}"
            first_image_id = job["images"][0]["id"]
            for name, suffix in [
                ("guest_page", ""),
                ("manifest", "/manifest.json"),
                ("original", f"/original/{first_image_id}"),
                ("zip", "/download.zip"),
                ("qr", "/qr.png"),
            ]:
                check(name, lambda s=suffix: request(local_url + s, timeout=10)[0])
            report["metrics"]["post_job_rss_bytes"] = rss_bytes(proc.pid)
            # Sequential guest requests only.
            for _ in range(3):
                request(local_url, timeout=8)
                request(local_url + "/download.zip", timeout=10)
            report["metrics"]["post_requests_rss_bytes"] = rss_bytes(proc.pid)
            def invalid_token():
                try:
                    request(base + "/d/not-a-token")
                    return False
                except urllib.error.HTTPError as exc:
                    return exc.code == 404

            check("invalid_token", invalid_token)
        # Single instance and port conflict.
        second = subprocess.run([py, "scripts/run_bridge.py"], cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=20)
        report["checks"]["single_instance"] = {"status": "PASS" if second.returncode == 2 else "FAIL", "detail": (second.stderr or second.stdout).strip()[-300:]}
        other_data = root / "other data"
        other_data.mkdir()
        env2 = env.copy(); env2["TERABOOTH_DATA_DIR"] = str(other_data)
        third = subprocess.run([py, "scripts/run_bridge.py"], cwd=str(ROOT), env=env2, capture_output=True, text=True, timeout=20)
        report["checks"]["port_conflict"] = {"status": "PASS" if third.returncode == 2 else "FAIL", "detail": (third.stderr or third.stdout).strip()[-300:]}
        # Graceful stop/restart/token persistence.
        if proc and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
        report["checks"]["clean_shutdown"] = {"status": "PASS" if proc and proc.poll() is not None else "PARTIAL", "detail": "terminated for validation"}
        proc = None
        start_info = None
        check("restart_health", lambda: (globals().__setitem__("start_info", start()) or start_info))
        if report["checks"].get("restart_health", {}).get("status") == "PASS":
            check("token_persistence", lambda: request(local_url, timeout=8)[0] == 200)
            with sqlite3.connect(data / "terabooth.db") as conn:
                report["checks"]["sqlite_wal"] = {"status": "PASS", "detail": conn.execute("PRAGMA journal_mode").fetchone()[0]}
        # Filesystem checks.
        def fs_check():
            target_dir = root / "unicode path café 照片"
            target_dir.mkdir()
            src = target_dir / "a.part"; dst = target_dir / "b.txt"
            src.write_text("atomic", encoding="utf-8"); os.replace(src, dst)
            assert dst.read_text(encoding="utf-8") == "atomic"
            assert not list(target_dir.glob(".download-*"))
            return "unicode/space/atomic/zip-temp"
        check("filesystem", fs_check)
        report["metrics"]["total_seconds"] = round(time.time() - started, 3)
        failures = [name for name, value in report["checks"].items() if value.get("status") == "FAIL"]
        report["status"] = "PASS" if not failures else "PARTIAL"
    except Exception as exc:
        report["errors"].append(str(exc))
        report["status"] = "BLOCKED"
    finally:
        if proc and proc.poll() is None:
            proc.terminate()
            try: proc.wait(timeout=10)
            except subprocess.TimeoutExpired: proc.kill()
        report_path = ROOT / "validation" / "validation-report.json"
        try:
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
            report["report_path"] = str(report_path)
        except OSError:
            pass
        if not args.keep_report:
            shutil.rmtree(root, ignore_errors=True)
        print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
