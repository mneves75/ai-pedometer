SUPERGOAL_PHASE_START
Phase: 1 of 8 — Correctness: goal save + sync windows
Task: Fix goal-save split-brain and sync-window off-by-one
Type: brownfield, bugfix
Mandatory commands: DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test, ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all
Acceptance criteria: 5
Evidence required: red test output before fix, green after, bucket-count assertions
Depends on phases: none

## Shared context (read first)

- Repo: /Users/mneves/dev/PROJETOS_MOBILE/ai-pedometer. Swift 6.2 strict concurrency, warnings-as-errors, Swift Testing (not XCTest) for unit tests.
- TOOLCHAIN: every xcodebuild MUST use `DEVELOPER_DIR=/Applications/Xcode.app` (stable 26.6). The default xcode-select points at Xcode 27 beta; the pinned RevenueCat does NOT compile there.
- Leave ALL changes uncommitted. Never run git commit/push/add. Never touch: `.supergoal/`, `memory/`, `MEMORY.md`, `plans/`, `agent_planning/`, `CHANGELOG.md`, `project.yml` version fields, `output/`.
- New/deleted Swift files require `xcodegen generate` before building.
- Repo discipline: reproducer-first — write the failing test, prove red, then fix, prove green.

## Why

Two confirmed data-integrity defects: (1) a failed SwiftData save still publishes the new goal to UI/widget/watch (split-brain until relaunch); (2) sync windows computed with fixed-second subtraction produce 31/8 day-buckets for advertised 30/7-day windows, plus a DST edge.

## Work

### COR-01 — goal save failure must not publish

Current state (verified):
- `AIPedometer/Core/StepTracking/StepTrackingService.swift` `updateGoal(_:)`: calls `goalService.setGoal(goal)` then UNCONDITIONALLY assigns `currentGoal = goal` and `updateSharedData()`.
- `AIPedometer/Core/Goals/GoalService.swift` `setGoal(_:)`: on `saveModelContext(context)` failure it rolls back (`context.delete(goal)` + restores previous active-goal state) and only LOGS the failure — the caller cannot tell it failed. Existing test `GoalServiceTests.setGoalRemovesPendingChangesWhenSaveFails` proves the model rollback.

Required change:
1. Make `setGoal` report the outcome (return `Bool` or throw after rollback — pick whichever matches the protocol's style; `GoalServiceProtocol` and its test fake must be updated consistently).
2. `StepTrackingService.updateGoal` publishes `currentGoal` + `updateSharedData()` ONLY on success; on failure keep the previous goal and surface a localized failure state consistent with how the goal editor reports other errors (inspect the settings/goal-edit call sites first and preserve their UX contract).
3. Keep the existing rollback behavior and its test green.

Test plan (red first): inject a failing save (follow the existing `setGoalRemovesPendingChangesWhenSaveFails` seam) → assert `currentGoal` and shared data still hold the previous durable goal → then fix and go green. Also assert the success path still publishes.

### COR-03 — sync windows use calendar-day arithmetic

Current state (verified):
- `AIPedometer/Core/HealthKit/HealthKitSyncService.swift`: cold start uses `Date.now.addingTimeInterval(-SyncPolicy.coldStartWindow)` (30*24*3600); pull-to-refresh uses `-SyncPolicy.pullToRefreshWindow` (7*24*3600).
- `AIPedometer/Core/HealthKit/HealthKitService.swift` range overload normalizes that timestamp to `calendar.startOfDay` and emits summaries `while current <= endDay` → 31 and 8 buckets respectively.
- The sibling API `fetchDailySummaries(days:)` already uses the correct inclusive convention `-(days - 1)` calendar days from the end-day.

Required change:
1. Construct cold-start and pull-to-refresh start dates with the injected calendar at `-(count - 1)` calendar days from `startOfDay(now)`, matching the `days:` API convention.
2. Keep incremental-overlap behavior and all existing guards unchanged.

Test plan (red first): fixed-clock tests asserting exactly 30 and 7 daily buckets; DST spring-forward and fall-back boundaries yield the same counts. Look for an existing clock injection seam in HealthKitSyncService tests before inventing one.

## Acceptance criteria (all must pass — verify each in transcript)

1. Failing-save injection leaves `currentGoal` and shared/widget state at the previous durable goal (test output shown).
2. Successful goal change still publishes everywhere (existing goal tests green).
3. Cold-start window produces exactly 30 calendar buckets; pull-to-refresh exactly 7 (test output shown).
4. DST spring + fall tests produce the same bucket counts (test output shown).
5. Full `AIPedometerTests` suite green and ast-grep scan clean (tail output + exit codes shown).

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests/GoalServiceTests -only-testing:AIPedometerTests/HealthKitSyncServiceTests test`
- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test`
- `ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all`

## Evidence required in transcript

- Red test output (both fixes) captured before production changes
- Green test output after
- The exact bucket-count assertions
- Note if `GoalServiceProtocol` fake needed changes and why

## Notes

- Do NOT change the rollback logic inside `setGoal` — it is proven by an existing test.
- If the goal editor's error-presentation contract is unclear, STOP and report the options instead of inventing new UX.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in .supergoal/PROTOCOL.md without further
instruction needed here.
