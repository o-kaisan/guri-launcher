#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
readonly SCRIPT="$REPOSITORY_ROOT/scripts/release/verify-release-tag.sh"
readonly TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "$TEST_ROOT/bin"
cat >"$TEST_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "$#" -eq 4 && "$1" == "api" ]] || exit 64
[[ "$2" == "repos/o-kaisan/guri-launcher/commits/v1.2.3" ]] || exit 65
[[ "$3" == "--jq" && "$4" == ".sha" ]] || exit 66
[[ "${FAKE_GH_FAILURE:-false}" != true ]] || exit 69
printf '%s\n' "$FAKE_CURRENT_TAG_COMMIT"
EOF
chmod +x "$TEST_ROOT/bin/gh"

readonly ORIGINAL_COMMIT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
readonly MOVED_COMMIT="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

[[ -x "$SCRIPT" ]] || fail "$SCRIPT is missing or is not executable"

output="$(
  PATH="$TEST_ROOT/bin:$PATH" \
    FAKE_CURRENT_TAG_COMMIT="$ORIGINAL_COMMIT" \
    GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
    "$SCRIPT" v1.2.3 "$ORIGINAL_COMMIT"
)"
[[ "$output" == *"still points to $ORIGINAL_COMMIT"* ]] \
  || fail "matching tag did not report the verified commit"

set +e
moved_output="$(
  PATH="$TEST_ROOT/bin:$PATH" \
    FAKE_CURRENT_TAG_COMMIT="$MOVED_COMMIT" \
    GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
    "$SCRIPT" v1.2.3 "$ORIGINAL_COMMIT" 2>&1
)"
moved_status=$?
set -e
[[ "$moved_status" -eq 2 ]] \
  || fail "moved tag returned status $moved_status instead of 2"
[[ "$moved_output" == *"tag moved after this workflow started"* ]] \
  || fail "moved tag did not explain why publication was rejected"

set +e
invalid_output="$(
  PATH="$TEST_ROOT/bin:$PATH" \
    FAKE_CURRENT_TAG_COMMIT="$ORIGINAL_COMMIT" \
    GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
    "$SCRIPT" v1.2 "$ORIGINAL_COMMIT" 2>&1
)"
invalid_status=$?
set -e
[[ "$invalid_status" -eq 2 ]] \
  || fail "invalid tag returned status $invalid_status instead of 2"
[[ "$invalid_output" == *"invalid release tag"* ]] \
  || fail "invalid tag was not rejected before the GitHub lookup"

set +e
lookup_output="$(
  PATH="$TEST_ROOT/bin:$PATH" \
    FAKE_CURRENT_TAG_COMMIT="$ORIGINAL_COMMIT" \
    FAKE_GH_FAILURE=true \
    GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
    "$SCRIPT" v1.2.3 "$ORIGINAL_COMMIT" 2>&1
)"
lookup_status=$?
set -e
[[ "$lookup_status" -eq 1 ]] \
  || fail "GitHub lookup failure returned status $lookup_status instead of 1"
[[ "$lookup_output" == *"could not resolve the current release tag"* ]] \
  || fail "GitHub lookup failure did not produce a clear error"

printf 'Release tag verification checks passed.\n'
