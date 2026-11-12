from __future__ import annotations

import os
import shutil
import sys
import time
from pathlib import Path
from typing import Any

try:
    import resource
except ImportError:  # Windows
    resource = None  # type: ignore[assignment]


def rss_bytes() -> int | None:
    if sys.platform.startswith("win"):
        try:
            import ctypes
            from ctypes import wintypes

            class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
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

            counters = PROCESS_MEMORY_COUNTERS()
            counters.cb = ctypes.sizeof(counters)
            process = ctypes.windll.kernel32.GetCurrentProcess()
            if ctypes.windll.psapi.GetProcessMemoryInfo(
                process, ctypes.byref(counters), counters.cb
            ):
                return int(counters.WorkingSetSize)
        except Exception:
            return None
    if sys.platform.startswith("linux"):
        try:
            pages = int(Path("/proc/self/statm").read_text().split()[1])
            return pages * os.sysconf("SC_PAGE_SIZE")
        except Exception:
            return None
    if resource is None:
        return None
    try:
        value = int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
        return value if sys.platform == "darwin" else value * 1024
    except Exception:
        return None


def directory_size(path: Path) -> int:
    total = 0
    if not path.exists():
        return 0
    for root, dirs, files in os.walk(path):
        # Do not follow symlinks or load directory contents.
        dirs[:] = [d for d in dirs if not Path(root, d).is_symlink()]
        for name in files:
            try:
                total += os.path.getsize(os.path.join(root, name))
            except OSError:
                continue
    return total


def snapshot(
    *,
    jobs_dir: Path,
    queue_depth: int,
    active_tasks: int,
    active_gif: int,
    active_zip: int,
    active_print: int,
    uptime_seconds: float,
) -> dict[str, Any]:
    try:
        usage = shutil.disk_usage(jobs_dir)
        disk = {"total_bytes": usage.total, "free_bytes": usage.free}
    except OSError:
        disk = {"total_bytes": None, "free_bytes": None}
    return {
        "process": {
            "pid": os.getpid(),
            "rss_bytes": rss_bytes(),
            "cpu_seconds": round(time.process_time(), 3),
            "uptime_seconds": round(uptime_seconds, 3),
        },
        "jobs": {
            "queue_depth": queue_depth,
            "active_tasks": active_tasks,
            "active_gif": active_gif,
            "active_zip": active_zip,
            "active_print": active_print,
        },
        "storage": {
            "asset_bytes": directory_size(jobs_dir),
            "disk_total_bytes": disk["total_bytes"],
            "disk_free_bytes": disk["free_bytes"],
        },
    }
