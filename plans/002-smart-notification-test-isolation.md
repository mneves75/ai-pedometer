# 002 — Isolate SmartNotificationService tests from real UserDefaults / app group

**Written against commit** `d4a2958`. Category: test isolation. Confidence: HIGH. Effort: S.
Fix risk: LOW (test-only, no production change).

## Why this matters

Two of the three tests in `AIPedometerTests/AI/SmartNotificationServiceTests.swift` construct
`SmartNotificationService` **without** the `userDefaults:`/`sharedUserDefaults:` arguments, so they
bind the production stores (`UserDefaults.standard` and the app-group defaults). The initializer runs
`loadPersistedState()` + `resetDailyCounterIfNeeded()`
(`AIPedometer/Core/AI/SmartNotificationService.swift:45-47,128-159`), which **reads and can write**
`smartNotificationLastDate` / `smartNotificationCount` back into `.standard` whenever a stale
prior-day timestamp exists. The third test injects `userDefaults` but omits `sharedUserDefaults`, so
`fetchTodayProgress` reads the real app-group `sharedStepData` (`:216`).

Result: order-dependent flakiness (a prior run's counter/date leaks into a later run) and pollution
of the shared simulator defaults that other suites' `.sharedAppGroup` reads can observe. Every other
suite already uses the isolated `TestUserDefaults` helper (`AIPedometerTests/Support/TestUserDefaults.swift`).

## Current state (exact)

`AIPedometerTests/AI/SmartNotificationServiceTests.swift`:
- Test 1 `motivationalReminderReturnsFalseWhenAIUnavailable` — constructor at lines 17-22, no
  `userDefaults:`/`sharedUserDefaults:`.
- Test 2 `cancelAllSmartNotificationsRemovesKnownIdentifiers` — constructor at lines 36-41, same.
- Test 3 `scheduleSmartNotificationUsesActivityModeUnits` — constructor at lines 81-87, passes
  `userDefaults: testDefaults.defaults` but not `sharedUserDefaults:`.

Reference for the correct isolated pattern already used elsewhere in this suite (the `defer` reset
plus injected defaults): lines 51-52 and 81-87.

## The fix

For **each** of the three constructor calls, create an isolated `TestUserDefaults` and inject it into
both `userDefaults:` and `sharedUserDefaults:`, with a `defer { testDefaults.reset() }`.

Test 1 (replace lines 15-22):

```swift
        let notificationCenter = MockNotificationCenter()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let service = SmartNotificationService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
        )
```

Test 2 (replace lines 34-41):

```swift
        let notificationCenter = MockNotificationCenter()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let service = SmartNotificationService(
            foundationModelsService: MockFoundationModelsService(),
            healthKitService: MockHealthKitService(),
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
        )
```

Test 3 (extend the existing constructor at lines 81-87 to also pass `sharedUserDefaults:`):

```swift
        let service = SmartNotificationService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
        )
```

## Verify the initializer signature first

Confirm the exact parameter labels and their defaults in
`AIPedometer/Core/AI/SmartNotificationService.swift` (the initializer around lines 30-47). If the
shared-store label is not literally `sharedUserDefaults:` (e.g. it is a differently named parameter
or is derived internally from `userDefaults:`), match the real label — the other tests at
`SmartNotificationServiceTests.swift:190/240/281` already inject the isolated pattern; copy whatever
labels they use. Do not invent a parameter that doesn't exist.

## Scope

- **In scope:** the three constructor calls in `SmartNotificationServiceTests.swift` only.
- **Out of scope:** `SmartNotificationService` production code — do not change the initializer or its
  defaults.

## Done criteria

1. All three tests pass with injected isolated defaults.
2. Running the suite twice in a row (or with `-only-testing:AIPedometerTests/SmartNotificationServiceTests`
   repeated) yields identical results — no order dependence.
3. No writes to `UserDefaults.standard` / the real app group during the run.

## Maintenance note

Any new test in this file must follow the same inject-and-reset pattern; never construct
`SmartNotificationService` against the production defaults in a test.
