#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

required_make_targets=(
  'test'
  'lint'
  'assemble-debug'
  'check'
  'android-sdk'
  'android-emulator-start'
  'android-emulator-install'
  'android-emulator-devices'
  'android-emulator-stop'
  'android-emulator-test'
)
for target in "${required_make_targets[@]}"; do
  grep -Eq "^${target}:" "$REPOSITORY_ROOT/Makefile"
done
make -s -C "$REPOSITORY_ROOT" help >/dev/null

for script in "$REPOSITORY_ROOT"/.codex/environments/setup.sh "$REPOSITORY_ROOT"/scripts/android/*.sh; do
  bash -n "$script"
done

required_setup_packages=(
  'platform-tools'
  'emulator'
  'platforms;android-35'
  'system-images;android-35;google_apis;x86_64'
)
for package in "${required_setup_packages[@]}"; do
  grep -Fq -- "\"$package\"" "$REPOSITORY_ROOT/scripts/android/setup-sdk.sh"
done

grep -Fq 'commandlinetools-linux-${COMMAND_LINE_TOOLS_VERSION}_latest.zip' \
  "$REPOSITORY_ROOT/scripts/android/setup-sdk.sh"

grep -Fq 'list avd -c' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq 'grep -Fxq' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq 'sys.boot_completed' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq 'adb -e wait-for-device &' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq 'trap on_exit EXIT' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq "trap 'exit 130' INT TERM" "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"

printf 'Android emulator script checks passed.\n'
