# Build, Test, and Development

## Project Generation
- `xcodegen generate`: regenerate `AIPedometer.xcodeproj` from `project.yml` (required after config/target changes).
- Entitlements are rewritten by the postGen hook `Scripts/restore-entitlements.sh`; edit that script, never the `.entitlements` files. The iOS app's Enhanced Security hardened-process keys are staged behind `ENHANCED_SECURITY_ENTITLEMENTS=1` (they need the team profile regenerated with the capability — one-time interactive Xcode sign-in). Security build-setting decisions: `xcode-security-settings.md`.

## Xcode
- Toolchain pin: when `xcode-select` points at an Xcode beta, prefix `xcodebuild` with `DEVELOPER_DIR=/Applications/Xcode.app` (project contract is Xcode 26.x; the pinned RevenueCat revision fails test builds under the 27-beta toolchain).
- Simulator runtime drift ("iOS X.Y is not installed" with the runtime present in `simctl`): `xcrun simctl runtime match set iphoneosX.Y <installed-build>`.
## CLI Build and Test
- `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=<SimName>' build`
- `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=<SimName>' test`
- `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=<SimName>' analyze`
- `asc doctor`: verify local ASC CLI/keychain/auth health before remote App Store Connect work.
- `asc xcode version view --project AIPedometer.xcodeproj --target AIPedometer`: confirm generated Xcode metadata matches `project.yml`.
- `asc validate --app "<APP_ID_ASC>" --version "0.90" --platform IOS --output table`: remote App Store readiness once ASC credentials and app ID are configured.
- `asc validate testflight --app "<APP_ID_ASC>" --build "<BUILD_ID>" --output table`: remote TestFlight readiness once a processed build exists.
- Full simulator E2E (iOS tests + widget build + watch build + screenshots): `bash Scripts/e2e-simulator.sh`
- Build/install on physical device by name (no hardcoded UDID): `bash Scripts/install-on-device.sh --device-name <DeviceName>`
- Build/install on iPhone + explicit install/verify on paired Watch: `bash Scripts/install-on-device.sh --device-name <DeviceName> --watch-name "<Apple Watch Name>" --launch`
- Retry/timeout knobs for flaky device/watch connectivity:
  - `--build-retries <n>`
  - `--install-retries <n>`
  - `--retry-delay <seg>`
  - `--destination-timeout <s>`
- Operational note: `devicectl` can emit `Failed to load provisioning paramter list ... No provider was found.` even when build/install/launch still succeed; current evidence points to a host-side CoreDevice/Xcode warning rather than a repo/script bug.
- Operational note: a locked physical iPhone can reject the first launch request with `Locked`; `Scripts/install-on-device.sh` already retries launch automatically.

## Utilities
- `swift Scripts/generate-app-icon.swift`: regenerate app icons (writes into each target's `AppIcon.appiconset`).
- `bash Scripts/check-agents-sync.sh`: verify AGENTS.md matches GUIDELINES-REF guidance.
- `bash Scripts/update-agents-guidelines.sh`: refresh AGENTS.md from GUIDELINES-REF guidance.
- `bash Scripts/verify-device-identifiers.sh`: fail if device IDs/UDIDs/ECIDs are hardcoded in tracked files.
- `bash Scripts/appstore-materials-prepare.sh`: assemble ordered App Store screenshots from captured UI-test artifacts.
- `bash Scripts/appstore-screenshots-validate.sh`: validate screenshot dimensions for ASC upload sets.
- `bash Scripts/appstore-screenshots-upload.sh`: upload prepared screenshot sets with `asc`.
- `bash Scripts/appstore-publishing-preflight.sh`: run end-to-end App Store screenshot preflight (matrix check + prepare + validate + optional upload dry-run).
