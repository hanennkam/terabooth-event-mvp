from __future__ import annotations

import json
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from .config import Settings


@dataclass
class PrintHandle:
    transport: str
    reference: str
    state: str = "printing"


@dataclass
class PrintStatus:
    state: str                 # printing | completed | failed | unknown
    detail: str = ""
    completion: str = "unknown"


class Printer(Protocol):
    name: str
    def submit(self, job_id: str, artefact: Path, copies: int) -> PrintHandle: ...
    def status(self, handle: PrintHandle) -> PrintStatus: ...
    def health(self) -> dict: ...


class MockPrinter:
    """Mac/CI printer. Writes the artefact; simulates completion/failure/unknown."""
    name = "Mock Printer"

    def __init__(self, settings: Settings):
        self.settings = settings
        self._submitted: dict[str, float] = {}
        self.submitted_copies: list[int] = []

    def submit(self, job_id: str, artefact: Path, copies: int) -> PrintHandle:
        self.settings.outbox_dir.mkdir(parents=True, exist_ok=True)
        self.submitted_copies.append(copies)
        dest = self.settings.outbox_dir / f"{job_id}.jpg"
        shutil.copyfile(artefact, dest)
        self._submitted[job_id] = time.monotonic()
        return PrintHandle("mock", str(dest), "printing")

    def status(self, handle: PrintHandle) -> PrintStatus:
        job_id = Path(handle.reference).stem
        elapsed = time.monotonic() - self._submitted.get(job_id, time.monotonic())
        if elapsed < self.settings.mock_delay_seconds:
            return PrintStatus("printing", "mock printing")
        if self.settings.mock_fail:
            return PrintStatus("failed", "mock failure", "unknown")
        if self.settings.mock_unknown:
            return PrintStatus("unknown", "mock unknown", "unknown")
        return PrintStatus("completed", "mock completed", "confirmed")

    def health(self) -> dict:
        return {"name": self.name, "state": "ready", "mode": "mock",
                "note": "NOT a physical printer"}


class HotFolderPrinter:
    """DNP Hot Folder Print transport (Windows). Unverified until tested with HFP."""
    name = "DNP Hot Folder Print"

    def __init__(self, settings: Settings):
        if not settings.hot_folder:
            raise ValueError("TERABOOTH_HOT_FOLDER is required for hotfolder mode")
        self.settings = settings
        self.hot = settings.hot_folder
        self.archive = settings.hot_folder_archive
        self.hot.mkdir(parents=True, exist_ok=True)

    def submit(self, job_id: str, artefact: Path, copies: int) -> PrintHandle:
        dest = self.hot / f"terabooth_{job_id}.jpg"
        shutil.copyfile(artefact, dest)
        return PrintHandle("hotfolder", str(dest), "printing")

    def status(self, handle: PrintHandle) -> PrintStatus:
        src = Path(handle.reference)
        if not self.archive:
            return PrintStatus("unknown", "no archive folder configured", "unknown")
        if (self.archive / src.name).exists():
            return PrintStatus("completed", "archived", "confirmed")
        if src.exists():
            return PrintStatus("printing", "waiting for HFP archive", "unknown")
        return PrintStatus("unknown", "file missing and not archived", "unknown")

    def health(self) -> dict:
        return {"name": self.name, "state": "ready" if self.hot.exists() else "offline",
                "mode": "hotfolder", "folder": str(self.hot),
                "note": "UNVERIFIED on actual DNP/HFP"}


class WindowsSpoolerPrinter:
    """Windows spooler via PowerShell System.Drawing.Printing.

    UNVERIFIED: no Windows/DNP printer is available in this environment.
    The script prints the image at 4x6 with zero margins. Completion is
    reported as `unknown` unless the operator verifies the physical print.
    """
    name = "Windows Spooler"

    def __init__(self, settings: Settings):
        self.settings = settings
        self.script = Path(__file__).resolve().parent.parent / "scripts" / "print_image.ps1"

    def submit(self, job_id: str, artefact: Path, copies: int) -> PrintHandle:
        if not self.script.exists():
            raise RuntimeError("print_image.ps1 missing")
        preflight = printer_preflight(self.settings)
        if not preflight.get("available"):
            raise RuntimeError(
                "DNP print blocked: printer preflight unavailable: "
                + str(preflight.get("query_error") or "unknown error")
            )
        if preflight.get("ready") is not True:
            blockers = preflight.get("blockers") or ["configuration_not_ready"]
            raise RuntimeError(
                "DNP print blocked: " + ", ".join(str(b) for b in blockers)
            )
        cmd = [
            "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(self.script),
            "-ImagePath", str(artefact),
            "-PrinterName", self.settings.printer_name,
            "-Copies", str(copies),
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if proc.returncode != 0:
            raise RuntimeError((proc.stderr or proc.stdout or "print failed").strip())
        return PrintHandle("spooler", self.settings.printer_name, "printing")

    def status(self, handle: PrintHandle) -> PrintStatus:
        # Do not pretend acceptance is completion.
        return PrintStatus("unknown", "spooler accepted; physical completion unverified", "unknown")

    def health(self) -> dict:
        return {"name": self.settings.printer_name, "state": "unknown",
                "mode": "spooler", "note": "UNVERIFIED until physical DNP print"}


def printer_preflight(settings: Settings) -> dict:
    """Read-only Windows queue/driver/media diagnostics.

    This never submits a print job and works while the active adapter is mock.
    """
    result = {
        "available": False,
        "queue_exists": False,
        "configured_queue_name": settings.printer_name,
        "spooler_mode_enabled": settings.printer_mode == "spooler",
        "queue_name": "",
        "driver_name": "",
        "driver_manufacturer": "",
        "driver_version": "",
        "port_name": "",
        "printer_status": "",
        "work_offline": False,
        "shared": False,
        "paper_size": "",
        "media": "",
        "orientation": "",
        "resolution": "",
        "cut": "",
        "queued_jobs": 0,
        "ready": False,
        "blockers": [],
        "machine_default": None,
        "user_default": None,
        "capabilities": None,
        "job_request": None,
        "job_level": None,
        "query_error": "",
    }
    if not sys.platform.startswith("win"):
        result["query_error"] = "Windows PowerShell preflight unavailable on this host"
        return result
    script = Path(__file__).resolve().parent.parent / "scripts" / "printer_preflight.ps1"
    if not script.exists():
        result["query_error"] = "printer_preflight.ps1 missing"
        return result
    try:
        proc = subprocess.run(
            [
                "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                "-File", str(script), "-QueueName", settings.printer_name,
            ],
            capture_output=True, text=True, timeout=20,
        )
        if proc.returncode != 0:
            result["query_error"] = (proc.stderr or proc.stdout or "preflight failed").strip()
            return result
        data = json.loads(proc.stdout)
        if isinstance(data, dict):
            result.update(data)
        result["configured_queue_name"] = settings.printer_name
        result["spooler_mode_enabled"] = settings.printer_mode == "spooler"
        return result
    except Exception as exc:  # noqa: BLE001
        result["query_error"] = str(exc)
        return result


def build_printer(settings: Settings) -> Printer:
    if settings.printer_mode == "mock":
        return MockPrinter(settings)
    if settings.printer_mode == "hotfolder":
        return HotFolderPrinter(settings)
    if settings.printer_mode == "spooler":
        return WindowsSpoolerPrinter(settings)
    raise ValueError(f"unknown printer mode {settings.printer_mode!r}")
