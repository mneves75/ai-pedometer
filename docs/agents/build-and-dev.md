# Build, Test, and Development

## Project Generation
- `xcodegen generate`: regenerate `AIPedometer.xcodeproj` from `project.yml` (required after config/target changes).

## Xcode
## CLI Build and Test
- `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=<SimName>' build`
- `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=<SimName>' test`
- Full simulator E2E (iOS tests + widget build + watch build + screenshots): `bash Scripts/e2e-simulator.sh`
- Build/install on physical device by name (no hardcoded UDID): `bash Scripts/install-on-device.sh --device-name <DeviceName>`

## Utilities
- `swift Scripts/generate-app-icon.swift`: regenerate app icons (writes into each target's `AppIcon.appiconset`).
- `bash Scripts/check-agents-sync.sh`: verify AGENTS.md matches GUIDELINES-REF guidance.
- `bash Scripts/update-agents-guidelines.sh`: refresh AGENTS.md from GUIDELINES-REF guidance.
- `bash Scripts/verify-device-identifiers.sh`: fail if device IDs/UDIDs/ECIDs are hardcoded in tracked files.
