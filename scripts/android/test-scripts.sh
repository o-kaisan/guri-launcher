#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tests=0

fail() { echo "not ok - $*" >&2; exit 1; }
pass() { tests=$((tests + 1)); echo "ok $tests - $*"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.android/avd"
cat >"$tmp/bin/avdmanager" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$MOCK_LOG"
mkdir -p "$ANDROID_AVD_HOME/${ANDROID_AVD_NAME}.avd"
: >"$ANDROID_AVD_HOME/${ANDROID_AVD_NAME}.avd/config.ini"
EOF
chmod +x "$tmp/bin/avdmanager"
export PATH="$tmp/bin:$PATH" MOCK_LOG="$tmp/mock.log" HOME="$tmp/home"
export ANDROID_AVD_HOME="$tmp/home/.android/avd" ANDROID_AVD_NAME=test_api_35
export ANDROID_EMULATOR_DRY_RUN=1

if ANDROID_EMULATOR_ACCELERATION=turbo "$SCRIPT_DIR/start-emulator.sh" >/dev/null 2>&1; then
  fail "invalid acceleration was accepted"
fi
pass "acceleration mode is allow-list validated"

if ANDROID_EMULATOR_ACCELERATION=auto ANDROID_KVM_DEVICE="$tmp/missing-kvm" "$SCRIPT_DIR/start-emulator.sh" >/dev/null 2>&1; then
  fail "auto acceleration continued without KVM"
fi
pass "auto mode rejects a host without KVM"

touch "$tmp/kvm"
auto_output="$(ANDROID_EMULATOR_ACCELERATION=auto ANDROID_KVM_DEVICE="$tmp/kvm" "$SCRIPT_DIR/start-emulator.sh")"
[[ "$auto_output" == *"-accel on"* ]] || fail "auto mode did not select KVM acceleration"
pass "auto mode selects acceleration when KVM is available"

off_output="$(ANDROID_EMULATOR_ACCELERATION=off ANDROID_KVM_DEVICE="$tmp/missing-kvm" "$SCRIPT_DIR/start-emulator.sh" 2>/dev/null)"
[[ "$off_output" == *"-accel off"* ]] || fail "off mode did not select software emulation"
pass "off mode explicitly selects software emulation"

before="$(wc -l <"$MOCK_LOG")"
ANDROID_EMULATOR_ACCELERATION=off "$SCRIPT_DIR/start-emulator.sh" >/dev/null 2>&1
after="$(wc -l <"$MOCK_LOG")"
[[ "$before" == "$after" ]] || fail "existing AVD was recreated"
pass "an existing AVD is not recreated"

echo "1..$tests"
