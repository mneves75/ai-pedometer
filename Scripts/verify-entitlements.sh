#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "Entitlements check failed: $*" >&2
  exit 1
}

require_plist_key_exists() {
  local file="$1"
  local key="$2"

  /usr/libexec/PlistBuddy -c "Print :${key}" "$file" >/dev/null 2>&1 || fail "${file} missing key '${key}'"
}

require_plist_key_true() {
  local file="$1"
  local key="$2"

  local v
  v="$(/usr/libexec/PlistBuddy -c "Print :${key}" "$file" 2>/dev/null || true)"
  [[ "$v" == "true" || "$v" == "YES" || "$v" == "1" ]] || fail "${file} key '${key}' is not true (got: '${v}')"
}

require_array_contains() {
  local file="$1"
  local key="$2"
  local expected="$3"

  require_plist_key_exists "$file" "$key"

  local i=0
  while true; do
    local item
    item="$(/usr/libexec/PlistBuddy -c "Print :${key}:${i}" "$file" 2>/dev/null || true)"
    if [[ -z "$item" ]]; then
      break
    fi
    if [[ "$item" == "$expected" ]]; then
      return 0
    fi
    i=$((i + 1))
  done

  fail "${file} key '${key}' does not contain '${expected}'"
}

IOS_ENTITLEMENTS="AIPedometer/Resources/AIPedometer.entitlements"
WATCH_ENTITLEMENTS="AIPedometerWatch/Resources/AIPedometerWatch.entitlements"
WIDGETS_ENTITLEMENTS="AIPedometerWidgets/Resources/AIPedometerWidgets.entitlements"

APP_GROUP="group.com.mneves.aipedometer"

[[ -f "$IOS_ENTITLEMENTS" ]] || fail "missing ${IOS_ENTITLEMENTS}"
[[ -f "$WATCH_ENTITLEMENTS" ]] || fail "missing ${WATCH_ENTITLEMENTS}"
[[ -f "$WIDGETS_ENTITLEMENTS" ]] || fail "missing ${WIDGETS_ENTITLEMENTS}"

require_plist_key_true "$IOS_ENTITLEMENTS" "com.apple.developer.healthkit"
require_array_contains "$IOS_ENTITLEMENTS" "com.apple.security.application-groups" "$APP_GROUP"

require_plist_key_true "$WATCH_ENTITLEMENTS" "com.apple.developer.healthkit"
require_array_contains "$WATCH_ENTITLEMENTS" "com.apple.security.application-groups" "$APP_GROUP"

require_array_contains "$WIDGETS_ENTITLEMENTS" "com.apple.security.application-groups" "$APP_GROUP"

echo "OK: entitlements are valid"

