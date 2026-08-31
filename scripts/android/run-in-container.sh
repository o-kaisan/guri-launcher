#!/usr/bin/env bash
set -euo pipefail

readonly IMAGE="${ANDROID_EMULATOR_IMAGE:-guri-launcher-android-emulator:api35}"
readonly VOLUME="${ANDROID_AVD_VOLUME:-guri-launcher-android-avd}"
readonly CONTAINER="${ANDROID_EMULATOR_CONTAINER:-guri-launcher-android-emulator}"
readonly ACCELERATION="${ANDROID_EMULATOR_ACCELERATION:-auto}"
readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "$ACCELERATION" in
  auto|off) ;;
  *) echo "error: ANDROID_EMULATOR_ACCELERATION must be 'auto' or 'off'." >&2; exit 64 ;;
esac

device_args=()
if [[ "$ACCELERATION" == "auto" ]]; then
  if [[ ! -e /dev/kvm ]]; then
    echo "error: /dev/kvm is unavailable. Explicitly set ANDROID_EMULATOR_ACCELERATION=off to continue without KVM." >&2
    exit 69
  fi
  device_args=(--device /dev/kvm:/dev/kvm)
else
  echo "warning: starting with software emulation because ANDROID_EMULATOR_ACCELERATION=off." >&2
fi

docker run --detach --name "$CONTAINER" --init \
  "${device_args[@]}" \
  -e "EMULATOR_ACCELERATION=$ACCELERATION" \
  -e "ANDROID_AVD_NAME=guri_docker_api_35" \
  -v "$REPOSITORY_ROOT:/workspace" \
  -v "$VOLUME:/root/.android/avd" \
  -w /workspace \
  "$IMAGE" \
  bash -lc './scripts/android/start-emulator.sh && exec tail -f /dev/null'

docker exec "$CONTAINER" bash -lc './scripts/android/install-and-launch.sh'
