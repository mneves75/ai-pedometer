# 012 — Close day-rollover, Watch ordering, and background cancellation races

**Written against commit** `cff33ec`. Category: concurrency / lifecycle / cross-target correctness.
Confidence: HIGH. Impact: HIGH. Effort: L. Fix risk: MED.

**Status:** DONE* for 0.94 (50).

## Goal

Keep daily step data correct across midnight, prevent delayed WatchConnectivity deliveries from
regressing state, and stop refresh work promptly after background-task expiration.

## Constraints

- Swift 6.2 strict concurrency and warnings-as-errors remain clean.
- Preserve backward decoding for Watch payloads already queued on devices.
- Preserve the latest-value shared-data coalescer and maximum-staleness guarantees.
- Cancellation must not leave partially committed shared state.

## Implementation plan

1. Add a deterministic fixed-calendar regression that crosses midnight while live pedometer
   updates remain active and proves yesterday's cumulative snapshot leaks into today.
2. Restart the live stream from the new start of day and tag callbacks with a generation so late
   callbacks from the prior stream are ignored.
3. Add a backward-compatible sender revision or sent-at ordering field to `WatchPayload`; add
   reversed-delivery tests and ignore stale payloads on watchOS.
4. Add a blocking refresh seam and expiration reproducer. Propagate cancellation into the owned
   serialized refresh task and check cancellation around expensive queries and commits.
5. Run iOS, watchOS, widget, payload-contract, coalescer, and background-task tests.

## Done when

- Midnight rollover starts a new stream and cannot restore yesterday's total.
- An older queued payload cannot replace newer watch state; legacy payloads still decode safely.
- Expiration cancels the actual refresh and prevents post-expiration state writes.
- Targeted concurrency tests and cross-target builds pass with strict concurrency enabled.

`DONE*`: the bounded release races are fixed. Future hardening may cap the lifetime generation
counter and add an explicit widget-freshness presentation policy; neither residual can regress
current state ordering or background cancellation in 0.94.
