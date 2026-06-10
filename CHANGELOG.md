# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.88] - 2026-06-10

### Changed

- Release-metadata bump to `0.88 (44)` for the first TestFlight/App Store submission attempt of the 0.87 review-cycle changes (Release override lockdown, stale-insight fix, goal/plan caches, Enhanced Security compiler hardening). No source changes beyond the version bump.

### Docs

- Synced every version-referencing doc to `0.88`: `README.md`, App Store publishing playbook, agent build/testing docs, and `test_plan.md`. (`CLAUDE.md`/`AGENTS.md` intentionally carry no hardcoded app version — `project.yml` is the source of truth.)

## [0.87] - 2026-06-10

### Security

- **Release builds no longer honor test launch overrides.** `LaunchConfiguration.isOverridable` returned true in Release when `-ui-testing`/`XCTestConfigurationFilePath` markers were present — both are attacker-suppliable launch inputs via `devicectl` on any Developer-Mode device, so `-force-premium-on` could unlock Premium in a store binary without a purchase. Release now returns `false` unconditionally; every legitimate harness (UI tests, e2e script, CI) runs Debug builds. RevenueCat docs updated to state the overrides are Debug-only.
- **Enhanced Security compiler hardening enabled** via the `audit-xcode-security-settings` audit: project-level `ENABLE_ENHANCED_SECURITY` (security compiler warnings, typed allocators, stack zero-init cascades) plus pointer authentication (arm64e) with an explicit opt-out on watchOS (no arm64e) and SPM arm64e opt-in for RevenueCat (source-only package, verified 0 binary targets) — device build verified. The hardened-process **entitlements** are staged but not default: signing them requires the team provisioning profile to gain the Enhanced Security capability, which needs a one-time interactive Xcode sign-in (`ENHANCED_SECURITY_ENTITLEMENTS=1 Scripts/restore-entitlements.sh` opts in afterwards). Decisions recorded in `xcode-security-settings.md`.
- **Identifier hygiene + guardrail teeth.** Developer team IDs and physical-device identifiers were redacted from tracked docs/memory, and `Scripts/verify-device-identifiers.sh` gained patterns for bare physical UDIDs and UDID-labelled UUIDs in prose (the old patterns only matched command-flag contexts).

### Fixed

- **Daily AI insight no longer inflated by yesterday's steps.** `InsightService.fetchTodayActivityData` merged the app-group shared snapshot into "today" without a freshness gate, so right after midnight (or when the insight task raced the tracking refresh) yesterday's total could be reported — and congratulated — as today's. The merge and both fallback paths now ignore stale snapshots, matching `SmartNotificationService`'s existing gate. Regression test: `dailyInsightIgnoresStaleSharedData`.
- **`Scripts/test-payments-device.sh` TestFlight-group step was dead code**: the embedded `python3 -c` one-liner contained literal `\n` escapes (guaranteed `SyntaxError`), aborting the script after the expensive Release archive on every run. Rewritten as a heredoc.

### Performance

- **Goal lookups are cached.** `GoalService.currentGoal`/`goal(for:)` ran a full-table SwiftData fetch per call, and `StreakCalculator` calls `goal(for:)` once per streak day (up to 400× per refresh, on the main actor, at startup and every foregrounding). Goals are now fetched once and invalidated on `setGoal`.
- **Training-plan lists are cached.** `WorkoutsView` computed properties triggered ~8–10 synchronous plan fetches per body evaluation; `TrainingPlanService.fetchActivePlans()/fetchAllPlans()` now cache with invalidation at the plan mutation points.
- **Workouts carousel query is bounded** (`fetchLimit` 6, completed-only predicate) instead of fetching every workout ever recorded.
- **Watch sync tick path slimmed.** `updateApplicationContext` (plist + XPC per CMPedometer tick) now shares the existing time/step-delta throttle, and the payload encode is skipped entirely when no channel is due.
- Per-render formatter allocations hoisted to cached statics (Dashboard relative-date formatter, Live Activity distance formatter, logger ISO8601 formatter).

### Changed

- Dead code removed: the caller-less AI goal-recommendation path (`generateGoalRecommendation`, prompt builder, `GoalRecommendation` model), `StepTrackingService.fetchTodayActivityCount`, the permanently no-op `registerBackgroundTasks` startup-coordinator step (registration correctly happens in `App.init`), the uncompilable `#else` duplicate of `SharedStepData` in `WatchSyncService`, and the widgets' drifted `WidgetStepData` duplicate (widgets now decode the canonical `SharedStepData`, schema-version aware).
- `saveWorkout`'s duplicated end/finish completion pyramid extracted to one helper; soft-deprecated `presentationMode` replaced with `dismiss`/`isPresented`; `StepTrackingService` gained injectable `calculator`/`sendToWatch` seams.

### Tests

- The 0.85 current-day-merge guard is now mutation-covered: new tests prove a past day is not inflated by today's live total (verified red with the guard removed) and that non-steps mode skips the merge. Suite grew to 460 tests / 79 suites, all passing.
- XCTest stragglers converted to Swift Testing; 11 tautological tests (`XCTAssertTrue(true)`, `XCTAssertNotNil` on non-optionals) deleted; first use of `@Test(arguments: zip(...))` for the DesignTokens monotonicity chains; onboarding accessibility IDs centralized in `A11yID`; `TestUserDefaults` now fails loudly instead of silently falling back to `.standard`.

### Docs

- Synced every version-referencing doc to `0.87`: `README.md`, App Store publishing playbook, agent build/testing docs, and `test_plan.md`. New decision document `xcode-security-settings.md`. Toolchain notes (Xcode 27 beta as machine default, `DEVELOPER_DIR` pinning, simulator runtime `match set`) recorded in `MEMORY.md`.

## [0.86] - 2026-05-31

### Changed

- Release-metadata bump to `0.86 (42)` for the on-device install milestone of the 0.85 review-cycle change (current-day summary merge now uses the shared `DailyStepCalculator`). No source changes beyond the version bump.

### Docs

- Synced every version-referencing doc to `0.86`: `README.md`, App Store publishing playbook, agent build/testing docs, and `test_plan.md`. (`CLAUDE.md`/`AGENTS.md` intentionally carry no hardcoded app version — `project.yml` is the source of truth.)

## [0.85] - 2026-05-31

### Changed

- **Full-review audit cycle (0.85 (41)).** A fresh multi-agent review (concurrency/data-races, state/data correctness, security/privacy, SwiftUI UX/accessibility, test quality) with adversarial verification against the real source found **0 critical, 0 high, 0 medium** correctness defects. Several reviewer findings were already fixed in 0.83 (zero-length streak start, zero-week trend) and were verified as such rather than re-applied.

### Fixed

- **Current-day summary merge now uses the service's shared day-boundary calculator.** `StepTrackingService.mergeCurrentDaySummaryIfNeeded` decided "is this today?" with a one-off `Calendar.current.isDate(_:inSameDayAs:)` — the only spot in the service that bypassed the injected `DailyStepCalculator` used by every other day-boundary decision (`seedLiveBaseline`, `currentBaseline`, `seedPendingBaselineIfNeeded`). It now routes through `calculator.didCrossMidnight`, keeping the merge consistent with the rest of the live-baseline logic and exercisable under a fixed test calendar. Behavior-preserving (both reflect the live time zone); no user-visible change.

### Notes

- **Live pedometer updates bypass the `refreshChain` serialization** (verified real, accepted not fixed): live CMPedometer ticks mutate the same `todaySteps`/`liveBaseline` state the refresh chain protects. The refresh's synchronous tail keeps the final state self-consistent, so the only artifact is a self-healing sub-second flicker; chaining live updates onto the refresh would break the synchronous live-update contract and add a hot-path cost on every tick. See `implementation-notes.html#finding-085-live-interleave`.

### Docs

- Synced every version-referencing doc to `0.85`: `README.md`, App Store publishing playbook, agent build/testing docs, and `test_plan.md`. (`CLAUDE.md`/`AGENTS.md` intentionally carry no hardcoded app version — `project.yml` is the source of truth.)

## [0.84] - 2026-05-31

### Changed

- Release metadata bump to `0.84 (40)` and on-device install milestone for the 0.83 audit-cycle fixes (goal-change gap, zero-week trend, streak start date, off-main GPX parse, DesignTokens cleanup). No source changes beyond the version bump. Built and **installed** on the `iMarcus` physical device (iPhone 17 Pro Max) — verified `0.84 (40)` present via `devicectl device info apps`, with the embedded watch app auto-delivered to the paired Apple Watch. Post-install launch initially failed because the device was locked (`FBSOpenApplicationErrorDomain error 7`); after the device was unlocked, a bounded auto-retry **launched the app successfully** on iMarcus.

### Docs

- Synced every version-referencing doc to `0.84`: `README.md`, App Store publishing playbook, agent build/testing docs, and `test_plan.md`. (`CLAUDE.md`/`AGENTS.md` intentionally carry no hardcoded app version — `project.yml` is the source of truth.)

## [0.83] - 2026-05-31

### Fixed

- **Daily-goal change left a sub-millisecond gap with no active goal.** `GoalService.setGoal` read `Date()` twice — once to close the previous goal and once (`.now`) to start the new one — so for the instant between them `goal(for:)` matched neither goal and silently fell back to the default daily goal. Both timestamps now share one value, so the closed goal's `endDate` equals the new goal's `startDate` exactly.
- **Week-over-week trend read "stable" when recovering from a zero week.** `HealthKitSyncService` computed no percentage change against a zero prior week, so going from no activity to active still reported "stable" in the AI context snapshot. A zero baseline with current activity now reports "increasing".
- **Streak start date was a future day for a zero-length streak.** `StreakCalculator` computed `-(streakCount - 1)` even when the streak was 0, resolving to *tomorrow*. An inactive streak now reports `streakStartDate == nil`. (No user-visible surface consumed this yet; corrected for model honesty.)

### Changed

- **GPX route import now parses off the main actor.** A selected GPX file (up to the 5 MiB cap) was parsed synchronously in the file-importer callback, hitching the dismissal animation on large routes. Parsing now runs on a background task and the `Sendable` result is applied back on the main actor.
- **DesignTokens enforcement cleanup.** Replaced literal visual constants with existing tokens where an exact-value token exists: Live Activity card `cornerRadius` → `CornerRadius.xl`, Live Activity stat icon frame → `IconSize.sm`, Health Access help-sheet number column → `IconSize.xs`. Zero rendered-size change. Remaining widget chart/ring geometry literals are intentional local layout math with no semantic token (documented in implementation notes).
- Release metadata bump: updated app version/build to `0.83 (39)`.

### Tests

- Added regression tests (each proven to fail before its fix): goal-change leaves no gap between goals, week-over-week trend increases from a zero baseline, and an active streak reports its first day while a zero streak reports `nil`.

### Docs

- Recorded a full goal-mode audit cycle in `implementation-notes.html`: ~14 reviewer-claimed critical/high findings were adversarially verified against the real code and **all were refuted** (false positives or documented-intentional designs); only LOW/MEDIUM polish remained, which is fixed or justified here.
- Synced every version-referencing doc to `0.83`: `README.md`, App Store publishing playbook, agent build/testing docs, and `test_plan.md`.

## [0.82] - 2026-05-28

### Fixed

- **Step count could visibly regress under concurrent refreshes.** `StepTrackingService.refreshTodayData()` had no in-flight guard, so overlapping callers (app foreground, background refresh, pull-to-refresh, settings changes) could interleave across its `await` points — an older, stale HealthKit read could overwrite a newer one and corrupt the live step baseline until the next clean refresh. Refreshes are now serialized so each runs to completion atomically, in call order. A prior cycle had justified this as idempotent; a concrete non-idempotent interleaving (live-baseline corruption) was found and fixed this cycle.
- **AI coaching over-reported earned badges.** The AI context snapshot counted raw `EarnedBadge` rows; older stores can contain duplicate rows for the same badge (the rest of the badge code dedups defensively). The count now reflects distinct badge types, matching the deduped value shown in the Badges UI, so the AI prompt no longer inflates the total.

### Tests

- Added a regression test proving concurrent `refreshTodayData()` calls are serialized (verified failing without the guard: two callers reached the HealthKit fetch simultaneously).
- Added a regression test proving the AI badge count de-duplicates by badge type.

### Changed

- Release metadata bump: updated app version/build to `0.82 (38)`.

### Docs

- Synced every version-referencing doc to `0.82`: `README.md`, App Store publishing playbook, agent build/testing docs, and `test_plan.md`.

## [0.81] - 2026-05-28

### Changed

- Release metadata bump: updated app version/build to `0.81 (37)`.

### Docs

- Synced every version-referencing doc to `0.81`: `README.md`, App Store publishing playbook, agent build/testing docs, and `test_plan.md` (which had drifted to `0.76`).
- Recorded the streak data-access seam in `MEMORY.md`: `StreakCalculator` now reads its historical window through `StepHistoryProviding.fetchDailySteps` (one bucketed `HKStatisticsCollectionQuery`) instead of one query per day.

## [0.80] - 2026-05-28

### Performance

- Streak calculation now prefetches its historical window in a single `HKStatisticsCollectionQuery` instead of issuing one `HKStatisticsQuery` per day (previously up to 400 serial HealthKit round-trips). The cost no longer scales with streak length, so engaged users with long streaks no longer pay seconds of serial query latency and battery on every startup, foreground, and goal change. Streak semantics are unchanged.

### Security

- Hardened the GPX importer against internal-entity expansion ("billion laughs"): a single element's accumulated text is now capped, so a small but hostile GPX cannot balloon memory before the existing element caps trigger. (`shouldResolveExternalEntities` already blocked XXE.)

### Changed

- Release metadata bump: updated app version/build to `0.80 (36)`.

### Tests

- Added `StreakCalculatorTests` (the streak engine previously had no direct coverage): consecutive-day counting, today-included vs. not, gap-breaks-streak, per-day historical goals, empty history, the 400-day lookback cap, and a query-count contract asserting a single bucketed daily query.
- Added a GPX parser regression test for the element-text cap.

## [0.79] - 2026-05-28

### Changed

- Release metadata bump: updated app version/build to `0.79 (35)`.
- Centralized icon sizing, component dimensions, and corner radii into `DesignTokens.IconSize` and extended `DesignTokens.Sizing`; replaced literal `.frame(width: 32/36/44/100, height: …)`, `cornerRadius: 8/10/12`, and chart/card magic numbers across Dashboard, History, Badges, Workouts, AI Coach, Settings, About, Premium gating, and AI availability surfaces.
- Switched fixed `.frame(height:)` to Dynamic-Type-safe `.frame(minHeight:)` on the History weekly chart and badge cards so large accessibility text sizes no longer clip content.
- Resolved the onboarding scroll-page bottom inset and AI Coach chat-bubble gutter to named tokens (`onboardingPageBottomInset`, `chatBubbleGutter`) instead of inline literals.

### Docs

- Updated `DESIGN_SYSTEM.md` and `FRONTEND_GUIDELINES.md` with the new icon-size, component-sizing, and corner-radius rules.
- Synced README, App Store publishing playbook, and agent build/testing docs with the `0.79 (35)` release.

### Tests

- Full simulator verification passed on iPhone 17 (iOS 26.5 Simulator): `480` tests passed, `0` failures, `0` skipped (XCTest unit + Swift Testing + 16 XCUITest UI). Build succeeded with `xcodegen generate` + entitlement restore.

### Fixed

- Honored Reduce Motion across animated dashboard, AI, badge, history, workout, and availability surfaces, and improved VoiceOver summaries for progress rings, widgets, watch summaries, support actions, and selected iPad sidebar rows.
- Made onboarding scroll-safe on compact screens, restored VoiceOver page-position context for the custom dots, preserved Skip as a no-permission-request exit path, and prevented the final onboarding step from completing before permission/goal persistence work finishes.
- Hardened Premium AI fail-closed behavior by removing UI-test auto-unlock and product-ID fallback access, requiring tests to opt into forced premium explicitly.
- Gated GPX route import at the import boundary, so non-premium users cannot bypass the Workouts card gate through direct import actions.
- Requested every HealthKit quantity type written with workout samples, including steps, distance, and active energy.
- Removed the unused BGProcessing task registration/configuration path instead of carrying a no-op background entitlement.
- Validated Foundation Models training-plan payload bounds before persistence and fall back to deterministic local plans when generated output is unsafe or incomplete.
- Made the payment device validation script delete only canonical build-artifact paths under the repo's `build/ipa` directory.

### Changed

- Live Activity workout distance now uses the app's measurement formatter instead of a hardcoded kilometer label.
- Live Activity workout distance uses a shorter `DIST` label because the formatted value already carries the natural unit.
- Locked badge cards keep their card readability while dimming only the locked icon.
- Training-plan generation now presents a blocking loading state instead of allowing concurrent form edits while a plan is being generated.

### Tests

- Added regression coverage for HealthKit write authorization, premium fail-closed behavior, training-plan validation, GPX import gating, removed background processing, motion-aware accessibility helpers, and payment-script path safety.
- Full simulator verification passed on iPhone 17: 16 XCTest unit tests, 438 Swift Testing tests, and 16 UI tests. Build, static analyzer, project generation, string-catalog validation, AGENTS sync, device-identifier scan, and payment-script safety tests also passed.

## [0.78] - 2026-05-23

### Changed

- Release metadata bump: updated app version/build to `0.78 (34)`.
- App Store publishing commands and top-level version references now point to `0.78`.
- Moved GPX route file-access and storage orchestration behind `GPXRouteImporter`, keeping Workouts focused on UI state while preserving local-only Routes & GPX behavior.
- Moved active training-plan workout recommendation projection into `TrainingPlanRecord`, so Workouts consumes a model-owned current-week recommendation instead of duplicating plan mapping logic.

### Docs

- Synced README, App Store publishing playbook, build/testing agent docs, and local memory with the `0.78 (34)` release.

### Tests

- Full simulator suite passed on iPhone 17 after the architecture cleanup: 16 XCTest unit tests, 435 Swift Testing tests, and 15 UI tests.

## [0.77] - 2026-05-20

### Added

- Added Premium-gated Expedition Mode on the Workouts screen; when enabled for a session, live workout metrics refresh at a lower cadence to reduce battery impact during long walks and hikes.
- Added a Premium-gated Routes & GPX card on Workouts with local GPX import, route preview, distance, elevation gain, waypoint count, estimated duration, and persisted last-route storage.
- Added latest HealthKit heart-rate read support and a Dashboard heart-rate stat card.
- Upgraded the imported GPX preview from a static route sketch to a non-interactive MapKit preview with start/finish markers and a route polyline.

### Fixed

- Fixed a regression where the Dashboard heart-rate card never displayed data because the production `HealthKitServiceFallback` wrapper inherited the protocol's default `fetchLatestHeartRate` (returning `nil`) instead of forwarding to the primary or demo HealthKit service.
- Hardened the GPX route importer against malformed or hostile input: file payloads are size-capped at 5 MiB before allocation (`GPXRouteImporter` checks file attributes before mapping into memory), parsing aborts after 50,000 track points / 5,000 waypoints, non-finite or out-of-range coordinates and elevations are rejected, and external XML entity resolution is explicitly disabled (XXE defense in depth).
- Made the test-only forced-premium / forced-HealthKit-sync launch overrides fail closed in App Store release builds, so a stray launch argument or environment variable on a tampered binary cannot unlock Premium AI or reshape user data.
- Gated AI-generated badge celebrations behind the same Premium boundary as the rest of the AI surfaces (Foundation Models is no longer invoked from `BadgeService` for non-Premium users), and reset the smart-notification interruption level from `.timeSensitive` to `.active` so coaching reminders respect Focus modes.
- Replaced `MotionService.query`'s `CMPedometer.startUpdates(from:)` workaround (live-updates API used for a one-shot read, manually guarded by a dedupe lock and `defer { stopUpdates() }`) with Apple's purpose-built `queryPedometerData(from:to:withHandler:)` — same behavior, no manual teardown, no callback dedupe gymnastics.
- Removed `AIPedometer/Core/Workouts/WorkoutService.swift`, which had no callers anywhere in production or tests after `WorkoutSessionController` superseded it; the leftover file was a maintenance hazard.
- Hardened RevenueCat premium access so unrelated active entitlements, expired historical premium products, or failed Trusted Entitlements verification cannot unlock Premium AI.
- Fixed the Premium sheet so an offering without a published RevenueCat Paywall v2 uses the app-owned package UI instead of showing RevenueCat's default debug paywall banner.
- Aligned target privacy manifests with Apple's official Health/Fitness data type identifiers and the no-analytics privacy promise.
- Removed invalid Health/Motion required-reason API categories and declared UserDefaults app-group access with the appropriate Apple reason code.
- Made app structured logger metadata values redacted by default to avoid exposing health-related data, paths, or launch arguments in OS logs.
- Localized HealthKit debug and premium subscription period labels through the app localization path.

### Docs

- Documented the RevenueCat Trusted Entitlements fail-closed behavior in the premium setup and operations docs.
- Added a dedicated RevenueCat + Apple payments setup runbook covering App Store Connect subscriptions, In-App Purchase Key setup, RevenueCat products/entitlements/offerings, local `xcconfig` wiring, sandbox/TestFlight validation, review notes, troubleshooting, and go-live checks.
- Synced README, App Store, testing, security, tech-stack, RevenueCat, and project field-guide docs with the 2026 source/security review and ASC/Xcode verification flow.
- Regenerated the Xcode project from `project.yml` so local ASC/Xcode version metadata matches `0.77 (33)`.
- Updated the PRD to reflect the current RevenueCat-backed Premium AI requirement instead of treating subscriptions as out of scope.
- Documented the recurring `devicectl` warning `Failed to load provisioning paramter list ... No provider was found.` as a host-side CoreDevice/Xcode issue that can appear even when install/launch succeeds.
- Clarified that `Scripts/install-on-device.sh` may hit a first launch denial when the iPhone is locked and then recover on the built-in retry path.

### Changed

- Release metadata bump: updated app version/build to `0.77 (33)`.
- App Store publishing commands, metadata drafts, and top-level version references now point to `0.77`.

### Tests

- Verified the release with targeted RevenueCat, startup, step-tracking, HealthKit, localization, and UI regressions; full simulator test suite (`462` tests), static analyzer, project generation, plist/string-catalog validation, AGENTS sync, and device-identifier scan.

## [0.76] - 2026-03-25

### Changed

- Release metadata bump: updated app version/build to `0.76 (32)`.
- App Store publishing commands and top-level version references now point to `0.76`.

### Tests

- No code changes in this release; verification was limited to release metadata/doc integrity checks.

## [0.75] - 2026-03-25

### Added

- Official `RevenueCatUI` integration for the iOS app target, enabling the native RevenueCat SwiftUI paywall and Customer Center on top of the app-owned premium state layer.
- Regression coverage for premium startup/loading behavior, smart-reminder fail-closed behavior, and training-plan AI unavailability handling.

### Fixed

- Premium access now preserves entitlement state even when offerings fail to load, avoiding false lockouts after a successful purchase or restore.
- Dashboard, History, AI Coach, Workouts, and Training Plans now show a consistent premium-loading state instead of flashing a false gate while customer info is still resolving.
- History weekly AI card now renders a proper empty state instead of showing a blank premium/AI section.
- HealthKit Sync setting changes now refresh current-day tracking state immediately so the dashboard and shared state do not keep stale values.
- Smart reminders now fail closed when premium or AI availability disappears, and reminder scheduling only remains enabled after a successful schedule operation.
- Training-plan generation now preserves the concrete AI unavailability reason instead of collapsing every unavailable state into `modelNotReady`.

### Changed

- Release metadata bump: updated app version/build to `0.75 (31)`.
- RevenueCat local test-store configuration now defaults to the provided local key with entitlement `premium` and offering `default`.

### Tests

- Full simulator release verification passed with RevenueCatUI enabled: `395` unit tests and `14` UI tests.
- Physical-device release verification passed on `iMarcus` after install and direct launch.

## [0.74] - 2026-03-10

### Changed

- Release metadata bump: updated app version/build to `0.74 (30)`.
- Release publication sync for the already-verified RevenueCat and workouts codebase shipped in `0.73`.

### Tests

- Release verification: regenerated the Xcode project with `xcodegen generate`, confirmed `AGENTS.md` sync, and reran the full simulator test suite before tagging and publishing.

## [0.73] - 2026-03-10

### Added

- RevenueCat-based premium access management with a native SwiftUI paywall, entitlement-aware feature gates, and local configuration via `Config/Local.xcconfig`.
- Local Markdown rendering support for AI coach/chat surfaces using native `AttributedString(markdown:)`, removing the external `SwiftFastMarkdown` dependency.
- Regression coverage for RevenueCat configuration resolution, premium launch overrides, recent workout filtering, and HealthKit workout sample generation.

### Fixed

- Workout recommendations and training-plan generation now fail closed to deterministic localized fallback content when Foundation Models return invalid, partial, or unavailable responses.
- HealthKit workout saving now persists workout samples for steps, distance, and calories instead of saving workouts without quantity payloads.
- Training Plans and Workouts surfaces now prioritize the user’s active saved plan over speculative AI recommendations and hide raw model-error copy from the UI.
- Recent workouts now exclude in-progress sessions and render a clearer empty state when there is no completed history.

### Improved

- Premium-gated experiences now cover dashboard AI insights, weekly history trends, AI Coach, smart reminders, training-plan creation, and AI workout recommendations with a consistent unavailable-subscriptions state.
- About screen now explains recurring premium support separately from the one-time tip jar.

### Changed

- Release metadata bump: updated app version/build to `0.73 (29)`.

### Tests

- Release verification: unit tests passed with `368 tests / 68 suites`; UI tests passed with `14 tests / 0 failures`, plus a focused rerun of `testWorkoutsShowPremiumGatesWhenPremiumIsForcedOff` passed with `1 test / 0 failures`.

## [0.72] - 2026-03-06

### Fixed

- Launch startup and the first foreground lifecycle refresh are now sequenced so the app does not double-run HealthKit refresh/sync work on first activation.
- Shared App Group step data now fails closed instead of falling back to process-local defaults, and corrupted payloads are quarantined on decode instead of poisoning all future reads.
- SQLite reset now removes the real `default.store-wal` and `default.store-shm` sidecars so UI-test resets and local store wipes do not leave stale state behind.
- HealthKit fallback now propagates real authorization/query failures to sync and workout flows instead of silently relabeling them as fresh zero-step data.
- Weekly summaries now merge the live current-day total before publishing to shared state so charts and widgets stay aligned with the dashboard ring.
- Workout discard now awaits Live Activity shutdown, initial live-metrics warm-up no longer surfaces a false “metrics unavailable” error, and post-HealthKit reconciliation-ID persistence failures are logged separately from HealthKit write failures.
- Training plan generation now rejects unpersistable weekly-target payloads, blocks overlapping generation requests, and rolls back in-memory status mutations when persistence saves fail.

### Improved

- Added regression coverage for startup/lifecycle gating, background-task completion races, shared-step payload staleness/corruption handling, SQLite sidecar cleanup, HealthKit fallback behavior, weekly-summary merging, training-plan fail-closed behavior, and workout shutdown/persistence edges.
- Agent guidance now includes the explicit Xcode AdditionalDocumentation path for Swift / iOS/iPadOS 26 code in both `AGENTS.md` and `CLAUDE.md`.

### Changed

- Release metadata bump: updated app version/build to `0.72 (28)`.

## [0.71] - 2026-02-24

### Fixed

- watchOS sync now handles interactive message payloads via `WCSessionDelegate.session(_:didReceiveMessage:)`, preventing dropped updates when the phone sends direct messages.

### Improved

- App Store publishing toolkit:
  - `Scripts/appstore-materials-prepare.sh` to assemble an ordered screenshot package from UI-test captures.
  - `Scripts/appstore-screenshots-validate.sh` to enforce ASC-compatible dimensions (`IPHONE_65` and `IPAD_PRO_3GEN_129`).
  - `Scripts/appstore-screenshots-upload.sh` to upload screenshot sets via `asc`, with optional automatic localization-ID resolution.
  - `Scripts/appstore-publishing-preflight.sh` to run screenshot matrix check + prepare + validate + optional upload dry-run in one command.
- App Store publishing documentation bundle in `docs/appstore/`:
  - `PUBLISHING_PLAYBOOK.md` (industry-standard flow + checklist),
  - metadata templates for `pt-BR` and `en-US`,
  - screenshot package instructions.
- Marked remaining English string-catalog entries as fully translated status for release readiness.

### Changed

- Release metadata bump: updated app version/build to `0.71 (27)`.
- Documentation sync: aligned release references across `README.md`, App Store playbook examples, and agent build docs.
- Removed redundant watch-only shim file `AIPedometerWatch/WatchDataModels.swift`.
- Localization policy is strict: only devices set to `pt-BR` use Portuguese (Brazil); all other device languages default to English (`en-US`).
- Localization pipeline now resolves strings through `L10n.localized(...)` using explicit app-locale mapping, removing the previous persistent `AppleLanguages` override side effect.

### Tests

- Full quality gate green on release commit: `xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' test` (`336 tests`, `66 suites`).

## [0.7] - 2026-02-24

### Fixed

- Background task registration now dispatches handler execution on the main queue with explicit actor isolation, removing the `@unchecked Sendable` wrapper used for `BGTask` bridging.
- Prompt distance formatting in AI services now uses Swift `FormatStyle` number formatting instead of legacy `String(format:)` interpolation in user-context prompts.

### Improved

- MetricKit telemetry logging now uses modern one-decimal `FormatStyle` formatting for memory, CPU, disk, animation hitch, and hang duration fields.
- Added repository-local `PRAGMATIC-RULES.md` and `SECURITY-GUIDELINES.md` documents to satisfy required guideline references in `AGENTS.md`.

### Changed

- Release metadata bump: updated app version/build to `0.7 (26)`.
- Documentation sync: aligned `README.md` version reference with `project.yml`.

## [0.6] - 2026-02-24

### Fixed

- Workouts: fixed a race condition during `preparing` state where discarding or finishing a workout before authorization completed could leave inconsistent in-memory state and continue parts of the startup pipeline.
- Workouts: replaced fragile fixed bottom spacing in scroll content with safe-area-aware bottom inset behavior so the primary CTA is not obscured by the tab bar.
- AI prompts: workout recommendation output now receives explicit app-language instruction to avoid mixed-language responses in localized UI.

### Improved

- Physical-device install workflow (`Scripts/install-on-device.sh`) now supports explicit paired Apple Watch install/verification by name.
- Physical-device install workflow now includes retry controls for build/install/verify and destination timeout tuning.
- Device install flow now auto-falls back from Xcode beta to stable Xcode when beta fails with embedded watch runtime mismatch.
- Device install flow now verifies iOS and watch bundle installation via `devicectl device info apps` after install.
- Dashboard/History/Workouts now share the same tab-bar-aware scroll inset modifier for consistent bottom-safe content layout.

### Tests

- Added workout regression tests for discard/finish during `preparing` to prevent startup-state leaks and stale transitions.
- Expanded state machine tests to cover `preparing -> discard` and `preparing -> finish` transitions.
- Updated install-script shell tests to validate iOS + watch install/verify paths and retry-aware behavior.
- Added prompt coverage ensuring workout recommendation prompt includes app-language directive.
- Strengthened workouts UI assertions to enforce tappable `Start Workout` button and frame separation from tab bar.

### Changed

- Release metadata bump: updated app version/build to `0.6 (25)`.
- Documentation sync: aligned release references across project docs.

## [0.5] - 2026-02-24

### Improved

- History AI weekly analysis flow is now resilient to concurrent in-flight generation: the History tab returns a deterministic fallback instead of surfacing transient contention failures.
- History tab analysis loading was consolidated to a single trigger path, reducing duplicate generation attempts and improving refresh consistency.
- Foundation Models one-shot request paths now use isolated per-call sessions, reducing context bleed across independent AI requests.

### Tests

- Added deterministic concurrent weekly-analysis coverage to ensure one active generation call with fallback behavior for overlapping requests.

### Changed

- Release metadata bump: updated app version/build to `0.5 (24)`.
- Documentation sync: aligned release references across project docs.

## [0.4.20] - 2026-02-11

### Changed

- Release metadata bump: updated app version/build to `0.4.20 (23)`.
- Documentation sync: aligned version references across project docs.

## [0.4.19] - 2026-02-11

### Improved

- AI Coach: stream-render telemetry now breaks down stale discards into `stale_discarded_before_render` and `stale_discarded_after_render`, while preserving aggregated `stale_discarded_updates`.
- AI Coach: aggregated `stale_discarded_updates` is now derived from phase counters (`before_render + after_render`) to eliminate counter drift risk in telemetry accounting.
- AI Coach: stream-render warning severity now triggers only for `stale_discarded_after_render` (work discarded after expensive render); pre-render stale discards are treated as informational coalescing.
- AI Coach: live stream markdown renderer is now injectable in `CoachService` (default unchanged), enabling deterministic performance/telemetry tests without altering production behavior.

### Tests

- Added invariant coverage ensuring aggregated stale-discard telemetry equals the sum of pre-render and post-render stale counters.
- Added deterministic coverage for stale-after-render telemetry using an intentionally slow injected live renderer.

### Changed

- Release metadata bump: updated app version/build to `0.4.19 (22)`.
- Documentation sync: aligned version references across project docs.

## [0.4.18] - 2026-02-11

### Improved

- AI Coach: `CoachService` now marks non-UI internal state with `@ObservationIgnored` to avoid unnecessary Observation churn during high-frequency streaming updates.
- AI Coach: stream-render telemetry now classifies expected coalescing/backpressure as informational (`ai.coach_stream_render_coalesced`) and reserves warnings for stale-discarded updates.
- AI Coach: stream-render telemetry field was clarified from dropped-by-backpressure to `uncommitted_updates` (scheduled but not committed), matching actual runtime accounting.
- AI Coach: stream-render telemetry now also captures explicit `dropped_by_backpressure` from `AsyncStream.YieldResult`, while preserving `uncommitted_updates` as a derived accounting metric.
- AI Coach: stream telemetry now tracks `terminated_input_yields` separately and only counts `scheduled_updates` for enqueued/dropped yields (excluding terminated attempts), improving accounting precision.
- AI Coach: stream markdown pipeline was simplified to a single background render worker that commits directly on `@MainActor`, removing an intermediate output stream stage and reducing concurrency surface area.
- AI Coach: live stream worker now performs a stale-generation pre-check before markdown rendering, avoiding expensive renders for already superseded snapshots.

### Tests

- Added coverage ensuring `clearConversation()` does not publish telemetry snapshots from a cancelled/stale generation.

### Changed

- Release metadata bump: updated app version/build to `0.4.18 (21)`.
- Documentation sync: aligned version references across project docs.

## [0.4.17] - 2026-02-11

### Changed

- Release metadata bump: updated app version/build to `0.4.17 (20)`.
- Documentation sync: aligned version references across project docs.

## [0.4.16] - 2026-02-11

### Improved

- AI Coach: streaming Markdown rendering was refactored to a single worker-pipeline per response (`AsyncStream` + `bufferingNewest(1)`), replacing the previous per-chunk task fan-out.
- AI Coach: live render updates now use generation-fenced delivery through an explicit input/output pipeline, preventing stale rendered chunks from being committed after cancellation or clear events.
- AI Coach: stream rendering keeps burst coalescing (debounce) while avoiding repeated detached-task churn under high-frequency model token snapshots.
- AI Coach: added explicit stream-render telemetry (`scheduled/committed/discarded/backpressure`) and live-render signposts for profile-driven tuning in Instruments/logs.

### Tests

- Added deterministic coverage to ensure `clearConversation()` blocks stale in-flight streamed Markdown renders from reappearing in the UI state.
- Added stress coverage for repeated `clearConversation()` + resend cycles and burst snapshot coalescing under stream backpressure.

## [0.4.15] - 2026-02-11

### Improved

- AI Coach: streaming Markdown rendering now uses an incremental parser + cached final `AttributedString` to keep scrolling smooth while the AI streams responses.
- AI Coach: hardened Markdown defaults (raw HTML disabled) and link opening policy (only `http/https`).
- AI Coach: added a guardrail for very large responses (live rendering falls back to plain text; final message still renders Markdown once).
- AI Coach: hardened streaming lifecycle with response-generation invalidation and explicit cancellation of pending live/final render tasks to prevent stale assistant messages.
- AI Coach: session creation was made protocol-driven (`CoachSessionProtocol`) to enable deterministic streaming tests without changing production behavior.
- AI Coach: empty stream completions now map to a localized invalid-response fallback instead of appending a blank assistant bubble.
- AI Coach: recoverable terminal stream failures now preserve already-generated assistant content and surface the error as banner state, matching modern chat UX expectations.
- AI Coach: stream bridge now uses newest-value buffering to avoid response snapshot backlog under bursty generation.
- AI Coach: partial assistant responses now carry explicit terminal-error metadata and display an inline warning under the message bubble for clearer interruption UX.
- AI Coach: global error banner is now suppressed when the latest assistant bubble already shows the same terminal interruption inline, reducing duplicate error UI noise.
- AI Coach: inline partial-response warnings are now specific and actionable by failure type (generation interruption vs conversation/token limit), instead of reusing generic error copy.
- AI Coach: inline partial-response warnings are now fully localized for `pt-BR` and `en` in the string catalog.
- AI Coach: `clearConversation()` now cancels any in-flight generation task immediately and resets streaming state, preventing latent/stale work from lingering in the background.

### Tests

- Added unit tests for the AI Markdown pipeline (parse options + incremental equivalence) and link policy.
- Reduced UI test flakiness in tab navigation by adding retries and coordinate-tap fallback when elements exist but are not hittable yet.
- Added deterministic `CoachService` streaming lifecycle tests covering clear-during-stream, duplicate chunks, large-response guardrails, terminal errors, and stale error suppression.
- Added deterministic coverage for empty-stream completion fallback in `CoachService`.
- Added deterministic coverage for preserving partial streamed content when a recoverable terminal generation error occurs.
- Added deterministic coverage for token-limit terminal failures preserving partial assistant content and message-level interruption metadata.
- Added deterministic coverage for AI Coach error-presentation policy (inline terminal warning vs global banner dedup).
- Added deterministic coverage for partial-response inline warning copy per error class in `AIServiceError`.
- Added deterministic coverage for explicit in-flight cancellation on `clearConversation()` and for safe immediate re-send after clear without stale-response leakage.
- Added localization coverage ensuring partial-response interruption notices resolve with explicit `pt-BR` translations.

### Security

- AI Markdown links now reject loopback/local hosts (`localhost`, `127.0.0.1`, `::1`, and `*.local`) in addition to scheme/host/credential checks.
- AI Markdown links now also reject private/link-local literal IP targets (RFC1918 IPv4, `169.254.0.0/16`, `fc00::/7`, and `fe80::/10`), reducing accidental local-network navigation from model output.
- AI Markdown links now reject additional non-public literal targets (CGNAT `100.64.0.0/10`, benchmarking `198.18.0.0/15`, IPv4 multicast/reserved ranges, IPv6 multicast `ff00::/8`, IPv6 documentation `2001:db8::/32`, and mapped non-public IPv4 literals).
- AI Markdown links now reject parser-dependent numeric host obfuscation forms (for example integer/short/hex/octal-like hosts such as `2130706433`, `127.1`, and `0x7f000001`) to reduce loopback bypass risk.

## [0.4.14] - 2026-02-10

### Changed

- Version bump for release packaging.

### Added

- `asc`-based TestFlight publishing script to test In-App Purchases on real devices: `Scripts/test-payments-device.sh`.

## [0.4.13] - 2026-02-10

### Fixed

- Step/distance/floors totals now rely on HealthKit's built-in aggregation (`HKStatisticsQuery` / daily `HKStatisticsCollectionQuery`) instead of a custom "pick one source per time bucket" heuristic. This aligns app totals with Health's own deduplication and user-configured source priority, reducing surprising History/Dashboard numbers on multi-device setups (iPhone + Watch + third-party).

### Debug

- Updated HealthKit debug screen copy to clarify that per-source totals are for diagnosis only and may exceed the aggregated total due to overlapping samples.

## [0.4.12] - 2026-02-10

### Changed

- Version bump for release packaging.

## [0.4.11] - 2026-02-10

### Improved

- Health Access help is now fully localized (pt-BR/en) and includes clearer guidance on Health “Data Sources & Access” ordering.
- Simulator E2E became more resilient to rare Accessibility (AX) initialization flakes by waiting for simulator boot readiness and avoiding blind xcodebuild retries.

## [0.4.10] - 2026-02-10

### Fixed

- Restored required entitlements for HealthKit + App Groups (widgets), and added an XcodeGen `postGenCommand` to keep entitlements correct after `xcodegen generate`. This fixes missing HealthKit data on real devices and widget data sharing regressions after regenerating the project.

### Improved

- Health Access help now includes guidance on Health app “Data Sources & Access” ordering, since source priority can change which step totals are shown as primary.

## [0.4.9] - 2026-02-10

### Fixed

- HealthKit totals are now merged across sources using time buckets (5 to 60 min depending on range) instead of picking a single source for the whole day. This prevents undercounting when users switch devices during the day, while still avoiding obvious double counting from overlapping sources.
- HealthKit source selection no longer sums multiple Apple sources (e.g., Watch + iPhone) within the same bucket, reducing inflated Apple totals in mixed-source setups.

### Debug

- HealthKit debug screen now shows the app's computed total (bucket-merged) alongside per-source raw totals for easier diagnosis.

## [0.4.8] - 2026-02-10

### Fixed

- Health access help now supports requesting Health authorization directly from the in-app instructions sheet (when iOS still allows prompting), with clearer error surfacing.
- E2E/UI automation stability improved by removing an early `XCUIApplication.windows` snapshot query that can fail transiently on some simulator environments.

### Tests

- Expanded UI test coverage to validate that Health Access help opens from Settings and can be dismissed reliably.

## [0.4.7] - 2026-02-10

### Fixed

- HealthKit per-source selection is now more robust: when Apple sources are present but significantly lower than a third-party source, the app will prefer the strongest non-Apple source to avoid undercounting for users whose primary step data comes from third-party devices.
- Health access troubleshooting no longer points users to generic app Settings only; it now includes in-app instructions for enabling Health access in the Health app (and the Settings > Health alternative path).

## [0.4.6] - 2026-02-10

### Fixed

- HealthKit step totals now fall back to non-Apple sources when Apple sources exist but sum to zero, avoiding empty history for users whose step data comes from third-party providers.

## [0.4.5] - 2026-02-10

### Fixed

- HealthKit read access is now handled using the request-status API (instead of inferring from share/write authorization), avoiding false "denied" states.
- Health permission prompts now request only the write types the app actually writes (workouts), improving the chance users grant the needed read access for steps/history.
- History now shows a clearer troubleshooting state when Motion has steps but Health history is empty, guiding users to Settings.
- Widgets are now embedded into the iOS app bundle correctly, ensuring the widget extension is installable and discoverable.

## [0.4.4] - 2026-02-10

### Fixed

- HealthKit data no longer fails silently: Dashboard/History now surface a clear permission state when Health access is missing.
- Step tracking falls back to Motion for steps mode when Health access is unavailable or denied, preventing misleading zero values.

### Improved

- Onboarding permissions screen now requests Motion & Health access and shows current permission status.
- Widgets now reload timelines when shared step data changes (throttled to reduce battery impact).
- watchOS sync is faster and more reliable via `updateApplicationContext` and reachable messaging (with throttled `transferUserInfo` fallback).

## [0.4.3] - 2026-02-10

### Improved

- Improved end-to-end QA reliability with more stable screen identifiers and deterministic UI test configuration.
- CI now publishes an E2E summary and produces richer artifacts for faster triage.

### Tests

- Expanded UI test coverage across primary screens, including Badges and Training Plans navigation.

## [0.4.2] - 2026-02-09

### Fixed

- Tip jar purchases now finish reliably even if the app is interrupted, by processing unfinished StoreKit transactions before handling live updates.
- Tip jar no longer shows a "thank you" state unexpectedly when opening the About screen; completion is only surfaced for in-flight purchases.

### Improved

- Tip jar purchase flow now handles restricted payment environments with a clearer error message.

## [0.4.1] - 2026-02-06

### Fixed

- Tip jar support section no longer shows a price placeholder when the product is unavailable.
- StoreKit Configuration now resolves correctly when launched from Xcode — tip jar shows product and price instead of "Product not available."

## [0.4] - 2026-02-04

### Added

- Optional one-time tip jar in About (“Buy me a coffee”) using StoreKit.
- Onboarding skip action for faster setup.

### Improved

- Clarified AI coaching guardrails and surfaced safety disclaimers across AI surfaces.
- Standardized step formatting across dashboard, history, watch, and widgets.
- Refined AI Coach and tip-jar localization copy for en/pt-BR.
- Lightened the progress ring, goal status badges, and locked medal styling for calmer hierarchy.
- Aligned selection, warning, and success accents to design tokens for consistent UI states.
- Documented UI design references and token usage for contributor alignment.

## [0.3] - 2026-02-03

### Fixed

- HealthKit totals now merge overlapping Apple Watch and iPhone samples to prevent double counting while still including non-overlapping device data.

### Observability

- Added structured logs when multi-source HealthKit merges remove overlaps in daily and cumulative totals.

### Tests

- Added HealthKitSourcePolicy priority coverage plus merge tests for overlapping and cross-midnight samples.

## [0.2] - 2026-02-03

### Fixed

- Hardened step merging to consistently prefer HealthKit totals and avoid Apple Watch double counting in live updates.
- Stabilized MotionService delivery tests to remove flaky concurrency timing.
- HealthKit daily summaries now use collection queries and sync respects activity settings (wheelchair/manual distance) to avoid mismatched counts.

### Tests

- Added StepTrackingService merge tests for HealthKit vs pedometer scenarios.
- Extended sync coverage for activity settings and daily summaries.
- Full unit suite now passes deterministically.

## [0.1] - 2026-01-29

Initial public release.

### Features

- **Step Tracking** — HealthKit integration with real-time pedometer and Apple Watch merging
- **AI Insights** — On-device AI analysis using Apple Foundation Models (no cloud, no data leaves device)
- **AI Coach** — Personalized coaching with structured responses via FoundationModelsService
- **AI Training Plans** — AI-generated walking programs adapted to fitness level
- **Workouts** — Active workout sessions with Live Activities and HealthKit recording
- **Badges & Achievements** — Unlockable badges with streak tracking
- **watchOS Companion** — Bidirectional sync via WatchConnectivity
- **Widgets** — Step count, progress ring, and weekly chart widgets (Lock Screen + Home Screen)
- **Accessibility** — Wheelchair push tracking mode, VoiceOver, Dynamic Type
- **Localization** — English and Portuguese Brazil (pt-BR)
- **Design System** — iOS 26 Liquid Glass support with unified design tokens and haptics

### Technical

- Swift 6.2 with strict concurrency (`complete` mode, warnings-as-errors)
- SwiftUI + SwiftData with App Group sharing across iOS, watchOS, and widgets
- Protocol-first architecture with `@MainActor @Observable` services
- XcodeGen for project generation
- Swift Testing framework for unit tests
- Background task scheduling for periodic sync
- DataConfidence pattern to prevent AI hallucination on unreliable data
