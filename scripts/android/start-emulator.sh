#!/usr/bin/env bash
set -euo pipefail

readonly AVD_NAME="${ANDROID_AVD_NAME:-guri_api_35}"
readonly SYSTEM_IMAGE="system-images;android-35;google_apis;x86_64"
readonly DEVICE_PROFILE="pixel_6"
readonly BOOT_TIMEOUT_SECONDS="${BOOT_TIMEOUT_SECONDS:-300}"
readonly EMULATOR_ACCELERATION="${EMULATOR_ACCELERATION:-auto}"

if [[ ! "$BOOT_TIMEOUT_SECONDS" =~ ^[1-9][0-9]{0,3}$ ]]; then
  printf 'BOOT_TIMEOUT_SECONDS must be an integer from 1 through 9999.\n' >&2
  exit 2
fi

if [[ ! "$AVD_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'ANDROID_AVD_NAME contains unsupported characters.\n' >&2
  exit 2
fi

case "$EMULATOR_ACCELERATION" in
  auto|on|off) ;;
  *)
    printf 'EMULATOR_ACCELERATION must be one of: auto, on, off.\n' >&2
    exit 2
    ;;
esac

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
export ANDROID_SDK_ROOT
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"

readonly AVDMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
readonly EMULATOR="$ANDROID_SDK_ROOT/emulator/emulator"
readonly PID_FILE="${TMPDIR:-/tmp}/${AVD_NAME}.pid"
readonly LOG_FILE="${TMPDIR:-/tmp}/${AVD_NAME}.log"
emulator_pid=""
adb_wait_pid=""

require_executable() {
  if [[ ! -x "$1" ]]; then
    printf 'Required Android SDK executable is missing: %s\n' "$1" >&2
    exit 1
  fi
}

diagnose() {
  printf '\n=== adb devices -l ===\n' >&2
  adb devices -l >&2 || true
  printf '\n=== emulator processes ===\n' >&2
  ps -ef | grep '[e]mulator.*-avd' >&2 || true
  printf '\n=== emulator log (last 200 lines) ===\n' >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  printf '\n=== adb properties ===\n' >&2
  adb -e shell getprop >&2 || true
}

stop_started_emulator() {
  if [[ -n "$adb_wait_pid" ]] && kill -0 "$adb_wait_pid" 2>/dev/null; then
    kill "$adb_wait_pid" 2>/dev/null || true
  fi
  adb -e emu kill >/dev/null 2>&1 || true
  if [[ -n "$emulator_pid" ]] && kill -0 "$emulator_pid" 2>/dev/null; then
    kill "$emulator_pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$emulator_pid" 2>/dev/null || break
      sleep 1
    done
    kill -KILL "$emulator_pid" 2>/dev/null || true
  fi
  rm -f -- "$PID_FILE"
}

on_exit() {
  local status=$?
  if (( status != 0 )); then
    diagnose
    stop_started_emulator
  fi
  exit "$status"
}
trap on_exit EXIT
trap 'exit 130' INT TERM

require_executable "$AVDMANAGER"
require_executable "$EMULATOR"
command -v adb >/dev/null || { printf 'adb is not available. Run setup-sdk.sh first.\n' >&2; exit 1; }

acceleration_mode="$EMULATOR_ACCELERATION"
if [[ "$acceleration_mode" == "auto" ]]; then
  acceleration_mode="off"
  if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]] && "$EMULATOR" -accel-check >/dev/null 2>&1; then
    acceleration_mode="on"
  fi
fi
readonly acceleration_mode
printf 'Android emulator acceleration: %s (requested: %s).\n' \
  "$acceleration_mode" "$EMULATOR_ACCELERATION"

# Match the complete AVD name so similarly named or existing AVDs are untouched.
if ! "$AVDMANAGER" list avd -c | grep -Fxq -- "$AVD_NAME"; then
  printf 'no\n' | "$AVDMANAGER" create avd \
    --name "$AVD_NAME" \
    --package "$SYSTEM_IMAGE" \
    --device "$DEVICE_PROFILE"
fi

readonly AVD_CONFIG="$HOME/.android/avd/${AVD_NAME}.avd/config.ini"
if [[ ! -f "$AVD_CONFIG" ]]; then
  printf 'AVD configuration was not created: %s\n' "$AVD_CONFIG" >&2
  exit 1
fi

set_avd_property() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$AVD_CONFIG"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$AVD_CONFIG"
  else
    printf '%s=%s\n' "$key" "$value" >>"$AVD_CONFIG"
  fi
}

# Explicit software-compatible hardware profile for unaccelerated cloud workers.
set_avd_property "hw.ramSize" "2048"
set_avd_property "hw.cpu.ncore" "2"
set_avd_property "hw.gpu.enabled" "no"
set_avd_property "hw.gpu.mode" "off"

emulator_args=(
  -avd "$AVD_NAME"
  -no-window
  -no-audio
  -no-boot-anim
  -no-snapshot-load
  -no-snapshot-save
  -gpu off
  -feature -Vulkan
  -accel "$acceleration_mode"
)
"$EMULATOR" "${emulator_args[@]}" >"$LOG_FILE" 2>&1 &
emulator_pid=$!
printf '%s\n' "$emulator_pid" >"$PID_FILE"

deadline=$((SECONDS + BOOT_TIMEOUT_SECONDS))
adb -e wait-for-device &
adb_wait_pid=$!
while kill -0 "$adb_wait_pid" 2>/dev/null; do
  if ! kill -0 "$emulator_pid" 2>/dev/null; then
    printf 'Android emulator exited before adb detected it.\n' >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    printf 'Timed out after %s seconds waiting for adb wait-for-device.\n' "$BOOT_TIMEOUT_SECONDS" >&2
    exit 1
  fi
  sleep 1
done
wait "$adb_wait_pid"
adb_wait_pid=""

while [[ "$(adb -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]]; do
  if ! kill -0 "$emulator_pid" 2>/dev/null; then
    printf 'Android emulator exited before boot completed.\n' >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    printf 'Timed out after %s seconds waiting for sys.boot_completed.\n' "$BOOT_TIMEOUT_SECONDS" >&2
    exit 1
  fi
  sleep 2
done

trap - EXIT INT TERM
printf 'AVD %s booted (ABI x86_64, device %s, RAM 2048 MiB, GPU off).\n' \
  "$AVD_NAME" "$DEVICE_PROFILE"
adb devices -l
