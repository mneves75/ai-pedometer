# 011 — Preserve workout state and export outcomes across failures

**Written against commit** `cff33ec`. Category: correctness / persistence / HealthKit.
Confidence: HIGH. Impact: HIGH. Effort: L. Fix risk: HIGH.

**Status:** DONE* for 0.94 (50).

## Goal

Ensure skipped HealthKit exports remain reconcilable, process termination cannot leave invisible
unfinished workouts, and startup failures remain visible to the user.

## Constraints

- Preserve the existing idempotent workout-export ledger and SwiftData migration contract.
- Do not fabricate HealthKit identifiers or mark an unsaved workout exported.
- Do not silently discard an unfinished workout or an orphaned Live Activity.
- Keep the app usable when HealthKit sync is disabled or fake-data mode is active.

## Implementation plan

1. Add a failing test showing a nonthrowing fallback/demo HealthKit save without an identifier is
   incorrectly persisted as exported.
2. Replace ambiguous save completion with an explicit exported/deferred/not-required outcome and
   keep deferred rows pending for reconciliation.
3. Add failing fresh-controller tests with a preseeded unfinished workout. Implement launch-time
   reconciliation that surfaces a recover/finish/discard decision and reconciles Live Activity
   state without automatically losing data.
4. Add a failing startup test proving `.unableToStart` is cleared before it can be shown. Separate
   cleanup from user-visible error acknowledgment and surface the error from the workouts screen.
5. Validate persistence migration, export retries, workout state transitions, and UI presentation.

## Done when

- Every reproducer is proven red before its fix and green afterward.
- Deferred exports remain pending; only a real HealthKit identifier produces `.exported`.
- A fresh controller detects and exposes a durable unfinished workout without allowing a hidden
  duplicate session.
- Startup errors remain observable until acknowledged.
- Targeted workout, persistence, HealthKit export, and UI tests pass.

`DONE*`: the release scope above is complete. A later optimization may consolidate remaining
HealthKit history queries, but it is not required for durability or correctness in 0.94.
