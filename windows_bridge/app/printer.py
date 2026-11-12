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
        self.script = Path(__file__).resolve().parent.parent / "scripts" / "print_xps.ps1"

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
        job_level = preflight.get("job_level") or {}
        if job_level.get("available") is not True:
            raise RuntimeError("DNP print blocked: job-level PrintTicket backend unavailable")
        config_out = self.settings.jobs_dir / job_id / "print_job_config.json"
        config_out.parent.mkdir(parents=True, exist_ok=True)
        cmd = [
            "powershell", "-NoProfile", "-Sta", "-ExecutionPolicy", "Bypass",
            "-File", str(self.script),
            "-ImagePath", str(artefact),
            "-PrinterName", self.settings.printer_name,
            "-Copies", str(copies),
            "-ConfigOut", str(config_out),
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if proc.returncode != 0:
            raise RuntimeError((proc.stderr or proc.stdout or "print failed").strip())
        try:
            config_data = json.loads(config_out.read_text(encoding="utf-8-sig"))
        except Exception as exc:  # noqa: BLE001
            raise RuntimeError(f"DNP print config missing/invalid: {exc}") from exc
        config_errors = validate_job_config(config_data)
        if config_errors:
            raise RuntimeError(
                "DNP print blocked after submission: " + ", ".join(config_errors)
            )
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


class WindowsDriverPrinter:
    """Print through the configured Windows DNP driver without overriding paper,
    orientation, margins or private cutter features. This mirrors the classic
    LumaBooth Assistant model: the driver/printer owns cut behaviour."""

    name = "Windows Driver Managed"

    def __init__(self, settings: Settings):
        self.settings = settings
        self.script = Path(__file__).resolve().parent.parent / "scripts" / "print_driver.ps1"

    def submit(self, job_id: str, artefact: Path, copies: int) -> PrintHandle:
        if not self.script.exists():
            raise RuntimeError("print_driver.ps1 missing")
        preflight = printer_preflight(self.settings)
        if not preflight.get("available"):
            raise RuntimeError(
                "DNP driver print blocked: preflight unavailable: "
                + str(preflight.get("query_error") or "unknown error")
            )
        page = preflight.get("default_page") or {}
        if page.get("is_4x6") is not True or page.get("landscape") is True:
            raise RuntimeError("DNP driver print blocked: default page is not 4x6 portrait")
        config_out = self.settings.jobs_dir / job_id / "driver_job_config.json"
        config_out.parent.mkdir(parents=True, exist_ok=True)
        cmd = [
            "powershell", "-NoProfile", "-Sta", "-ExecutionPolicy", "Bypass",
            "-File", str(self.script),
            "-ImagePath", str(artefact),
            "-PrinterName", self.settings.printer_name,
            "-Copies", str(copies),
            "-ConfigOut", str(config_out),
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if proc.returncode != 0:
            raise RuntimeError((proc.stderr or proc.stdout or "print failed").strip())
        try:
            config_data = json.loads(config_out.read_text(encoding="utf-8-sig"))
        except Exception as exc:  # noqa: BLE001
            raise RuntimeError(f"Driver print config missing/invalid: {exc}") from exc
        config_errors = validate_driver_job_config(config_data)
        if config_errors:
            raise RuntimeError(
                "Driver print blocked after submission: " + ", ".join(config_errors)
            )
        return PrintHandle("driver", self.settings.printer_name, "printing")

    def status(self, handle: PrintHandle) -> PrintStatus:
        return PrintStatus("unknown", "driver accepted; physical completion unverified", "unknown")

    def health(self) -> dict:
        return {"name": self.settings.printer_name, "state": "unknown",
                "mode": "driver",
                "note": "Uses configured Windows DNP driver; physical completion unverified"}


def validate_driver_job_config(data: dict) -> list[str]:
    errors: list[str] = []
    if data.get("mechanism") != "driver_managed_PrintDocument":
        errors.append("mechanism_not_driver_managed")
    if data.get("mode") != "spooler_job":
        errors.append("mode_not_spooler_job")
    if data.get("paper_overridden") is not False:
        errors.append("paper_must_not_be_overridden")
    if data.get("orientation_overridden") is not False:
        errors.append("orientation_must_not_be_overridden")
    if data.get("margins_overridden") is not False:
        errors.append("margins_must_not_be_overridden")
    if data.get("private_vendor_features_set") is not False:
        errors.append("private_vendor_features_must_not_be_set")
    if data.get("cut_source") != "Windows DNP driver preferences":
        errors.append("cut_must_use_driver_preferences")
    if data.get("physical_completion") != "unverified":
        errors.append("physical_completion_must_remain_unverified")
    return errors


def validate_job_config(data: dict) -> list[str]:
    """Validate the sidecar written by print_xps.ps1 before claiming acceptance."""
    errors: list[str] = []
    if data.get("mode") != "spooler_job":
        errors.append("mode_not_spooler_job")
    if "XpsDocumentWriter" not in str(data.get("mechanism", "")):
        errors.append("mechanism_not_xps")
    if data.get("page_inches") != "4x6":
        errors.append("page_not_4x6")
    if data.get("page_px_96dpi") != "384x576":
        errors.append("page_geometry_wrong")
    expected = {
        "media": "PR_4x6",
        "orientation": "Portrait",
        "resolution": "300x300",
        "cut": "CUT_STANDARD",
    }
    for key, value in expected.items():
        if data.get(key) != value:
            errors.append(f"{key}_not_required")
        if data.get(f"ticket_{key}") != value:
            errors.append(f"ticket_{key}_not_required")
        if data.get(f"driver_accepted_{key}") != value:
            errors.append(f"driver_{key}_not_accepted")
    if data.get("driver_conflict") != "NoConflict":
        errors.append("driver_ticket_conflict")
    if data.get("driver_validated") is not True:
        errors.append("driver_ticket_not_validated")
    if data.get("physical_completion") != "unverified":
        errors.append("physical_completion_must_remain_unverified")
    return errors


def build_printer(settings: Settings) -> Printer:
    if settings.printer_mode == "mock":
        return MockPrinter(settings)
    if settings.printer_mode == "driver":
        return WindowsDriverPrinter(settings)
    if settings.printer_mode == "hotfolder":
        return HotFolderPrinter(settings)
    if settings.printer_mode == "spooler":
        return WindowsSpoolerPrinter(settings)
    raise ValueError(f"unknown printer mode {settings.printer_mode!r}")
