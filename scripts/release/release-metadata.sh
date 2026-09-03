#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
  echo "usage: $0 <vX.Y.Z>" >&2
  exit 2
fi

readonly TAG="$1"
readonly TAG_PATTERN='^v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$'
readonly MAX_ANDROID_VERSION_CODE=2100000000

invalid_tag() {
  echo "error: invalid release tag '$TAG'; expected vX.Y.Z within Android versionCode limits." >&2
  exit 2
}

[[ "$TAG" =~ $TAG_PATTERN ]] || invalid_tag

readonly MAJOR="${BASH_REMATCH[1]}"
readonly MINOR="${BASH_REMATCH[2]}"
readonly PATCH="${BASH_REMATCH[3]}"
readonly VERSION_NAME="$MAJOR.$MINOR.$PATCH"
readonly VERSION_CODE=$((MAJOR * 1000000 + MINOR * 1000 + PATCH))

((VERSION_CODE > 0 && VERSION_CODE <= MAX_ANDROID_VERSION_CODE)) || invalid_tag

printf 'version_name=%s\n' "$VERSION_NAME"
printf 'version_code=%s\n' "$VERSION_CODE"
printf 'apk_name=guri-launcher-%s.apk\n' "$TAG"
