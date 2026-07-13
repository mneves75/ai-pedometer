# 004 — Test the widget data loader and the app↔widget payload contract

**Written against commit** `d4a2958`. Category: test coverage. Confidence: HIGH (zero coverage
confirmed). Effort: S. Fix risk: LOW (test-only).

## Why this matters

No test references `WidgetDataLoader`, `StepTimelineProvider`, or `WidgetDataProvider` (grep over
`AIPedometerTests` returns none). `AIPedometerWidgets/Shared/WidgetDataProvider.swift:14-25` swallows
a decode failure and returns `nil`; `getTimeline` (`:49-54`) then ships `WidgetStepEntry(data: nil)`
with a 30-minute refresh policy, and the widget views must render that nil. The two branches that
produce a visibly broken widget on a real home screen — corrupt payload and missing data — are
untested, and so is the JSON round-trip contract between the app's `SharedStepData` writer and the
widget's decoder. A schema drift there silently degrades every widget to placeholder/blank with no
test catching it.

## What to add

`WidgetDataLoader.loadSharedData()` is a static function over an injectable app-group
`UserDefaults` suite (confirm the exact injection point in
`AIPedometerWidgets/Shared/WidgetDataProvider.swift` / `WidgetDataLoader`), so it is testable without
WidgetKit. Add a test file `AIPedometerTests/Widgets/WidgetDataProviderTests.swift` (create the
`Widgets` group if absent; it is picked up automatically by XcodeGen's `AIPedometerTests` source
path). Use the isolated `TestUserDefaults` helper.

Cases:
1. **Valid payload** — write a `SharedStepData` (encoded exactly as the app writes it) into the
   injected suite; assert `loadSharedData()` decodes it with the expected fields.
2. **Missing key** — empty suite; assert `loadSharedData()` returns `nil` (and does not crash).
3. **Corrupt bytes** — set the key to non-decodable `Data`; assert `nil` and that the corrupt blob is
   handled (matching whatever `WidgetDataProvider` does — return `nil`, and purge if the app-group
   helper purges).
4. **Round-trip contract** — encode a `SharedStepData` via the app's writer path and decode via the
   widget's loader; assert field equality. This is the regression guard against schema drift.

Verify first exactly how the app writes the shared payload (the writer that feeds the widget — likely
`SharedDataStore` / `WidgetDataProvider.save` / `UserDefaults+AppGroup`) so the test encodes with the
real writer, not a hand-rolled encoder. A hand-rolled encoder would defeat the contract test.

## Scope

- **In scope:** new test file only.
- **Out of scope:** widget production code. If the round-trip test fails because writer and reader
  already disagree, that is a real bug — stop and report it as a new finding rather than tweaking the
  test to pass.

## Done criteria

1. Four cases green under the `plans/README.md` verification gate.
2. The round-trip test uses the real app writer + real widget loader (no hand-rolled codec).
3. No production change; no new warnings.

## Note on AboutView / reduce-motion

The auditor also flagged `AboutView` and the reduce-motion collapse as untested. These are **not**
worth dedicated tests: `TipJarStore` (the only logic behind About) is already covered by
`TipJarStoreTests`, and reduce-motion is pure view-modifier plumbing already gated by the shared
`MotionEffects` modifiers. Recorded here so it is not re-audited; no plan.
