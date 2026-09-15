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

/bin/bash "${TMP_DIR}/Scripts/verify-entitlements.sh"

# NEGATIVE CONTROLS for capabilities that must stay OFF: a widget must never gain HealthKit, and
# hardened-process keys stay staged until provisioning supports them (AGENTS.md).
WIDGET_FILE="${TMP_DIR}/AIPedometerWidgets/Resources/AIPedometerWidgets.entitlements"
cp "${WIDGET_FILE}" "${TMP_DIR}/widget.backup"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.healthkit bool true" "${WIDGET_FILE}"
if /bin/bash "${TMP_DIR}/Scripts/verify-entitlements.sh" >/dev/null 2>&1; then
  echo "Expected HealthKit in the widget entitlements to fail validation." >&2
  exit 1
fi
cp "${TMP_DIR}/widget.backup" "${WIDGET_FILE}"

APP_FILE="${TMP_DIR}/AIPedometer/Resources/AIPedometer.entitlements"
cp "${APP_FILE}" "${TMP_DIR}/app.backup"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.hardened-process bool true" "${APP_FILE}"
if /bin/bash "${TMP_DIR}/Scripts/verify-entitlements.sh" >/dev/null 2>&1; then
  echo "Expected ungated hardened-process entitlements to fail validation." >&2
  exit 1
fi
ENHANCED_SECURITY_ENTITLEMENTS=1 /bin/bash "${TMP_DIR}/Scripts/verify-entitlements.sh" >/dev/null \
  || { echo "Expected the explicit opt-in to accept hardened-process entitlements." >&2; exit 1; }
cp "${TMP_DIR}/app.backup" "${APP_FILE}"
/bin/bash "${TMP_DIR}/Scripts/verify-entitlements.sh" >/dev/null

printf '%s\n' 'not a plist' \
  > "${TMP_DIR}/AIPedometerWatch/Resources/AIPedometerWatch.entitlements"

if /bin/bash "${TMP_DIR}/Scripts/verify-entitlements.sh"; then
  echo "Expected malformed watch entitlements to fail validation." >&2
  exit 1
fi

echo "verify-entitlements.sh tests passed."
