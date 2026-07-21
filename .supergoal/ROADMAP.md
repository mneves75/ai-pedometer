# Roadmap: ai-pedometer audit-fix run (Tier 1 + Tier 2)

**Task:** Fix the 22 vetted audit findings from the 2026-07-21 deep survey (correctness, perf, deps, tests, docs/DX) with per-phase verification
**Type:** brownfield, bugfix, refactor
**Created:** 2026-07-21
**Total phases:** 8

## Context summary

- **Stack:** Swift 6.2 (strict concurrency, warnings-as-errors), SwiftUI+Observation, SwiftData, HealthKit/CoreMotion, on-device Foundation Models, RevenueCat; targets AIPedometer / AIPedometerWatch / AIPedometerWidgets / AIPedometerTests / AIPedometerUITests; XcodeGen via project.yml.
- **Package manager:** SwiftPM (single dep: RevenueCat, pinned immutably).
- **Build / test / lint commands:**
  - Unit: `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test`
  - Targeted: same + `-only-testing:AIPedometerTests/<SuiteName>`
  - Lint: `ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all`
  - Shell lint: `shellcheck Scripts/*.sh Scripts/tests/*.sh Scripts/tests/fixtures/*.sh Scripts/lib/*.sh .githooks/pre-commit`
  - Sync gate: `bash Scripts/check-agents-sync.sh`
  - Script tests: `bash Scripts/tests/xcresult-summary.sh`
  - E2E (phase 8 only): `bash Scripts/e2e-simulator.sh`
- **Toolchain pin (CRITICAL):** `xcode-select` points at Xcode 27 BETA on this machine; the pinned RevenueCat does NOT compile there. EVERY xcodebuild command MUST use `DEVELOPER_DIR=/Applications/Xcode.app` (stable 26.6). Never use the beta.
- **Risky areas:** purchase marker state machine (revenue-critical both directions), workout/goal persistence contracts, Shared/ compiles into watchOS arm64_32 (32-bit Int).

## Assumptions

- All changes stay UNCOMMITTED; the main session reviews the diff and commits (repo contract for delegated work).
- Files owned by the main session (never touch): `.supergoal/`, `memory/`, `MEMORY.md`, `plans/`, `agent_planning/`, `CHANGELOG.md`, `project.yml` version fields, anything under `output/`.
- New/deleted Swift source files require `xcodegen generate` (auto-runs `Scripts/restore-entitlements.sh`) before building.
- iOS Simulator runtimes were restored 2026-07-20 (iOS 26.5 23F77, watchOS 26.5 23T570); `iPhone 17` destination exists.
- The availability self-heal fix (FoundationModelsService observation seam, HEAD `2c7dbb7`) is DONE — do not re-open its design; phase 5 only removes its now-dead stored-session bookkeeping.

## Risk top 3

1. **Purchase reconciliation clears a genuine pending transaction** — likelihood: M, mitigation: distinct `attempting` vs confirmed `pending` phases; never auto-clear confirmed pending; conservative verified-transaction reconcile only; existing pending-survival tests must stay green.
2. **A "dead" symbol turns out to have a dynamic caller** — likelihood: L, mitigation: every deletion requires a repo-wide `rg` proof printed in the transcript; full unit + e2e gates.
3. **Perf "quick wins" alter observable behavior** — likelihood: M, mitigation: keep all generation/cancellation guards; preserve documented serialization (refreshChain untouched); tests pin behavior before/after within each phase.

## Phase map

| # | Phase | Depends on | Deliverable |
|---|-------|------------|-------------|
| 1 | Correctness: goal save + sync windows | — | COR-01, COR-03 fixed + regression tests |
| 2 | Purchase marker reconciliation | — | COR-02 fixed + recreation tests |
| 3 | Perf quick wins | — | PERF-01/02/03/07 + tests |
| 4 | Unify GenerationError mapper | — | DEPS-01 shared mapper + tests |
| 5 | Dead code removal | 4 | TD-01/02/03, DEPS-07 removed + gates |
| 6 | Test coverage additions | 5 | TEST-02, TEST-03, TEST-01R suite rename |
| 7 | Docs + DX batch | — | DOCS-01/02/03, DX-02/03/04/05 |
| 8 | Polish & Harden | 1..7 | Full gates green, diff hygiene proven |

---

## Phase 1 — Correctness: goal save + sync windows

**Why:** Two confirmed split-brain/off-by-one defects on user-visible data (goal value, sync day windows).

**Deliverables:**
- `GoalService.setGoal` reports save success/failure; `StepTrackingService.updateGoal` publishes only on success
- Sync windows built with calendar-day arithmetic matching `fetchDailySummaries(days:)` convention
- Regression tests for both

**Acceptance criteria:**
- [ ] Failing-save injection leaves `currentGoal` and shared/widget state at the previous durable goal
- [ ] Successful goal change still publishes everywhere (existing tests green)
- [ ] Cold-start and pull-to-refresh windows produce exactly 30 and 7 calendar buckets at a fixed clock
- [ ] DST-boundary test (spring + fall) yields the same bucket counts
- [ ] Full `AIPedometerTests` suite green

**Mandatory commands:**
- Targeted suites: GoalServiceTests, HealthKitSyncServiceTests
- Full unit suite + ast-grep scan

**Evidence required:** red test output before fix, green after; bucket-count assertions in transcript

**Dependencies:** none

---

## Phase 2 — Purchase marker reconciliation

**Why:** An orphaned pre-await purchase marker currently disables purchases across every later launch; fixing it wrong could double-charge — the phase isolates this revenue-critical state machine.

**Deliverables:**
- Distinct `attempting` vs platform-confirmed `pending` persisted states in `PremiumAccessStore` (mirrored in `TipJarStore` if its marker contract matches)
- Launch reconciliation of `attempting` against verified unfinished transactions / CustomerInfo
- Process-recreation tests for orphaned markers and confirmed-pending preservation

**Acceptance criteria:**
- [ ] Marker written before the purchase await returns, with no platform transaction, is cleared at next launch reconcile
- [ ] Confirmed pending (platform transaction exists / Ask-to-Buy style) survives recreation — existing tests green
- [ ] `purchase()` remains single-flight; no duplicate attempt path introduced
- [ ] PremiumAccessStoreTests + TipJarStoreTests green; full unit suite green

**Mandatory commands:**
- `-only-testing:AIPedometerTests/PremiumAccessStoreTests -only-testing:AIPedometerTests/TipJarStoreTests`
- Full unit suite + ast-grep scan

**Evidence required:** red test output before fix (orphan marker blocks purchase), green after; explicit statement of how confirmed-pending is distinguished

**Dependencies:** none

---

## Phase 3 — Perf quick wins

**Why:** Four independently-confirmed waste sites on hot paths (workout Live Activity, today-refresh, weekly AI cache, background-export fetches).

**Deliverables:**
- Live Activity updates throttled (interval or step delta) in `WorkoutSessionController`
- `performRefreshTodayData`: distance/floors/heartRate fetched concurrently after steps
- `HistoryView` load path uses the week cache (`forceRefresh: false`); explicit pull-to-refresh still forces
- Bounded SwiftData fetches in pending-export paths

**Acceptance criteria:**
- [ ] LA update skipped when below interval/delta; still updates on milestone/terminal events
- [ ] The three independent queries overlap (test or instrumentation evidence); cancellation guards intact
- [ ] Repeat History visits without week change perform no new model inference; pull-to-refresh still regenerates
- [ ] Existence check uses fetchCount/fetchLimit; batch predicate pushes stored properties into `#Predicate`
- [ ] refreshChain serialization untouched; full unit suite green

**Mandatory commands:**
- Targeted suites: WorkoutSessionControllerTests, HealthKitServiceTests, HealthKitSyncServiceTests, InsightServiceTests
- Full unit suite + ast-grep scan

**Evidence required:** per-fix red/green or measurement; explicit note of any behavior change

**Dependencies:** none

---

## Phase 4 — Unify GenerationError mapper

**Why:** Two divergent copies of the `GenerationError`→`AIServiceError` mapping (one with plain `default`, one with `@unknown default`); future SDK cases silently collapse in one of them, and the iOS 27 `assetsUnavailable` deprecation becomes a build error the day the toolchain migrates.

**Deliverables:**
- One shared mapper (e.g. `AIServiceError.init(generationError:)` or a free function in the AI layer) with `@unknown default`
- Both `FoundationModelsService.mapError` and `CoachService.mapError` delegate to it
- Unit tests for every mapped case + the unknown-case path

**Acceptance criteria:**
- [ ] Exactly one switch over `LanguageModelSession.GenerationError` remains in production code
- [ ] Both services return identical mappings for identical inputs (tests)
- [ ] `@unknown default` present; no plain `default` in the mapper
- [ ] Builds warning-clean on stable Xcode 26.6 (warnings-as-errors)

**Mandatory commands:**
- Targeted suites: AIServiceErrorTests, FoundationModelsServiceTests, CoachServiceStreamingTests
- Full unit suite + ast-grep scan

**Evidence required:** grep proof of one remaining mapper; test output

**Dependencies:** none

---

## Phase 5 — Dead code removal

**Why:** Vetted dead inventory (zero call sites proven during audit) inflates every target's compile/warning/localization surface.

**Deliverables:**
- `FoundationModelsService`: remove stored `session`, `configureSession`, `streamResponse`, `configure(with:)`; simplify refresh to availability-state only (KEEP the observation seam, `systemAvailability` injection, os_log line — committed design)
- Delete `Shared/Utilities/Hashing.swift`, `Shared/Models/TimeRange.swift`, `Shared/DesignSystem/GlassMorphTransition.swift` and unused helpers in `Shared/Extensions/View+Glass.swift` (only the ones with zero call sites)
- Remove `SyncPolicy.staleDataPruneThreshold` + its tautology test (fixture test at HealthKitSyncServiceTests.swift:795 switches to a local literal)
- Delete `NotificationServiceProtocol`, `HealthKitSyncServiceProtocol` (+ conformances)
- Delete `AppConstants.UserDefaultsKeys.lastWidgetRefresh`
- `xcodegen generate` after file deletions

**Acceptance criteria:**
- [ ] Every deleted symbol has a repo-wide `rg` zero-call-site proof printed in the transcript
- [ ] Full unit suite green (incl. FoundationModelsServiceTests, BadgeServiceTests)
- [ ] iOS app + watchOS scheme both build (Shared/ hits arm64_32)
- [ ] ast-grep scan clean

**Mandatory commands:**
- Full unit suite
- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometerWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (42mm)' build`
- ast-grep scan

**Evidence required:** per-symbol rg proofs; build/test outputs; note that BadgeService.configure(with:) is a DIFFERENT method and stays

**Dependencies:** phase 4 (both touch `FoundationModelsService.swift`)

---

## Phase 6 — Test coverage additions

**Why:** The finish-workout journey, recovery card, and AI-coach UI states have zero E2E coverage; the StepTrackingService tests live in a misnamed file.

**Deliverables:**
- XCUITest: start → end workout → sheet dismisses → recent list updated
- XCUITest: recovery card finish/discard flow (add a UI-testing-gated seed seam ONLY if no existing seam works — mirror existing launch-flag patterns)
- Launch flag `-force-ai-unavailable` (UI-testing-gated, Release-inert) + 2-3 AI Coach UI tests (banner visible, input disabled)
- Move StepTrackingService-instantiating tests from `HealthKitServiceTests.swift` into a new `StepTrackingServiceTests.swift`; `xcodegen generate` after renames

**Acceptance criteria:**
- [ ] New XCUITests pass via `-only-testing:AIPedometerUITests`
- [ ] New launch flags are inert in Release (`isOverridable` false)
- [ ] Moved tests pass under the new suite name; no test count loss (592 + additions)
- [ ] ast-grep scan clean

**Mandatory commands:**
- `-only-testing:AIPedometerUITests` run
- Full unit suite + ast-grep scan

**Evidence required:** test names + counts before/after; flag-gating proof (Release path returns false)

**Dependencies:** phase 5

---

## Phase 7 — Docs + DX batch

**Why:** Doc drift and CI/tooling friction confirmed against source; all S-effort.

**Deliverables:**
- `docs/agents/testing.md`: shellcheck list copied exactly from `ci.yml`; drop duplicate python test line
- `docs/agents/coding-style.md`: empty Formatting section → state "no enforced formatter — match surrounding style"
- `CLAUDE.md` + `AGENTS.md`: `autoreview` skill pointer → `review` (edits ABOVE the `## GUIDELINES-REF` marker only; keep `check-agents-sync.sh` green)
- Both CI workflows: resolve newest `/Applications/Xcode_26*.app` at runtime with fallback
- `CONTRIBUTING.md`: hooks + `brew install ast-grep ripgrep shellcheck` + `-parallel-testing-enabled NO` alignment
- `Scripts/e2e-simulator.sh`: `command -v rg python3` preflight with brew hint
- `Scripts/restore-entitlements.sh`: `trap 'rm -f "$temp_file"' RETURN` in `write_entitlement`

**Acceptance criteria:**
- [ ] `bash Scripts/check-agents-sync.sh` green
- [ ] `shellcheck` on the full CI list green
- [ ] `bash Scripts/tests/xcresult-summary.sh` green
- [ ] `bash Scripts/verify-entitlements.sh` green
- [ ] No behavior change to app code

**Mandatory commands:**
- check-agents-sync, shellcheck (full list), script tests, verify-entitlements

**Evidence required:** each gate's output; note any item found already-fixed and skipped with proof

**Dependencies:** none

---

## Phase 8 — Polish & Harden

**Why:** Re-verify the cumulative diff against every repo gate before the main session's release steps.

**Acceptance criteria:**
- [ ] Full `AIPedometerTests` green (report exact count; must be ≥ 592 minus deliberate removals)
- [ ] `bash Scripts/e2e-simulator.sh` full pass (unit + 16+ XCUITest + watchOS build)
- [ ] ast-grep scan clean; `bash Scripts/verify-entitlements.sh` green; `bash Scripts/check-agents-sync.sh` green
- [ ] `git diff --stat` reviewed: no debug prints, no TODO/FIXME added, no out-of-scope files (memory/, .supergoal/, plans/, output/, CHANGELOG.md, project.yml version fields untouched)
- [ ] One-paragraph summary per phase of what changed and what was deliberately NOT changed

**Mandatory commands:**
- Full unit suite, e2e script, ast-grep scan, verify-entitlements, check-agents-sync

**Evidence required:** every gate's tail output; final `git diff --stat`

**Dependencies:** phases 1..7
