#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
readonly GITHUB_REPOSITORY="${GURI_GITHUB_REPOSITORY:-o-kaisan/guri-launcher}"
readonly KEY_ALIAS="guri-launcher"
readonly CERT_FINGERPRINT_VARIABLE="ANDROID_RELEASE_CERT_SHA256"
readonly ALLOW_KEY_ROTATION="${GURI_ALLOW_RELEASE_KEY_ROTATION:-false}"
readonly CONFIG_DIRECTORY="${XDG_CONFIG_HOME:-${HOME:?HOME is required}/.config}/guri-launcher"
readonly KEYSTORE_PATH_INPUT="${GURI_RELEASE_KEYSTORE_PATH:-$CONFIG_DIRECTORY/release.keystore}"
readonly -a SIGNING_SECRET_NAMES=(
  ANDROID_RELEASE_KEYSTORE_BASE64
  ANDROID_RELEASE_KEYSTORE_PASSWORD
  ANDROID_RELEASE_KEY_ALIAS
  ANDROID_RELEASE_KEY_PASSWORD
)

case "$ALLOW_KEY_ROTATION" in
  true | false) ;;
  *)
    echo "error: GURI_ALLOW_RELEASE_KEY_ROTATION must be 'true' or 'false'." >&2
    exit 2
    ;;
esac

for command_name in keytool gh base64 tr; do
  command -v "$command_name" >/dev/null 2>&1 \
    || { echo "error: required command not found: $command_name" >&2; exit 1; }
done

case "$KEYSTORE_PATH_INPUT" in
  /*) readonly KEYSTORE_PATH_OPERAND="$KEYSTORE_PATH_INPUT" ;;
  *) readonly KEYSTORE_PATH_OPERAND="./$KEYSTORE_PATH_INPUT" ;;
esac
readonly KEYSTORE_DIRECTORY_INPUT="$(dirname "$KEYSTORE_PATH_OPERAND")"
readonly KEYSTORE_FILENAME="$(basename "$KEYSTORE_PATH_OPERAND")"
if [[ "$KEYSTORE_FILENAME" == "." || "$KEYSTORE_FILENAME" == ".." ]]; then
  echo "error: the release keystore path must include a file name." >&2
  exit 2
fi
mkdir -p "$KEYSTORE_DIRECTORY_INPUT"
if ! resolved_keystore_directory="$(cd "$KEYSTORE_DIRECTORY_INPUT" && pwd -P)"; then
  echo "error: could not resolve the release keystore directory." >&2
  exit 2
fi
readonly KEYSTORE_PATH="$resolved_keystore_directory/$KEYSTORE_FILENAME"
case "$KEYSTORE_PATH" in
  "$REPOSITORY_ROOT" | "$REPOSITORY_ROOT"/*)
    echo "error: the release keystore must be stored outside the repository." >&2
    exit 2
    ;;
esac
if [[ -L "$KEYSTORE_PATH" ]]; then
  echo "error: the release keystore path must not be a symbolic link." >&2
  exit 2
fi

rotation_confirmed=false
confirm_key_rotation() {
  local reason="$1"

  if [[ "$ALLOW_KEY_ROTATION" != true ]]; then
    printf 'error: %s\n' "$reason" >&2
    echo "Restore the original keystore or explicitly authorize an incompatible key rotation." >&2
    exit 2
  fi
  echo "warning: rotating the release key prevents updates to every existing installation." >&2
  printf 'Type ROTATE RELEASE KEY to continue: ' >&2
  if ! IFS= read -r rotation_confirmation \
    || [[ "$rotation_confirmation" != "ROTATE RELEASE KEY" ]]; then
    echo "error: release-key rotation was not confirmed." >&2
    exit 2
  fi
  rotation_confirmed=true
}

existing_secret_names="$(
  gh secret list --repo "$GITHUB_REPOSITORY" --json name --jq '.[].name'
)"
signing_secrets_exist=false
for signing_secret_name in "${SIGNING_SECRET_NAMES[@]}"; do
  while IFS= read -r existing_secret_name; do
    if [[ "$existing_secret_name" == "$signing_secret_name" ]]; then
      signing_secrets_exist=true
      break 2
    fi
  done <<<"$existing_secret_names"
done

keystore_existed=false
if [[ -e "$KEYSTORE_PATH" ]]; then
  keystore_existed=true
elif [[ "$signing_secrets_exist" == true ]]; then
  confirm_key_rotation \
    "signing secrets already exist, but the local release keystore is missing."
fi

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

if [[ "$keystore_existed" == true ]]; then
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

if ! keytool_details="$(
  LC_ALL=C keytool \
    -J-Duser.language=en \
    -J-Duser.country=US \
    -list -v \
    -alias "$KEY_ALIAS" \
    -keystore "$KEYSTORE_PATH" \
    -storepass:file "$PASSWORD_FILE" 2>/dev/null
)"; then
  echo "error: could not read the release certificate fingerprint." >&2
  exit 2
fi
release_cert_sha256=''
while IFS= read -r keytool_line; do
  if [[ "$keytool_line" =~ SHA256:[[:space:]]*([0-9A-Fa-f:]+) ]]; then
    release_cert_sha256="${BASH_REMATCH[1]}"
    break
  fi
done <<<"$keytool_details"
release_cert_sha256="$(
  printf '%s' "$release_cert_sha256" \
    | tr -d ':' \
    | tr '[:lower:]' '[:upper:]'
)"
if [[ ! "$release_cert_sha256" =~ ^[0-9A-F]{64}$ ]]; then
  echo "error: keytool did not return a valid SHA-256 certificate fingerprint." >&2
  exit 2
fi
readonly RELEASE_CERT_SHA256="$release_cert_sha256"

if [[ "$signing_secrets_exist" == true && "$rotation_confirmed" != true ]]; then
  configured_cert_sha256=''
  if configured_cert_sha256="$(
    gh variable get "$CERT_FINGERPRINT_VARIABLE" \
      --repo "$GITHUB_REPOSITORY" \
      --json value \
      --jq .value 2>/dev/null
  )"; then
    configured_cert_sha256="$(
      printf '%s' "$configured_cert_sha256" \
        | tr -d ':[:space:]' \
        | tr '[:lower:]' '[:upper:]'
    )"
  fi

  if [[ "$configured_cert_sha256" != "$RELEASE_CERT_SHA256" ]]; then
    if [[ -z "$configured_cert_sha256" ]]; then
      rotation_reason="signing secrets already exist, but their certificate fingerprint is unavailable."
    else
      rotation_reason="certificate fingerprint does not match the configured release signer."
    fi
    confirm_key_rotation "$rotation_reason"
  fi
fi

base64 <"$KEYSTORE_PATH" | tr -d '\n' \
  | gh secret set ANDROID_RELEASE_KEYSTORE_BASE64 --repo "$GITHUB_REPOSITORY"
printf '%s' "$key_password" \
  | gh secret set ANDROID_RELEASE_KEYSTORE_PASSWORD --repo "$GITHUB_REPOSITORY"
printf '%s' "$KEY_ALIAS" \
  | gh secret set ANDROID_RELEASE_KEY_ALIAS --repo "$GITHUB_REPOSITORY"
printf '%s' "$key_password" \
  | gh secret set ANDROID_RELEASE_KEY_PASSWORD --repo "$GITHUB_REPOSITORY"
printf '%s' "$RELEASE_CERT_SHA256" \
  | gh variable set "$CERT_FINGERPRINT_VARIABLE" --repo "$GITHUB_REPOSITORY"

key_password=''
key_password_confirmation=''

printf 'Signing secrets configured for %s.\n' "$GITHUB_REPOSITORY"
printf 'Release certificate SHA-256: %s\n' "$RELEASE_CERT_SHA256"
printf 'Back up the keystore at %s and its password; both are required for future updates.\n' \
  "$KEYSTORE_PATH"
