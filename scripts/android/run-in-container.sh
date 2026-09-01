#!/usr/bin/env bash
set -euo pipefail

readonly ACCELERATION="${ANDROID_EMULATOR_ACCELERATION:-auto}"
readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "$ACCELERATION" in
  auto|off) ;;
  *) echo "error: ANDROID_EMULATOR_ACCELERATION must be 'auto' or 'off'." >&2; exit 64 ;;
esac

if [[ "$ACCELERATION" == "auto" ]]; then
  if [[ ! -e /dev/kvm ]]; then
    echo "error: /dev/kvm is unavailable. Explicitly set ANDROID_EMULATOR_ACCELERATION=off to continue without KVM." >&2
    exit 69
  fi
  readonly SERVICE="android-emulator"
  compose_args=()
else
  echo "warning: starting with software emulation because ANDROID_EMULATOR_ACCELERATION=off." >&2
  readonly SERVICE="android-emulator-software"
  compose_args=(--profile software)
fi

cd "$REPOSITORY_ROOT"
docker compose "${compose_args[@]}" down --remove-orphans
docker compose "${compose_args[@]}" build "$SERVICE"
docker compose "${compose_args[@]}" run --rm --no-deps -T "$SERVICE" \
  bash -lc 'ANDROID_USER_HOME=/root/.android-build ./gradlew assembleDebug'
docker compose "${compose_args[@]}" up --detach --wait --remove-orphans --no-build "$SERVICE"
docker compose "${compose_args[@]}" exec -T "$SERVICE" \
  bash -lc 'SKIP_ANDROID_BUILD=true ./scripts/android/install-and-launch.sh'
