# 007 — Test the real HealthKit query adapters

**Written against commit** `fa3c252`. Category: test coverage. Confidence: HIGH. Impact: MED.
Effort: M. Fix risk: LOW.

**Status:** DONE in 0.92 (48).

## Implementation result

Quantity-query construction is represented by an injectable specification that fixes type, unit,
aggregation, and strict-start predicate behavior. Injected sum and daily-total executors prove
exactly-once nil conversion, cancellation propagation, calendar-day conversion, and step/distance/
floor units. Existing authorization, fallback, workout-sample, and error-mapping suites cover the
remaining adapter contracts; real-store authorization remains device-only.

## Why this matters

Most service tests use protocol doubles. They validate orchestration but not the adapters that build
and execute `HKStatisticsQuery`, `HKStatisticsCollectionQuery`, workout, and authorization requests.
Predicate boundaries, aggregation options, unit conversions, and continuation completion can drift
without a deterministic test failing.

## Implementation plan

1. Extract only the HealthKit query construction/execution seams needed to inject a query executor;
   keep the public `HealthKitServiceProtocol` unchanged.
2. Unit-test the generated predicates, anchors, options, units, and result conversion for steps,
   distance, flights, summaries, and workout export.
3. Exercise nil result, HealthKit error, cancellation, and exactly-once continuation completion.
4. Keep a small physical-device integration smoke for authorization and one read because the
   simulator cannot prove real HealthKit store behavior.

## Done criteria

1. Tests fail when a predicate boundary, unit, or aggregation option is intentionally wrong.
2. Every async adapter completes exactly once for success, nil result, error, and cancellation.
3. Full simulator suite passes; device-only limitations are stated separately.
