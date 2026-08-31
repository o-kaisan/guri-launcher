#!/usr/bin/env bash
set -euo pipefail

# Test Android Apps uses this repository environment bootstrap before invoking adb.
make -C "$(git rev-parse --show-toplevel)" android-sdk
