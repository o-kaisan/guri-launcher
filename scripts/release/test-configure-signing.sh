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

[[ -x "$SCRIPT" ]] || fail "$SCRIPT is missing or is not executable"

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/secrets" "$TEST_ROOT/config"
readonly CONFIG_DIRECTORY_MODE="$(stat -c '%a' "$TEST_ROOT/config")"
cat >"$TEST_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == "secret" && "${2:-}" == "set" && "$#" -eq 5 ]] || exit 64
readonly secret_name="$3"
[[ "$4" == "--repo" && "$5" == "$FAKE_EXPECTED_REPOSITORY" ]] || exit 65
cat >"$FAKE_SECRET_DIRECTORY/$secret_name"
EOF
chmod +x "$TEST_ROOT/bin/gh"

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
[[ "$(stat -c '%a' "$TEST_ROOT/config")" == "$CONFIG_DIRECTORY_MODE" ]] \
  || fail "setup changed permissions of the existing keystore directory"
[[ "$(stat -c '%a' "$KEYSTORE_PATH")" == "600" ]] \
  || fail "release keystore permissions are not owner-only"
keytool -list -keystore "$KEYSTORE_PATH" -storepass:file "$PASSWORD_FILE" \
  -alias guri-launcher >/dev/null \
  || fail "generated keystore does not contain the release alias"

base64 --decode "$TEST_ROOT/secrets/ANDROID_RELEASE_KEYSTORE_BASE64" \
  >"$TEST_ROOT/uploaded.keystore"
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
readonly ORIGINAL_KEYSTORE_DIGEST="$(sha256sum "$KEYSTORE_PATH" | awk '{print $1}')"
mkdir -p "$TEST_ROOT/reuse-secrets"
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
[[ "$(sha256sum "$KEYSTORE_PATH" | awk '{print $1}')" == "$ORIGINAL_KEYSTORE_DIGEST" ]] \
  || fail "re-running setup replaced the existing signing key"
base64 --decode "$TEST_ROOT/reuse-secrets/ANDROID_RELEASE_KEYSTORE_BASE64" \
  >"$TEST_ROOT/reused-upload.keystore"
cmp -s "$KEYSTORE_PATH" "$TEST_ROOT/reused-upload.keystore" \
  || fail "re-running setup uploaded a different signing key"
[[ "$reuse_output" == *"Using existing release keystore"* ]] \
  || fail "re-running setup did not explain that it preserved the existing key"

printf 'Release signing setup checks passed.\n'
