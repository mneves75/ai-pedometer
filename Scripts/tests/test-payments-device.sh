#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if ! AIPEDOMETER_TEST_PAYMENTS_VALIDATE_PATHS_ONLY=1 \
  IPA_DIR="build/ipa" \
  ARCHIVE_PATH="build/ipa/AIPedometer.xcarchive" \
  IPA_PATH="build/ipa/AIPedometer.ipa" \
  bash "${ROOT_DIR}/Scripts/test-payments-device.sh" >"${TMP_DIR}/valid.log"; then
  echo "Expected default TestFlight output paths to validate." >&2
  exit 1
fi

if ! rg -n "Path validation OK" "${TMP_DIR}/valid.log" >/dev/null; then
  echo "Expected path validation success marker." >&2
  exit 1
fi

if AIPEDOMETER_TEST_PAYMENTS_VALIDATE_PATHS_ONLY=1 \
  IPA_DIR="${TMP_DIR}/outside" \
  bash "${ROOT_DIR}/Scripts/test-payments-device.sh" >"${TMP_DIR}/outside.log" 2>&1; then
  echo "Expected absolute output path outside build/ipa to fail." >&2
  exit 1
fi

if AIPEDOMETER_TEST_PAYMENTS_VALIDATE_PATHS_ONLY=1 \
  IPA_DIR="build/ipa" \
  ARCHIVE_PATH="build/ipa/../AIPedometer.xcarchive" \
  bash "${ROOT_DIR}/Scripts/test-payments-device.sh" >"${TMP_DIR}/traversal.log" 2>&1; then
  echo "Expected traversal output path outside build/ipa to fail." >&2
  exit 1
fi

echo "test-payments-device.sh path validation tests passed."
