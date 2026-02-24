# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Changed

- Release metadata bump: updated app version/build to `0.71 (27)`.
- Documentation sync: aligned release references across `README.md`, App Store playbook examples, and agent build docs.
- Removed redundant watch-only shim file `AIPedometerWatch/WatchDataModels.swift`.

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
