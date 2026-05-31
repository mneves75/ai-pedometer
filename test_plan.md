# Test Plan

## Success Criteria

- Repo behavior aligns with current Apple/Swift guidance for background task registration, Observation/SwiftUI state management, and Swift concurrency safety.
- Any confirmed bug gets a regression test when practical.
- Final verification includes a real simulator build/test pass, not static reasoning alone.

## Baseline

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' test`
- `asc doctor`
- `asc xcode version view --project AIPedometer.xcodeproj --target AIPedometer`

## Focused Checks After Fixes

- Run targeted `xcodebuild test -only-testing:` suites for changed subsystems first.
- Rerun full unit and UI suites for closure:
  - `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:AIPedometerTests test`
  - `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:AIPedometerUITests test`
- Run static analysis: `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' analyze`
- If ASC credentials are configured, run remote readiness:
  - `asc validate --app "<APP_ID_ASC>" --version "0.83" --platform IOS --output table`
  - `asc validate testflight --app "<APP_ID_ASC>" --build "<BUILD_ID>" --output table`
- If build/test instability appears, use the repo’s canonical harness: `bash Scripts/e2e-simulator.sh`.

## Review Areas

- App bootstrap and lifecycle
- Persistence and migration/fail-closed behavior
- HealthKit, motion fallback, and daily/weekly sync integrity
- Workout session lifecycle and persisted reconciliation
- AI service grounding and recovery behavior
- watchOS/widget/shared-state consistency
