# Phase 5A-2 — Windows OS Version Compatibility Fix

## Scope

Validation tooling only:

- `windows_bridge/validation/validate_bridge.py`
- `windows_bridge/tests/test_validation_bridge.py`

No production Bridge code, API, schema, printer adapter or Flutter code changed.

## Root cause

The validation report used:

```python
sys.getwindowsversion()._asdict()
```

CPython does not guarantee `_asdict()` on the object returned by
`sys.getwindowsversion()`. On the target Windows Python 3.14.10 runtime this
raised:

```text
'sys.getwindowsversion' object has no attribute '_asdict'
```

The exception occurred while building `report["environment"]`, before any
validation checks, so the run ended as `BLOCKED` with empty checks/metrics.

## Correction

Added `windows_version_info(version=None)`:

- On non-Windows, returns `None`.
- On Windows, calls `sys.getwindowsversion()` and reads documented fields with
  `getattr`:
  - `major`
  - `minor`
  - `build`
  - `platform`
  - `service_pack`
  - `service_pack_major`
  - `service_pack_minor`
  - `suite_mask`
  - `product_type`
- Missing fields are omitted; no `_asdict()` assumption.
- Exceptions are not broadly suppressed.

The report keeps the same structure:

```json
"environment": {
  "platform": "win32",
  "windows": {
    "major": 10,
    "minor": 0,
    "build": 22631,
    "platform": 2,
    "service_pack": ""
  },
  "python": "3.14.10"
}
```

## Regression test

`tests/test_validation_bridge.py` loads the validation module and passes a
CPython-compatible version object that deliberately has no `_asdict()` method.
It asserts all documented fields are reported correctly.

## Verification performed

```text
tests/test_validation_bridge.py: 1 passed
tests/test_validation_runtime.py: 1 passed
Full bridge suite: 55 passed
Static compile: PASS
```

`validation/validate_bridge.py` was also smoke-run on macOS and completed
without an OS-version exception; that is not Windows evidence.

## Windows status

**Actual Windows execution still required.** Rerun on the target laptop:

```powershell
cd C:\Terabooth\terabooth-event-mvp\windows_bridge
.\.venv\Scripts\python.exe validation\validate_runtime.py
.\.venv\Scripts\python.exe validation\validate_bridge.py --port 18787 --keep-report
```

Expected:

- `RUNTIME_PASS`
- `environment.windows` contains `major`/`minor`/`build`/`platform`
- no `_asdict` error
- validation proceeds to startup/health/guest/restart checks

macOS results are not a substitute for this Windows rerun.
