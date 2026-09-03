#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly GITHUB_REPOSITORY="${GURI_GITHUB_REPOSITORY:-o-kaisan/guri-launcher}"
readonly KEY_ALIAS="guri-launcher"
readonly CONFIG_DIRECTORY="${XDG_CONFIG_HOME:-${HOME:?HOME is required}/.config}/guri-launcher"
readonly KEYSTORE_PATH_INPUT="${GURI_RELEASE_KEYSTORE_PATH:-$CONFIG_DIRECTORY/release.keystore}"

for command_name in keytool gh base64 tr realpath; do
  command -v "$command_name" >/dev/null 2>&1 \
    || { echo "error: required command not found: $command_name" >&2; exit 1; }
done

readonly KEYSTORE_PATH="$(realpath -m -- "$KEYSTORE_PATH_INPUT")"
case "$KEYSTORE_PATH" in
  "$REPOSITORY_ROOT" | "$REPOSITORY_ROOT"/*)
    echo "error: the release keystore must be stored outside the repository." >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname "$KEYSTORE_PATH")"

printf 'Release-key password: ' >&2
IFS= read -r -s key_password
printf '\nConfirm password: ' >&2
IFS= read -r -s key_password_confirmation
printf '\n' >&2

if [[ "$key_password" != "$key_password_confirmation" ]]; then
  key_password=''
  key_password_confirmation=''
  echo "error: passwords do not match." >&2
  exit 2
fi
if ((${#key_password} < 16)); then
  key_password=''
  key_password_confirmation=''
  echo "error: password must contain at least 16 characters." >&2
  exit 2
fi

readonly PASSWORD_FILE="$(mktemp)"
cleanup() {
  rm -f -- "$PASSWORD_FILE"
}
trap cleanup EXIT
printf '%s' "$key_password" >"$PASSWORD_FILE"

if [[ -e "$KEYSTORE_PATH" ]]; then
  if ! keytool -list \
    -alias "$KEY_ALIAS" \
    -keystore "$KEYSTORE_PATH" \
    -storepass:file "$PASSWORD_FILE" >/dev/null 2>&1; then
    echo "error: the existing keystore, password, or alias is invalid." >&2
    exit 2
  fi
  printf 'Using existing release keystore at %s.\n' "$KEYSTORE_PATH"
else
  keytool -genkeypair \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 4096 \
    -sigalg SHA256withRSA \
    -validity 10000 \
    -dname "CN=guri-launcher, OU=Personal Distribution, O=o-kaisan, C=JP" \
    -keystore "$KEYSTORE_PATH" \
    -storetype PKCS12 \
    -storepass:file "$PASSWORD_FILE" \
    -keypass:file "$PASSWORD_FILE" >/dev/null
fi
chmod 600 "$KEYSTORE_PATH"

base64 <"$KEYSTORE_PATH" | tr -d '\n' \
  | gh secret set ANDROID_RELEASE_KEYSTORE_BASE64 --repo "$GITHUB_REPOSITORY"
printf '%s' "$key_password" \
  | gh secret set ANDROID_RELEASE_KEYSTORE_PASSWORD --repo "$GITHUB_REPOSITORY"
printf '%s' "$KEY_ALIAS" \
  | gh secret set ANDROID_RELEASE_KEY_ALIAS --repo "$GITHUB_REPOSITORY"
printf '%s' "$key_password" \
  | gh secret set ANDROID_RELEASE_KEY_PASSWORD --repo "$GITHUB_REPOSITORY"

key_password=''
key_password_confirmation=''

printf 'Signing secrets configured for %s.\n' "$GITHUB_REPOSITORY"
printf 'Back up the keystore at %s and its password; both are required for future updates.\n' \
  "$KEYSTORE_PATH"
