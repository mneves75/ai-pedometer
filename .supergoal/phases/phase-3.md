SUPERGOAL_PHASE_START
Phase: 3 of 8 — Perf quick wins
Task: Fix four confirmed waste sites on hot paths without altering observable behavior
Type: brownfield, perf
Mandatory commands: DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test, ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all
Acceptance criteria: 5
Evidence required: per-fix red/green or measurement, behavior-change note
Depends on phases: none

## Shared context (read first)

- Repo: /Users/mneves/dev/PROJETOS_MOBILE/ai-pedometer. Swift 6.2 strict concurrency, warnings-as-errors, Swift Testing.
- TOOLCHAIN: every xcodebuild MUST use `DEVELOPER_DIR=/Applications/Xcode.app` (stable 26.6). NEVER the Xcode 27 beta.
- Leave ALL changes uncommitted. Never run git commit/push/add. Never touch: `.supergoal/`, `memory/`, `MEMORY.md`, `plans/`, `agent_planning/`, `CHANGELOG.md`, `project.yml` version fields, `output/`.
- DO NOT touch `StepTrackingService.refreshChain` — inter-refresh serialization is a documented, deliberate contract. This phase is INTRA-refresh only.

## Why

Four vetted waste sites: Live Activity pushed every 5s tick for whole workouts; four independent HealthKit queries serialized inside the hottest refresh; History forcing full weekly AI re-analysis on every load and nullifying its cache; unbounded SwiftData fetches on background-refresh paths.

## Work

### PERF-01 — throttle Live Activity updates

- `AIPedometer/Core/Workouts/WorkoutSessionController.swift`: `updateMetrics(from:)` awaits `liveActivityManager.update(...)` unconditionally on every metrics tick (default interval 5s).
- Fix: decouple LA cadence from the metrics loop — track last-sent timestamp/steps and skip updates below an interval (15–30s) or a step delta (~25), ALWAYS updating on state transitions (start/pause/resume/finish/discard). Mirror the existing `shouldReloadWidgets` pattern in `StepTrackingService.swift:759-781`. Expedition Mode behavior must not change.

### PERF-02 — parallelize intra-refresh queries

- `AIPedometer/Core/StepTracking/StepTrackingService.swift` `performRefreshTodayData`: after `fetchSteps`, `resolveDistance`/`resolveFloors`/`resolveLatestHeartRate` are awaited serially though only distance depends on steps.
- Fix: after fetchSteps, bind the three with `async let` and await the tuple. Keep every existing `Task.isCancelled` guard after the join. Apply the same shape to the wheelchair branch only if it has the identical serial pattern; otherwise leave it.

### PERF-03 — History uses its weekly cache

- `AIPedometer/Features/History/HistoryView.swift`: `loadData()` calls `loadWeeklyAnalysis(forceRefresh: true)` unconditionally, so every load-trigger flip re-runs HealthKit weekly queries + a full on-device inference even when the week cache is valid (`InsightService` has a week-start-keyed cache + day-rollover invalidation).
- Fix: the automatic load path passes `forceRefresh: false`; explicit pull-to-refresh keeps `forceRefresh: true` (split the refreshable path out of shared `loadData()` if needed). User-visible content must not change for a same-week revisit.

### PERF-07 — bound the export fetches

- `AIPedometer/Core/HealthKit/HealthKitSyncService.swift`: `hasPendingWorkoutExports()` fetches ALL pending rows to answer `.contains`; `syncWorkouts` candidate fetch has no limit and permanently matches `.notRequired` rows (they keep `healthKitWorkoutID == nil`).
- Fix: existence check → `fetchCount` (or `fetchLimit = 1`) with the full in-memory filter semantics preserved; candidate fetch → fold `endTime != nil` and `healthKitExportStateRaw == pending` into the `#Predicate` (both stored), keep the existing in-memory multi-key sort + `prefix(20)` batching.

## Acceptance criteria (all must pass — verify each in transcript)

1. LA update skipped below interval/delta and always sent on state transitions (test or instrumentation evidence).
2. The three queries run concurrently (test seam or timing evidence) and cancellation guards are intact; `refreshChain` untouched (diff shows no change to it).
3. Repeat History visits within the same week trigger no new inference (test or log evidence); pull-to-refresh still regenerates.
4. Existence check issues a bounded query; candidate predicate excludes `.notRequired`/unfinished rows in SQLite (test evidence via HealthKitSyncServiceTests).
5. Full `AIPedometerTests` green; ast-grep scan clean (tail output + exit codes).

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests/WorkoutSessionControllerTests -only-testing:AIPedometerTests/HealthKitServiceTests -only-testing:AIPedometerTests/HealthKitSyncServiceTests -only-testing:AIPedometerTests/InsightServiceTests test`
- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test`
- `ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all`

## Evidence required in transcript

- Per-fix: what changed, behavior unchanged proof, and any red→green test
- One line per fix: expected user-visible effect (should be "none" for all four)

## Notes

- If a throttle constant needs a home, put it next to the code it throttles (no new config files).
- If PERF-02's `async let` trips a Swift 6 sendability diagnostic, STOP and report the diagnostic instead of working around it with unsafe constructs.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in .supergoal/PROTOCOL.md without further
instruction needed here.
