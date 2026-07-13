# 009 — Measure and bound shared step-data persistence writes

**Written against commit** `fa3c252`. Category: performance / battery. Confidence: MED.
Impact: MED. Effort: M. Fix risk: MED.

**Status:** DONE in code/tests for 0.92 (48). A representative walking trace still requires a person carrying the physical device.

## Implementation result

Privacy-safe signposts cover encoding, app-group writes, widget reload requests, and watch sends.
Production uses a latest-value coalescer with five-second maximum staleness; day/goal/streak/week
changes, 100-step milestones, and lifecycle backgrounding bypass the delay. Deterministic tests
prove coalescence, latest-value retention, obsolete-timer invalidation, bounded delay after a
wall-clock rollback, background/widget-boundary durability, maximum delay, and immediate milestone
flush. The remaining device trace is observational validation, not an unimplemented code path.

## Why this matters

`StepTrackingService.updateSharedData()` JSON-encodes and writes app-group `UserDefaults`, then
sends WatchConnectivity data. Live pedometer callbacks can call this frequently. The code is
correct, but the actual write rate and battery cost have not been measured; an arbitrary debounce
could make widgets or the watch visibly stale.

## Implementation plan

1. Add privacy-safe signposts/counters around encoding, app-group writes, widget reload requests,
   and watch sends. Do not include step totals or identifiers in signpost payloads.
2. Capture a representative physical-device trace while walking and during a foreground refresh.
3. If the measured rate is material, introduce a latest-value coalescer with explicit maximum
   staleness and immediate flushes for goal/settings changes, workout terminal events, backgrounding,
   and significant milestones.
4. Add deterministic clock-based tests for coalescing, maximum delay, and immediate flush paths.

## Done criteria

1. Before/after device evidence records callback, encode, write, widget reload, and watch-send rates.
2. Any throttle has a documented maximum staleness and cannot lose the latest value.
3. Widget/watch contract tests, full simulator suite, and device smoke pass.
