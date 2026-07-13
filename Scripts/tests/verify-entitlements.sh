#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p \
  "${TMP_DIR}/Scripts" \
  "${TMP_DIR}/AIPedometer/Resources" \
  "${TMP_DIR}/AIPedometerWatch/Resources" \
  "${TMP_DIR}/AIPedometerWidgets/Resources"

cp "${PROJECT_ROOT}/Scripts/verify-entitlements.sh" "${TMP_DIR}/Scripts/"
cp "${PROJECT_ROOT}/AIPedometer/Resources/AIPedometer.entitlements" \
  "${TMP_DIR}/AIPedometer/Resources/"
cp "${PROJECT_ROOT}/AIPedometerWatch/Resources/AIPedometerWatch.entitlements" \
  "${TMP_DIR}/AIPedometerWatch/Resources/"
cp "${PROJECT_ROOT}/AIPedometerWidgets/Resources/AIPedometerWidgets.entitlements" \
  "${TMP_DIR}/AIPedometerWidgets/Resources/"

bash "${TMP_DIR}/Scripts/verify-entitlements.sh"

printf '%s\n' 'not a plist' \
  > "${TMP_DIR}/AIPedometerWatch/Resources/AIPedometerWatch.entitlements"

if bash "${TMP_DIR}/Scripts/verify-entitlements.sh"; then
  echo "Expected malformed watch entitlements to fail validation." >&2
  exit 1
fi

echo "verify-entitlements.sh tests passed."
