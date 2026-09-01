#!/usr/bin/env bash
set -euo pipefail

readonly PACKAGE_NAME="io.github.okaisan.gurilauncher"
readonly ACTIVITY_NAME=".presentation.MainActivity"
readonly APK_PATH="app/build/outputs/apk/debug/app-debug.apk"
readonly ANDROID_SERVICE_TIMEOUT_SECONDS=180

case "${SKIP_ANDROID_BUILD:-false}" in
  false) ./gradlew assembleDebug ;;
  true) ;;
  *) echo "error: SKIP_ANDROID_BUILD must be 'true' or 'false'." >&2; exit 2 ;;
esac

deadline=$((SECONDS + ANDROID_SERVICE_TIMEOUT_SECONDS))
consecutive_ready_checks=0
while ((SECONDS < deadline)); do
  if adb -e shell service check package 2>/dev/null | grep -Fq 'found' \
    && adb -e shell service check activity 2>/dev/null | grep -Fq 'found'; then
    ((consecutive_ready_checks += 1))
    if ((consecutive_ready_checks >= 3)); then
      break
    fi
  else
    consecutive_ready_checks=0
  fi
  sleep 2
done

if ((consecutive_ready_checks < 3)); then
  echo "error: Android package and activity services did not become stable." >&2
  exit 1
fi

if ! install_output="$(adb -e install -r "$APK_PATH" 2>&1)"; then
  printf '%s\n' "$install_output" >&2
  if [[ "$install_output" != *INSTALL_FAILED_UPDATE_INCOMPATIBLE* ]]; then
    exit 1
  fi

  echo "Existing app uses a different signing key; reinstalling it." >&2
  adb -e uninstall "$PACKAGE_NAME"
  adb -e install "$APK_PATH"
else
  printf '%s\n' "$install_output"
fi

readonly MAX_LAUNCH_ATTEMPTS=5
for ((attempt = 1; attempt <= MAX_LAUNCH_ATTEMPTS; attempt++)); do
  adb -e wait-for-device
  if adb -e shell am start -W -n "${PACKAGE_NAME}/${ACTIVITY_NAME}"; then
    exit 0
  fi

  if ((attempt == MAX_LAUNCH_ATTEMPTS)); then
    echo "error: Failed to launch the Android activity after ${MAX_LAUNCH_ATTEMPTS} attempts." >&2
    exit 1
  fi

  echo "Android activity launch failed; retrying (${attempt}/${MAX_LAUNCH_ATTEMPTS})..." >&2
  sleep 2
done
