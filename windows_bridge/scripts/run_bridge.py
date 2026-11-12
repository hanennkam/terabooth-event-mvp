#!/usr/bin/env python3
"""Portable foreground entry point for the Terabooth Bridge.

This is intentionally a single-process, single-worker launcher. It performs
configuration validation, an OS-backed single-instance lock, a port preflight,
then hands control to Uvicorn. No Windows service is installed.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


def load_dotenv(path: Path = ROOT / ".env") -> None:
    if not path.exists():
        return
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        if key and key not in os.environ:
            os.environ[key] = value


def main(argv: list[str] | None = None) -> int:
    import uvicorn

    from app.config import ConfigurationError, load_settings, validate_settings
    from app.runtime import InstanceLock, InstanceLockError, PortInUseError, ensure_port_available

    load_dotenv()
    try:
        settings = load_settings()
        warnings = validate_settings(settings)
        lock = InstanceLock(settings.data_dir / ".bridge.lock")
        lock.acquire()
        try:
            ensure_port_available(settings.host, settings.port)
            print(f"Terabooth Bridge {settings.host}:{settings.port}")
            print(f"  data:   {settings.data_dir}")
            print(f"  assets: {settings.jobs_dir}")
            print(f"  db:     {settings.db_path}")
            print(f"  printer:{settings.printer_mode}")
            for warning in warnings:
                print(f"  warning: {warning}")
            uvicorn.run(
                "app.main:app",
                host=settings.host,
                port=settings.port,
                workers=1,
                log_level="info",
                access_log=False,
            )
            return 0
        finally:
            lock.release()
    except (ConfigurationError, InstanceLockError, PortInUseError) as exc:
        print(f"Terabooth Bridge startup failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
