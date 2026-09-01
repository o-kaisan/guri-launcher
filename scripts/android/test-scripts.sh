#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

for script in "$REPOSITORY_ROOT"/.codex/environments/setup.sh "$REPOSITORY_ROOT"/scripts/android/*.sh; do
  bash -n "$script"
done

required_setup_packages=(
  'platform-tools'
  'emulator'
  'platforms;android-35'
  'build-tools;36.0.0'
  'system-images;android-37.0;google_apis;x86_64'
)
for package in "${required_setup_packages[@]}"; do
  grep -Fq -- "\"$package\"" "$REPOSITORY_ROOT/scripts/android/setup-sdk.sh"
done

grep -Fq 'commandlinetools-linux-${COMMAND_LINE_TOOLS_VERSION}_latest.zip' \
  "$REPOSITORY_ROOT/scripts/android/setup-sdk.sh"
grep -Fq '"$SDKMANAGER" --channel=3' "$REPOSITORY_ROOT/scripts/android/setup-sdk.sh"

grep -Fq 'list avd -c' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq 'grep -Fxq' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq 'sys.boot_completed' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq 'adb -e wait-for-device &' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq 'trap on_exit EXIT' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq "trap 'exit 130' INT TERM" "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq 'emulator_args+=(-gpu host)' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq -- 'hardware-qemu.ini.lock' "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"
grep -Fq 'pm disable-user --user 0 "$SYSTEM_LAUNCHER_PACKAGE"' \
  "$REPOSITORY_ROOT/scripts/android/start-emulator.sh"

test_acceleration_selection() {
  local expected="$1" kvm_available="$2" accel_check_status="$3"
  local test_root script output
  test_root="$(mktemp -d)"
  script="$test_root/start-emulator.sh"
  trap 'rm -rf -- "$test_root"' RETURN

  mkdir -p "$test_root/home/.android/avd/guri_api_37.avd" \
    "$test_root/sdk/cmdline-tools/latest/bin" "$test_root/sdk/emulator" \
    "$test_root/sdk/platform-tools"
  : >"$test_root/home/.android/avd/guri_api_37.avd/config.ini"
  if [[ "$kvm_available" == "yes" ]]; then
    : >"$test_root/kvm"
  fi
  sed "s|/dev/kvm|$test_root/kvm|g" \
    "$REPOSITORY_ROOT/scripts/android/start-emulator.sh" >"$script"

  cat >"$test_root/sdk/cmdline-tools/latest/bin/avdmanager" <<'EOF'
#!/usr/bin/env bash
printf 'guri_api_37\n'
EOF
  cat >"$test_root/sdk/emulator/emulator" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-accel-check" ]]; then
  exit "${FAKE_ACCEL_CHECK_STATUS:-1}"
fi
printf '%s\n' "$@" >"$FAKE_EMULATOR_ARGS"
sleep 5
EOF
  cat >"$test_root/sdk/platform-tools/adb" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"shell getprop sys.boot_completed"* ]]; then
  printf '1\n'
elif [[ "$*" == *"shell service check package"* ]]; then
  printf 'Service package: found\n'
fi
exit 0
EOF
  chmod +x "$script" "$test_root/sdk/cmdline-tools/latest/bin/avdmanager" \
    "$test_root/sdk/emulator/emulator" "$test_root/sdk/platform-tools/adb"

  output="$(HOME="$test_root/home" ANDROID_SDK_ROOT="$test_root/sdk" \
    FAKE_ACCEL_CHECK_STATUS="$accel_check_status" \
    FAKE_EMULATOR_ARGS="$test_root/emulator-args" "$script")"
  grep -Fq "Android emulator acceleration: $expected (requested: auto)." <<<"$output"
  grep -Fxq -- "$expected" < <(awk '$0 == "-accel" { getline; print; exit }' "$test_root/emulator-args")
}

# Auto mode enables KVM only when both the device checks and emulator probe succeed.
test_acceleration_selection on yes 0
test_acceleration_selection off no 0
test_acceleration_selection off yes 1

invalid_output="$(EMULATOR_ACCELERATION=turbo \
  "$REPOSITORY_ROOT/scripts/android/start-emulator.sh" 2>&1 || printf 'status=%s\n' "$?")"
grep -Fq 'EMULATOR_ACCELERATION must be one of: auto, on, off.' <<<"$invalid_output"
grep -Fq 'status=2' <<<"$invalid_output"

invalid_avd_output="$(ANDROID_AVD_NAME='../shared' \
  "$REPOSITORY_ROOT/scripts/android/start-emulator.sh" 2>&1 || printf 'status=%s\n' "$?")"
grep -Fq 'ANDROID_AVD_NAME contains unsupported characters.' <<<"$invalid_avd_output"
grep -Fq 'status=2' <<<"$invalid_avd_output"

invalid_window_output="$(EMULATOR_WINDOW_MODE=visible \
  "$REPOSITORY_ROOT/scripts/android/start-emulator.sh" 2>&1 || printf 'status=%s\n' "$?")"
grep -Fq 'EMULATOR_WINDOW_MODE must be one of: headless, window.' <<<"$invalid_window_output"
grep -Fq 'status=2' <<<"$invalid_window_output"

invalid_gui_port_output="$(NOVNC_PORT=70000 \
  "$REPOSITORY_ROOT/scripts/android/start-gui-emulator.sh" 2>&1 || printf 'status=%s\n' "$?")"
grep -Fq 'NOVNC_PORT must be an integer from 1 through 65535.' <<<"$invalid_gui_port_output"
grep -Fq 'status=2' <<<"$invalid_gui_port_output"

invalid_skip_build_output="$(SKIP_ANDROID_BUILD=maybe \
  "$REPOSITORY_ROOT/scripts/android/install-and-launch.sh" 2>&1 || printf 'status=%s\n' "$?")"
grep -Fq "SKIP_ANDROID_BUILD must be 'true' or 'false'." <<<"$invalid_skip_build_output"
grep -Fq 'status=2' <<<"$invalid_skip_build_output"
grep -Fq 'MAX_LAUNCH_ATTEMPTS=5' \
  "$REPOSITORY_ROOT/scripts/android/install-and-launch.sh"
grep -Fq 'adb -e wait-for-device' \
  "$REPOSITORY_ROOT/scripts/android/install-and-launch.sh"
grep -Fq 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' \
  "$REPOSITORY_ROOT/scripts/android/install-and-launch.sh"
grep -Fq 'consecutive_ready_checks >= 3' \
  "$REPOSITORY_ROOT/scripts/android/install-and-launch.sh"

grep -Fq -- 'run --rm --no-deps -T "$SERVICE"' \
  "$REPOSITORY_ROOT/scripts/android/run-in-container.sh"
grep -Fq -- 'up --detach --wait --remove-orphans --no-build "$SERVICE"' \
  "$REPOSITORY_ROOT/scripts/android/run-in-container.sh"
grep -Fq -- 'SKIP_ANDROID_BUILD=true ./scripts/android/install-and-launch.sh' \
  "$REPOSITORY_ROOT/scripts/android/run-in-container.sh"
grep -Fq -- 'android-emulator-software' "$REPOSITORY_ROOT/compose.yaml"
grep -Fq -- '/dev/kvm:/dev/kvm' "$REPOSITORY_ROOT/compose.yaml"
grep -Fq -- 'ANDROID_AVD_NAME: guri_docker_api_37' "$REPOSITORY_ROOT/compose.yaml"
grep -Fq -- '"127.0.0.1:${ANDROID_EMULATOR_GUI_PORT:-6080}:6080"' \
  "$REPOSITORY_ROOT/compose.yaml"
grep -Fq -- './scripts/android/start-gui-emulator.sh' "$REPOSITORY_ROOT/compose.yaml"
grep -Fq -- 'android-gradle-cache:/root/.gradle' "$REPOSITORY_ROOT/compose.yaml"
grep -Fq -- 'android-build-home:/root/.android-build' "$REPOSITORY_ROOT/compose.yaml"
grep -Fq -- 'ANDROID_USER_HOME=/root/.android-build ./gradlew assembleDebug' \
  "$REPOSITORY_ROOT/scripts/android/run-in-container.sh"
grep -Fq -- "service check package" "$REPOSITORY_ROOT/compose.yaml"
grep -Fq -- "service check activity" "$REPOSITORY_ROOT/compose.yaml"
grep -Fq -- 'websockify --web=/usr/share/novnc' \
  "$REPOSITORY_ROOT/scripts/android/start-gui-emulator.sh"

printf 'Android emulator script checks passed.\n'
