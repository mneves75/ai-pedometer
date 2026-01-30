# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Agent Notes
Run notes are stored at `agent_planning/ultrawork-notes.txt` (append each run and reuse between sessions).

For detailed guidelines (mission, quality gates, playbooks), see `AGENTS.md`.

## Build Commands

```bash
# Generate Xcode project (required after project.yml changes)
# IMPORTANT: Always restore entitlements after — xcodegen resets them to empty dicts
xcodegen generate && Scripts/restore-entitlements.sh

# Build for simulator
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run all tests
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# Run a single test file (Swift Testing)
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test -only-testing:AIPedometerTests/DailyStepCalculatorTests

# Build and install on physical device (iMarcus)
xcodebuild -scheme AIPedometer -destination 'platform=iOS,id=00008150-00124C8C3440401C' clean build
xcrun devicectl device install app --device 0DEB0D58-EF4B-559C-925D-A88F11E866D8 \
  ~/Library/Developer/Xcode/DerivedData/AIPedometer-*/Build/Products/Debug-iphoneos/AIPedometer.app

# Regenerate app icons
swift Scripts/generate-app-icon.swift

# Verify AGENTS.md sync with GUIDELINES-REF
bash Scripts/check-agents-sync.sh
```

If XcodeBuildMCP is available, prefer using MCP tools:
```
mcp__xcodebuildmcp__build_run_sim   # Build and run on simulator
mcp__xcodebuildmcp__run_tests       # Run tests
```

**Device UDID formats** (same device, different tools):
- `devicectl`/CoreDevice: `0DEB0D58-EF4B-559C-925D-A88F11E866D8` (hashed)
- `xcodebuild`/libimobiledevice: `00008150-00124C8C3440401C` (native)

## Git Hooks

Enable repo hooks for AGENTS.md sync enforcement:
```bash
git config core.hooksPath .githooks
```

## Architecture Overview

### Dependency Graph

```
AIPedometerApp (entry point)
    ├── AppStartupCoordinator   → one-time init (after onboarding)
    ├── AppLifecycleCoordinator → scene phase transitions
    ├── PersistenceController.shared → ModelContainer (SwiftData)
    ├── StepTrackingService ← (HealthKitService, MotionService, SharedDataStore)
    ├── FoundationModelsService → LanguageModelSession (Apple AI)
    │   └── InsightService, CoachService, TrainingPlanService
    ├── WorkoutSessionController ← (HealthKitService, LiveActivityManager)
    ├── NotificationService / SmartNotificationService
    ├── HealthKitSyncService ← (HealthKitService, SwiftData)
    ├── BackgroundTaskService ← StepTrackingService
    ├── MetricKitService.shared (singleton)
    └── WatchSyncService.shared
```

All services are created in `AIPedometerApp.init()` and injected via `.environment()`. Views access them with `@Environment(ServiceType.self)`.

**Coordinators pattern**: `AppStartupCoordinator` handles one-time initialization after onboarding (background tasks, watch sync, tracking). `AppLifecycleCoordinator` handles foreground refresh on `.active` scene phase. Both use closure injection for testability.

### Service Patterns

**Protocol-first design**: Every service has a protocol suffix (e.g., `HealthKitServiceProtocol`) enabling test mocks. Services are `@MainActor @Observable` classes.

**Structured logging**: Use `Loggers.category.level("event.name", metadata: [...])`. Categories: `app`, `health`, `motion`, `tracking`, `workouts`, `badges`, `background`, `widgets`, `ai`, `sync`.

### SwiftData Schema

Models defined in `SchemaV1` (`AIPedometer/Core/Persistence/Migrations/ModelMigrationPlan.swift`):
- `DailyStepRecord`, `StepGoal`, `Streak`, `EarnedBadge`
- `WorkoutSession`, `TrainingPlanRecord`, `AuditEvent`

Persistence uses App Group (`group.com.mneves.aipedometer`) for widget/watch data sharing.

### AI Integration

`FoundationModelsService` wraps Apple's Foundation Models framework. It provides:
- `respond(to:)` for text responses
- `respond(to:as:)` for structured `Generable` types
- `streamResponse(to:)` for streaming
- Tool support via `configure(with:)`

AI-related services (InsightService, CoachService, TrainingPlanService) compose this service with domain-specific prompts.

**DataConfidence pattern**: AI services use `DataConfidence.reliable` vs `.uncertain` to distinguish between confirmed zero-step data and unavailable/loading states. This prevents AI hallucination when data sources are unreliable—the system returns a fallback message instead of generating insights from potentially stale data.

## Code Conventions

### Swift 6.2 Strict Concurrency

All warnings are errors. Key settings from `project.yml`:
- `SWIFT_STRICT_CONCURRENCY: complete`
- `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES`
- `SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY: YES` - requires `any` prefix for protocol existentials
- `SWIFT_UPCOMING_FEATURE_GLOBAL_CONCURRENCY: YES` - global actor isolation enforcement

Services must be `@MainActor` or properly isolated. Use `Sendable` for cross-isolation types. Build configuration lives in `Config/*.xcconfig`.

### Testing

Uses Swift Testing framework (`import Testing`, `@Test`, `#expect`). Example pattern:

```swift
@Test
func descriptiveTestName() {
    let sut = SystemUnderTest()
    #expect(sut.result == expected)
}

// Table-driven tests with arguments
@Test(arguments: [
    (input: 0, expected: "0 steps"),
    (input: 1000, expected: "1,000 steps"),
])
func formatsStepCount(input: Int, expected: String) {
    #expect(formatSteps(input) == expected)
}
```

Mocks follow naming convention: `Mock<ServiceName>` (e.g., `MockFoundationModelsService`).

### Localization

All user-facing strings go in `Shared/Resources/Localizable.xcstrings`. Currently supports:
- English (en)
- Portuguese Brazil (pt-BR)

### Shared Module

`Shared/` contains cross-target code used by iOS app, watchOS, and widgets:
- `Models/` - Data transfer types (`SharedStepData`, `WatchPayload`, etc.)
- `DesignSystem/` - `DesignTokens`, `GlassModifiers`, `HapticService`
- `Utilities/` - `Logger`, `Formatters`, `LaunchConfiguration`
- `Extensions/` - Date, View, Int, Double helpers

### Feature Organization

Features in `AIPedometer/Features/` follow structure:
```
FeatureName/
├── FeatureNameView.swift    # Main view
└── Components/              # Feature-specific subviews (if needed)
```

Core services in `AIPedometer/Core/` organized by domain:
```
Core/
├── AI/            # FoundationModelsService, InsightService, CoachService, TrainingPlanService
├── Background/    # BackgroundTaskService for refresh/processing tasks
├── Badges/        # BadgeService, achievement definitions
├── Goals/         # GoalService, step goal management
├── HealthKit/     # HealthKitService, authorization, sync
├── Motion/        # MotionService, CoreMotion wrapper
├── Notifications/ # NotificationService, SmartNotificationService
├── Performance/   # MetricKitService for system metrics
├── Persistence/   # SwiftData controller, models, migrations
├── StepTracking/  # Main tracking service, calculators, aggregators
├── WatchConnectivity/  # WatchSyncService
└── Workouts/      # WorkoutSessionController, LiveActivityManager
```

## Signing & Entitlements

**Team ID**: `Q96FUTC5G8` (Marcus Neves)
**Bundle ID**: `com.mneves.aipedometer`

Entitlements are defined in target-specific `.entitlements` files:
- `AIPedometer/Resources/AIPedometer.entitlements` - HealthKit, App Groups
- `AIPedometerWatch/Resources/AIPedometerWatch.entitlements` - HealthKit, App Groups
- `AIPedometerWidgets/Resources/AIPedometerWidgets.entitlements` - App Groups only

**Critical**: `xcodegen generate` resets all entitlements to empty `<dict/>`. Always run `Scripts/restore-entitlements.sh` after regenerating. The combined command `xcodegen generate && Scripts/restore-entitlements.sh` prevents silent HealthKit failures.

## Common Pitfalls

1. **Enum alignment**: AI-related enums (like `TrainingGoal`) must match between `AIGenerableModels.swift` and UI code. Case names are lowercase (`.reach10k` not `.reach10K`).

2. **Protocol existentials**: Swift 6 requires `any` prefix for protocol types used as values (e.g., `any HealthKitServiceProtocol`).

3. **@MainActor services**: All services are `@MainActor`. When accessing from non-isolated contexts, use `await MainActor.run { }`.

4. **Version sync**: Keep `MARKETING_VERSION` in `project.yml` aligned with `CHANGELOG.md` version.

5. **HealthKit fallback**: `HealthKitServiceFallback` wraps real HealthKit with demo mode support. When `DemoModeStore.useFakeData` is enabled, it returns synthetic data for testing.

6. **AI zero-step handling**: When step count is zero with `.reliable` confidence, AI must not hallucinate activity. Use explicit prompts that acknowledge inactivity rather than generating fictional insights.
