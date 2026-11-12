# Phase 3A-2J — Test Orchestration Safety Hardening

## Overall result

**PASS**

The active macOS test orchestration is now a single safe entry point with
explicit modes, a read-only competing-camera-app guard, persistent logs, and no
external application termination. Only source/process modes were exercised in
this phase; no camera or Studio interaction occurred.

---

## 1. Files inspected

- `macos_cascable_demo/main.swift`
- `macos_cascable_demo/README.md`
- `macos_cascable_demo/TeraboothCascableMacDemo.xcodeproj/project.pbxproj`
- `macos_cascable_demo/.gitignore`
- `docs/technical/PHASE_3A_2I_CASCABLE_STUDIO_SHUTTER_INVESTIGATION.md`
- All repository `.sh`/`.command`/`.zsh`/`.bash` files
- Current process table (read-only)

No active hardware script existed before this phase. The destructive commands
identified by Phase 3A-2I were in the **agent-side execution sequence**
(`osascript … quit Cascable Studio`, and an earlier `pkill` fallback), not in
the harness source.

---

## 2. Destructive commands found and removed

### Found in historical documentation / execution history

```text
osascript -e 'tell application "Cascable Studio" to quit'
pkill -f '/Applications/Cascable Studio.app/Contents/MacOS/Cascable Studio'
```

These were documented as the root cause of Studio closing in Phase 3A-2I.
They were not present in any active repository script.

### Active orchestration after hardening

The new `macos_cascable_demo/orchestration/run-safe-test.sh` contains:

- **No** executable `osascript`
- **No** `pkill`/`killall`
- **No** `kill` targeting camera apps
- **No** `launchctl`
- **No** `NSRunningApplication`/`forceTerminate`
- **No** external application lifecycle management

The only process inspection is a read-only `ps -axo` and `grep`.

Harness source `main.swift` was **not changed**. It has no external application
termination; its only termination calls target its own process.

---

## 3. New competing-application guard

Before any future hardware mode, the script calls a guard that reads the process
table and looks for:

- Cascable Studio
- EOS Utility
- Image Capture
- Photos (the full app, not Photos widget extensions)

If any is detected:

- Prints the detected process line.
- Explains that the user must close it manually.
- Aborts with exit status `2`.
- Never signals, quits, kills, or relaunches the application.
- Never proceeds to camera discovery.

If none is detected:

```text
COMPETING_APPLICATION_DETECTED=false
GUARD=PASS
```

The guard itself has **no camera connection or discovery**.

A synthetic fixture test supplied a fake process-table line and confirmed the
abort path without touching any real process.

---

## 4. Explicit test-mode separation

`run-safe-test.sh` requires an explicit `--mode`; there is no default and no
automatic escalation.

| Mode | Camera command | Requirements |
|---|---|---|
| `source` | **NO** | none |
| `process` | **NO** | none |
| `capability` | Future no-shutter harness | `--allow-hardware` + `--authorization capability-preflight` + guard |
| `transfer` | Future one-shot harness | `--allow-hardware` + `--authorization one-shot-transfer` + `--single-shot` + guard |

For Phase 3A-2J, only **source** and **process** were executed. The future
hardware modes cannot silently run; missing flags abort before the harness.

---

## 5. Logging

Each run writes a unique log under:

```text
macos_cascable_demo/logs/orchestration-<timestamp>-<pid>.log
```

Records include:

- timestamp
- exact command/invocation
- selected mode
- guard result
- abort state and reason
- whether a camera-related command was invoked (`CAMERA_COMMAND=true/false`)

Logs contain no licence bytes, credentials, or sensitive data. `logs/*.log` is
ignored by git.

---

## 6. Verification evidence

### Source mode

```text
$ ./orchestration/run-safe-test.sh --mode source
RC=0
CAMERA_COMMAND=false
SOURCE_AUDIT_END
```

No external termination references were found in active harness/orchestration
files (excluding the safe script’s own audit pattern).

### Process mode

```text
$ ./orchestration/run-safe-test.sh --mode process
COMPETING_APPLICATION_DETECTED=false
GUARD=PASS
PROCESS_DIAGNOSTIC=PASS
CAMERA_COMMAND=false
RC=0
```

### Guard abort with synthetic process

```text
COMPETING_APPLICATION_DETECTED=true
  424242 /Applications/Cascable Studio.app/Contents/MacOS/Cascable Studio
The camera application above must be closed manually if you want to proceed.
This guard will never quit, terminate, kill, or relaunch it.
ABORTED=true
REASON=competing camera application is running
CAMERA_COMMAND=false
RC=2
```

No real Studio process was touched.

### Hardware-mode refusal

```text
$ ./orchestration/run-safe-test.sh --mode transfer
ABORTED=true
REASON=hardware mode requires --allow-hardware
CAMERA_COMMAND=false
RC=64

$ ./orchestration/run-safe-test.sh --mode capability
ABORTED=true
REASON=hardware mode requires --allow-hardware
CAMERA_COMMAND=false
RC=64
```

No harness was launched.

### Static command check

```text
grep -nE '^[[:space:]]*(osascript|pkill|killall|kill[[:space:]])' \
  orchestration/run-safe-test.sh
→ no output
```

---

## 7. Safety confirmations

| Requirement | Confirmation |
|---|---|
| No shutter requests | **NONE** |
| No camera capture | **NONE** |
| No image transfer | **NONE** |
| No CascableCore discovery/connection | **NONE** |
| No USB/PTP manipulation | **NONE** |
| No camera settings changes | **NONE** |
| No camera file operations | **NONE** |
| No Studio/EOS Utility/Image Capture/Photos termination | **NONE** |
| No camera-related command in source/process modes | **CONFIRMED (`CAMERA_COMMAND=false`)** |
| Hardware modes executed | **NO** |
| Harness source changed | **NO** |
| Production camera integration changed | **NO** |
| Production Bundle ID changed | **NO** |
| MockCameraService default changed | **NO** |
| Printing/GIF/QR/Windows Bridge changed | **NO** |
| Licence data exposed | **NO** |

### Current process state

Read-only check found no Cascable Studio, EOS Utility, Image Capture or Photos
app process. No harness process was running. No process was terminated by this
phase.

---

## 8. Remaining limitations

- Hardware modes remain unavailable without a new explicit decision and
  authorization.
- The guard detects known application names/paths; an unknown camera-owning
  process is not detected.
- The guard cannot prove that no kernel/system PTP service owns the camera; it
  aborts only on known user applications.
- No camera discovery or connection was performed, so no current camera state
  is claimed.

---

## 9. Recommended next action

1. Use `--mode source` or `--mode process` only for current diagnostics.
2. Never add automatic application termination back into orchestration.
3. If Studio is running, close it manually; do not modify the script to kill it.
4. For future hardware tests, require a new explicit authorization and use the
   gated `capability`/`transfer` modes.
5. Preserve the per-run logs for audit.

**No further camera or hardware test was performed.**
