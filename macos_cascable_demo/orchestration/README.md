# Safe macOS Test Orchestration

Canonical entry point: `run-safe-test.sh`

- `--mode source` — inspect active harness/orchestration source only.
- `--mode process` — read-only competing camera-app check; no camera command.
- `--mode capability` — future no-shutter preflight; requires
  `--allow-hardware --authorization capability-preflight`.
- `--mode transfer` — future single-shot test; requires
  `--allow-hardware --authorization one-shot-transfer --single-shot`.

The guard uses `ps` only. If Cascable Studio, EOS Utility, Image Capture or
Photos is running, the script aborts and asks the user to close it manually. It
never quits, terminates, kills or relaunches another application.

Logs are written under `logs/` with the timestamp, command, mode, guard result,
abort state and whether a camera-related command was invoked. Logs contain no
licence data or credentials.

Phase 3A-2J only permits `source` and `process`.
