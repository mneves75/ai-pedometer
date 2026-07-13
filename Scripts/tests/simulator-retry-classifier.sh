#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

printf '%s\n' \
  'Failed to get background assertion for target app with pid 123: Timed out while acquiring background assertion.' \
  > "${TMP_DIR}/transient.log"

if ! bash "${ROOT_DIR}/Scripts/simulator-retry-classifier.sh" "${TMP_DIR}/transient.log"; then
  echo "Expected the background-assertion timeout to be classified as retryable." >&2
  exit 1
fi

printf '%s\n' \
  'XCTAssertEqual failed: ("1") is not equal to ("2")' \
  > "${TMP_DIR}/functional.log"

if bash "${ROOT_DIR}/Scripts/simulator-retry-classifier.sh" "${TMP_DIR}/functional.log"; then
  echo "Expected a functional assertion failure to remain non-retryable." >&2
  exit 1
fi

echo "simulator retry classifier tests passed."
