# Build, Test, and Development

## Project Generation
- `xcodegen generate`: regenerate `AIPedometer.xcodeproj` from `project.yml` (required after config/target changes).
- Entitlements are rewritten by the postGen hook `Scripts/restore-entitlements.sh`; edit that script, never the `.entitlements` files. The iOS app's Enhanced Security hardened-process keys are staged behind `ENHANCED_SECURITY_ENTITLEMENTS=1` (they need the team profile regenerated with the capability — one-time interactive Xcode sign-in). Security build-setting decisions: `xcode-security-settings.md`.

## Xcode
- Run `bash Scripts/preflight.sh` first. It resolves the toolchain, prints the exact version and build, and checks free disk, required tools, `core.hooksPath`, `Config/Local.xcconfig` and the generated project before you spend minutes on a build that cannot succeed.
- Supported toolchains are Xcode 26.x and 27.x, selected by `Scripts/lib/xcode-toolchain.sh` (`aipedometer_select_xcode`). An explicit `AIPEDOMETER_XCODE_DEVELOPER_DIR` pin wins; otherwise it prefers `DEVELOPER_DIR`, then `xcode-select -p`, then `/Applications/Xcode.app`, skipping any candidate that is missing or unsupported, and exports `AIPEDOMETER_RESOLVED_XCODE_VERSION` / `AIPEDOMETER_RESOLVED_XCODE_BUILD`. Record both in release evidence: a range is weaker than a pin, so evidence must name the toolchain that actually produced the artifact.
- To force one toolchain, set `AIPEDOMETER_XCODE_DEVELOPER_DIR`; an unusable explicit pin fails instead of silently drifting. `AIPEDOMETER_SUPPORTED_XCODE_MAJORS` widens or narrows the accepted range.
- When `xcode-select -p` points at an Xcode-beta but the work targets the stable SDK, pin both variables for scripts and direct Xcode commands:

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export AIPEDOMETER_XCODE_DEVELOPER_DIR="$DEVELOPER_DIR"
  bash Scripts/preflight.sh
  xcodebuild -version
  ```

- Use a concrete simulator destination for `build-for-testing` and `test`. A *generic* destination (`generic/platform=iOS Simulator`) compiles arm64 and x86_64; through 1.0.7 that failed on the prebuilt RevenueCat module (`built for incompatible target`). RevenueCat was removed in 1.0.8 and the generic destination has not been re-tested since, so keep the concrete destination.
- Simulator runtime drift ("iOS X.Y is not installed" with the runtime present in `simctl`): `xcrun simctl runtime match set iphoneosX.Y <installed-build>`.
## CLI Build and Test
- `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=<SimName>' build`
- `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=<SimName>' test`
- `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=<SimName>' analyze`
- Release simulator builds on Apple Silicon also need `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`:
  Release otherwise requests both arm64 and x86_64 even with a concrete destination, and
  through 1.0.7 the x86_64 compile failed on the prebuilt RevenueCat module (removed in 1.0.8;
  not re-tested without it). This simulator-only selection does not change supported device
  architectures or replace archive validation.
- Release archive and TestFlight upload:
  1. `xcodebuild -project AIPedometer.xcodeproj -scheme AIPedometer -configuration Release -destination 'generic/platform=iOS' -archivePath <out>/AIPedometer.xcarchive -allowProvisioningUpdates archive`
  2. `python3 Scripts/validate-release-artifact.py --archive <archive> --bundle-id com.mneves.aipedometer --version <V> --build <B>`
  3. Export with an options plist of `method` `app-store-connect`, `destination` `export`,
     `signingStyle` `automatic` and the team ID, **under a system-only PATH**:
     `env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath <archive> -exportOptionsPlist <plist> -exportPath <out>/export -allowProvisioningUpdates`.
     Xcode's `/usr/bin/rsync` spawns the first `rsync` on `PATH`; Homebrew's rsync 3.x rejects
     `--extended-attributes` and the export ends in the generic `Copy failed` (the real line is in
     `IDEDistributionPipeline.log` under `/var/folders/**/T/AIPedometer_*.xcdistributionlogs`).
  4. Rerun the validator with `--ipa`, then `asc builds upload --app 6778799265 --ipa <ipa> --wait`.
     `--wait` surfaces Apple's processing verdict; ITMS-90183 (missing `CFBundlePackageType`)
     rejected build 61 this way. A rejected build number is not reused.
  `Scripts/test-payments-device.sh` automates the same path but also creates a TestFlight group
  and invites testers; a beta delivery does not authorize those steps.
- `asc doctor`: verify local ASC CLI/keychain/auth health before remote App Store Connect work.
- `asc xcode version view --project AIPedometer.xcodeproj --target AIPedometer`: confirm generated Xcode metadata matches `project.yml`.
- `asc validate --app "<APP_ID_ASC>" --version "<VERSION>" --platform IOS --output table`: remote App Store readiness once ASC credentials and app ID are configured.
- `asc validate testflight --app "<APP_ID_ASC>" --build "<BUILD_ID>" --output table`: remote TestFlight readiness once a processed build exists.
- Full simulator E2E: select available dedicated iPhone/watch IDs with Argent, then
  run `E2E_IOS_UDID="<selected-iphone-id>" E2E_WATCH_UDID="<selected-watch-id>" bash Scripts/e2e-simulator.sh`.
  For an explicit iPhone-only run, use `E2E_IOS_UDID="<selected-iphone-id>" E2E_ENABLE_WATCH=0 bash Scripts/e2e-simulator.sh`.
  Local IDs are required; `CI=true` alone does not enable auto-selection. Only
  GitHub-hosted Actions runners auto-select. The script rejects obsolete
  `E2E_IOS_DEST`/`E2E_WATCH_DEST` overrides so test and recovery targets cannot diverge.
- Build/install on physical device by name (no hardcoded UDID): `bash Scripts/install-on-device.sh --device-name <DeviceName>`
- Build/install on iPhone + explicit install/verify on paired Watch: `bash Scripts/install-on-device.sh --device-name <DeviceName> --watch-name "<Apple Watch Name>" --launch`
- Retry/timeout knobs for flaky device/watch connectivity:
  - `--build-retries <n>`
  - `--install-retries <n>`
  - `--retry-delay <seg>`
  - `--destination-timeout <s>`
- Operational note: `devicectl` can emit `Failed to load provisioning paramter list ... No provider was found.` even when build/install/launch still succeed; current evidence points to a host-side CoreDevice/Xcode warning rather than a repo/script bug.
- Operational note: a locked physical iPhone can reject the first launch request with `Locked`; `Scripts/install-on-device.sh` already retries launch automatically.
- Crash logs from a physical iPhone without USB: when the phone shares the Wi-Fi network it
  appears in `pymobiledevice3 usbmux list` with `ConnectionType: Network`, and
  `idevicecrashreport -n -u <device-udid> -k <dir>` pulls the `.ips` reports over the network.
  Pass the UDID from that listing; never hardcode it in a tracked file.

## Utilities
- `bash Scripts/preflight.sh [--with-tests] [--quiet]`: verify this host can build and test at all — resolved Xcode version/build, free disk, required tools, `core.hooksPath`, `Config/Local.xcconfig`, generated project, booted simulators — then run the fast gate tier. Run it before any long build. Exit 1 means a required check failed.
- `swift Scripts/generate-app-icon.swift`: regenerate app icons (writes into each target's `AppIcon.appiconset`).
- `bash Scripts/check-agents-sync.sh`: validate the canonical AGENTS.md contract, CLAUDE.md import, instruction-size budget and local reference targets. Works without an external guidelines checkout. Edit AGENTS.md directly; generic guidance and installed skill catalogs are referenced only when needed.
- `bash Scripts/verify-device-identifiers.sh`: fail if device IDs/UDIDs/ECIDs are hardcoded in tracked files.
- `bash Scripts/verify-entitlements.sh`: validate entitlement plist syntax and required/forbidden capabilities.
- `bash Scripts/verify-swift-build-settings.sh`: fail if `project.yml` declares a `SWIFT_*` build setting the selected Xcode does not define. Xcode ignores unknown settings silently, so a fabricated name reads as an enabled feature forever.
- `bash Scripts/appstore-materials-prepare.sh`: assemble ordered App Store screenshots from captured UI-test artifacts.
- `bash Scripts/appstore-screenshots-validate.sh`: validate screenshot dimensions for ASC upload sets.
- `bash Scripts/appstore-screenshots-upload.sh`: upload prepared screenshot sets with `asc`.
- `bash Scripts/appstore-publishing-preflight.sh`: run end-to-end App Store screenshot preflight (matrix check + prepare + validate + optional upload dry-run).
