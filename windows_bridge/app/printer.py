from __future__ import annotations

import shutil
import subprocess
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


def build_printer(settings: Settings) -> Printer:
    if settings.printer_mode == "mock":
        return MockPrinter(settings)
    if settings.printer_mode == "hotfolder":
        return HotFolderPrinter(settings)
    if settings.printer_mode == "spooler":
        return WindowsSpoolerPrinter(settings)
    raise ValueError(f"unknown printer mode {settings.printer_mode!r}")
