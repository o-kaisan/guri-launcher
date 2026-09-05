#!/usr/bin/env bash
set -euo pipefail

if (($# != 3)); then
  echo "usage: $0 <vX.Y.Z> <expected-commit-sha> <apk-path>" >&2
  exit 2
fi

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TAG="$1"
readonly EXPECTED_COMMIT_SHA="$2"
readonly APK_PATH="$3"

metadata="$("$SCRIPT_DIRECTORY/release-metadata.sh" "$TAG")"
expected_apk_name=''
while IFS='=' read -r metadata_name metadata_value; do
  if [[ "$metadata_name" == apk_name ]]; then
    expected_apk_name="$metadata_value"
    break
  fi
done <<<"$metadata"

if [[ -z "$expected_apk_name" ]]; then
  echo "error: release metadata did not include an APK name." >&2
  exit 1
fi
if [[ "$(basename "$APK_PATH")" != "$expected_apk_name" ]]; then
  printf 'error: APK name must be %s for release %s.\n' "$expected_apk_name" "$TAG" >&2
  exit 2
fi
if [[ ! -f "$APK_PATH" ]]; then
  printf 'error: release APK not found: %s\n' "$APK_PATH" >&2
  exit 2
fi
if [[ ! "$EXPECTED_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: expected commit SHA must contain exactly 40 lowercase hexadecimal characters." >&2
  exit 2
fi
command -v gh >/dev/null 2>&1 \
  || { echo "error: required command not found: gh" >&2; exit 1; }

verify_tag() {
  "$SCRIPT_DIRECTORY/verify-release-tag.sh" "$TAG" "$EXPECTED_COMMIT_SHA"
}

release_details=''
if release_details="$(
  gh release view "$TAG" \
    --json isDraft,assets \
    --jq '.isDraft, (.assets[]?.name)' 2>/dev/null
)"; then
  release_is_draft=''
  expected_asset_exists=false
  line_number=0
  while IFS= read -r release_line; do
    ((line_number += 1))
    if ((line_number == 1)); then
      release_is_draft="$release_line"
    elif [[ "$release_line" == "$expected_apk_name" ]]; then
      expected_asset_exists=true
    fi
  done <<<"$release_details"

  case "$release_is_draft" in
    true)
      verify_tag
      gh release upload "$TAG" "$APK_PATH" --clobber
      verify_tag
      gh release edit "$TAG" --draft=false
      printf 'Recovered and published draft release %s.\n' "$TAG"
      ;;
    false)
      if [[ "$expected_asset_exists" != true ]]; then
        printf 'error: published release %s does not contain the expected APK %s.\n' \
          "$TAG" "$expected_apk_name" >&2
        exit 2
      fi
      printf 'Release %s is already published with %s.\n' "$TAG" "$expected_apk_name"
      ;;
    *)
      echo "error: GitHub returned an invalid release draft state." >&2
      exit 1
      ;;
  esac
  exit 0
fi

verify_tag
gh release create "$TAG" --draft \
  --generate-notes --verify-tag --title "$TAG"
verify_tag
gh release upload "$TAG" "$APK_PATH" --clobber
verify_tag
gh release edit "$TAG" --draft=false
