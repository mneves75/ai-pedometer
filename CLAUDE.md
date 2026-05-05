# CLAUDE.md

This repository expects operator behavior, not passive assistance. `AGENTS.md` is the full operating contract; this file is the compact Claude-facing checklist for `AIPedometer`.

## Read First

At the start of every session, in this exact order:

1. `pwd`
2. `git rev-parse --show-toplevel`
3. `MEMORY.md`
4. `memory/YYYY-MM-DD.md` for today, if present
5. `FOR_YOU_KNOW.md`
6. `PRAGMATIC-RULES.md`
7. `SECURITY-GUIDELINES.md`

Then read the task-relevant docs before editing:

- `README.md`
- `TECH_STACK.md`
- `APP_FLOW.md`
- `docs/agents/build-and-dev.md`
- `docs/agents/testing.md`
- `docs/agents/project-structure.md`
- `docs/agents/coding-style.md`
- `docs/agents/git-workflow.md`

## Project Snapshot

- Product: iOS + watchOS pedometer with widgets, Live Activities, HealthKit/CoreMotion tracking, and local Apple Foundation Models AI.
- Tooling: Swift 6.2, Xcode 26.x, XcodeGen, SwiftUI, Observation, SwiftData, Swift Testing, XCUITest.
- Source of truth: `project.yml`; regenerate `AIPedometer.xcodeproj` after target/package/entitlement/new Swift source changes.
- Premium behavior: RevenueCat-backed AI surfaces fail closed when not configured.
- Privacy posture: health and AI data stays local-first; do not add cloud AI calls unless explicitly requested.

## Common Commands

```bash
xcodegen generate
Scripts/restore-entitlements.sh
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' test
bash Scripts/e2e-simulator.sh
bash Scripts/check-agents-sync.sh
bash Scripts/verify-device-identifiers.sh
```

Physical-device install must use device names, not hardcoded identifiers:

```bash
bash Scripts/install-on-device.sh --device-name "<iPhone Name>" --launch
bash Scripts/install-on-device.sh --device-name "<iPhone Name>" --watch-name "<Apple Watch Name>" --launch
```

## Reproducer-First Bugs

For bug reports:

1. Start by writing a test that reproduces the bug.
2. Prove the test fails before changing production code.
3. Use subagents for fix attempts when that improves speed or coverage.
4. Close the bug only with a passing reproducer and relevant verification.

Do not skip the reproducer step. `Executed 0 tests` is not evidence.

## Swift and Product Rules

- Keep Swift 6.2 strict concurrency and warnings-as-errors clean.
- Prefer existing services, shared models, and design/localization utilities before adding new abstractions.
- Put cross-target code in `Shared/` when iOS, watchOS, widgets, or Live Activities need the same behavior.
- Add user-facing strings to `Shared/Resources/Localizable.xcstrings`.
- `pt-BR` devices use Portuguese; every other locale defaults to English.
- Check official Apple documentation in `/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation` before guessing iOS/watchOS 26 behavior.

## Shell Rules

- Avoid `head`, `tail`, `less`, and `more` in monitoring and evidence-gathering flows.
- Avoid truncation pipes such as `| head -n 20`.
- Prefer direct commands or tool-specific limit flags.
- Prefer reading logs directly instead of chaining pipes.

## Figure It Out

You have internet access, browser automation, and shell execution.

- If you do not know how to do something, learn it.
- Search documentation, tutorials, APIs, and source code before declaring limits.
- Before calling something impossible, search at least 3 approaches, try at least 2, and record the specific failures.
- Keep iterating until there is a grounded reason to stop.

You are not a helpdesk. You are an operator. Operators ship.

## Project Memory Files

- `FOR_YOU_KNOW.md`: engaging plain-language project explainer and landmine map.
- `MEMORY.md`: long-term curated repo and user memory.
- `memory/YYYY-MM-DD.md`: timestamped daily journal.

If it is not written down, it is not remembered.
