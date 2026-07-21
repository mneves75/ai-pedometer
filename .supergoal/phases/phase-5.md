SUPERGOAL_PHASE_START
Phase: 5 of 8 — Dead code removal
Task: Remove vetted zero-call-site code and regenerate the project
Type: brownfield, refactor
Mandatory commands: DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test, DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometerWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (42mm)' build, ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all
Acceptance criteria: 4
Evidence required: per-symbol rg zero-call-site proofs, build/test outputs
Depends on phases: 4

## Shared context (read first)

- Repo: /Users/mneves/dev/PROJETOS_MOBILE/ai-pedometer. Swift 6.2 strict concurrency, warnings-as-errors, Swift Testing.
- TOOLCHAIN: every xcodebuild MUST use `DEVELOPER_DIR=/Applications/Xcode.app` (stable 26.6). NEVER the Xcode 27 beta.
- Leave ALL changes uncommitted. Never run git commit/push/add. Never touch: `.supergoal/`, `memory/`, `MEMORY.md`, `plans/`, `agent_planning/`, `CHANGELOG.md`, `project.yml` version fields, `output/`.
- After deleting Swift files you MUST run `xcodegen generate` (auto-runs Scripts/restore-entitlements.sh) before building.
- Shared/ compiles into the watchOS target (arm64_32) — deletions there must keep the watch build green.

## Why

Every item below was verified to have zero production/test call sites during the audit. Dead code inflates compile time, warning surface, and maintainer confusion across four targets.

## Work

### TD-01 — FoundationModelsService dead session path

- `AIPedometer/Core/AI/FoundationModelsService.swift`: stored `session: LanguageModelSession?`, `configureSession()`, `streamResponse(to:)`, and `configure(with:)` have NO callers (both `respond` overloads create one-shot local sessions; the coach owns its own session via `CoachService`).
- Delete the stored session and those three methods; `refreshAvailability()` keeps publishing availability state but drops the session bookkeeping (`session = nil` lines go away with the property).
- DO NOT TOUCH (committed design, HEAD 2c7dbb7): the `systemAvailability` injection seam, `withObservationTracking` observation (`startObservingSystemAvailability`, `handleSystemAvailabilityChange`, `isObservingSystemAvailability`), the public `os_log` availability line, the UI-testing early returns, and both `respond` overloads.
- `FoundationModelsServiceTests` (6 tests) and `BadgeServiceTests` must stay green without modification. NOTE: `BadgeService.configure(with:)` in `AIPedometer/Core/Badges/BadgeService.swift` is a DIFFERENT method on a different type — it stays.

### TD-02 — dead utilities

Delete after printing a repo-wide `rg` zero-call-site proof for each:
- `Shared/Utilities/Hashing.swift` (whole file)
- `Shared/Models/TimeRange.swift` (whole file)
- `Shared/DesignSystem/GlassMorphTransition.swift` (whole file)
- In `Shared/Extensions/View+Glass.swift`: ONLY the helpers with zero call sites (verify each individually; keep any that are used)
- `SyncPolicy.staleDataPruneThreshold` in `AIPedometer/Core/HealthKit/HealthKitSyncService.swift` — production-dead (only tests reference it). Delete the constant AND the tautology test `staleDataPruneThresholdIs30Days`; change the fixture use in `HealthKitSyncServiceTests.swift` (~line 795) to a local literal (`30 * 24 * 60 * 60 + 3600` offset as today, inlined with a comment).

### TD-03 — payoff-less protocols

- Delete `NotificationServiceProtocol` (`AIPedometer/Core/Notifications/NotificationService.swift`) and `HealthKitSyncServiceProtocol` (`AIPedometer/Core/HealthKit/HealthKitSyncService.swift`) declarations and the conformances (concrete classes keep their APIs unchanged). Print rg proof that nothing else references them first.

### DEPS-07 — dead constant

- Delete `AppConstants.UserDefaultsKeys.lastWidgetRefresh` (`Shared/Constants/AppConstants.swift`). Print rg proof first.

## Acceptance criteria (all must pass — verify each in transcript)

1. Every deleted symbol has a printed repo-wide `rg` zero-call-site proof (excluding the symbol's own declaration).
2. Full `AIPedometerTests` green — exact count printed (expected: 592 minus the removed tautology test = 591, plus any tests added in phases 1–4).
3. `AIPedometerWatch` scheme builds clean (arm64_32 coverage for Shared/ deletions).
4. ast-grep scan clean; `xcodegen generate` ran after file deletions and `git status` shows the regenerated project state consistent (no stale file references in build errors).

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test`
- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometerWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (42mm)' build`
- `ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all`

## Evidence required in transcript

- Per-symbol rg proofs (hashing, TimeRange, GlassMorphTransition + View+Glass helpers, staleDataPruneThreshold, both protocols, lastWidgetRefresh, fmService session/streamResponse/configure(with:))
- Test count before/after with the arithmetic explained
- Watch build result
- Any symbol that turned out to have a dynamic caller (string-based lookup, `#selector`, XCUITest accessibility string) — if found, keep it and report instead of deleting

## Notes

- If ANY proof shows a caller, that item leaves the deletion list immediately — report it; do not "fix" the caller to force the deletion.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in .supergoal/PROTOCOL.md without further
instruction needed here.
