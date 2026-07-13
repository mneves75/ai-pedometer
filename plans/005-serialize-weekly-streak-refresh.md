# 005 — Serialize weekly-summary and streak refreshes to avoid stale published state

**Written against commit** `d4a2958`. Category: concurrency. Confidence: MED. Impact: LOW
(staleness/flicker, not corruption). Effort: S. Fix risk: LOW.

## Why this matters

`StepTrackingService.refreshTodayData` is serialized through a `refreshChain` `Task` (protecting it
against overlap — `AIPedometer/Core/StepTracking/StepTrackingService.swift:122-137`). But two sibling
refreshes are **not** on that chain:

- `refreshWeeklySummaries()` (`:276`) awaits `healthKitService.fetchDailySummaries(...)` (`:301`)
  then writes `weeklySummaries` (`:308`) and calls `updateSharedData()`.
- `refreshStreak()` (`:264`) awaits `streakCalculator.calculateCurrentStreak()` then writes
  `currentStreak` (`:267`) and `updateSharedData()`.

Concurrent entry points that can overlap these: `applySettingsChange()` (`:117-119`),
`updateGoalAndRefresh()` (`:339-344`), and view-driven refreshes (`SettingsView.swift:99/158/200/244`,
`HistoryView`). Two overlapping runs each suspend at the HealthKit `await`, then resume and write
`weeklySummaries`/`currentStreak` last-writer-wins. The older result can land after the newer one, so
the chart/streak and the `SharedStepData` pushed to the widget + watch briefly show a stale value
until the next clean refresh. Each individual mutation is atomic between awaits (`updateSharedData`
at `:642` has no internal `await`), so this is staleness, not corruption.

This is distinct from documented finding-085 (live-CMPedometer-tick interleave with
`refreshTodayData`), which is deliberately not fixed — do not touch that.

## Fix options (pick the smaller that fits the existing style)

**Option A — extend the existing serialization chain.** Route `refreshWeeklySummaries` and
`refreshStreak` through the same serialize-after-previous `Task` chain used by `refreshTodayData`
(`:130`). Confirm the exact chain mechanism there and reuse it so all three refreshes serialize
against one another. Lowest conceptual surface; matches the established pattern.

**Option B — generation counter.** Give each of the two methods a monotonically increasing
generation token captured before the `await`; after the `await`, drop the write if a newer generation
has started. This preserves concurrency but discards superseded writes. Use only if serializing (A)
would regress a latency requirement (it should not — these are background refreshes).

Prefer **A** for consistency with `refreshTodayData`.

## Verify before implementing

Read `refreshTodayData` and the `refreshChain` definition (`:122-137`) to learn the exact chaining
idiom (it may be an `actor`-less `Task`-append pattern or a stored `Task` that the next call awaits).
Match it precisely; do not invent a new synchronization primitive.

## Test

Add a test in `AIPedometerTests` (near the existing `StepTrackingService` tests) that issues two
overlapping refreshes with a mock HealthKit whose `fetchDailySummaries` for the *first* call resolves
*after* the second (e.g. gate the first behind a continuation the test releases last), and assert the
final `weeklySummaries` reflects the **second** (newest) call's data, not the first. Mirror the
blocking-stub technique already used by `BlockingWorkoutSessionHealthKitStub`
(`WorkoutSessionControllerTests.swift:417-475`).

## Scope

- **In scope:** `refreshWeeklySummaries` + `refreshStreak` serialization, plus the overlap test.
- **Out of scope:** `refreshTodayData`, finding-085's CMPedometer interleave, `updateSharedData`.

## Done criteria

1. Overlap test green: newest write wins deterministically.
2. Full `AIPedometerTests` suite green under the `plans/README.md` gate.
3. No new warnings; strict-concurrency clean.

## Maintenance note

If more `@Observable` refreshers are added to `StepTrackingService`, they should join the same chain
— the invariant is that all writers of published aggregate state serialize so the widget/watch never
observe an out-of-order snapshot.
