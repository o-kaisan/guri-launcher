#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
readonly SCRIPT="$REPOSITORY_ROOT/scripts/release/verify-apk-signer.sh"
readonly TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "$TEST_ROOT/bin"
cat >"$TEST_ROOT/bin/apksigner" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$FAKE_APKSIGNER_LOG"
[[ "$#" -eq 4 ]] || exit 60
[[ "$1" == "verify" && "$2" == "--verbose" && "$3" == "--print-certs" ]] \
  || exit 61
[[ -f "$4" ]] || exit 62
[[ "${FAKE_APKSIGNER_FAILURE:-false}" != true ]] || exit 63
if [[ "${FAKE_MISSING_CERTIFICATE:-false}" != true ]]; then
  printf 'Signer %s certificate SHA-256 digest: %s\n' \
    "${FAKE_SIGNER_LABEL:-#1}" "$FAKE_SIGNER_DIGEST"
fi
if [[ "${FAKE_SECOND_SIGNER_DIGEST:-}" != '' ]]; then
  printf 'Signer #2 certificate SHA-256 digest: %s\n' "$FAKE_SECOND_SIGNER_DIGEST"
fi
EOF
chmod +x "$TEST_ROOT/bin/apksigner"

readonly APK_PATH="$TEST_ROOT/guri-launcher-v1.2.3.apk"
readonly EXPECTED_FINGERPRINT="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
readonly EXPECTED_FINGERPRINT_LOWER="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
readonly OTHER_FINGERPRINT="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
readonly FAKE_APKSIGNER_LOG="$TEST_ROOT/apksigner.log"
export FAKE_APKSIGNER_LOG
: >"$APK_PATH"

[[ -x "$SCRIPT" ]] || fail "$SCRIPT is missing or is not executable"

output="$(
  APKSIGNER="$TEST_ROOT/bin/apksigner" \
    FAKE_SIGNER_DIGEST="$EXPECTED_FINGERPRINT_LOWER" \
    "$SCRIPT" "$APK_PATH" "$EXPECTED_FINGERPRINT"
)"
[[ "$output" == *"match the configured release signer"* ]] \
  || fail "matching APK signer was not accepted"

targeted_output="$(
  APKSIGNER="$TEST_ROOT/bin/apksigner" \
    FAKE_SIGNER_DIGEST="$EXPECTED_FINGERPRINT_LOWER" \
    FAKE_SIGNER_LABEL='(minSdkVersion=24, maxSdkVersion=32)' \
    "$SCRIPT" "$APK_PATH" "$EXPECTED_FINGERPRINT"
)"
[[ "$targeted_output" == *"match the configured release signer"* ]] \
  || fail "SDK-targeted matching APK signer was not accepted"

set +e
mismatch_output="$(
  APKSIGNER="$TEST_ROOT/bin/apksigner" \
    FAKE_SIGNER_DIGEST="$OTHER_FINGERPRINT" \
    "$SCRIPT" "$APK_PATH" "$EXPECTED_FINGERPRINT" 2>&1
)"
mismatch_status=$?
set -e
[[ "$mismatch_status" -eq 2 ]] \
  || fail "wrong APK signer returned status $mismatch_status"
[[ "$mismatch_output" == *"does not match"* ]] \
  || fail "wrong APK signer did not explain the identity mismatch"

set +e
multiple_output="$(
  APKSIGNER="$TEST_ROOT/bin/apksigner" \
    FAKE_SIGNER_DIGEST="$EXPECTED_FINGERPRINT" \
    FAKE_SECOND_SIGNER_DIGEST="$OTHER_FINGERPRINT" \
    "$SCRIPT" "$APK_PATH" "$EXPECTED_FINGERPRINT" 2>&1
)"
multiple_status=$?
set -e
[[ "$multiple_status" -eq 2 ]] \
  || fail "APK with multiple signers returned status $multiple_status"
[[ "$multiple_output" == *"does not match"* ]] \
  || fail "APK with a different targeted signer did not explain the identity mismatch"

multiple_matching_output="$(
  APKSIGNER="$TEST_ROOT/bin/apksigner" \
    FAKE_SIGNER_DIGEST="$EXPECTED_FINGERPRINT" \
    FAKE_SECOND_SIGNER_DIGEST="$EXPECTED_FINGERPRINT_LOWER" \
    "$SCRIPT" "$APK_PATH" "$EXPECTED_FINGERPRINT"
)"
[[ "$multiple_matching_output" == *"match the configured release signer"* ]] \
  || fail "multiple SDK-targeted entries for the configured signer were not accepted"

: >"$FAKE_APKSIGNER_LOG"
set +e
invalid_expected_output="$(
  APKSIGNER="$TEST_ROOT/bin/apksigner" \
    FAKE_SIGNER_DIGEST="$EXPECTED_FINGERPRINT" \
    "$SCRIPT" "$APK_PATH" not-a-fingerprint 2>&1
)"
invalid_expected_status=$?
set -e
[[ "$invalid_expected_status" -eq 2 ]] \
  || fail "invalid expected fingerprint returned status $invalid_expected_status"
[[ "$invalid_expected_output" == *"expected certificate fingerprint"* ]] \
  || fail "invalid expected fingerprint did not produce a clear error"
[[ ! -s "$FAKE_APKSIGNER_LOG" ]] \
  || fail "invalid expected fingerprint invoked apksigner"

set +e
missing_certificate_output="$(
  APKSIGNER="$TEST_ROOT/bin/apksigner" \
    FAKE_MISSING_CERTIFICATE=true \
    FAKE_SIGNER_DIGEST="$EXPECTED_FINGERPRINT" \
    "$SCRIPT" "$APK_PATH" "$EXPECTED_FINGERPRINT" 2>&1
)"
missing_certificate_status=$?
set -e
[[ "$missing_certificate_status" -eq 1 ]] \
  || fail "missing signer digest returned status $missing_certificate_status"
[[ "$missing_certificate_output" == *"did not report"* ]] \
  || fail "missing signer digest did not produce a clear error"

printf 'APK signer verification checks passed.\n'
