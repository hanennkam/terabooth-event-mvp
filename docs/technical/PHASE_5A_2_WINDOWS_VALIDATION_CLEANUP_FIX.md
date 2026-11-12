# Phase 5A-2 — Windows Runtime Validation Cleanup Fix

## Scope

Validation tooling only:

```text
windows_bridge/validation/validate_runtime.py
windows_bridge/tests/test_validation_runtime.py
```

No Bridge production code, database schema, API, printer behavior or Flutter
code was changed.

## Root cause

The script used:

```python
with sqlite3.connect(db_path) as conn:
    ...
```

`sqlite3.Connection` used as a context manager commits/rolls back the
transaction. It does **not** close the underlying database connection. The
connection remained alive until garbage collection, so Windows still held
`bridge.db` open when `TemporaryDirectory` cleanup ran:

```text
PermissionError: [WinError 32]
The process cannot access the file because it is being used by another process
```

## Cleanup correction

- Replaced the connection context-manager pattern with explicit lifecycle:
  - `connection = sqlite3.connect(...)`
  - `cursor = connection.cursor()`
  - `try: ... finally: cursor.close(); connection.close()`
- `cursor.close()` and `connection.close()` run before leaving the
  `TemporaryDirectory` context.
- SQLite WAL assertions still occur while the connection is open.
- Pillow source image is explicitly closed after saving.
- QR image is explicitly closed after saving.
- Image reads continue to use `with Image.open(...)`.
- No `PermissionError` suppression and no `ignore_errors=True` were added.

## Regression test

`windows_bridge/tests/test_validation_runtime.py` runs the validation script as
a subprocess and requires:

- exit code 0,
- `RUNTIME_PASS`,
- no `PermissionError`/`WinError 32`.

Because the validation script owns a `TemporaryDirectory`, a leaked SQLite
handle on Windows would fail the script on cleanup and fail this test.

## Verification performed

```text
.venv/bin/python validation/validate_runtime.py
RUNTIME_PASS
python=3.11.9
pillow=13.0.0
sqlite=3.51.0
unicode_atomic=ok
```

Local immediate-cleanup check using a dedicated `TMPDIR`:

```text
RC=0
LEFTOVER_COUNT:0
```

Test suite:

```text
.venv/bin/python -m pytest -q
54 passed
```

## Windows status

The original Windows failure is understood and the handle lifetime is fixed.
The fix has **not been independently rerun on the physical Windows laptop** in
this session. It must be rerun there:

```powershell
cd C:\Terabooth\terabooth-event-mvp\windows_bridge
.\.venv\Scripts\python.exe validation\validate_runtime.py
```

Expected: `RUNTIME_PASS` and no `WinError 32` cleanup exception. macOS results
are not a substitute for that Windows rerun.

## Remaining risk

- Windows Python 3.14.10 / SQLite 3.50.4 behavior is still to be reverified.
- No production runtime behavior was intentionally changed.
