#!/usr/bin/env bash
set -euo pipefail

if (($# != 2)); then
  echo "usage: $0 <apk-path> <expected-certificate-sha256>" >&2
  exit 2
fi

readonly APK_PATH="$1"
expected_cert_sha256="$(
  printf '%s' "$2" \
    | tr -d ':[:space:]' \
    | tr '[:lower:]' '[:upper:]'
)"
if [[ ! "$expected_cert_sha256" =~ ^[0-9A-F]{64}$ ]]; then
  echo "error: expected certificate fingerprint must contain exactly 64 hexadecimal characters." >&2
  exit 2
fi
readonly EXPECTED_CERT_SHA256="$expected_cert_sha256"
if [[ ! -f "$APK_PATH" ]]; then
  printf 'error: APK not found: %s\n' "$APK_PATH" >&2
  exit 2
fi

readonly APKSIGNER_COMMAND="${APKSIGNER:-apksigner}"
if [[ "$APKSIGNER_COMMAND" == */* ]]; then
  if [[ ! -x "$APKSIGNER_COMMAND" ]]; then
    printf 'error: apksigner is not executable: %s\n' "$APKSIGNER_COMMAND" >&2
    exit 1
  fi
elif ! command -v "$APKSIGNER_COMMAND" >/dev/null 2>&1; then
  echo "error: required command not found: apksigner" >&2
  exit 1
fi

if ! signer_output="$(
  "$APKSIGNER_COMMAND" verify --verbose --print-certs "$APK_PATH" 2>&1
)"; then
  echo "error: APK signature verification failed." >&2
  exit 1
fi

signer_count=0
readonly SIGNER_DIGEST_PATTERN='^Signer (#[0-9]+|\(.*\)) certificate SHA-256 digest:[[:space:]]*([0-9A-Fa-f:]+)[[:space:]]*$'
while IFS= read -r signer_line; do
  if [[ "$signer_line" =~ $SIGNER_DIGEST_PATTERN ]]; then
    ((signer_count += 1))
    actual_cert_sha256="$(
      printf '%s' "${BASH_REMATCH[2]}" \
        | tr -d ':' \
        | tr '[:lower:]' '[:upper:]'
    )"
    if [[ "$actual_cert_sha256" != "$EXPECTED_CERT_SHA256" ]]; then
      echo "error: APK certificate fingerprint does not match the configured release signer." >&2
      exit 2
    fi
  fi
done <<<"$signer_output"

if ((signer_count == 0)); then
  echo "error: apksigner did not report an APK signer certificate SHA-256 digest." >&2
  exit 1
fi
printf 'All APK signer certificate SHA-256 digests match the configured release signer: %s\n' \
  "$EXPECTED_CERT_SHA256"
