#!/usr/bin/env bash
set -euo pipefail

# Test Android Apps uses this repository environment bootstrap before invoking adb.
"$(git rev-parse --show-toplevel)/scripts/android/setup-sdk.sh"
