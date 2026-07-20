# 016 — Close purchase, HealthKit, and async-test coverage gaps

**Written against commit** `cff33ec`. Category: tests / payments / HealthKit / determinism.
Confidence: HIGH. Impact: HIGH. Effort: L. Fix risk: MED.

**Status:** DONE* for 0.94 (50).

## Goal

Exercise the untested money-moving and HealthKit adapter branches and replace timing-dependent
concurrency assertions with deterministic handshakes where current tests can flake under load.

## Constraints

- Do not make a real purchase, publish TestFlight, use credentials, or call production services.
- Do not weaken fail-closed premium behavior or transaction verification.
- Preserve the real HealthKit query semantics; add the minimum executor/descriptor seam needed for
  deterministic tests rather than replacing the framework adapter with a fake implementation.
- Timeouts may remain only as safety bounds, not as the event-ordering mechanism under test.

## Implementation plan

1. Complete unit matrices for `PremiumAccessStore.purchase`, `syncPurchases`, and `TipJarStore`
   success, pending, cancellation, verification failure, unknown result, and client error branches.
2. Use the existing local StoreKit configuration for any deterministic Tip Jar integration path it
   supports; keep RevenueCat sandbox/TestFlight purchase/restore as an explicit external manual gate.
3. Extract a minimal HealthKit statistics-query descriptor/executor boundary from
   `StepDataAggregator` and test predicate/anchor, empty/error, timezone day buckets, and source
   aggregation against the concrete mapping code.
4. Replace fixed sleeps in Coach streaming, background expiration, and Tip Jar stream tests with
   continuations/probes or injected clock/scheduler signals. Keep bounded timeout failure messages.
5. Run each targeted suite repeatedly before the full suite to prove deterministic behavior.

## Done when

- Every enumerated purchase/sync/Tip Jar branch has an assertion on state, entitlement, or error.
- Concrete `StepDataAggregator` query construction and result mapping are covered without querying
  private user health data.
- The audited async tests no longer use fixed sleeps to order events.
- Targeted suites pass repeatedly and the full stable-Xcode unit/UI gates pass.

`DONE*`: event ordering is continuation-driven and every wait has a bounded diagnostic deadline.
Those deadlines remain safety gates by design; converting them to an injected clock is optional
unless a future reproducer shows timing sensitivity.
