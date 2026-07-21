SUPERGOAL_PHASE_START
Phase: 6 of 8 — Test coverage additions
Task: Finish-workout XCUITest journey, AI-forcing launch seam + coach UI tests, suite rename
Type: brownfield, tests
Mandatory commands: DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerUITests test, DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test, ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all
Acceptance criteria: 4
Evidence required: test names + counts before/after, Release flag-gating proof
Depends on phases: 5

## Shared context (read first)

- Repo: /Users/mneves/dev/PROJETOS_MOBILE/ai-pedometer. Swift 6.2 strict concurrency, warnings-as-errors; unit tests use Swift Testing; UI tests use XCUITest (16 tests today in `AIPedometerUITests/AIPedometerUITests.swift`).
- TOOLCHAIN: every xcodebuild MUST use `DEVELOPER_DIR=/Applications/Xcode.app` (stable 26.6). NEVER the Xcode 27 beta.
- Leave ALL changes uncommitted. Never run git commit/push/add. Never touch: `.supergoal/`, `memory/`, `MEMORY.md`, `plans/`, `agent_planning/`, `CHANGELOG.md`, `project.yml` version fields, `output/`.
- After adding/renaming Swift files run `xcodegen generate` before building.
- Launch flags live in `Shared/Utilities/LaunchConfiguration.swift` and MUST be inert in Release: every override guards on `isOverridable`, which is compile-time `false` in Release. Mirror the existing patterns (`-ui-testing`, `-force-premium-on/off`, `-force-healthkit-sync-on/off`) exactly.
- UI tests drive tabs by ordinal when the Label identifier is missing and MUST assert the destination screen's own accessibility marker after every tap (existing driver does this — reuse it).

## Why

The start→end→persist→visible workout journey and the recovery card have no E2E coverage; the AI Coach tab is only asserted to render; the StepTrackingService direct tests live in the misnamed `HealthKitServiceTests.swift`.

## Work

### TEST-02 — finish-workout journey + recovery card

- Extend the active-workout XCUITest: start workout → tap `A11yID.ActiveWorkout.endButton` (`active_workout_end_button`) → sheet dismisses → recent-workouts area no longer shows the empty state.
- Add a recovery-flow test for the recovery card (`workouts_recovery_card`, `workouts_finish_recovered_workout_button`, `workouts_discard_recovered_workout_button`). First check for an existing seed seam (demo mode / existing launch flags). If none fits, add a MINIMAL UI-testing-gated launch flag to seed an unfinished session — follow the existing flag patterns, Release-inert. If a seed seam would require touching the workout state machine, STOP and report instead.

### TEST-03 — AI availability forcing seam + coach UI tests

- Add `-force-ai-unavailable` (and optionally `-force-ai-available`) to `LaunchConfiguration`, gated exactly like the premium flags (UI-testing only; Release returns false via `isOverridable`).
- `FoundationModelsService.checkAvailability`/`refreshAvailability` consult the flag BEFORE the real system value (precedence: `isUITesting()` existing early return is about the whole UI-testing mode — integrate cleanly: forced-unavailable wins when the flag is present).
- 2–3 XCUITests: AI Coach shows the unavailable state view with the flag; input is not interactable; Dashboard shows the availability banner with the flag.
- Unit-test the flag parsing in `LaunchConfigurationTests` (mirror the premium flag tests).

### TEST-01R — honest suite names

- Move the tests that instantiate `StepTrackingService` directly (e.g. at `AIPedometerTests/Services/HealthKitServiceTests.swift` lines ~363, ~389, ~639, ~671, ~1589 and related) into a new `AIPedometerTests/Services/StepTrackingServiceTests.swift`. Keep genuine HealthKitService tests where they are. Do not change any test body — move only (imports/fixtures may move with them as needed). Run `xcodegen generate` after creating the file.

## Acceptance criteria (all must pass — verify each in transcript)

1. New XCUITests pass: finish-journey, recovery flow(s), AI-unavailable coach states (names + results printed).
2. Flag-gating proof: in Release semantics (`isOverridable == false`) the new flags return false (unit test or code inspection shown).
3. Unit test count before/after printed; no test lost in the rename (592 + additions from phases 1–4 and this phase).
4. Full `AIPedometerTests` + `AIPedometerUITests` green; ast-grep scan clean.

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerUITests test`
- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test`
- `ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all`

## Evidence required in transcript

- New test names and results (unit + UI)
- The Release-inertness proof for new flags
- Move-only diff summary for the suite rename (no behavior edits)

## Notes

- UI tests must remain deterministic: no Apple Intelligence dependency in any UI test (the simulator has none) — the flag forces the unavailable state, never the reverse in XCUITest.
- Keep `LaunchConfiguration.isUITesting()` early return in FoundationModelsService coherent: UI-testing defaults to deviceNotEligible unless explicitly forced otherwise by the new flag.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in .supergoal/PROTOCOL.md without further
instruction needed here.
