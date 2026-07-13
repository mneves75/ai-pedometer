# Improve-deep audit — AIPedometer

Written against commit `d4a2958` (0.91 / build 47). Advisor: main session (Fable-orchestrator
routing). Audit fanned out over 4 read-only Explore subagents (concurrency, 32-bit/time,
security, correctness+test-gaps). Every finding below was **vetted against the real code by the
advisor** before being written here — subagent line numbers were treated as leads, not facts.

## Why these are plans and not commits

The simulator build is **environment-blocked** on this host: `xcodebuild` wedges deterministically
during build-planning when `SWBBuildService` invokes its `clang -v -E -dM` compiler probe — the
`clang` child hangs 100% in a `write()` syscall (pipe not drained by the service), 0% CPU,
reproduced 4× independent of host load. Microsoft Defender's Endpoint Security extension (`epsext`,
hooking `exec`) is the prime suspect. The same `clang` probe runs standalone in 0.038 s. This is a
host toolchain/AV-integration defect, **not** an AIPedometer code defect, and cannot be fixed
without excluding Xcode/DerivedData from Defender (admin/MDM, out of session scope).

Because nothing can be build-verified here, no source was edited and nothing was committed. Each
plan below inlines the exact patch and the exact reproducer test so it can be applied, built, and
verified in a single pass once the host is quiet (or Defender excludes `~/Library/Developer/Xcode`).

## Verification gate (run for every plan before marking DONE)

```bash
xcodegen generate && Scripts/restore-entitlements.sh
DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO -only-testing:AIPedometerTests test
```
Warnings-as-errors + strict concurrency are on; a clean build is a hard gate. Prove the reproducer
RED before applying the fix (plans 001), per the repo's reproducer-first rule.

## Execution order & status

| # | Plan | Category | Confidence | Effort | Status |
|---|------|----------|------------|--------|--------|
| 001 | [Workout discard save-failure rollback](001-workout-discard-rollback.md) | correctness / data-loss | MED | S | TODO |
| 002 | [SmartNotificationService test isolation](002-smart-notification-test-isolation.md) | test isolation | HIGH | S | TODO |
| 003 | [WorkoutSessionController save-failure coverage](003-workout-save-failure-coverage.md) | test coverage | HIGH | M | TODO |
| 004 | [Widget data-loader tests](004-widget-data-loader-tests.md) | test coverage | HIGH | S | TODO |
| 005 | [Serialize weekly/streak refresh](005-serialize-weekly-streak-refresh.md) | concurrency | MED (LOW impact) | S | TODO |

No hard dependencies between plans; 001 and 002 are the highest leverage. 003 characterizes the
same code 001 fixes — land 001 first, then 003's tests document the recovered behavior.

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
