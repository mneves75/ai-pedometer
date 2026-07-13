# 003 — Characterize WorkoutSessionController save-failure branches

**Written against commit** `d4a2958`. Category: test coverage (data-mutation critical path).
Confidence: HIGH (coverage gap confirmed). Effort: M. Fix risk: LOW (test-only). **Land plan 001 first.**

**Status:** DONE on 2026-07-13. Start, resume, finish, and discard save failures have retry-safety
coverage; the reproducers exposed real mutation-order bugs that were fixed in production code.

## Why this matters

`WorkoutSessionControllerTests.swift` (12 tests) covers happy-path start/pause/resume/finish/discard
and the *second* (HealthKit-id) save in finish
(`finishWorkoutSeparatesHealthKitIdPersistenceFailure`, `:296-322`). It does **not** cover the three
primary SwiftData save-failure branches on the money path:

- `startWorkout` first-save failure — `WorkoutSessionController.swift:123-129` (→ `.error(.unableToSave)`).
- `finishWorkout` first-save failure — `:225-231` (→ `.failed`, **retains `activeSession`**).
- `discardWorkout` save failure — `:273-278` (the branch plan 001 fixes).

These are unpinned, so a refactor can regress the recovery behavior undetected. The finish
first-save-failure case is the sharpest: it transitions to `.failed` while keeping `activeSession`,
`startWorkout` early-returns because `activeSession != nil` (`:113-116`), and `WorkoutStateMachine`
has no `(.failed, .finish)` transition (`WorkoutStateMachine.swift:41-66`) — so a retried finish
can't reach `.completed`. Whether that is the intended recovery UX is a product question; either way
it must be characterized so it can't drift silently.

## What to add

Add tests to `AIPedometerTests/Workouts/WorkoutSessionControllerTests.swift` using the existing
`saveModelContext:` injection seam (see `:302-315` for the pattern) and the existing
`MockMetricsSource`/`WorkoutSessionHealthKitStub` helpers. Set `metricsSource.snapshotErrorToThrow =
MotionError.noData` so `refreshMetrics` performs no save and the save-call indices are deterministic
(start = save #1).

1. **`startWorkoutFirstSaveFailureSurfacesErrorAndDoesNotActivate`** — throw on `saveCalls == 1`.
   Assert: `controller.lastError?.id.contains("saveFailed") == true`; `!controller.isActive`;
   `controller.activeSession == nil` (verify the property's visibility — if `activeSession` is not
   test-visible, assert via `!controller.isPresenting` / `controller.state == .idle` and a
   `fetch(FetchDescriptor<WorkoutSession>())` count reflecting the failed insert per SwiftData
   semantics).

2. **`finishFirstSaveFailureRetainsSessionAndReportsFailure`** — start (save #1 ok), then throw on
   the finish first-save (`saveCalls == 2`). Assert: `lastError?.id.contains("saveFailed") == true`;
   the state after the failed finish (characterize whatever it actually is — likely `.failed`); and
   that a subsequent `startWorkout` is a no-op because a session is still active (assert
   `metricsSource.startCount` did not increase, or `isPresenting == true`). This test documents the
   current recovery behavior; if the team decides that behavior is a bug, that becomes a follow-up
   plan — this test simply locks today's contract.

3. **`discardSaveFailureRollsBackInMemorySoftDelete`** — already specified in plan 001; if 001 landed
   it, do not duplicate.

## Scope

- **In scope:** new tests in `WorkoutSessionControllerTests.swift`.
- **Out of scope:** production code. If a test reveals behavior the team wants changed, write a new
  plan — do not change `WorkoutSessionController` under this plan (except via plan 001).

## Done criteria

1. New tests green under the `plans/README.md` verification gate.
2. Each asserts on `lastError`, resulting `state`, and post-failure recoverability.
3. No production change in this plan; no new warnings.

## Escape hatch

If `activeSession` is `private` and not observable from tests, characterize recovery through the
public surface (`isPresenting`, `isActive`, `state`, and a subsequent `startWorkout` being a no-op)
rather than exposing internals — do not widen access just for the test.
