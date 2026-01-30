#!/bin/bash
# Restores entitlements after xcodegen generate, which resets them to empty <dict/>.
# Usage: Run after xcodegen generate, or use as post-generate hook.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

write_entitlement() {
  local file="$1"
  local content="$2"
  echo "$content" > "$file"
  echo "  Restored: $file"
}

HEALTHKIT_AND_APPGROUP=$(cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.healthkit</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.mneves.aipedometer</string>
    </array>
</dict>
</plist>
PLIST
)

APPGROUP_ONLY=$(cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.mneves.aipedometer</string>
    </array>
</dict>
</plist>
PLIST
)

echo "Restoring entitlements..."
write_entitlement "$REPO_ROOT/AIPedometer/Resources/AIPedometer.entitlements" "$HEALTHKIT_AND_APPGROUP"
write_entitlement "$REPO_ROOT/AIPedometerWatch/Resources/AIPedometerWatch.entitlements" "$HEALTHKIT_AND_APPGROUP"
write_entitlement "$REPO_ROOT/AIPedometerWidgets/Resources/AIPedometerWidgets.entitlements" "$APPGROUP_ONLY"
echo "Done."
