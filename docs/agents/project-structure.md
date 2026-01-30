# Project Structure

## Modules and Targets
- `AIPedometer/`: main iOS app target source.
- `AIPedometerWatch/`: watchOS companion app.
- `AIPedometerWidgets/`: iOS widgets and Live Activities.
- `Shared/`: shared models, services, utilities, and resources used across targets.
- `Resources/`: shared assets and catalogs.
- `AIPedometerTests/` and `AIPedometerUITests/`: unit and UI tests.

## Project Configuration
- `project.yml` is the XcodeGen source of truth for the Xcode project.
- `Config/` holds xcconfig build settings (warnings as errors, strict concurrency).
- Minimum targets: iOS 26.0, watchOS 26.0 (see `project.yml`).
- HealthKit entitlements live in each target's `Resources/*.entitlements`.
