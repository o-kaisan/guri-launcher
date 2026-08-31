#!/usr/bin/env bash
set -euo pipefail

readonly PACKAGE_NAME=io.github.okaisan.gurilauncher
readonly ACTIVITY_NAME=.presentation.MainActivity

./gradlew assembleDebug
adb wait-for-device
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -W -n "${PACKAGE_NAME}/${ACTIVITY_NAME}"
