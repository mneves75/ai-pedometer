#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p \
  "$TMP_ROOT/Scripts" \
  "$TMP_ROOT/AIPedometer/Resources" \
  "$TMP_ROOT/AIPedometerWatch/Resources" \
  "$TMP_ROOT/AIPedometerWidgets/Resources" \
  "$TMP_ROOT/AIPedometer.xcodeproj"
cp "$ROOT_DIR/Scripts/restore-entitlements.sh" "$TMP_ROOT/Scripts/restore-entitlements.sh"

run_restore() {
  perl -e 'alarm 10; exec @ARGV' /bin/bash "$TMP_ROOT/Scripts/restore-entitlements.sh"
}

run_restore
run_restore

APP_ENTITLEMENTS="$TMP_ROOT/AIPedometer/Resources/AIPedometer.entitlements"
WATCH_ENTITLEMENTS="$TMP_ROOT/AIPedometerWatch/Resources/AIPedometerWatch.entitlements"
WIDGET_ENTITLEMENTS="$TMP_ROOT/AIPedometerWidgets/Resources/AIPedometerWidgets.entitlements"
WORKSPACE_SETTINGS="$TMP_ROOT/AIPedometer.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.healthkit' "$APP_ENTITLEMENTS")" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$APP_ENTITLEMENTS")" == "group.com.mneves.aipedometer" ]]

if /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.healthkit' "$WATCH_ENTITLEMENTS" >/dev/null 2>&1; then
  echo "watch entitlement unexpectedly contains HealthKit" >&2
  exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$WATCH_ENTITLEMENTS" >/dev/null 2>&1; then
  echo "watch entitlement unexpectedly contains an app group" >&2
  exit 1
fi

[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$WIDGET_ENTITLEMENTS")" == "group.com.mneves.aipedometer" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :iOSPackagesShouldBuildARM64e' "$WORKSPACE_SETTINGS")" == "true" ]]

if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.hardened-process' "$APP_ENTITLEMENTS" >/dev/null 2>&1; then
  echo "default restore unexpectedly enabled Enhanced Security entitlements" >&2
  exit 1
fi

ENHANCED_SECURITY_ENTITLEMENTS=1 run_restore
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.hardened-process' "$APP_ENTITLEMENTS")" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.hardened-process.hardened-heap' "$APP_ENTITLEMENTS")" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.hardened-process.dyld-ro' "$APP_ENTITLEMENTS")" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.hardened-process.enhanced-security-version-string' "$APP_ENTITLEMENTS")" == "2" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.hardened-process.platform-restrictions-string' "$APP_ENTITLEMENTS")" == "2" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :iOSPackagesShouldBuildARM64e' "$WORKSPACE_SETTINGS")" == "true" ]]

run_restore
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.hardened-process' "$APP_ENTITLEMENTS" >/dev/null 2>&1; then
  echo "default restore did not remove staged Enhanced Security entitlements" >&2
  exit 1
fi

if find "$TMP_ROOT" -name '*.tmp.*' -print -quit | grep -q .; then
  echo "restore left temporary entitlement files behind" >&2
  exit 1
fi

echo "restore-entitlements script tests passed"
