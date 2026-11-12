import subprocess
import sys
from pathlib import Path


def test_runtime_validation_script_deletes_its_temp_directory():
    script = Path(__file__).resolve().parents[1] / "validation" / "validate_runtime.py"
    completed = subprocess.run(
        [sys.executable, str(script)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert completed.returncode == 0, completed.stderr
    assert "RUNTIME_PASS" in completed.stdout
    # The script owns a TemporaryDirectory. A leaked SQLite handle on Windows
    # would surface as WinError 32 during that context's cleanup and fail here.
    assert "PermissionError" not in completed.stderr
    assert "WinError 32" not in completed.stderr
