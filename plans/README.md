# Improve-deep audits — AIPedometer

Written against commit `d4a2958` (0.91 / build 47). Implemented locally on 2026-07-13.

## Implementation result

All nine findings are implemented. The workout save-failure and overlapping-refresh reproducers
were proven red before the production fixes. The final stable-toolchain verification on an iOS 26.5
simulator passed 504 unit tests and 16 UI tests with zero failures. Static analysis and a Release
simulator build also passed, validating the embedded watch app and widget extension.

Split local `autoreview` passes left the core and app slices clean (confidence 0.84). The operations
slice found one valid malformed-entitlements gate; its reproducer was red before the fix and green
afterward. A final automated rerun was attempted but the review engine reached its usage limit, so
the last two shell-only changes were closed with targeted tests, `shellcheck`, `actionlint`, and the
full script suite rather than an unsupported clean-review claim.

The final signed stable-Xcode device build succeeded and installed AI Pedometer 0.93 (49) on
iMarcus. The forced HealthKit failure/retry/relaunch smoke passed with one durable row and no
duplicate after a second relaunch. A representative walking trace remains a manual observational
check because the user deferred the required physical walk; it is not an unimplemented code path.

The earlier build blockage was a full stdout/stderr pipe in an `SWBBuildService` compiler-capability
probe. Terminating only the blocked probe child allowed the build service to continue. Microsoft
Defender remains an unproven hypothesis, not a confirmed root cause.

A second deep pass on 2026-07-13 found and locally fixed additional bounded correctness, security,
CI/DX, and documentation issues. Plans 006–009 were then implemented with reproducer-first tests,
an explicit SwiftData V1→V2 migration, deterministic adapter/performance seams, and bounded
background reconciliation.

## Verification gate (run for every plan before marking DONE)

```bash
xcodegen generate && Scripts/restore-entitlements.sh
DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' \
  -parallel-testing-enabled NO -only-testing:AIPedometerTests test
```
Warnings-as-errors + strict concurrency are on; a clean build is a hard gate. Prove the reproducer
RED before applying the fix (plans 001), per the repo's reproducer-first rule.

## Execution order & status

| # | Plan | Category | Confidence | Effort | Status |
|---|------|----------|------------|--------|--------|
| 001 | [Workout discard save-failure rollback](001-workout-discard-rollback.md) | correctness / data-loss | MED | S | DONE |
| 002 | [SmartNotificationService test isolation](002-smart-notification-test-isolation.md) | test isolation | HIGH | S | DONE |
| 003 | [WorkoutSessionController save-failure coverage](003-workout-save-failure-coverage.md) | test coverage | HIGH | M | DONE |
| 004 | [Widget data-loader tests](004-widget-data-loader-tests.md) | test coverage | HIGH | S | DONE |
| 005 | [Serialize weekly/streak refresh](005-serialize-weekly-streak-refresh.md) | concurrency | MED (LOW impact) | S | DONE |
| 006 | [Durable, idempotent HealthKit workout export](006-durable-healthkit-workout-export.md) | correctness / data durability | HIGH | L | DONE |
| 007 | [Real HealthKit query-adapter tests](007-healthkit-query-adapter-tests.md) | test coverage | HIGH | M | DONE |
| 008 | [Batch daily-record upserts](008-batch-healthkit-daily-record-upserts.md) | performance | HIGH | M | DONE |
| 009 | [Measure/bound shared-data write rate](009-measure-shared-step-data-write-rate.md) | performance / battery | MED | M | DONE* |

`DONE*`: instrumentation, production policy, and deterministic gates are complete; a representative
walking trace cannot be manufactured by automation and remains a manual device-observation step.

Plan 005 uses latest-request-wins generation counters rather than serializing network-independent
HealthKit reads; stale completions cannot overwrite newer state and newer refreshes are not delayed.

## Considered and rejected / by-design (do not re-audit)

- **SEC-01 SwiftData data-protection = `untilFirstUnlock`** (`PersistenceController.swift:36`) —
  informational, **by-design**. Widgets/background refresh must read the store while the device is
  locked; raising to `.complete` breaks them. Optionally record as an ADR; no code change.
- **`ProgressClamp.percent` no high-side clamp** (`Shared/Utilities/ProgressClamp.swift:11`) — guards
  `isFinite`, clamps low to 0. `Int(...)` would only trap on the watch (Int32) for progress
  >~21.4M× the goal — unreachable with real step/goal data (2M steps / goal 1 = 2e8, still ~10×
  under Int32.max). Not a finding; a high-side clamp would be gold-plating.
- **32-bit overflow class** — swept all of `Shared/` + `AIPedometerWatch/`; the only large constant
  is the already-fixed `ConfettiView` wrapping-`UInt32` hash (0.90). No ms/ns-epoch-in-Int, no
  hash accumulators, no bit-packing in the watch slice.
- **0.89 non-`@Sendable` framework-callback crash class** — clean at every remaining site
  (HealthKit/CoreMotion/WatchConnectivity/BGTask closures are resume-only / `nonisolated`).
- **Continuation double-resume/leak, actor reentrancy, fire-and-forget Task error-drop** — clean.
- Security: GPX parser (XXE off + size/element/text caps), redacted logging, premium fail-closed,
  no network egress, app-group decode guarded (zero `try!`/`as!`) — all confirmed hardened.
- Already fixed at HEAD (do not re-report): distance badges earnable, monthlyChallenge hidden,
  MARKETING_VERSION quoted "0.91", README watch-sync wording, AGENTS.md GUIDELINES-REF sync.
