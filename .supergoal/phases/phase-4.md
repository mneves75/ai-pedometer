SUPERGOAL_PHASE_START
Phase: 4 of 8 — Unify GenerationError mapper
Task: Replace two divergent GenerationError→AIServiceError mappers with one shared mapper
Type: brownfield, refactor
Mandatory commands: DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test, ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all
Acceptance criteria: 4
Evidence required: grep proof of one remaining mapper, test output
Depends on phases: none

## Shared context (read first)

- Repo: /Users/mneves/dev/PROJETOS_MOBILE/ai-pedometer. Swift 6.2 strict concurrency, warnings-as-errors, Swift Testing.
- TOOLCHAIN: every xcodebuild MUST use `DEVELOPER_DIR=/Applications/Xcode.app` (stable 26.6). NEVER the Xcode 27 beta.
- Leave ALL changes uncommitted. Never run git commit/push/add. Never touch: `.supergoal/`, `memory/`, `MEMORY.md`, `plans/`, `agent_planning/`, `CHANGELOG.md`, `project.yml` version fields, `output/`.
- If you add a new Swift file, run `xcodegen generate` before building (it auto-runs Scripts/restore-entitlements.sh — leave entitlements as the script writes them).

## Why

`GenerationError`→`AIServiceError` mapping exists twice and has already diverged: `FoundationModelsService.mapError` uses `@unknown default` (future-proof) while `CoachService.mapError` uses a plain `default` (future SDK cases collapse silently into a generic error with no exhaustiveness diagnostic). The iOS 27 SDK also deprecates `assetsUnavailable`; keeping one mapper makes that migration a one-line change later.

## Work

Current state (verified):
- `AIPedometer/Core/AI/FoundationModelsService.swift` `mapError(_:)`: 6-case switch incl. `.assetsUnavailable → .modelUnavailable(.modelNotReady)`, `.rateLimited/.concurrentRequests → .generationFailed("Please try again in a moment")`, ends `@unknown default`.
- `AIPedometer/Core/AI/Services/CoachService.swift` `mapError(_:)`: 4-case switch with plain `default → .generationFailed(underlying: error.localizedDescription)`; lacks the rate-limited special-case.

Required change:
1. Create ONE shared mapping (preferred: `extension AIServiceError { init(generationError: ...) }` or a free function near `AIServiceError` in `AIPedometer/Core/AI/`), preserving the RICHER FoundationModelsService semantics (including the rate-limit message) and `@unknown default`.
2. Both services' `mapError` delegate to it (keep their non-GenerationError fall-through behavior identical).
3. Do not rename or change any `AIServiceError` case — UI and tests depend on them.

Test plan: unit tests covering every mapped case + an unknown-case path (construct the closest thing to a future case the current SDK allows, or test the default path via a non-GenerationError input if a synthetic case can't be constructed — say which in the transcript). Put them in `AIPedometerTests/AI/AIServiceErrorTests.swift` (extend the existing file).

## Acceptance criteria (all must pass — verify each in transcript)

1. Repo-wide grep proof that exactly one switch over `LanguageModelSession.GenerationError` remains in production code (show the grep).
2. Both services return identical mappings for identical GenerationError inputs (tests).
3. The mapper has `@unknown default`; no plain `default` remains in it (show the code).
4. Full `AIPedometerTests` green; ast-grep scan clean; build warning-clean under stable Xcode (warnings-as-errors stays on).

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests/AIServiceErrorTests -only-testing:AIPedometerTests/FoundationModelsServiceTests -only-testing:AIPedometerTests/CoachServiceStreamingTests test`
- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test`
- `ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all`

## Evidence required in transcript

- The single-mapper grep proof
- New test names + results
- Note on how you handled the iOS 27 `assetsUnavailable` deprecation (must still compile clean on SDK 26.5 today)

## Notes

- Do NOT bump the RevenueCat pin or touch the toolchain — the Xcode 27 migration is a separate user decision; this phase only makes the code ready for it.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in .supergoal/PROTOCOL.md without further
instruction needed here.
