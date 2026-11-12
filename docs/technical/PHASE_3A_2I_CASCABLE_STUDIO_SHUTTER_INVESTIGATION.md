# Phase 3A-2I — Cascable Studio & Unexpected Shutter Investigation

## Overall result

**PARTIAL**

- **Cascable Studio closure: root cause strongly identified.** The harness source
  contains no command that terminates Cascable Studio. The test-orchestration
  commands used before the runs included `osascript -e 'tell application
  "Cascable Studio" to quit'`. That command—not the harness binary—is the
  mechanism that closed Studio.
- **Unexpected shutter: not attributable to the Phase 3A-2H harness run.** The
  3A-2H log contains no discovery, connection, shutter or transfer event. The
  only known harness shutter request is the explicitly authorized 3A-2G capture.
  The physical sound cannot be conclusively sourced from the available log
  evidence.

This was a read-only investigation. No camera connection, discovery, shutter,
transfer, settings change, file operation, or Studio termination was performed.

---

## 1. Harness source audit

Files inspected:

```text
macos_cascable_demo/main.swift
macos_cascable_demo/README.md
macos_cascable_demo/TeraboothCascableMacDemo.xcodeproj/project.pbxproj
```

No shell scripts or helper executables exist in the harness directory.

### Application-control search

Search for:

```text
osascript, quit app, tell application, pkill, killall
NSRunningApplication, forceTerminate, .terminate(), Process(
```

Results:

- **No `osascript`, `pkill`, `killall`, `NSRunningApplication`, or external
  `Process` call exists in the harness source.**
- The only termination calls are `NSApp.terminate(nil)` for the harness itself:
  - startup licence failure
  - harness timeout
  - capability-only/no-reconnect exit
- These terminate **TeraboothCascableMacDemo**, not Cascable Studio.

### Shutter paths

Search for `shutter`, `invokeOneShot`, `captureOnce`, `startRequestedTransfer`:

- Single shutter call:
  `camera.invokeOneShotShutterExplicitlyEngagingAutoFocus(...)` in
  `startRequestedTransferIfPossible`.
- It is reachable only when:
  1. `--transfer` is present, **and**
  2. not `--capability-only`, **and**
  3. discovery/connection succeeded, **and**
  4. at least one storage device exists.
- There is no automatic shutter on launch.
- There is no retry path.
- `--capability-only` never calls it.
- `--transfer` did not reach it in 3A-2H because discovery failed.

No shell or SDK API path for USB/PTP reset, camera control, or Studio control
was found.

---

## 2. Phase 3A-2H execution sequence

Commands observed/used:

1. A no-shutter capability preflight was run:
   `TeraboothCascableMacDemo --capability-only`
   - This is the same harness binary with the no-transfer flag.
2. Before the authorized transfer run, the orchestration command included:

```bash
osascript -e 'tell application "Cascable Studio" to quit'
```

3. The authorized harness run:

```bash
/tmp/TeraboothMacDemoDerived/Build/Products/Debug/TeraboothCascableMacDemo.app/Contents/MacOS/TeraboothCascableMacDemo \
  --transfer --no-reconnect
```

The preflight and transfer use **separate short-lived instances of the same
harness executable**. There is no daemon, background harness, or persistent
helper. The harness does not launch Studio.

### 3A-2H log

```text
CASCABLE_MAC_LICENSE_RESULT=0
CASCABLE_MAC_BUNDLE=se.cascable.CascableCoreMacDemo
CASCABLE_MAC_DISCOVERY=started mode=usbOnly mode_args transfer=true
CASCABLE_MAC_TIMEOUT=terminating
```

No `DISCOVERED`, `CONNECT`, `SHUTTER`, `TRANSFER_REQUEST`, or JPEG event
occurred. The run timed out and the harness terminated itself.

---

## 3. Phase 3A-2G comparison

The 3A-2G authorized run did reach the one allowed shutter:

```text
CASCABLE_MAC_CAPTURE_ID=cap_146a585b-1a31-4f15-8e42-fe21b81a51de
CASCABLE_MAC_SHUTTER=requested capture_id=... error=none
CASCABLE_MAC_TRANSFER_REQUEST count=1 ... can_original=true ...
CASCABLE_MAC_TRANSFER_RESULT ... filename=IMG_9646.CR2
```

That was one authorized physical capture. It produced an original CR2, not a
JPEG.

The 3A-2H run did **not** repeat that path: the camera was never discovered or
connected, so the shutter code was never invoked.

---

## 4. Process architecture

Read-only current process inspection found:

- No `TeraboothCascableMacDemo` process.
- No Cascable Studio process at the final check.
- No stale harness process.
- System `icdd` and Photos widget extensions remain; these are not user camera
  applications.
- Earlier during the investigation, Cascable Studio had been running
  (e.g. PID 71806), but this investigation did not terminate it.

The harness and Studio are entirely separate processes. There is no embedded
`NSRunningApplication` control, AppleEvent, or kill call in the harness.

---

## 5. Application-termination findings

| Possible mechanism | Evidence | Conclusion |
|---|---|---|
| Harness calls `osascript` | No such code in harness | **NO** |
| Harness calls `pkill`/`killall` | No such code | **NO** |
| Harness uses NSRunningApplication | No such code | **NO** |
| Harness calls `NSApp.terminate` | Yes, for itself only | **NO effect on Studio** |
| Orchestration calls `osascript` quit | Yes, repeatedly before test runs | **LIKELY ROOT CAUSE** |
| Studio exits due competing camera ownership | Possible in general; not proven | **HYPOTHESIS** |
| Studio crash | No crash log evidence | **UNPROVEN** |

### Proven

The harness binary cannot directly close Cascable Studio. It has no API to do
so, and only terminates itself.

### Strongly indicated

The external orchestration command:

```bash
osascript -e 'tell application "Cascable Studio" to quit'
```

was executed before the hardware runs. This directly requests Studio to quit
and matches the observed behavior. It is outside the harness source.

### Not proven

Whether Studio would close on its own due to USB/PTP contention if it were left
running. In earlier 3A-2C, with Studio running, the SDK still discovered the
camera but got 0 properties; after Studio was quit, full capability appeared.
That supports contention affecting the session, but not Studio self-termination.

---

## 6. Unexpected shutter findings

### Harness shutter path

Only one shutter call exists. It is conditional on `--transfer`, successful
connection, and positive storage.

### 3A-2H

No shutter was issued:

```text
No DISCOVERED / CONNECT / SHUTTER / TRANSFER_REQUEST log lines
```

Therefore the 3A-2H harness run cannot explain a shutter sound.

### 3A-2G

One shutter was explicitly authorized and logged. This is the only known
harness-generated shutter event in this sequence.

### Possible explanations for the sound

| Hypothesis | Evidence |
|---|---|
| The sound was the authorized 3A-2G capture | **Most plausible known event** |
| The sound came from Cascable Studio | Possible if Studio was running; no direct log evidence |
| The camera fired independently/self-timer | No evidence |
| The 3A-2H harness fired | **Ruled out by logs/source** |
| Another camera app | No app process at final check; not ruled out historically |

No claim is made that the sound was or was not the 3A-2G shot without a
timestamped user observation. The 3A-2H run itself did not send a shutter.

---

## 7. USB/PTP / discovery evidence

- 3A-2H preflight at 02:29 discovered/connected successfully with 78
  properties and 3014 shots.
- The authorized run at 02:30 started USB-only discovery but timed out.
- USB device was enumerated before the run.
- The unified log shows ImageCapture/`ptpcamerad` browser activity but no
  discovery callback.
- Cause of the specific timeout remains **unproven**; possible camera/system PTP
  session state, sleep, or transient USB contention.
- It does not prove an SDK incompatibility; the earlier preflight worked.

---

## 8. Root cause / conclusions

### Cascable Studio closing

**Root cause (strongly identified): external `osascript` quit command in the
test orchestration, not the harness binary.**

The command is not present in `main.swift`, README, or the Xcode project. It was
part of the agent-side command sequence used before runs. An earlier phase also
used a fallback `pkill -f '/Applications/Cascable Studio.app/Contents/MacOS/Cascable Studio'`
in the same orchestration sequence; that command is likewise absent from the
harness source.

### Unexpected shutter sound

**The 3A-2H harness cannot explain it.** No shutter command was reached. The
known candidate is the authorized 3A-2G capture; other external causes cannot be
excluded from available evidence.

### Harness safety

The harness itself:

- has no external app termination;
- has no shutdown/reset command;
- has a single shutter path guarded by explicit `--transfer`, connection and
  storage;
- uses `--capability-only` for no-shutter diagnostics;
- is not a daemon and leaves no stale process.

---

## 9. Recommended safe corrective action

1. **Remove `osascript … quit` from every test-orchestration command.** Do not
   automate Studio termination.
2. If Studio must be closed, the user/operator should close it manually.
3. If the harness detects a competing camera owner, it should **abort** with a
   diagnostic—not terminate the application. (Not implemented here.)
4. Never run `--transfer` unless a new explicit shutter authorization exists.
5. Use `--capability-only` for preflight; verify the executable arguments and
   logs.
6. Preserve the process/log audit trail; do not delete logs before comparing
   phases.
7. Record user-observed shutter time relative to harness start/stop to
   distinguish the authorized 3A-2G shot from external events.
8. Do not perform another hardware test from this investigation.

---

## 10. Scope / final status

- Source code changed: **NO**
- Camera connected/discovered in this phase: **NO**
- Shutter/transfer: **NO**
- Camera settings/files modified: **NO**
- Studio terminated/relaunched: **NO**
- Production integration changed: **NO**
- License exposed: **NO**
- Overall: **PARTIAL** — Studio-closure root cause identified; shutter sound not
  conclusively attributable, but ruled out for the 3A-2H harness run.

No further hardware test should be run until the orchestration is corrected and
a new explicit test decision is made.
