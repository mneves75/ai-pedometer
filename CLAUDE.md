# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Run Notes

Append notes for each run in `agent_planning/ultrawork-notes.txt` (what worked, what didn’t, missing context) and reuse between sessions. Link: [agent_planning/ultrawork-notes.txt](agent_planning/ultrawork-notes.txt).

## Apple Platforms

For Swift / iOS/iPadOS 26 code, look for info in:

`/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation`

If using an unreleased iOS SDK, look in Xcode beta:

`/Applications/Xcode-beta.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation`

## Build Commands

```bash
# Generate Xcode project (required after project.yml changes)
# CRITICAL: xcodegen resets entitlements to empty dicts — always restore after
xcodegen generate && Scripts/restore-entitlements.sh

# Build for simulator (CI uses iPhone 17)
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run all tests
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' test

# Run a single test file
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:AIPedometerTests/DailyStepCalculatorTests

# Run a single test method
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:AIPedometerTests/DailyStepCalculatorTests/testMergeSteps

# Build + install on physical device by name (no hardcoded UDID)
bash Scripts/install-on-device.sh --device-name "My iPhone"

# Build + install + launch on physical device
bash Scripts/install-on-device.sh --device-name "My iPhone" --launch

# Build + install + launch on iPhone and explicit install/verify on paired Watch
bash Scripts/install-on-device.sh --device-name "My iPhone" --watch-name "My Apple Watch" --launch

# Build + install with stronger retries/timeouts for unstable device/watch tunnels
bash Scripts/install-on-device.sh \
  --device-name "My iPhone" \
  --watch-name "My Apple Watch" \
  --launch \
  --build-retries 3 \
  --install-retries 4 \
  --retry-delay 4 \
  --destination-timeout 180
```

If XcodeBuildMCP is available, prefer MCP tools (`build_run_sim`, `run_tests`).

## StoreKit Tip Jar

- Product ID: `com.mneves.aipedometer.coffee`
- StoreKit config for local testing: `StoreKit/TipJar.storekit` (referenced in the shared scheme)
- The `StoreKit` directory is included in the main target's `sources` with `buildPhase: none` — this is required because xcodegen's `fileGroups` silently skips `.storekit` files
- StoreKit Configuration only works when launched from Xcode (Cmd+R) — installing via `devicectl` does NOT activate the test config

**CI pipeline** (`.github/workflows/ci.yml`): xcodegen generate → restore entitlements → build (DEBUG, no signing) → unit tests → UI tests. Runs on `macos-15` with Xcode 26.

## Design Docs (UI Work Only)

For any UI/UX changes, read these first:

- `DESIGN_SYSTEM.md`
- `FRONTEND_GUIDELINES.md`
- `APP_FLOW.md`
- `PRD.md`
- `TECH_STACK.md`
- `LESSONS.md`
- `progress.txt`

Use design tokens for all colors, spacing, and type (no hardcoded values).

## Architecture

### Targets

| Target | Platform | Purpose |
|--------|----------|---------|
| `AIPedometer` | iOS 26+ | Main app |
| `AIPedometerWatch` | watchOS 26+ | Companion watch app |
| `AIPedometerWidgets` | iOS 26+ | Lock Screen + Home Screen widgets |
| `AIPedometerTests` | iOS | Unit tests (Swift Testing) |
| `AIPedometerUITests` | iOS | UI tests |

All targets share code from `Shared/` (models, design system, utilities, resources).

### Service Dependency Graph

```
AIPedometerApp.init()  ← creates all services, injects via .environment()
    ├── AppStartupCoordinator   → one-time init (after onboarding, skipped in UI tests)
    ├── AppLifecycleCoordinator → foreground refresh on .active scene phase
    ├── PersistenceController.shared → SwiftData ModelContainer
    ├── StepTrackingService ← (HealthKitServiceFallback, MotionService, SharedDataStore)
    ├── FoundationModelsService → Apple Foundation Models (LanguageModelSession)
    │   ├── InsightService   → daily step insights
    │   ├── CoachService     → personalized coaching
    │   └── TrainingPlanService → AI-generated training plans
    ├── WorkoutSessionController ← (HealthKitServiceFallback, LiveActivityManager)
    ├── HealthKitSyncService ← (HealthKitServiceFallback, SwiftData)
    ├── BadgeService, NotificationService, SmartNotificationService
    ├── BackgroundTaskService ← StepTrackingService
    └── WatchSyncService.shared, MetricKitService.shared (singletons)
```

Views access services with `@Environment(ServiceType.self)`.

### Step Data Flow

The dashboard merges two data sources to avoid double-counting Apple Watch steps:

```
HealthKit (includes Watch)  ──┐
                               ├── StepTrackingService.mergeSteps() → max(HK, pedometer)
CMPedometer (iPhone only)  ───┘
                                    ↓
                              SharedDataStore (today's steps/goal)
                                    ↓
                        ┌─────────────────────────┐
                        │ DashboardView (ring)     │
                        │ InsightService (AI card) │
                        │ Widgets (via App Group)  │
                        └─────────────────────────┘
```

### Demo Mode Architecture

`DemoModeStore` controls two independent toggles:
- `isPremiumEnabled` — bypasses subscription checks (unlocks AI features)
- `useFakeData` — switches to synthetic HealthKit data

`HealthKitServiceFallback` wraps the real `HealthKitService` and delegates to `DemoHealthKitService` when `useFakeData` is on. All services receive `HealthKitServiceFallback`, never the raw service.

### AI Data Confidence

AI services use `DataConfidence.reliable` vs `.uncertain` to prevent hallucination. When confidence is uncertain (data not yet loaded, HealthKit unavailable), the system returns a fallback message instead of generating insights from stale data.

### Coordinator Pattern

Both coordinators use closure injection (no direct service references) for testability:
- `AppStartupCoordinator` — runs once after onboarding: registers background tasks, starts watch sync, begins step tracking, performs initial HealthKit sync
- `AppLifecycleCoordinator` — runs on each `.active` transition: refreshes authorizations, AI availability, today's data, foreground sync

### Persistence

SwiftData with dual-store strategy: primary store in App Group shared container (accessible by app, watch, widgets), fallback to Application Support, then in-memory. `PersistenceController.resetStore()` available for UI test state reset.

Models in `SchemaV1` (`Core/Persistence/Migrations/ModelMigrationPlan.swift`): `DailyStepRecord`, `StepGoal`, `Streak`, `EarnedBadge`, `WorkoutSession`, `TrainingPlanRecord`, `AuditEvent`, `AIContextSnapshot`. All models use soft delete (`deletedAt: Date?`).

## Code Conventions

### Swift 6.2 Strict Concurrency

All warnings are errors (`SWIFT_TREAT_WARNINGS_AS_ERRORS: YES`). Key constraints:
- `SWIFT_STRICT_CONCURRENCY: complete` — full data-race safety
- `SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY: YES` — requires `any` prefix for protocol types used as values
- Services must be `@MainActor @Observable`. Cross-isolation types must be `Sendable`.
- Build configuration in `Config/*.xcconfig`, project definition in `project.yml`.

### Protocol-First Design

Every service has a protocol (e.g., `HealthKitServiceProtocol`). Mocks follow `Mock<ServiceName>` naming. Services are injected via `.environment()`, never instantiated in views.

### Testing

Swift Testing framework (`import Testing`, `@Test`, `#expect`). Prefer table-driven tests with `arguments:` for parameterized cases. Unit tests in `AIPedometerTests/`, UI tests in `AIPedometerUITests/`. Closure injection pattern for mocking coordinators (counter-based tracking, no heavy mock frameworks).

### Localization

String Catalogs at `Shared/Resources/Localizable.xcstrings`. Supports English (en) and Portuguese Brazil (pt-BR). All user-facing strings use `String(localized:)`.

### Logging

`Loggers.category.level("event.name", metadata: [...])`. Categories: `app`, `health`, `motion`, `tracking`, `workouts`, `badges`, `background`, `widgets`, `ai`, `sync`.

## Signing & Entitlements


Three entitlements files (HealthKit + App Groups for app/watch, App Groups only for widgets). `xcodegen generate` **silently resets all entitlements to empty dicts** — always run `Scripts/restore-entitlements.sh` after. The CI workflow does this automatically.

App Group `group.com.mneves.aipedometer` enables data sharing between app, widgets, and watch.

## Common Pitfalls

1. **Entitlements wipe**: `xcodegen generate` alone = broken HealthKit. Always combine with `Scripts/restore-entitlements.sh`.
2. **Enum alignment**: AI enums (e.g., `TrainingGoal`) must match between `AIGenerableModels.swift` and UI code. Cases are lowercase (`.reach10k` not `.reach10K`).
3. **Protocol existentials**: Swift 6 requires `any` prefix — `any HealthKitServiceProtocol`, not `HealthKitServiceProtocol`.
4. **Version sync**: Keep `MARKETING_VERSION` in `project.yml` aligned with `CHANGELOG.md`.
5. **AI zero-step grounding**: When steps=0 with `.reliable` confidence, AI prompts must acknowledge inactivity — never fabricate achievements.
6. **No hardcoded device IDs**: use device name + `Scripts/install-on-device.sh`; avoid committing raw UDIDs/UUIDs in docs/scripts.
7. **Simulator name**: CI uses `iPhone 17` — keep local commands consistent to avoid destination mismatches.
8. **Release tags**: Use `v<MARKETING_VERSION>` (for example `v0.6`) after docs/version sync and tests pass. After tag push, always create/publish the matching GitHub Release (`gh release create ...`) and confirm it is marked as Latest.

## Further Reading

| Document | Purpose |
|----------|---------|
| `AGENTS.md` | Agent guidelines, mandatory reading lists, quality gates |
| `docs/agents/` | Detailed guides: project structure, build/dev, coding style, testing, git workflow |
| `CONTRIBUTING.md` | Setup instructions, PR checklist |
| `CHANGELOG.md` | Version history (keep aligned with `MARKETING_VERSION`) |

## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Offload research, exploration, and parallel analysis to subagents to keep main context window clean
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests → then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. No hacks. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.
