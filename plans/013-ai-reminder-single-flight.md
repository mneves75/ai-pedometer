# 013 — Make AI analysis and smart reminders latest-state safe

**Written against commit** `cff33ec`. Category: concurrency / AI / notifications.
Confidence: HIGH. Impact: MED. Effort: M. Fix risk: MED.

**Status:** DONE* for 0.94 (50).

## Goal

Prevent overlapping weekly analysis from caching fallback over a successful generation and prevent
an old notification-authorization task from scheduling after premium/AI eligibility was revoked.

## Constraints

- AI remains fully on-device through Foundation Models.
- Premium gating remains fail-closed.
- Do not weaken useful fallback content when no generation is in flight.
- Notification permission denial remains a non-crashing, recoverable state.

## Implementation plan

1. Add a deterministic overlapping-analysis test where a follower finishes after the primary AI
   generation and currently overwrites the cache.
2. Implement single-flight or generation ownership so followers await/return without mutating the
   successful result; a third call must receive the generated analysis.
3. Add a suspended-authorization test that revokes premium, disables AI, or toggles the setting off
   before permission returns.
4. Re-check current preference and eligibility after suspension and use cancellable/latest-wins
   ownership before scheduling.
5. Run InsightService, History, premium gate, and SmartNotificationService tests.

## Done when

- Both race reproducers fail on the old behavior and pass after the fix.
- No in-flight fallback overwrites generated analysis or shared error state.
- Revoked or disabled smart reminders cannot be scheduled by stale work.
- Relevant AI, history, settings, and notification tests pass under strict concurrency.

`DONE*`: the single-flight and stale-authorization scope is complete. Removing an unused cached
Foundation Models session remains a cleanup opportunity, not a correctness or release blocker.
