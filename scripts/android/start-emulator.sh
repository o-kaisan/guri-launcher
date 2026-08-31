#!/usr/bin/env bash
set -euo pipefail

readonly AVD_NAME="${ANDROID_AVD_NAME:-guri_docker_api_35}"
readonly ACCELERATION="${ANDROID_EMULATOR_ACCELERATION:-auto}"
readonly KVM_DEVICE="${ANDROID_KVM_DEVICE:-/dev/kvm}"
readonly SYSTEM_IMAGE="system-images;android-35;google_apis;x86_64"

case "$ACCELERATION" in
  auto|off) ;;
  *)
    echo "error: ANDROID_EMULATOR_ACCELERATION must be 'auto' or 'off' (received: $ACCELERATION)" >&2
    exit 64
    ;;
esac

if [[ "$ACCELERATION" == "auto" ]]; then
  if [[ ! -e "$KVM_DEVICE" || ! -r "$KVM_DEVICE" || ! -w "$KVM_DEVICE" ]]; then
    echo "error: KVM is unavailable. Pass ANDROID_EMULATOR_ACCELERATION=off explicitly to use slow software emulation." >&2
    exit 69
  fi
  acceleration_args=(-accel on)
else
  echo "warning: KVM acceleration is disabled; software emulation will be significantly slower." >&2
  acceleration_args=(-accel off)
fi

avd_home="${ANDROID_AVD_HOME:-${HOME}/.android/avd}"
avd_dir="${avd_home}/${AVD_NAME}.avd"
if [[ ! -d "$avd_dir" ]]; then
  mkdir -p "$avd_home"
  printf 'no\n' | avdmanager create avd --force --name "$AVD_NAME" --package "$SYSTEM_IMAGE" --device pixel_6
  # These defaults apply only to this newly-created, Docker-specific AVD.
  cat >>"$avd_dir/config.ini" <<'EOF'
hw.cpu.ncore=4
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader_indirect
hw.ramSize=4096
EOF
fi

emulator_args=(
  -avd "$AVD_NAME"
  "${acceleration_args[@]}"
  -no-window
  -no-audio
  -no-boot-anim
  -gpu swiftshader_indirect
)

if [[ "${ANDROID_EMULATOR_DRY_RUN:-0}" == "1" ]]; then
  printf '%q ' emulator "${emulator_args[@]}"
  printf '\n'
  exit 0
fi

emulator "${emulator_args[@]}" >"${ANDROID_EMULATOR_LOG:-/tmp/guri-emulator.log}" 2>&1 &
adb wait-for-device
timeout "${ANDROID_BOOT_TIMEOUT_SECONDS:-300}" bash -c \
  'until [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d "\r")" == "1" ]]; do sleep 2; done'
adb devices
