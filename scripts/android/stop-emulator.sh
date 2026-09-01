#!/usr/bin/env bash
set -euo pipefail

readonly AVD_NAME="guri_api_37"
readonly PID_FILE="${TMPDIR:-/tmp}/${AVD_NAME}.pid"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"

adb -e emu kill >/dev/null 2>&1 || true
if [[ -f "$PID_FILE" ]]; then
  emulator_pid="$(cat "$PID_FILE")"
  if [[ "$emulator_pid" =~ ^[0-9]+$ ]] && kill -0 "$emulator_pid" 2>/dev/null; then
    kill "$emulator_pid" 2>/dev/null || true
  fi
  rm -f -- "$PID_FILE"
fi
