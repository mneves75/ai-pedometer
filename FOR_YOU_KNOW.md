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
overwrite newer state. Today's refresh serialization is a separate invariant.

`InsightService` serializes Foundation Models access through a generation-tagged
flight. Incompatible callers wait and re-evaluate after invalidation or week
rollover. Obsolete generations cannot repopulate the cache.

Badge celebrations use UUID ownership. Dismissal, failure, cancellation and
replacement invalidate that owner before a late response can publish or clear
state. Inspect ownership cleanup before changing the view.

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

`FoundationModelsService` checks device availability and owns text/structured
generation. Feature services own insights, coaching, plans and smart notifications.
Health context and AI inference stay on-device. Heart rate is the latest current-day
sample for display; it is not a training-zone or medical recommendation.

`PremiumAccessStore` owns RevenueCat offerings and access. Missing configuration,
unrelated entitlements, expired products and failed Trusted Entitlements verification
cannot unlock AI. Informational SDK verification still requires the app to reject
`.failed`. UI tests use explicit premium flags; `isUITesting` alone grants no access.
Unavailable access is distinct from authoritative revocation, as specified in AGENTS.md.

Expedition Mode has both a premium UI gate and a controller check of persisted
preferences before changing live-metric cadence. Keep the controller check.

GPX imports currently provide a local summary and MapKit preview. They do not
implement live navigation, offline maps or watch maps. `GPXRouteImporter` owns
security-scoped access, size preflight, mapped reading, parsing handoff and storage.
`GPXRouteParser` validates XML and builds the summary; `ImportedRouteStorage`
retains only the last summary. Keep file ingest out of `WorkoutsView`.

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
