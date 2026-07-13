# 006 — Make HealthKit workout export durable and idempotent

**Written against commit** `fa3c252`. Category: correctness / data durability. Confidence: HIGH.
Impact: HIGH. Effort: L. Fix risk: HIGH.

**Status:** DONE in 0.92 (48). Automated migration and idempotency gates pass; the physical forced-failure scenario remains a manual release smoke.

## Implementation result

Schema V2 adds nullable export fields and an explicit lightweight V1→V2 migration. Completion
persists a stable external UUID and pending state before touching HealthKit. HealthKit lookup by
`HKMetadataKeyExternalUUID` makes retries idempotent, and bounded reconciliation runs in initial,
foreground, pull-to-refresh, and background flows. Tests cover migration from an actual V1 store,
failure/retry, remote-commit/local-save recovery, revoked authorization, and eligibility filters.
Concurrent exports share one in-flight task; cancellation stops the batch without recording a
false failure, and retry ordering gives unattempted/newly pending rows a fair turn.

## Why this matters

`WorkoutSessionController.finishWorkout()` persists the completed local `WorkoutSession` before
calling `HealthKitService.saveWorkout(_:)`. If that HealthKit write fails, the failure is logged but
there is no durable retry marker. `HealthKitSyncService.syncWorkouts(from:to:)` is currently empty,
so a transient HealthKit error can leave a locally completed workout permanently absent from
HealthKit. Blind retries are unsafe because the current model has no exported-workout identifier or
idempotency contract and could create duplicates.

## Implementation plan

1. Add explicit export state to `WorkoutSession` through the normal SwiftData schema/migration path:
   pending, exported, and last-failure metadata. Persist the HealthKit workout UUID after success.
2. Make the local transaction mark a completed workout pending before attempting HealthKit export.
3. Give the HealthKit adapter an idempotent lookup contract based on stable app metadata before it
   creates a workout. Never infer success from a matching time range alone.
4. Implement `HealthKitSyncService.syncWorkouts(from:to:)` to retry pending records with bounded
   batches, record failures without deleting local data, and mark success atomically.
5. Trigger reconciliation after HealthKit authorization, foreground sync, and background sync.
6. Add privacy-safe structured logs and metrics for pending/exported/failed counts; do not log route
   samples, HealthKit values, or user identifiers.

## Reproducer-first tests

- A HealthKit save that fails once leaves a durable pending record; recreating the controller/sync
  service and retrying marks it exported.
- Retrying after HealthKit committed but before SwiftData recorded success does not create a second
  workout.
- Revoked authorization preserves the local workout and pending state.
- Reconciliation skips soft-deleted and already-exported sessions.
- Schema migration opens an existing 0.91 store without data loss.

## Done criteria

1. All reproducers fail before the production change and pass afterward.
2. Migration tests and the full simulator suite pass with strict concurrency enabled.
3. A physical-device smoke proves local completion, HealthKit export, relaunch, and no duplicate
   after a forced retry.
4. `FOR_YOU_KNOW.md` documents the export state machine and recovery invariant.
