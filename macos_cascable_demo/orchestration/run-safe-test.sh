#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS="${TERABOOTH_HARNESS_BIN:-/tmp/TeraboothMacDemoDerived/Build/Products/Debug/TeraboothCascableMacDemo.app/Contents/MacOS/TeraboothCascableMacDemo}"
LOG_DIR="$ROOT/macos_cascable_demo/logs"
ORIGINAL_ARGS=("$@")
MODE=""
AUTHORIZATION=""
ALLOW_HARDWARE=0
SINGLE_SHOT=0
GUARD_FIXTURE="${GUARD_FIXTURE:-}"

usage() {
  cat <<'USAGE'
Usage: run-safe-test.sh --mode <mode> [options]

Modes (explicit; no automatic escalation):
  source       Inspect active harness/orchestration source only. No camera command.
  process      Read-only competing camera-application check. No camera command.
  capability   Future no-shutter capability preflight. Requires:
               --allow-hardware --authorization capability-preflight
  transfer     Future single-shot transfer test. Requires:
               --allow-hardware --authorization one-shot-transfer --single-shot

This phase permits source and process modes only. No camera connection,
discovery, shutter, or transfer is performed by source/process modes.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --authorization) AUTHORIZATION="${2:-}"; shift 2 ;;
    --allow-hardware) ALLOW_HARDWARE=1; shift ;;
    --single-shot) SINGLE_SHOT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

if [ -z "$MODE" ]; then
  usage >&2
  exit 64
fi

mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR" 2>/dev/null || true
STAMP="$(date '+%Y%m%dT%H%M%S%z')-$$"
LOG="$LOG_DIR/orchestration-$STAMP.log"
exec > >(tee -a "$LOG") 2>&1

printf 'TIMESTAMP=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
printf 'COMMAND=%q' "$0"; for arg in "${ORIGINAL_ARGS[@]}"; do printf ' %q' "$arg"; done; printf '\n'
printf 'MODE=%s\n' "$MODE"
printf 'LOG=%s\n' "$LOG"
printf 'CAMERA_COMMAND=false\n'

abort() {
  printf 'ABORTED=true\nREASON=%s\nCAMERA_COMMAND=false\n' "$1"
  exit "${2:-2}"
}

check_competing_apps() {
  local source_output
  if [ -n "$GUARD_FIXTURE" ]; then
    if [ ! -r "$GUARD_FIXTURE" ]; then
      abort "guard fixture is not readable" 64
    fi
    source_output="$(cat "$GUARD_FIXTURE")"
  else
    source_output="$(ps -axo pid=,command= 2>/dev/null || true)"
  fi

  printf '%s\n' "$source_output" | grep -E \
    'Cascable Studio\.app/Contents/MacOS/Cascable Studio|EOS Utility\.app/Contents/MacOS/EOS Utility|Image Capture\.app/Contents/MacOS/Image Capture|/Photos\.app/Contents/MacOS/Photos( |$)' \
    | grep -v -E 'grep -E|run-safe-test\.sh' || true
}

guard_or_abort() {
  local detected
  detected="$(check_competing_apps)"
  if [ -n "$detected" ]; then
    printf 'COMPETING_APPLICATION_DETECTED=true\n'
    printf '%s\n' "$detected"
    printf 'The camera application above must be closed manually if you want to proceed.\n'
    printf 'This guard will never quit, terminate, kill, or relaunch it.\n'
    abort "competing camera application is running" 2
  fi
  printf 'COMPETING_APPLICATION_DETECTED=false\nGUARD=PASS\n'
}

case "$MODE" in
  source)
    printf 'SOURCE_AUDIT_BEGIN\n'
    printf 'Active harness/orchestration files:\n'
    find "$ROOT/macos_cascable_demo" -maxdepth 3 -type f \
      \( -name '*.sh' -o -name '*.swift' -o -name '*.md' \) -print | sort
    printf 'Termination-control references (excluding this safe script):\n'
    grep -RInE 'osascript|tell application|pkill|killall|launchctl|NSRunningApplication|forceTerminate' \
      "$ROOT/macos_cascable_demo" \
      --exclude='run-safe-test.sh' --exclude-dir='logs' 2>/dev/null || true
    printf 'SOURCE_AUDIT_END\nCAMERA_COMMAND=false\n'
    ;;
  process)
    guard_or_abort
    printf 'PROCESS_DIAGNOSTIC=PASS\nCAMERA_COMMAND=false\n'
    ;;
  capability)
    [ "$ALLOW_HARDWARE" -eq 1 ] || abort "hardware mode requires --allow-hardware" 64
    [ "$AUTHORIZATION" = "capability-preflight" ] || abort "capability mode requires --authorization capability-preflight" 64
    guard_or_abort
    [ -x "$HARNESS" ] || abort "harness binary is not executable" 66
    printf 'CAMERA_COMMAND=true\n'
    "$HARNESS" --capability-only
    ;;
  transfer)
    [ "$ALLOW_HARDWARE" -eq 1 ] || abort "hardware mode requires --allow-hardware" 64
    [ "$SINGLE_SHOT" -eq 1 ] || abort "transfer mode requires --single-shot" 64
    [ "$AUTHORIZATION" = "one-shot-transfer" ] || abort "transfer mode requires --authorization one-shot-transfer" 64
    guard_or_abort
    [ -x "$HARNESS" ] || abort "harness binary is not executable" 66
    printf 'CAMERA_COMMAND=true\n'
    "$HARNESS" --transfer --no-reconnect
    ;;
  *)
    abort "unknown mode '$MODE'" 64
    ;;
esac
