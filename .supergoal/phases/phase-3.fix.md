# Phase 3 focused fix spec — SwiftData predicate compiler timeout

## Scope

Target only `HealthKitSyncService.pendingWorkoutExportDescriptor`. Do not touch unrelated files or weaken the required eligibility semantics.

## Procedure

1. Run a quiet stable-Xcode build to capture the exact predicate diagnostic.
2. Restructure the database predicate into a form Swift 6.2 can type-check.
3. Preserve all four database-side conditions: not deleted, no HealthKit identifier, completed, and raw export state pending.
4. Keep `fetchCount` with `fetchLimit = 1`, and keep candidate in-memory retry ordering plus `prefix(20)`.

## Success gate

Re-run the original phase VERIFY block:

- Focused WorkoutSessionController, HealthKitService, HealthKitSyncService, and InsightService suites pass.
- Full `AIPedometerTests` pass.
- `ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all` passes.
- All five phase criteria and cleanliness checks pass.
