#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SCRIPT="$REPOSITORY_ROOT/scripts/release/release-metadata.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_metadata() {
  local tag="$1"
  local expected_version_name="$2"
  local expected_version_code="$3"
  local expected_apk_name="$4"
  local actual expected

  actual="$("$SCRIPT" "$tag")"
  expected="$(printf 'version_name=%s\nversion_code=%s\napk_name=%s' \
    "$expected_version_name" "$expected_version_code" "$expected_apk_name")"

  [[ "$actual" == "$expected" ]] \
    || fail "$tag produced unexpected metadata: $actual"
}

assert_invalid_tag() {
  local tag="$1"
  local output status

  set +e
  output="$("$SCRIPT" "$tag" 2>&1)"
  status=$?
  set -e

  [[ "$status" -eq 2 ]] \
    || fail "$tag returned status $status instead of 2"
  [[ "$output" == *"invalid release tag"* ]] \
    || fail "$tag did not explain that the release tag is invalid: $output"
}

assert_invalid_invocation() {
  local output status

  set +e
  output="$("$SCRIPT" "$@" 2>&1)"
  status=$?
  set -e

  [[ "$status" -eq 2 ]] \
    || fail "invalid invocation returned status $status instead of 2"
  [[ "$output" == *"usage:"* ]] \
    || fail "invalid invocation did not print usage: $output"
}

[[ -x "$SCRIPT" ]] || fail "$SCRIPT is missing or is not executable"

# A valid tag drives Android version metadata and the downloadable filename.
assert_metadata "v0.1.0" "0.1.0" "1000" "guri-launcher-v0.1.0.apk"
assert_metadata "v1.2.3" "1.2.3" "1002003" "guri-launcher-v1.2.3.apk"
assert_metadata "v2100.0.0" "2100.0.0" "2100000000" \
  "guri-launcher-v2100.0.0.apk"

# Malformed, ambiguous, and Android-incompatible versions must not be released.
for invalid_tag in \
  "1.2.3" \
  "v1.2" \
  "v1.2.3-rc1" \
  "v01.2.3" \
  "v1.1000.0" \
  "v1.2.1000" \
  "v2100.0.1" \
  "v0.0.0" \
  "v1.2.3/other"; do
  assert_invalid_tag "$invalid_tag"
done

# Missing or extra arguments must fail rather than silently using wrong metadata.
assert_invalid_invocation
assert_invalid_invocation "v1.2.3" "unexpected"

printf 'Release metadata checks passed.\n'
