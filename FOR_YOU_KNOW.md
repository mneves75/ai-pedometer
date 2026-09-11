# Engineering lessons

The project contract is [AGENTS.md](AGENTS.md). This file records behavior and
failure modes that are easy to miss when reading individual files. Current
verification results belong in [MEMORY.md](MEMORY.md) and the daily journal.

## Ownership and navigation

`AIPedometerApp` creates and injects the services. `AppStartupCoordinator` owns
one-time startup; `AppLifecycleCoordinator` owns foreground refresh. Keep that
policy out of feature views.

`RootView` selects onboarding or the main app. `MainTabView` uses `TabView` on
iPhone and `NavigationSplitView` on iPad. Passing one layout does not verify the
other. [APP_FLOW.md](APP_FLOW.md) maps the product flows.

SwiftUI can omit a `Label` identifier from the concrete tab-bar button. The UI
driver may select the five stable iPhone tabs by ordinal, but must then assert
the destination's accessibility marker. A tap alone does not prove navigation.
Markers must be visually empty: `opacity(0.01)` still renders text. Preserve
the clear 1×1 `uiTestMarker` and its primary-tabs regression.

## Async state and persistence

`StepTrackingService` combines activity sources, updates current metrics and
shared snapshots, and triggers weekly summaries and badges. Weekly-summary and
streak calculations use latest-request-wins generations so older results cannot
overwrite newer state.

`refreshTodayData()` is serialized separately, by a chained `Task` (`refreshChain`).
It is `@MainActor` but `async`, and about five callers can fire it concurrently;
`@MainActor` serializes only synchronous regions, so without the chain a stale-low
HealthKit read overwrites a newer `todaySteps` and clamps the `seedLiveBaseline`
Apple Watch offset to 0. Keep it run-to-completion: a drop/coalesce guard trades
this bug for a different one. The regression is `refreshTodayDataSerializesConcurrentCalls`
in `AIPedometerTests/Services/StepTrackingServiceTests.swift`, which asserts a mock's
`maxConcurrentFetchSteps` stays at 1. Known-accepted gap: live CMPedometer ticks reach
`updateLiveData` outside the chain, so a tick inside an `await` can interleave. It is
low severity and self-healing, and chaining live updates was rejected because it breaks
the synchronous live-update contract that several tests assert. Read
`implementation-notes.html#finding-085-live-interleave` before "fixing" it.

`StreakCalculator` reads history through the `StepHistoryProviding` seam on the
`StepDataAggregator` actor. `fetchDailySteps(from:to:)` issues one bucketed
`HKStatisticsCollectionQuery` keyed by start-of-day and the streak loop iterates that
in memory, instead of up to 400 serial per-day queries. Inside the actor, bind
`calendar` to a local `let` before `enumerateStatistics`, or Swift 6 reports a
sending-risk data race.

`InsightService` serializes Foundation Models access through a generation-tagged
flight. Incompatible callers wait and re-evaluate after invalidation or week
rollover. Obsolete generations cannot repopulate the cache.

Badge celebrations use UUID ownership. Dismissal, failure, cancellation and
replacement invalidate that owner before a late response can publish or clear
state. Inspect ownership cleanup before changing the view.

`HealthKitSyncService.fetchEarnedBadgeCount()` counts distinct `badgeRaw` values rather
than rows, because the count feeds the AI coaching prompt and older stores can hold
duplicate `EarnedBadge` rows. Keep it consistent with `BadgeService.deduplicateBadges`;
a raw `fetchCount` would make the AI over-report the total.

`WorkoutSessionController` snapshots mutable fields and commits transitions only
after SwiftData saves succeed. Failed start, resume, finish or discard operations
remain retryable. Terminal finish/discard calls are single-flight across awaits.

Completed workouts persist before HealthKit export. Schema V2 stores export state,
a stable external UUID and privacy-safe failure metadata. Startup, foreground,
pull-to-refresh and background reconciliation retry bounded pending batches even
inside the six-hour daily-sync throttle. An empty pending queue must not request
HealthKit authorization. The adapter resolves `HKMetadataKeyExternalUUID` before
export so a crash after HealthKit commits cannot create a duplicate. Preserve the
V1→V2 migration and idempotency tests when changing this path.

Historical activity uses `GoalService.goal(for:)` for each summary date. The
current goal is only a fallback when no historical goal exists.

## Health, AI and premium boundaries

Only the iOS app owns HealthKit. Widgets read `SharedStepData` from app-group
UserDefaults; the watch receives snapshots through WatchConnectivity and has
neither HealthKit nor app-group entitlements. The fallback service supports denied
permissions and unavailable HealthKit; deterministic demo data belongs to explicit
test/demo flows.

A callback from a C or Objective-C framework whose block is not `@Sendable`, invoked from a
`@MainActor` or actor context and called by the framework on a background queue, traps at
runtime. Extract a `nonisolated static func makeXCallback(continuation:) -> @Sendable (…) -> Void`
so the closure is formally nonisolated; `MotionService.makeQueryCallback` and
`makePedometerCallback` are the reference, mirrored in `HealthKitService` and `WatchSyncService`.
Check the SDK header for `@Sendable` on the specific handler parameter — that annotation is the
dividing line, and it is why the HealthKit paths never crashed while CoreMotion did.

`FoundationModelsService` checks device availability and owns text/structured
generation. Feature services own insights, coaching, plans and smart notifications.
Health context and AI inference stay on-device. Heart rate is the latest current-day
sample for display; it is not a training-zone or medical recommendation.

`PremiumAccessStore` owns RevenueCat offerings and access. Missing configuration,
unrelated entitlements, expired products and failed Trusted Entitlements verification
cannot unlock AI. Informational SDK verification still requires the app to reject
`.failed`. UI tests use explicit premium flags; `isUITesting` alone grants no access.

Access is a tri-state, and `canAccessAIFeatures == false` also means "cannot tell":
`isPremiumActive` is false whenever `customerInfo` is nil, and `isResolvingAccess`
deliberately returns false for `.unavailable`, which any cold-launch fetch or
verification failure sets. So a paying subscriber launching offline reads both as
false. Check `hasAuthoritativeAccessState` before treating a false reading as
revocation. Two separate attempts to auto-cancel premium smart reminders on such a
reading would each have cancelled reminders and erased `smartRemindersEnabled` for
paying users; both were reverted. The shipped design suspends delivery through
`smartRemindersSuspendedByAccess` and resumes it, and only explicit user action clears
the saved preference — see `SettingsSideEffects.smartReminderAccessAction` and the
enforcement in `AIPedometerApp`.

Expedition Mode has both a premium UI gate and a controller check of persisted
preferences before changing live-metric cadence. Keep the controller check.

GPX imports currently provide a local summary and MapKit preview. They do not
implement live navigation, offline maps or watch maps. `GPXRouteImporter` owns
security-scoped access, the bounded read, parsing handoff and storage. It reads at
most `maxFileSizeBytes + 1` through a `FileHandle` and rejects the file when the read
exceeds the cap; a `stat` preflight is deliberately not used, because reported size is
not a bound on what the handle yields. `GPXRouteParser` validates XML and builds the
summary; `ImportedRouteStorage` retains only the last summary. Keep file ingest out of
`WorkoutsView`.

`TrainingPlanRecord.currentWorkoutRecommendation` and
`currentWorkoutRecommendationSummary` own current-week selection, intent,
difficulty and estimated duration. Views consume those projections.

## Shared storage and performance

App-group snapshot writes coalesce the latest value for at most five seconds.
Goal/streak/week changes, day rollover, 100-step milestones and backgrounding flush
immediately. Encoding, persistence, widget reload and watch transport have Points
of Interest signposts without step totals or identifiers.

Fresh SwiftData stores live in private Application Support. Upgrades with an existing
app-group store continue opening it in place to preserve history. Widgets never open
SwiftData. Moving legacy SQLite/WAL files requires an interruption-tested migration;
the fresh-store policy does not prove isolation for all existing installations.

For streaming text, Swift semantic prefix equality is not byte-prefix equality.
`K` and `K` exposed a corruption bug when a semantic match reused a UTF-8 offset.
Use the production accumulator's exact byte-prefix invariant and Unicode regressions.
The synthetic parser benchmark does not measure SwiftUI rendering, model inference
or battery usage.

## Verification and release lessons

- XcodeGen snapshots version/build fields. Change `project.yml` before generation,
  then inspect compiled and archived values. Entitlements are restored by the
  postGen hook; manual generated-file edits disappear.
- The app uses a manual `AIPedometer/Resources/Info.plist`. `INFOPLIST_KEY_*` settings
  alone may not reach the bundle. Test the source plist and inspect the built one.
- Zero tests, skipped tests and inconsistent xcresult counts do not prove completion.
  A negative gate needs a violation inside its actual path/selector scope and a
  clean control. Empty redaction output is not a useful test.
- Identifier-scanner exemptions must name existing self/fixture paths. Obsolete
  allowlist entries can silently exempt new files from the privacy gate.
- On this shared host, inspect destination ownership, available storage and actual
  service state. Argent reported a boot error in September 2026 while a later
  inventory showed the requested simulator booted. Reconcile state before retrying.
- Keep project version, compiled version, archive, IPA, uploaded build, TestFlight
  availability and App Store availability separate. Release authentication and
  Apple RevenueCat configuration must exist before building the final artifact.
- AGENTS.md owns agent instructions; CLAUDE.md imports it. A copied global skill
  catalog hid project rules and made triggers stale. Keep references conditional
  and validate the portable contract on a clean clone.
- After any push, check the hosted run before calling a cycle verified. Local green
  is not CI green; a red workflow went unnoticed for a week.
- Never wholesale-rewrite a tool-owned file. Reserializing `Localizable.xcstrings`
  through a generic JSON writer reformatted every line and lost Xcode's own key
  collation. Preserve original order and formatting, then confirm the diff is
  purely additive.
- `#expect(!localized.isEmpty)` is satisfied by the returned key itself, so a set of
  localization assertions written that way cannot fail. Two suites had encoded the
  missing translations as expected behavior and only failed once the strings were
  actually translated. Assert the resolved value, not mere non-emptiness.
  Still open (2026-09-10): 14 such assertions remain in `LocalizationTests` and
  `PluralTests` for English-source keys, where `localized != key` is *not* a valid fix
  because the catalog key legitimately is the English string. The real fix is one test
  asserting each key exists in `Localizable.xcstrings`; the pt-BR suites already assert
  `localized != key` and are fine.
- A test must not assert a result against the same constant that produced it. While adding
  the GPX route-name bound, the first version of the regression asserted
  `route.name.count <= GPXRouteParser.maxRouteNameCharacters` — which passes for *any* value
  of that constant, including the 1,000,000 it was meant to prevent. Neutralising the bound
  to see red caught it; the assertion now uses a literal. Run the red half of every negative
  test, especially in a change whose purpose is deleting tests that cannot fail.
- Swift evaluates default-argument expressions at the *call site*, before the callee body, so
  an early `guard` in the callee does not prevent them from running. `LaunchConfiguration`
  read `ProcessInfo.processInfo.environment` — which rebuilds a dictionary on each access,
  measured 23.7 µs for 87 variables — on every call from SwiftUI modifier bodies, despite a
  `guard allowsOverrides else { return false }` that is a compile-time `false` in Release.
  Snapshot expensive defaults in a `static let`.
- A gate that tests fixtures cannot detect that the host is broken. `Scripts/tests/xcode-toolchain.sh`
  passed while the selector it tests failed on every real invocation, because no Xcode 26 was
  installed. Fixture tests pin logic; `Scripts/preflight.sh` pins the host. Keep both.
- Shell scripts must run under `/bin/bash`, which is **bash 3.2** on macOS and on GitHub's macOS
  runners. A dev machine with a homebrew bash 5 will happily run `mapfile`, `readarray`,
  `declare -A` or `${x^^}` and then fail in CI with `command not found`. This shipped once:
  `Scripts/verify-swift-build-settings.sh` used `mapfile` and turned CI red on its first run.
  New script tests should invoke the script under `/bin/bash` explicitly, for both the passing
  and the violating case, rather than trusting the ambient shell.
- Configuration that no gate executes drifts to fiction, and reviewing it by eye does not help.
  Sixteen fabricated `SWIFT_UPCOMING_FEATURE_*` names and a `DEVELOPER_DIR` pin to an Xcode that
  was not installed both survived months of audits, because reading them proves nothing — Xcode
  ignores an unknown build setting silently, and the pin resolved to whatever was there. The
  durable fix is an executable check (`Scripts/verify-swift-build-settings.sh`,
  `Scripts/preflight.sh`), not a better-worded instruction. Published analysis of agent
  instruction files puts prose compliance around 25–40% against roughly 95% for an enforced gate;
  prefer converting a lesson here into a gate whenever the lesson is mechanically checkable.
- When a structural argument and an experiment disagree, the experiment wins. Bisect
  before defending a hypothesis, and scope any find/replace to the specific call.

## Settled non-findings (do not re-audit)

- `ProgressClamp.percent` intentionally has no high-side clamp. It guards `isFinite`
  and clamps low to zero; the watch's 32-bit `Int` would only trap above roughly
  21 million times the goal, which real step data cannot reach.
- `Shared/` and `AIPedometerWatch/` were swept for the 32-bit overflow class. The only
  large constant was the wrapping-`UInt32` hash already fixed in 0.90. Shared code still
  compiles for `arm64_32`, so new hashing there needs explicit wrapping arithmetic.
- Fresh SwiftData stores in private Application Support are the mitigation for the store
  boundary. Existing app-group stores stay in place to avoid upgrade data loss, and
  SwiftData has no public relocation API — do not implement a raw SQLite/WAL move.
