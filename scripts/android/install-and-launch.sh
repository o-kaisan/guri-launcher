#!/usr/bin/env bash
set -euo pipefail

readonly PACKAGE_NAME="io.github.okaisan.gurilauncher"
readonly ACTIVITY_NAME=".presentation.MainActivity"
readonly APK_PATH="app/build/outputs/apk/debug/app-debug.apk"

./gradlew assembleDebug
adb -e install -r "$APK_PATH"
adb -e shell am start -W -n "${PACKAGE_NAME}/${ACTIVITY_NAME}"
