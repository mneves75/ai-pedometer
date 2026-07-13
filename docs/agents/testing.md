# Testing

## Framework
- Swift Testing (`import Testing`, `@Test`, `#expect`).

## Locations
- Unit tests: `AIPedometerTests/`.
- UI tests: `AIPedometerUITests/`.

## Conventions
- Prefer table-driven tests with `arguments:` where useful.

## Full Local Gate
- Unit suite: `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:AIPedometerTests test`.
- UI suite: `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:AIPedometerUITests test`.
- Static analysis: `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' analyze`.
- Project metadata: `asc xcode version view --project AIPedometer.xcodeproj --target AIPedometer`.
- ASC auth health: `asc doctor`.

## App Store Connect Gate
- Remote ASC validation requires stored credentials or `ASC_KEY_ID`, `ASC_ISSUER_ID`, and private key configuration.
- Version readiness: `asc validate --app "<APP_ID_ASC>" --version "0.91" --platform IOS --output table`.
- TestFlight readiness: `asc validate testflight --app "<APP_ID_ASC>" --build "<BUILD_ID>" --output table`.
- Release dashboard: `asc status --app "<APP_ID_ASC>" --include app,builds,testflight,appstore,submission --output table`.
