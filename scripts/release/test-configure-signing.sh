#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SCRIPT="$REPOSITORY_ROOT/scripts/release/configure-signing.sh"
readonly TEST_ROOT="$(mktemp -d)"
readonly INSIDE_REPOSITORY_ROOT="$(mktemp -d "$REPOSITORY_ROOT/.release-signing-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT" "$INSIDE_REPOSITORY_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

permission_bits() {
  LC_ALL=C ls -ld "$1" | awk '{print substr($1, 1, 10)}'
}

decode_base64() {
  local input_path="$1"
  local output_path="$2"

  if base64 --decode <"$input_path" >"$output_path" 2>/dev/null; then
    return
  fi
  base64 -D <"$input_path" >"$output_path"
}

[[ -x "$SCRIPT" ]] || fail "$SCRIPT is missing or is not executable"

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/secrets" "$TEST_ROOT/config"
readonly CONFIG_DIRECTORY_MODE="$(permission_bits "$TEST_ROOT/config")"
cat >"$TEST_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-} ${2:-}" in
  "variable list")
    [[ "$#" -eq 8 ]] || exit 60
    [[ "$3" == "--repo" && "$4" == "$FAKE_EXPECTED_REPOSITORY" ]] || exit 61
    [[ "$5" == "--json" && "$6" == "name,value" ]] || exit 62
    [[ "$7" == "--jq" ]] || exit 63
    [[ "$8" == '.[] | select(.name == "ANDROID_RELEASE_CERT_SHA256") | [.name, .value] | @tsv' ]] \
      || exit 64
    [[ "${FAKE_VARIABLE_LIST_FAILURE:-false}" != true ]] || exit 65
    readonly variable_path="${FAKE_SECRET_DIRECTORY}.variables/ANDROID_RELEASE_CERT_SHA256"
    if [[ -f "$variable_path" ]]; then
      printf 'ANDROID_RELEASE_CERT_SHA256\t'
      cat "$variable_path"
      printf '\n'
    fi
    ;;
  "variable set")
    [[ "$#" -eq 5 ]] || exit 60
    [[ "$4" == "--repo" && "$5" == "$FAKE_EXPECTED_REPOSITORY" ]] || exit 61
    mkdir -p "${FAKE_SECRET_DIRECTORY}.variables"
    cat >"${FAKE_SECRET_DIRECTORY}.variables/$3"
    ;;
  "secret list")
    [[ "$#" -eq 8 ]] || exit 64
    [[ "$3" == "--repo" && "$4" == "$FAKE_EXPECTED_REPOSITORY" ]] || exit 65
    [[ "$5" == "--json" && "$6" == "name" ]] || exit 66
    [[ "$7" == "--jq" && "$8" == ".[].name" ]] || exit 67
    for secret_path in "$FAKE_SECRET_DIRECTORY"/*; do
      [[ -f "$secret_path" ]] || continue
      basename "$secret_path"
    done | sort
    ;;
  "secret set")
    [[ "$#" -eq 5 ]] || exit 64
    readonly secret_name="$3"
    [[ "$4" == "--repo" && "$5" == "$FAKE_EXPECTED_REPOSITORY" ]] || exit 65
    cat >"$FAKE_SECRET_DIRECTORY/$secret_name"
    ;;
  *)
    exit 68
    ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/gh"

cat >"$TEST_ROOT/bin/realpath" <<'EOF'
#!/usr/bin/env bash
echo "GNU realpath must not be required" >&2
exit 99
EOF
chmod +x "$TEST_ROOT/bin/realpath"

readonly KEYSTORE_PATH="$TEST_ROOT/config/release.keystore"
readonly PASSWORD='correct horse battery staple'
readonly PASSWORD_FILE="$TEST_ROOT/password"
printf '%s' "$PASSWORD" >"$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

output="$(
  printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/secrets" \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$KEYSTORE_PATH" \
      "$SCRIPT"
)"

[[ -f "$KEYSTORE_PATH" ]] || fail "release keystore was not created"
[[ "$(permission_bits "$TEST_ROOT/config")" == "$CONFIG_DIRECTORY_MODE" ]] \
  || fail "setup changed permissions of the existing keystore directory"
[[ "$(permission_bits "$KEYSTORE_PATH")" == "-rw-------" ]] \
  || fail "release keystore permissions are not owner-only"
keytool -list -keystore "$KEYSTORE_PATH" -storepass:file "$PASSWORD_FILE" \
  -alias guri-launcher >/dev/null \
  || fail "generated keystore does not contain the release alias"

decode_base64 "$TEST_ROOT/secrets/ANDROID_RELEASE_KEYSTORE_BASE64" \
  "$TEST_ROOT/uploaded.keystore"
cmp -s "$KEYSTORE_PATH" "$TEST_ROOT/uploaded.keystore" \
  || fail "uploaded keystore secret differs from the generated keystore"
[[ "$(<"$TEST_ROOT/secrets/ANDROID_RELEASE_KEYSTORE_PASSWORD")" == "$PASSWORD" ]] \
  || fail "keystore password secret differs from the entered password"
[[ "$(<"$TEST_ROOT/secrets/ANDROID_RELEASE_KEY_PASSWORD")" == "$PASSWORD" ]] \
  || fail "key password secret differs from the entered password"
[[ "$(<"$TEST_ROOT/secrets/ANDROID_RELEASE_KEY_ALIAS")" == "guri-launcher" ]] \
  || fail "key alias secret is incorrect"
[[ "$output" != *"$PASSWORD"* ]] || fail "password was written to output"
[[ "$output" == *"Back up the keystore"* ]] \
  || fail "successful setup did not explain that the keystore needs a backup"
[[ -f "$TEST_ROOT/secrets.variables/ANDROID_RELEASE_CERT_SHA256" ]] \
  || fail "setup did not persist the release certificate fingerprint"
[[ "$(<"$TEST_ROOT/secrets.variables/ANDROID_RELEASE_CERT_SHA256")" \
  =~ ^[0-9A-F]{64}$ ]] \
  || fail "persisted release certificate fingerprint is invalid"

# Fingerprint lookup failures must stop before any signing material changes.
mkdir -p "$TEST_ROOT/fingerprint-lookup-secrets" "$TEST_ROOT/fingerprint-lookup-config"
set +e
fingerprint_lookup_output="$(
  PATH="$TEST_ROOT/bin:$PATH" \
    FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
    FAKE_SECRET_DIRECTORY="$TEST_ROOT/fingerprint-lookup-secrets" \
    FAKE_VARIABLE_LIST_FAILURE=true \
    GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
    GURI_RELEASE_KEYSTORE_PATH="$TEST_ROOT/fingerprint-lookup-config/release.keystore" \
    "$SCRIPT" 2>&1
)"
fingerprint_lookup_status=$?
set -e

[[ "$fingerprint_lookup_status" -eq 1 ]] \
  || fail "fingerprint lookup failure returned status $fingerprint_lookup_status"
[[ "$fingerprint_lookup_output" == *"could not inspect"* ]] \
  || fail "fingerprint lookup failure did not explain why setup stopped"
[[ ! -e "$TEST_ROOT/fingerprint-lookup-config/release.keystore" ]] \
  || fail "fingerprint lookup failure generated a keystore"
[[ -z "$(find "$TEST_ROOT/fingerprint-lookup-secrets" -type f -print -quit)" ]] \
  || fail "fingerprint lookup failure uploaded signing secrets"

# An existing but different keystore must not replace the configured signer.
mkdir -p "$TEST_ROOT/wrong-key-secrets" "$TEST_ROOT/wrong-key-config"
cp "$TEST_ROOT/secrets/"* "$TEST_ROOT/wrong-key-secrets/"
mkdir -p "$TEST_ROOT/wrong-key-secrets.variables"
cp "$TEST_ROOT/secrets.variables/"* "$TEST_ROOT/wrong-key-secrets.variables/"
readonly WRONG_KEYSTORE_PATH="$TEST_ROOT/wrong-key-config/release.keystore"
keytool -genkeypair -noprompt \
  -alias guri-launcher \
  -keyalg RSA \
  -keysize 2048 \
  -validity 1 \
  -dname "CN=different signer" \
  -keystore "$WRONG_KEYSTORE_PATH" \
  -storetype PKCS12 \
  -storepass:file "$PASSWORD_FILE" \
  -keypass:file "$PASSWORD_FILE" >/dev/null
readonly ORIGINAL_SECRET_BEFORE_WRONG_KEY="$TEST_ROOT/original-before-wrong-key"
cp "$TEST_ROOT/wrong-key-secrets/ANDROID_RELEASE_KEYSTORE_BASE64" \
  "$ORIGINAL_SECRET_BEFORE_WRONG_KEY"
set +e
wrong_key_output="$(
  printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/wrong-key-secrets" \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$WRONG_KEYSTORE_PATH" \
      "$SCRIPT" 2>&1
)"
wrong_key_status=$?
set -e

[[ "$wrong_key_status" -eq 2 ]] \
  || fail "existing wrong keystore replaced the configured signer"
[[ "$wrong_key_output" == *"certificate fingerprint does not match"* ]] \
  || fail "existing wrong keystore did not explain the signer mismatch"
cmp -s "$TEST_ROOT/wrong-key-secrets/ANDROID_RELEASE_KEYSTORE_BASE64" \
  "$ORIGINAL_SECRET_BEFORE_WRONG_KEY" \
  || fail "existing wrong keystore overwrote the configured signer"

# The persisted fingerprint remains authoritative if all signing secrets are absent.
mkdir -p \
  "$TEST_ROOT/fingerprint-only-missing-secrets" \
  "$TEST_ROOT/fingerprint-only-missing-config" \
  "$TEST_ROOT/fingerprint-only-missing-secrets.variables"
cp "$TEST_ROOT/secrets.variables/ANDROID_RELEASE_CERT_SHA256" \
  "$TEST_ROOT/fingerprint-only-missing-secrets.variables/ANDROID_RELEASE_CERT_SHA256"
readonly FINGERPRINT_ONLY_MISSING_COPY="$TEST_ROOT/fingerprint-only-missing-copy"
cp "$TEST_ROOT/fingerprint-only-missing-secrets.variables/ANDROID_RELEASE_CERT_SHA256" \
  "$FINGERPRINT_ONLY_MISSING_COPY"
set +e
fingerprint_only_missing_output="$(
  printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/fingerprint-only-missing-secrets" \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$TEST_ROOT/fingerprint-only-missing-config/release.keystore" \
      "$SCRIPT" 2>&1
)"
fingerprint_only_missing_status=$?
set -e

[[ "$fingerprint_only_missing_status" -eq 2 ]] \
  || fail "persisted fingerprint did not guard a missing local keystore"
[[ "$fingerprint_only_missing_output" == *"fingerprint already exists"* ]] \
  || fail "fingerprint-only guard did not explain the signer conflict"
[[ ! -e "$TEST_ROOT/fingerprint-only-missing-config/release.keystore" ]] \
  || fail "fingerprint-only guard generated a replacement keystore"
[[ -z "$(find "$TEST_ROOT/fingerprint-only-missing-secrets" -type f -print -quit)" ]] \
  || fail "fingerprint-only guard uploaded replacement signing secrets"
cmp -s \
  "$TEST_ROOT/fingerprint-only-missing-secrets.variables/ANDROID_RELEASE_CERT_SHA256" \
  "$FINGERPRINT_ONLY_MISSING_COPY" \
  || fail "fingerprint-only guard replaced the persisted signer identity"

mkdir -p \
  "$TEST_ROOT/fingerprint-only-wrong-secrets" \
  "$TEST_ROOT/fingerprint-only-wrong-secrets.variables"
cp "$TEST_ROOT/secrets.variables/ANDROID_RELEASE_CERT_SHA256" \
  "$TEST_ROOT/fingerprint-only-wrong-secrets.variables/ANDROID_RELEASE_CERT_SHA256"
set +e
fingerprint_only_wrong_output="$(
  printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/fingerprint-only-wrong-secrets" \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$WRONG_KEYSTORE_PATH" \
      "$SCRIPT" 2>&1
)"
fingerprint_only_wrong_status=$?
set -e

[[ "$fingerprint_only_wrong_status" -eq 2 ]] \
  || fail "persisted fingerprint accepted a different existing keystore"
[[ "$fingerprint_only_wrong_output" == *"certificate fingerprint does not match"* ]] \
  || fail "fingerprint-only mismatch did not explain the signer conflict"
[[ -z "$(find "$TEST_ROOT/fingerprint-only-wrong-secrets" -type f -print -quit)" ]] \
  || fail "fingerprint-only mismatch uploaded replacement signing secrets"

mkdir -p \
  "$TEST_ROOT/fingerprint-only-recovery-secrets" \
  "$TEST_ROOT/fingerprint-only-recovery-secrets.variables"
cp "$TEST_ROOT/secrets.variables/ANDROID_RELEASE_CERT_SHA256" \
  "$TEST_ROOT/fingerprint-only-recovery-secrets.variables/ANDROID_RELEASE_CERT_SHA256"
set +e
fingerprint_only_recovery_output="$(
  printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/fingerprint-only-recovery-secrets" \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$KEYSTORE_PATH" \
      "$SCRIPT" 2>&1
)"
fingerprint_only_recovery_status=$?
set -e

[[ "$fingerprint_only_recovery_status" -eq 0 ]] \
  || fail "matching fingerprint could not restore deleted signing secrets: $fingerprint_only_recovery_output"
decode_base64 \
  "$TEST_ROOT/fingerprint-only-recovery-secrets/ANDROID_RELEASE_KEYSTORE_BASE64" \
  "$TEST_ROOT/fingerprint-only-recovery-upload.keystore"
cmp -s "$KEYSTORE_PATH" "$TEST_ROOT/fingerprint-only-recovery-upload.keystore" \
  || fail "fingerprint-only recovery uploaded a different signing key"

# Missing local key material must not silently replace already-configured secrets.
mkdir -p "$TEST_ROOT/rotation-guard-secrets" "$TEST_ROOT/rotation-guard-config"
cp "$TEST_ROOT/secrets/"* "$TEST_ROOT/rotation-guard-secrets/"
mkdir -p "$TEST_ROOT/rotation-guard-secrets.variables"
cp "$TEST_ROOT/secrets.variables/"* "$TEST_ROOT/rotation-guard-secrets.variables/"
readonly GUARDED_SECRET_COPY="$TEST_ROOT/original-guarded-secret"
cp "$TEST_ROOT/rotation-guard-secrets/ANDROID_RELEASE_KEYSTORE_BASE64" \
  "$GUARDED_SECRET_COPY"
set +e
rotation_guard_output="$(
  printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/rotation-guard-secrets" \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$TEST_ROOT/rotation-guard-config/release.keystore" \
      "$SCRIPT" 2>&1
)"
rotation_guard_status=$?
set -e

[[ "$rotation_guard_status" -eq 2 ]] \
  || fail "missing local key replaced existing signing secrets"
[[ "$rotation_guard_output" == *"signing secrets already exist"* ]] \
  || fail "missing local key did not explain the existing signing-secret conflict"
[[ ! -e "$TEST_ROOT/rotation-guard-config/release.keystore" ]] \
  || fail "missing local key generated a replacement without confirmation"
cmp -s "$TEST_ROOT/rotation-guard-secrets/ANDROID_RELEASE_KEYSTORE_BASE64" \
  "$GUARDED_SECRET_COPY" \
  || fail "missing local key overwrote the configured keystore secret"

# Rotation needs both the explicit opt-in and an exact interactive confirmation.
mkdir -p "$TEST_ROOT/rotation-abort-secrets" "$TEST_ROOT/rotation-abort-config"
cp "$TEST_ROOT/secrets/"* "$TEST_ROOT/rotation-abort-secrets/"
mkdir -p "$TEST_ROOT/rotation-abort-secrets.variables"
cp "$TEST_ROOT/secrets.variables/"* "$TEST_ROOT/rotation-abort-secrets.variables/"
set +e
rotation_abort_output="$(
  printf '%s\n' 'DO NOT ROTATE' \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/rotation-abort-secrets" \
      GURI_ALLOW_RELEASE_KEY_ROTATION=true \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$TEST_ROOT/rotation-abort-config/release.keystore" \
      "$SCRIPT" 2>&1
)"
rotation_abort_status=$?
set -e

[[ "$rotation_abort_status" -eq 2 ]] \
  || fail "unconfirmed release-key rotation returned status $rotation_abort_status"
[[ "$rotation_abort_output" == *"rotation was not confirmed"* ]] \
  || fail "unconfirmed release-key rotation did not explain why it stopped"
[[ ! -e "$TEST_ROOT/rotation-abort-config/release.keystore" ]] \
  || fail "unconfirmed release-key rotation generated a keystore"

mkdir -p "$TEST_ROOT/rotation-confirm-secrets" "$TEST_ROOT/rotation-confirm-config"
cp "$TEST_ROOT/secrets/"* "$TEST_ROOT/rotation-confirm-secrets/"
mkdir -p "$TEST_ROOT/rotation-confirm-secrets.variables"
cp "$TEST_ROOT/secrets.variables/"* "$TEST_ROOT/rotation-confirm-secrets.variables/"
set +e
rotation_confirm_output="$(
  printf '%s\n%s\n%s\n' 'ROTATE RELEASE KEY' "$PASSWORD" "$PASSWORD" \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/rotation-confirm-secrets" \
      GURI_ALLOW_RELEASE_KEY_ROTATION=true \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$TEST_ROOT/rotation-confirm-config/release.keystore" \
      "$SCRIPT" 2>&1
)"
rotation_confirm_status=$?
set -e

[[ "$rotation_confirm_status" -eq 0 ]] \
  || fail "confirmed release-key rotation failed: $rotation_confirm_output"
[[ -f "$TEST_ROOT/rotation-confirm-config/release.keystore" ]] \
  || fail "confirmed release-key rotation did not generate a keystore"
decode_base64 "$TEST_ROOT/rotation-confirm-secrets/ANDROID_RELEASE_KEYSTORE_BASE64" \
  "$TEST_ROOT/rotated-upload.keystore"
cmp -s "$TEST_ROOT/rotation-confirm-config/release.keystore" \
  "$TEST_ROOT/rotated-upload.keystore" \
  || fail "confirmed release-key rotation did not upload the new keystore"
[[ "$rotation_confirm_output" == *"prevents updates to every existing installation"* ]] \
  || fail "confirmed release-key rotation did not print the compatibility warning"

# A mistyped confirmation must not create or upload signing material.
mkdir -p "$TEST_ROOT/mismatch-secrets" "$TEST_ROOT/mismatch-config"
set +e
mismatch_output="$(
  printf '%s\n%s\n' 'first secure password' 'different secure password' \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/mismatch-secrets" \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$TEST_ROOT/mismatch-config/release.keystore" \
      "$SCRIPT" 2>&1
)"
mismatch_status=$?
set -e

[[ "$mismatch_status" -eq 2 ]] \
  || fail "mismatched passwords returned status $mismatch_status instead of 2"
[[ "$mismatch_output" == *"passwords do not match"* ]] \
  || fail "mismatched passwords did not produce a clear error"
[[ ! -e "$TEST_ROOT/mismatch-config/release.keystore" ]] \
  || fail "mismatched passwords created a keystore"
[[ -z "$(find "$TEST_ROOT/mismatch-secrets" -type f -print -quit)" ]] \
  || fail "mismatched passwords uploaded a secret"
[[ "$mismatch_output" != *'first secure password'* ]] \
  || fail "mismatched password was written to output"

# Weak passwords must be rejected before any signing material is created.
mkdir -p "$TEST_ROOT/weak-secrets" "$TEST_ROOT/weak-config"
set +e
weak_output="$(
  printf '%s\n%s\n' '123456789012345' '123456789012345' \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/weak-secrets" \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$TEST_ROOT/weak-config/release.keystore" \
      "$SCRIPT" 2>&1
)"
weak_status=$?
set -e

[[ "$weak_status" -eq 2 ]] \
  || fail "weak password returned status $weak_status instead of 2"
[[ "$weak_output" == *"at least 16 characters"* ]] \
  || fail "weak password did not explain the minimum length"
[[ ! -e "$TEST_ROOT/weak-config/release.keystore" ]] \
  || fail "weak password created a keystore"
[[ -z "$(find "$TEST_ROOT/weak-secrets" -type f -print -quit)" ]] \
  || fail "weak password uploaded a secret"

# A private signing key must never be generated anywhere in the repository.
mkdir -p "$TEST_ROOT/inside-secrets"
set +e
inside_output="$(
  printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/inside-secrets" \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$INSIDE_REPOSITORY_ROOT/release.keystore" \
      "$SCRIPT" 2>&1
)"
inside_status=$?
set -e

[[ "$inside_status" -eq 2 ]] \
  || fail "repository-local keystore returned status $inside_status instead of 2"
[[ "$inside_output" == *"outside the repository"* ]] \
  || fail "repository-local keystore did not explain the safe location"
[[ ! -e "$INSIDE_REPOSITORY_ROOT/release.keystore" ]] \
  || fail "repository-local keystore was created"
[[ -z "$(find "$TEST_ROOT/inside-secrets" -type f -print -quit)" ]] \
  || fail "repository-local keystore was uploaded"

# Re-running setup must preserve the existing key while restoring its secrets.
readonly ORIGINAL_KEYSTORE_COPY="$TEST_ROOT/original-release.keystore"
cp "$KEYSTORE_PATH" "$ORIGINAL_KEYSTORE_COPY"
mkdir -p "$TEST_ROOT/reuse-secrets"
cp "$TEST_ROOT/secrets/"* "$TEST_ROOT/reuse-secrets/"
mkdir -p "$TEST_ROOT/reuse-secrets.variables"
cp "$TEST_ROOT/secrets.variables/"* "$TEST_ROOT/reuse-secrets.variables/"
set +e
reuse_output="$(
  printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
    | PATH="$TEST_ROOT/bin:$PATH" \
      FAKE_EXPECTED_REPOSITORY="o-kaisan/guri-launcher" \
      FAKE_SECRET_DIRECTORY="$TEST_ROOT/reuse-secrets" \
      GURI_GITHUB_REPOSITORY="o-kaisan/guri-launcher" \
      GURI_RELEASE_KEYSTORE_PATH="$KEYSTORE_PATH" \
      "$SCRIPT" 2>&1
)"
reuse_status=$?
set -e

[[ "$reuse_status" -eq 0 ]] \
  || fail "reusing the signing key failed with status $reuse_status: $reuse_output"
cmp -s "$KEYSTORE_PATH" "$ORIGINAL_KEYSTORE_COPY" \
  || fail "re-running setup replaced the existing signing key"
decode_base64 "$TEST_ROOT/reuse-secrets/ANDROID_RELEASE_KEYSTORE_BASE64" \
  "$TEST_ROOT/reused-upload.keystore"
cmp -s "$KEYSTORE_PATH" "$TEST_ROOT/reused-upload.keystore" \
  || fail "re-running setup uploaded a different signing key"
[[ "$reuse_output" == *"Using existing release keystore"* ]] \
  || fail "re-running setup did not explain that it preserved the existing key"

printf 'Release signing setup checks passed.\n'
