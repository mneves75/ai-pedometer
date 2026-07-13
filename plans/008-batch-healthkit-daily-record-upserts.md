# 008 — Batch HealthKit daily-record upserts

**Written against commit** `fa3c252`. Category: performance / persistence. Confidence: HIGH.
Impact: MED. Effort: M. Fix risk: MED.

**Status:** DONE in 0.92 (48).

## Implementation result

Each sync range now performs one SwiftData fetch, groups rows by calendar day, updates the newest
active row, inserts only when the day has no row, and intentionally preserves soft-deleted-only
days. Tests lock in one-fetch behavior, existing/new rows, historical goals, soft deletes, and DST
calendar boundaries.

## Why this matters

`HealthKitSyncService` currently resolves persisted daily records inside the per-day loop. A 30-day
sync can issue roughly one SwiftData fetch per summary before saving. The work is bounded, but it
adds avoidable main-actor database latency to foreground and background refreshes.

## Implementation plan

1. Add a regression/performance test that counts fetches for a multi-day sync.
2. Fetch all non-deleted `DailyStepRecord` rows for the requested date interval once.
3. Index them by calendar start-of-day in memory and apply inserts/updates from that dictionary.
4. Preserve historical per-day goal resolution, soft-delete semantics, and one final save.
5. Measure the query count and elapsed signpost before and after with the same 30-day fixture.

## Done criteria

1. The 30-day test uses one range fetch rather than one fetch per day.
2. Existing and new records, DST boundaries, historical goals, and soft-deleted rows behave exactly
   as before.
3. Full simulator suite and strict-concurrency build pass.
