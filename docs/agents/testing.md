# Testing

## Framework
- Swift Testing (`import Testing`, `@Test`, `#expect`).

## Locations
- Unit tests: `AIPedometerTests/`.
- UI tests: `AIPedometerUITests/`.

## Conventions
- Prefer table-driven tests with `arguments:` where useful.

## Full Local Gate

Start with `bash Scripts/preflight.sh` (add `--with-tests` for the shell regression suite). It resolves a supported toolchain — Xcode 26.x or 27.x, see the [build guide](build-and-dev.md) — and fails fast when the host cannot build at all, which the fixture-based script tests cannot detect.

List devices with Argent and select an available simulator whose runtime the project supports; substitute its name and OS in the commands below, and always use a **concrete** destination, never `generic/platform=iOS Simulator`. Serialize simulator jobs and use a task-specific `-derivedDataPath` and fresh `-resultBundlePath` for each test run. Prefer `build-for-testing` once followed by `test-without-building` while iterating: the rebuild dominates, the suite itself runs in seconds.

- Unit suite: `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=<SimName>,OS=<OSVersion>' -parallel-testing-enabled NO -only-testing:AIPedometerTests test`.
- UI suite: the same command with `-only-testing:AIPedometerUITests`.
- Static analysis: `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=<SimName>,OS=<OSVersion>' analyze`.
- Script regressions: `bash -c 'set -euo pipefail; for test_script in Scripts/tests/*.sh; do bash "$test_script"; done'`.
- Shell/workflow lint: `shellcheck Scripts/*.sh Scripts/tests/*.sh Scripts/tests/fixtures/*.sh Scripts/lib/*.sh .githooks/pre-commit` and `actionlint`.
- Development dependency audit: `pnpm audit --audit-level moderate`. Include dev dependencies; `--prod` omits the Wrangler toolchain and cannot verify it.
- Project invariants: `bash Scripts/verify-entitlements.sh`, `bash Scripts/verify-revenuecat-lock.sh`, `bash Scripts/check-agents-sync.sh` and `bash Scripts/verify-device-identifiers.sh`.
- Staged candidate: `bash .githooks/pre-commit` after explicit staging.
- Shared 32-bit code: use CI's direct `-project AIPedometer.xcodeproj -target AIPedometerWatch -configuration Debug -sdk watchos` build with `ARCHS=arm64_32`, `ONLY_ACTIVE_ARCH=YES`, `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO` and task-specific `SYMROOT`, `OBJROOT`, `SHARED_PRECOMPS_DIR`. The watch scheme can also pull in iPhone dependencies that cannot build for this architecture. An iOS or watch simulator build is insufficient.
- Release archive: use the [build guide](build-and-dev.md), preserving the embedded watch app. Inspect actual bundle versions and archive `ApplicationProperties`; there must be exactly one primary app under `Products/Applications`.
- Project metadata: `asc xcode version view --project AIPedometer.xcodeproj --target AIPedometer`.

Validate every xcresult with `python3 Scripts/xcresult-summary.py <result.xcresult> --validate`. Zero, failed, skipped, negative or inconsistent test counts fail validation. Swift Testing function selectors need trailing `()`; prefer suite selectors when possible. Never weaken assertions or count an empty test selection as proof.

Before release, also run `bash Scripts/check-revenuecat-staleness.sh` and review upstream notes. Exit 10 reports a newer version and requires a recorded update/retention decision; it is not a passing freshness check or proof of a vulnerability. Network/provenance errors remain unresolved. The separate immutable-pin integrity check above must pass regardless of that decision. A payment SDK update requires relevant purchase/restore and archive validation.

## Debug and UI verification

Before building, record `df -h .`, the selected Xcode version, the current commit
and the task's DerivedData/result paths. Check free space again before archiving;
an earlier reading cannot reserve capacity on this shared host. Use Argent to
discover a destination and reserve its use in the session's plan. A booted simulator
named for another repository is not an available test destination.

`AIPedometerUITests/Support/AppDriver.swift` owns deterministic launch/reset and fixture flags. Use its synthetic data instead of personal HealthKit data. Debug overrides are disabled in Release. Keep stable accessibility identifiers as the primary selectors and retain xcresult screenshots when a UI check fails.

Run relevant onboarding, five-tab navigation, premium unavailable/locked, workout start/end/recovery and settings flows on iPhone; include iPad for layout/navigation changes. Use Argent for manual app interaction and accessibility discovery. Real motion, HealthKit permissions/export, notification delivery, paired watch UI and StoreKit sandbox transactions need an explicitly selected device and remain unverified until exercised there.

Do not add another E2E runner merely to duplicate XCUITest. Add a saved Argent flow when a repeated manual path lacks coverage; record before walking the path and require stable replay evidence.

### Observing a running build without writing a test

You do not need a new XCUITest to look at one seeded screen. On a Debug build:

- Seed and launch: `xcrun simctl launch <udid> com.mneves.aipedometer -ui-testing -reset-state -skip-onboarding -force-premium-on`. `LaunchConfiguration` reads `ProcessInfo.arguments` directly, so every flag works outside XCUITest. The full set is `-ui-testing`, `-reset-state`, `-skip-onboarding`, `-force-healthkit-sync-on|-off`, `-force-premium-on|-off`, `-force-ai-unavailable`, `-seed-unfinished-workout`; environment: `UI_TESTING`, `DEMO_DETERMINISTIC`, `PREMIUM_ENABLED`. All are inert in Release by design — see `LaunchConfiguration.isOverridable`.
- Screenshot: `xcrun simctl io <udid> screenshot <path>.png`.
- Logs: `xcrun simctl spawn <udid> log stream --predicate 'subsystem == "com.mneves.aipedometer"'`. Categories are `app, health, motion, tracking, workouts, badges, background, widgets, ai, sync`, plus `metrics`.
- **Known ceiling:** `AppLogger` replaces every metadata *value* with `[private]` before the payload reaches `os_log`, and wraps the result in `privacy: .private`. A log stream yields event names, levels and timestamps — never a value. To observe state, use the `#if DEBUG` debug section in Settings (`HealthKitDebugView`), or assert it in a test.
- Debug menu: any Debug build exposes `SettingsView.debugSection` with `HealthKitDebugView` and a fake-data toggle; no test code required.

For production, record the build, device/OS, scenario and observed result for these
physical checks. Use synthetic data or data the owner explicitly authorizes:

| Scenario | Required result |
| --- | --- |
| HealthKit permission denied | App remains usable through its documented fallback; no invented health readings. |
| Workout interruption and recovery | Recoverable session state persists; terminal actions and HealthKit exports remain single-flight. |
| Export failure and retry | Pending export survives; eventual success produces one workout. |
| Watch disconnect and reconnect | The current valid snapshot replaces stale state without losing phone history. |
| Notification delivery | Enabled reminders arrive under the chosen access state; suspension preserves the saved preference. |
| Purchase, restore and offline access | Real sandbox transactions unlock only verified access; unavailable state does not erase preferences. |
| Upgrade from an existing installation | History and pending exports survive; a clean-install pass is insufficient. |

On iOS 27 the HealthKit authorization flow gained an extra step ("Past 30 Days" versus
"Full History"); a script or UI driver that assumes the older sheet will stall there.

The [payment runbook](../revenuecat/apple-payments-setup.md) owns the complete
purchase matrix. Simulation, launch overrides and mocked SDK calls do not close
these physical checks.

CodeQL builds the complete app scheme once with `ARCHS=arm64`. Do not combine the
`-arch` option with its generic simulator destination: Xcode rejects that pair.
GitHub recommends a single
architecture for Swift analysis; a generic simulator build otherwise compiles the
same sources for arm64 and x86_64. Preserve the separate watch `arm64_32` gate.
When changing the scan build, compare the database's production-source archive and
extraction diagnostics against the prior successful analysis. Nonzero query coverage
and a published analysis for the exact SHA are required; zero alerts alone is insufficient.

## Performance evidence

Measure an identified hot path before changing it. Keep the baseline and candidate inputs, compiler optimization, host and iterations identical; use interleaved runs where feasible. Include ASCII, pt-BR and emoji for text processing. Report the distribution and workload, not just the best run.

Use Instruments/Argent profiling for SwiftUI updates, CPU and hangs; retain traces in ignored output folders. A synthetic algorithm benchmark proves only that workload. Simulator timings do not prove battery savings, physical walking behavior or Foundation Models latency.

## App Store Connect Gate

- Before export, run `python3 Scripts/validate-release-artifact.py --archive <archive> --bundle-id com.mneves.aipedometer --version <VERSION> --build <BUILD>`; after export, add `--ipa <ipa>`. It checks the app/watch/widget structure, resolved configuration, nonempty executables and archive/IPA metadata equality without extracting the ZIP.
- That validator does not verify code signatures, provisioning profiles or entitlements. Inspect those on the real signed products separately; a synthetic fixture or metadata match is insufficient. An Apple key prefix does not prove RevenueCat products, offerings or purchase/restore behavior.
- Remote ASC validation requires stored credentials or `ASC_KEY_ID`, `ASC_ISSUER_ID`, and private key configuration.
- ASC auth health: `asc auth doctor`; never print tokens or private-key contents. Use an explicitly verified app record rather than the global default app ID.
- Version readiness: `asc validate --app "<APP_ID_ASC>" --version "<VERSION>" --platform IOS --output table`.
- TestFlight readiness: `asc validate testflight --app "<APP_ID_ASC>" --build "<BUILD_ID>" --output table`.
- Release dashboard: `asc status --app "<APP_ID_ASC>" --include app,builds,testflight,appstore,submission --output table`.

Keep a release evidence entry in the existing daily journal: commit, version/build,
Xcode/SDK, lockfile identity, resolved configuration kind, test results, archive/IPA
paths and hashes, and ASC build identity. Record configuration kind only, never keys.
Promote the same verified ASC build from TestFlight to production. Upload, processing,
group availability, review approval and actual store availability are separate states.
