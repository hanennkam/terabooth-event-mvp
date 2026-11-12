"""No-print XPS backend verification for the Windows DNP queue."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from calibration_print import _make_image  # noqa: E402


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="terabooth-xps-verify-") as raw:
        root = Path(raw)
        image = root / "calibration.jpg"
        image.write_bytes(_make_image())
        xps = root / "calibration.xps"
        config_out = root / "xps_job_config.json"
        cmd = [
            "powershell", "-NoProfile", "-Sta", "-ExecutionPolicy", "Bypass",
            "-File", str(HERE / "print_xps.ps1"),
            "-ImagePath", str(image),
            "-PrinterName", "DS-RX1",
            "-Copies", "1",
            "-ConfigOut", str(config_out),
            "-DryRun",
            "-XpsOut", str(xps),
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if proc.returncode != 0:
            print("DRY-RUN FAILED")
            print((proc.stderr or proc.stdout or "unknown error")[:2000])
            return 1
        config = json.loads(config_out.read_text(encoding="utf-8"))
        page = None
        with zipfile.ZipFile(xps) as package:
            for name in package.namelist():
                if name.endswith(".fpage"):
                    page = ET.fromstring(package.read(name))
                    break
        if page is None:
            print("DRY-RUN FAILED: no FixedPage in XPS package")
            return 1
        ns = {"x": "http://schemas.microsoft.com/xps/2005/06"}
        width = page.attrib.get("Width")
        height = page.attrib.get("Height")
        print("DRY-RUN PASS")
        print(json.dumps({
            "xps_file": str(xps),
            "fixedpage_width": width,
            "fixedpage_height": height,
            "page_count": 1,
            "config": config,
        }, indent=2))
        if width != "384" or height != "576":
            print("DRY-RUN FAILED: unexpected FixedPage geometry")
            return 1
        if config.get("driver_validated") is not True:
            print("DRY-RUN FAILED: driver ticket not validated")
            return 1
        if config.get("physical_completion") != "unverified":
            print("DRY-RUN FAILED: dry-run must remain physically unverified")
            return 1
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
