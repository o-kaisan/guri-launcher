#!/usr/bin/env bash
set -euo pipefail

readonly COMMAND_LINE_TOOLS_VERSION="11076708"
readonly SYSTEM_IMAGE="system-images;android-37.0;google_apis;x86_64"

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
export ANDROID_SDK_ROOT
export ANDROID_HOME="$ANDROID_SDK_ROOT"

install_command_line_tools() (
  local archive temporary_directory
  archive="commandlinetools-linux-${COMMAND_LINE_TOOLS_VERSION}_latest.zip"
  temporary_directory="$(mktemp -d)"
  trap 'rm -rf -- "$temporary_directory"' EXIT

  curl --fail --location --retry 3 \
    "https://dl.google.com/android/repository/${archive}" \
    --output "$temporary_directory/command-line-tools.zip"
  unzip -q "$temporary_directory/command-line-tools.zip" -d "$temporary_directory"
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  rm -rf -- "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  mv -- "$temporary_directory/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
)

if [[ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  install_command_line_tools
fi

readonly SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

# Automated environments cannot answer the interactive Android SDK license prompt.
# sdkmanager still returns a non-zero status for actual download/install failures.
set +o pipefail
yes | "$SDKMANAGER" --licenses >/dev/null
license_status=${PIPESTATUS[1]}
set -o pipefail
if (( license_status != 0 )); then
  printf 'Android SDK license acceptance failed (status %d).\n' "$license_status" >&2
  exit "$license_status"
fi

"$SDKMANAGER" --channel=3 \
  "platform-tools" \
  "emulator" \
  "platforms;android-35" \
  "build-tools;36.0.0" \
  "$SYSTEM_IMAGE"

printf 'Android 17 (API 37.0) emulator dependencies are installed in %s.\n' "$ANDROID_SDK_ROOT"
