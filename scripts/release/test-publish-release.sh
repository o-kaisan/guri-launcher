#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
readonly SCRIPT="$REPOSITORY_ROOT/scripts/release/publish-release.sh"
readonly TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

command_count() {
  local expected="$1"

  awk -v expected="$expected" '$0 == expected { count++ } END { print count + 0 }' \
    "$FAKE_GH_LOG"
}

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/dist"
cat >"$TEST_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$FAKE_GH_LOG"

case "${1:-} ${2:-}" in
  "release view")
    [[ "$#" -eq 7 ]] || exit 60
    [[ "$3" == "v1.2.3" ]] || exit 61
    [[ "$4" == "--json" && "$5" == "isDraft,assets" ]] || exit 62
    [[ "$6" == "--jq" && "$7" == '.isDraft, (.assets[]?.name)' ]] || exit 63
    case "$(<"$FAKE_RELEASE_STATE_FILE")" in
      missing) exit 1 ;;
      draft) printf 'true\n' ;;
      published)
        printf 'false\n'
        if [[ -f "$FAKE_RELEASE_ASSET_FILE" ]]; then
          cat "$FAKE_RELEASE_ASSET_FILE"
        fi
        ;;
      *) exit 64 ;;
    esac
    ;;
  "release upload")
    [[ "$#" -eq 5 ]] || exit 65
    [[ "$3" == "v1.2.3" && "$5" == "--clobber" ]] || exit 66
    [[ -f "$4" && "$(basename "$4")" == "guri-launcher-v1.2.3.apk" ]] || exit 67
    [[ "$(<"$FAKE_RELEASE_STATE_FILE")" == draft ]] || exit 68
    printf 'guri-launcher-v1.2.3.apk\n' >"$FAKE_RELEASE_ASSET_FILE"
    ;;
  "release edit")
    [[ "$#" -eq 4 ]] || exit 69
    [[ "$3" == "v1.2.3" && "$4" == "--draft=false" ]] || exit 70
    [[ "$(<"$FAKE_RELEASE_STATE_FILE")" == draft ]] || exit 71
    printf 'published\n' >"$FAKE_RELEASE_STATE_FILE"
    ;;
  "release create")
    [[ "$#" -eq 8 ]] || exit 72
    [[ "$3" == "v1.2.3" ]] || exit 73
    [[ -f "$4" && "$(basename "$4")" == "guri-launcher-v1.2.3.apk" ]] || exit 74
    [[ "$5" == "--generate-notes" && "$6" == "--verify-tag" ]] || exit 75
    [[ "$7" == "--title" && "$8" == "v1.2.3" ]] || exit 76
    [[ "$(<"$FAKE_RELEASE_STATE_FILE")" == missing ]] || exit 78
    if [[ "${FAKE_CREATE_FAILURE:-false}" == true ]]; then
      printf 'draft\n' >"$FAKE_RELEASE_STATE_FILE"
      exit 79
    fi
    printf 'guri-launcher-v1.2.3.apk\n' >"$FAKE_RELEASE_ASSET_FILE"
    printf 'published\n' >"$FAKE_RELEASE_STATE_FILE"
    ;;
  "api repos/o-kaisan/guri-launcher/commits/v1.2.3")
    [[ "$#" -eq 4 ]] || exit 80
    [[ "$3" == "--jq" && "$4" == ".sha" ]] || exit 81
    printf '%s\n' "$FAKE_CURRENT_TAG_COMMIT"
    ;;
  *) exit 82 ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/gh"

readonly APK_PATH="$TEST_ROOT/dist/guri-launcher-v1.2.3.apk"
readonly EXPECTED_COMMIT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
: >"$APK_PATH"
readonly FAKE_GH_LOG="$TEST_ROOT/gh.log"
readonly FAKE_RELEASE_STATE_FILE="$TEST_ROOT/release-state"
readonly FAKE_RELEASE_ASSET_FILE="$TEST_ROOT/release-asset"
export FAKE_GH_LOG FAKE_RELEASE_STATE_FILE FAKE_RELEASE_ASSET_FILE

run_publish() {
  PATH="$TEST_ROOT/bin:$PATH" \
    FAKE_CURRENT_TAG_COMMIT="${CURRENT_TAG_COMMIT:-$EXPECTED_COMMIT}" \
    GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
    "$SCRIPT" v1.2.3 "$EXPECTED_COMMIT" "$APK_PATH"
}

[[ -x "$SCRIPT" ]] || fail "$SCRIPT is missing or is not executable"

# A new tag creates and publishes one release with the signed APK.
: >"$FAKE_GH_LOG"
printf 'missing\n' >"$FAKE_RELEASE_STATE_FILE"
run_publish >/dev/null
[[ "$(<"$FAKE_RELEASE_STATE_FILE")" == published ]] \
  || fail "new release was not published"
[[ "$(command_count "release create v1.2.3 $APK_PATH --generate-notes --verify-tag --title v1.2.3")" -eq 1 ]] \
  || fail "new release was not created with the expected arguments"

# A failed create can leave a draft; the next run must upload and publish it.
: >"$FAKE_GH_LOG"
rm -f -- "$FAKE_RELEASE_ASSET_FILE"
printf 'missing\n' >"$FAKE_RELEASE_STATE_FILE"
set +e
FAKE_CREATE_FAILURE=true run_publish >/dev/null 2>&1
failed_create_status=$?
set -e
[[ "$failed_create_status" -ne 0 ]] || fail "simulated release failure succeeded"
[[ "$(<"$FAKE_RELEASE_STATE_FILE")" == draft ]] \
  || fail "simulated release failure did not leave a recoverable draft"

run_publish >/dev/null
[[ "$(<"$FAKE_RELEASE_STATE_FILE")" == published ]] \
  || fail "existing draft was not published on retry"
[[ "$(command_count "release upload v1.2.3 $APK_PATH --clobber")" -eq 1 ]] \
  || fail "draft recovery did not replace the APK asset"
[[ "$(command_count "release edit v1.2.3 --draft=false")" -eq 1 ]] \
  || fail "draft recovery did not publish the release"
[[ "$(command_count "release create v1.2.3 $APK_PATH --generate-notes --verify-tag --title v1.2.3")" -eq 1 ]] \
  || fail "draft recovery tried to create a second release"

# A moved tag must stop draft recovery before the draft or asset is changed.
: >"$FAKE_GH_LOG"
rm -f -- "$FAKE_RELEASE_ASSET_FILE"
printf 'draft\n' >"$FAKE_RELEASE_STATE_FILE"
set +e
CURRENT_TAG_COMMIT="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" \
  run_publish >/dev/null 2>&1
moved_tag_status=$?
set -e
[[ "$moved_tag_status" -eq 2 ]] \
  || fail "moved tag did not stop draft recovery"
[[ "$(<"$FAKE_RELEASE_STATE_FILE")" == draft ]] \
  || fail "moved tag changed the draft release"
[[ "$(command_count "release upload v1.2.3 $APK_PATH --clobber")" -eq 0 ]] \
  || fail "moved tag replaced the draft APK"
[[ "$(command_count "release edit v1.2.3 --draft=false")" -eq 0 ]] \
  || fail "moved tag published the draft release"

# A rerun after successful publication is idempotent when the APK is present.
: >"$FAKE_GH_LOG"
printf 'guri-launcher-v1.2.3.apk\n' >"$FAKE_RELEASE_ASSET_FILE"
printf 'published\n' >"$FAKE_RELEASE_STATE_FILE"
run_publish >/dev/null
[[ "$(command_count "release upload v1.2.3 $APK_PATH --clobber")" -eq 0 ]] \
  || fail "published release was modified on rerun"
[[ "$(command_count "release create v1.2.3 $APK_PATH --generate-notes --verify-tag --title v1.2.3")" -eq 0 ]] \
  || fail "published release was recreated on rerun"

# A published release without the expected APK must fail instead of being hidden.
: >"$FAKE_GH_LOG"
rm -f -- "$FAKE_RELEASE_ASSET_FILE"
set +e
missing_asset_output="$(run_publish 2>&1)"
missing_asset_status=$?
set -e
[[ "$missing_asset_status" -eq 2 ]] \
  || fail "published release without its APK returned status $missing_asset_status"
[[ "$missing_asset_output" == *"does not contain the expected APK"* ]] \
  || fail "published release without its APK did not explain the conflict"

printf 'Release publication checks passed.\n'
