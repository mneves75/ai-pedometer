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

# iOS app variant with Enhanced Security (hardened process) on top of HealthKit + app
# group. STAGED, not default: signing with these keys requires the team provisioning
# profile to include the Enhanced Security capability, which Xcode only regenerates with
# an Apple ID signed in to Xcode (interactive). Until that one-time step is done, opt in
# with: ENHANCED_SECURITY_ENTITLEMENTS=1 bash Scripts/restore-entitlements.sh
# The ENABLE_ENHANCED_SECURITY build setting (compiler hardening + pointer auth) is
# always on and does not require the profile capability.
# watchOS does not support Enhanced Security; the watch app keeps the plain variant.
HEALTHKIT_APPGROUP_HARDENED=$(cat <<'PLIST'
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
    <key>com.apple.security.hardened-process</key>
    <true/>
    <key>com.apple.security.hardened-process.enhanced-security-version-string</key>
    <string>2</string>
    <key>com.apple.security.hardened-process.hardened-heap</key>
    <true/>
    <key>com.apple.security.hardened-process.dyld-ro</key>
    <true/>
    <key>com.apple.security.hardened-process.platform-restrictions-string</key>
    <string>2</string>
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
if [ "${ENHANCED_SECURITY_ENTITLEMENTS:-0}" = "1" ]; then
  write_entitlement "$REPO_ROOT/AIPedometer/Resources/AIPedometer.entitlements" "$HEALTHKIT_APPGROUP_HARDENED"
else
  write_entitlement "$REPO_ROOT/AIPedometer/Resources/AIPedometer.entitlements" "$HEALTHKIT_AND_APPGROUP"
fi
write_entitlement "$REPO_ROOT/AIPedometerWatch/Resources/AIPedometerWatch.entitlements" "$HEALTHKIT_AND_APPGROUP"
write_entitlement "$REPO_ROOT/AIPedometerWidgets/Resources/AIPedometerWidgets.entitlements" "$APPGROUP_ONLY"

# Enhanced Security enables pointer authentication (arm64e); SPM packages
# (RevenueCat) only build arm64e when the workspace opts in. xcodegen rewrites
# the project, so re-assert the workspace setting after every generate.
WORKSPACE_SETTINGS="$REPO_ROOT/AIPedometer.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings"
if [ -d "$REPO_ROOT/AIPedometer.xcodeproj" ]; then
  mkdir -p "$(dirname "$WORKSPACE_SETTINGS")"
  if [ ! -f "$WORKSPACE_SETTINGS" ]; then
    plutil -create xml1 "$WORKSPACE_SETTINGS"
  fi
  plutil -replace iOSPackagesShouldBuildARM64e -bool YES "$WORKSPACE_SETTINGS"
  echo "  Restored: $WORKSPACE_SETTINGS (iOSPackagesShouldBuildARM64e=YES)"
fi
echo "Done."
