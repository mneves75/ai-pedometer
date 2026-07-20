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
- The iOS app owns HealthKit. Widgets read only the bounded `SharedStepData` snapshot from app-group
  `UserDefaults`; fresh SwiftData stores stay in the app sandbox, while existing app-group stores
  remain a compatibility fallback until relocation can be proven data-safe. The watch companion
  receives data through WatchConnectivity and intentionally has no HealthKit or app-group entitlement.

## Ownership Notes
- GPX file access, security-scoped reads, file-size preflight, parsing handoff, and persisted route storage are owned by `Shared/Utilities/GPXRouteImporter.swift`.
- GPX XML validation and coordinate parsing are owned by `Shared/Utilities/GPXRouteParser.swift`.
- Active training-plan workout recommendation projection is owned by `TrainingPlanRecord`; Workouts should consume the model projection instead of duplicating current-week mapping rules.
