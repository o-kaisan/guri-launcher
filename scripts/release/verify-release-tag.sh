#!/usr/bin/env bash
set -euo pipefail

if (($# != 2)); then
  echo "usage: $0 <vX.Y.Z> <expected-commit-sha>" >&2
  exit 2
fi

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TAG="$1"
readonly EXPECTED_COMMIT_SHA="$2"
readonly REPOSITORY="${GITHUB_REPOSITORY:-}"

"$SCRIPT_DIRECTORY/release-metadata.sh" "$TAG" >/dev/null
if [[ ! "$EXPECTED_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: expected commit SHA must contain exactly 40 lowercase hexadecimal characters." >&2
  exit 2
fi
if [[ ! "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "error: GITHUB_REPOSITORY must use the owner/repository form." >&2
  exit 2
fi
command -v gh >/dev/null 2>&1 \
  || { echo "error: required command not found: gh" >&2; exit 1; }

if ! current_commit_sha="$(
  gh api "repos/$REPOSITORY/commits/$TAG" --jq .sha
)"; then
  echo "error: could not resolve the current release tag from GitHub." >&2
  exit 1
fi
if [[ ! "$current_commit_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: GitHub returned an invalid commit SHA for release tag $TAG." >&2
  exit 1
fi
if [[ "$current_commit_sha" != "$EXPECTED_COMMIT_SHA" ]]; then
  echo "error: release tag moved after this workflow started; refusing to publish a stale APK." >&2
  exit 2
fi

printf 'Release tag %s still points to %s.\n' "$TAG" "$EXPECTED_COMMIT_SHA"
