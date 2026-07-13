# 001 — Roll back the in-memory soft-delete when a workout discard save fails

**Written against commit** `d4a2958`. Category: correctness / silent data loss. Confidence: MED
(clear code reading; the triggering save-failure is rare). Effort: S. Fix risk: LOW.

**Status:** DONE on 2026-07-13. The red reproducer now passes, and the controller restores the
session mutation while preserving an active workout when persistence fails.

## Why this matters

`WorkoutSessionController.discardWorkout()` mutates the live SwiftData model **before** it saves,
and on save failure it returns without rolling back that mutation. The session is left in an
inconsistent in-memory state: still `.active` per the state machine, but already carrying
`deletedAt`. If the user then taps **Finish** instead of retrying Discard, the finished row is
persisted with both `endTime` and `deletedAt` set — it is soft-deleted, so it disappears from every
`deletedAt == nil` query. The user's completed workout silently vanishes.

Every other mutate-then-save path in the codebase already rolls back on failure. The canonical
example is `TrainingPlanService.applyPlanMutation` (`AIPedometer/Core/AI/Services/TrainingPlanService.swift:326-343`):
it snapshots `status`/`endDate`/`updatedAt`/`deletedAt`, mutates, saves, and restores all four
fields in the `catch`. `discardWorkout` is the one place that skips this.

## Current state (exact)

`AIPedometer/Core/Workouts/WorkoutSessionController.swift:262-282`:

```swift
    func discardWorkout() async {
        guard let session = activeSession else {
            lastError = .sessionUnavailable
            transition(.error(.unableToSave))
            return
        }

        await endLiveMetrics()
        session.deletedAt = now()
        session.updatedAt = now()

        do {
            try saveModelContext(modelContext)
        } catch {
            lastError = .discardFailed(error.localizedDescription)
            return
        }

        transition(.discard)
        resetSession()
    }
```

`WorkoutSession` fields (`AIPedometer/Core/Persistence/Models/WorkoutSession.swift:15-16`):
`var updatedAt: Date`, `var deletedAt: Date?`.

## The fix (exact replacement for lines 262-282)

```swift
    func discardWorkout() async {
        guard let session = activeSession else {
            lastError = .sessionUnavailable
            transition(.error(.unableToSave))
            return
        }

        await endLiveMetrics()
        // Snapshot before mutating so a failed save can roll the soft-delete back. Otherwise the
        // session stays .active in memory but carries deletedAt, and a subsequent finishWorkout
        // persists a finished-AND-soft-deleted row that vanishes from every deletedAt == nil query.
        // Mirrors TrainingPlanService.applyPlanMutation's rollback-on-save-failure.
        let previousDeletedAt = session.deletedAt
        let previousUpdatedAt = session.updatedAt
        session.deletedAt = now()
        session.updatedAt = now()

        do {
            try saveModelContext(modelContext)
        } catch {
            session.deletedAt = previousDeletedAt
            session.updatedAt = previousUpdatedAt
            lastError = .discardFailed(error.localizedDescription)
            return
        }

        transition(.discard)
        resetSession()
    }
```

Behavior on the **success** path is byte-for-byte identical (snapshot + assign nets the same final
state). Only the **failure** path changes: it now restores the pre-discard field values. No other
method is touched.

## Reproducer test (write FIRST, prove it RED before applying the fix)

Add to `AIPedometerTests/Workouts/WorkoutSessionControllerTests.swift` inside the
`WorkoutSessionControllerTests` struct (place it after
`finishWorkoutSeparatesHealthKitIdPersistenceFailure`, before the closing brace of the struct at
line 323). It uses the existing `saveModelContext:` injection seam and the existing
`MockMetricsSource`/`WorkoutSessionHealthKitStub` helpers already in this file:

```swift
    @Test
    func discardSaveFailureRollsBackInMemorySoftDelete() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        // Force refreshMetrics() to early-return so start performs exactly one save,
        // making the discard save deterministically the 2nd saveModelContext call.
        metricsSource.snapshotErrorToThrow = MotionError.noData
        let liveActivity = MockLiveActivityManager()
        let healthKit = WorkoutSessionHealthKitStub()
        var saveCalls = 0
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity,
            saveModelContext: { context in
                saveCalls += 1
                if saveCalls == 2 { // the discard save
                    throw CocoaError(.validationMultipleErrors)
                }
                try context.save()
            }
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil) // save #1 (ok)
        await controller.discardWorkout()                                    // save #2 (throws)

        #expect(controller.lastError?.id.contains("discardFailed") == true)

        // The soft-delete must have been rolled back: a later finishWorkout must not be able to
        // persist a finished-AND-deleted row that disappears from deletedAt == nil queries.
        let sessions = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.deletedAt == nil)
    }
```

Expected without the fix: `sessions.first?.deletedAt == nil` is **false** (deletedAt was set in
memory and never rolled back) → test RED. With the fix: deletedAt is restored to nil → GREEN.

Notes locking the save-count assumption (verify if the test miscounts):
- `startWorkout` saves once (`WorkoutSessionController.swift:124`); `requestAuthorization` and
  `metricsSource.start` don't save; `refreshMetrics` early-returns on `MotionError.noData`
  (`:290-291`) so it performs no save — mirrors the existing
  `finishWorkoutSeparatesHealthKitIdPersistenceFailure` test's use of `snapshotErrorToThrow`.
- `discardWorkout` saves once (`:274`). So save #2 is the discard save.
- `.discardFailed(message).id` = `"discardFailed-\(message)"` (`:20-21`), so `.contains("discardFailed")` holds.

## Scope

- **In scope:** `discardWorkout()` body only, plus the one new test.
- **Out of scope:** `finishWorkout`, `startWorkout`, the state machine, `resetSession`. Do NOT add a
  new `(.failed, …)` transition or change any success-path behavior.

## Done criteria

1. New test present and RED before the fix, GREEN after (prove both).
2. Full `AIPedometerTests` suite green under the verification gate in `plans/README.md`.
3. No new warnings (warnings-as-errors build stays clean).

## Maintenance note

If a future change makes `discardWorkout` mutate additional `WorkoutSession` fields, extend the
snapshot/restore set to cover them — the rollback must restore every field the mutation touched, the
same contract `applyPlanMutation` maintains.

## Escape hatch

If `saveCalls == 2` does not correspond to the discard save when you run it RED (e.g. the count is
off), do not guess — add a `print(saveCalls)` probe or assert on `deletedAt` after each step to find
the real discard-save index, then set the throw condition accordingly. Report back rather than
loosening the assertion.
