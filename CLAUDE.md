# CLAUDE.md

This repository expects operator behavior, not passive assistance. `AGENTS.md` is the full operating contract; this file is the compact Claude-facing checklist for `AIPedometer`.

## Purpose and Quality

- Operate as a senior Apple-platform engineer; keep responses concise and clarify material uncertainty before coding.
- Challenge assumptions with evidence. Follow KISS and prefer clear, maintainable, current patterns over shortcuts or speculative abstraction.
- Add comments only for tricky constraints, then review and verify the result twice before completion.
- List any unresolved questions at the end of a response when material questions remain open.

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
- `docs/revenuecat/README.md` and `docs/revenuecat/apple-payments-setup.md` for premium, RevenueCat, Apple payments, StoreKit subscription, entitlement, or paywall work
- `docs/agents/build-and-dev.md`
- `docs/agents/testing.md`
- `docs/agents/project-structure.md`
- `docs/agents/coding-style.md`
- `docs/agents/git-workflow.md`

Do not create standalone completion-report markdown files. Temporary markdown plans belong under `agent_planning/` and obsolete plans under `agent_planning/archive/`. Do not use emojis in repository documentation. For complex features or significant refactors, run an ExecPlan (living execution plan per `~/dev/GUIDELINES-REF/EXECPLANS-GUIDELINES.md`) and keep it under `agent_planning/` while active.

## Code Discovery and AST-Grep

- Prefer the codebase knowledge graph when available.
- For syntax-aware or structural search, default to `ast-grep --lang swift -p '<pattern>'` and select the appropriate language for other files. Use `rg` or `grep` only for intentional plain-text/config/doc searches or when structural matching is insufficient.
- Run the exact repository linter with `bash .githooks/pre-commit`; it scans the staged Git snapshot with every ast-grep ignore source disabled and blocks findings or a missing ast-grep binary. Do not bypass it.

## Project Snapshot

- Product: iOS + watchOS pedometer with widgets, Live Activities, HealthKit/CoreMotion tracking, and local Apple Foundation Models AI.
- Tooling: Swift 6.2, Xcode 26.x, XcodeGen, SwiftUI, Observation, SwiftData, Swift Testing, XCUITest.
- Source of truth: `project.yml`; regenerate `AIPedometer.xcodeproj` after target/package/entitlement/new Swift source changes. When bumping `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`, **always edit `project.yml` first, then re-run `xcodegen generate`** — the generated `.xcodeproj` snapshots those fields, so a build started after the bump but before regeneration will ship the old version (the installed `Info.plist` will silently lag).
- Premium behavior: RevenueCat-backed AI surfaces fail closed when not configured.
- Payment setup: recurring premium uses RevenueCat + App Store Connect subscriptions; the Tip Jar remains separate through StoreKit 2.
- Privacy posture: health and AI data stays local-first; do not add cloud AI calls unless explicitly requested.

## Common Commands

If `xcode-select` points at an Xcode beta (this machine has Xcode 27 beta as default), pin every build/test to the stable Xcode 26.x with `DEVELOPER_DIR=/Applications/Xcode.app` — the pinned RevenueCat revision does not compile in test builds under the beta's Swift toolchain. If the stable Xcode reports "iOS X.Y is not installed" with the runtime present in `simctl`, fix the SDK/runtime build drift with `xcrun simctl runtime match set iphoneosX.Y <installed-build>`.

```bash
xcodegen generate
Scripts/restore-entitlements.sh
DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' build
DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' test
bash Scripts/e2e-simulator.sh
bash Scripts/check-agents-sync.sh
bash Scripts/verify-device-identifiers.sh
bash Scripts/verify-entitlements.sh
bash Scripts/test-payments-device.sh
ast-grep test --config sgconfig.yml --skip-snapshot-tests
ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all
```

Entitlements are rewritten on every `xcodegen generate` by `Scripts/restore-entitlements.sh` — entitlement changes go in that script, never in the `.entitlements` files. Enhanced Security compiler hardening (`ENABLE_ENHANCED_SECURITY` + pointer auth) is always on; the hardened-process *entitlements* are staged behind `ENHANCED_SECURITY_ENTITLEMENTS=1` because signing them needs the team profile regenerated with the capability (one-time interactive Xcode sign-in). Security build-setting decisions live in `xcode-security-settings.md`.

Physical-device install must use device names, not hardcoded identifiers. The canonical `DEVELOPMENT_TEAM` lives in `Config/Local.xcconfig` — read it from there, do not derive it from `security find-identity` output (that returns the Apple Development identity suffix, which is the personal team and breaks provisioning):

```bash
DEVELOPMENT_TEAM=$(grep '^DEVELOPMENT_TEAM' Config/Local.xcconfig | awk '{print $3}') \
  DEVELOPER_DIR=/Applications/Xcode.app \
  bash Scripts/install-on-device.sh --device-name "<iPhone Name>" --launch
DEVELOPER_DIR=/Applications/Xcode.app \
  bash Scripts/install-on-device.sh --device-name "<iPhone Name>" --watch-name "<Apple Watch Name>" --launch
```

## Reproducer-First Bugs

For bug reports:

1. Start by writing a test that reproduces the bug.
2. Prove the test fails before changing production code.
3. Use subagents for fix attempts when that improves speed or coverage.
4. Close the bug only with a passing reproducer and relevant verification.

Do not skip the reproducer step. `Executed 0 tests` is not evidence.

## Execution Routing

- Keep planning, visual/UI work, product copy, and the hardest judgment calls in the primary session.
- For independent backend, bulk, or mechanically heavy implementation, write a self-contained specification with acceptance checks and delegate when useful. Prefer `gpt-5.6-sol` at high reasoning through Codex when available; use `/goal` only when the runtime exposes it.
- Correctness and intelligence outrank taste, which outranks cost. Verify delegated output and redo weak work without asking merely to change models.
- The model-defaults table lives in `AGENTS.md` (Execution Routing); treat entries as defaults, not limits — escalate on weak output without asking. Never use Haiku.

## Swift and Product Rules

- Keep Swift 6.2 strict concurrency and warnings-as-errors clean.
- Prefer existing services, shared models, and design/localization utilities before adding new abstractions.
- Consume `DesignTokens` for every spacing, corner radius, color, typography, icon size, and component dimension. The relevant enums are `DesignTokens.Spacing`, `CornerRadius`, `Colors`, `Typography`, `IconSize` (xs/sm/md/lg/touchTarget/hero), and `Sizing` (progressRing, workoutCardWidth, routePreviewHeight, badgeCardMinHeight, chartHeight, chartBarMaxHeight, chatBubbleGutter, onboardingPageBottomInset). Do not reintroduce literal `.frame(width:height:)`, `cornerRadius:` integers, or magic-number paddings — enforcement greps are `\.frame(width: [0-9]` and `cornerRadius: [0-9]`.
- For motion, reuse the shared reduce-motion-aware modifiers in `Shared/DesignSystem/MotionEffects.swift` (`breathingGlow`, `goalCelebration`, `scrollFadeIn`, `staggeredReveal`) and `Shared/DesignSystem/ConfettiView.swift` before adding new animation code. They already collapse to a static, identity-stable state under `accessibilityReduceMotion` and UI testing — do not reinvent per-view motion that skips those gates. New continuous animations belong behind the same guards.
- Put cross-target code in `Shared/` when iOS, watchOS, widgets, or Live Activities need the same behavior.
- Add user-facing strings to `Shared/Resources/Localizable.xcstrings`.
- `pt-BR` devices use Portuguese; every other locale defaults to English.
- For RevenueCat/App Store payments work, follow `docs/revenuecat/apple-payments-setup.md`; never commit `.p8` keys, ASC credentials, RevenueCat secret keys, sandbox accounts, or local Apple account details.
- Check official Apple documentation in `/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation` before guessing iOS/watchOS 26 behavior.
- Check official Apple documentation in `/Applications/Xcode-beta.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation` before guessing iOS/watchOS 27 behavior.
- Prefer Context7 for current third-party documentation when available; otherwise use primary official docs.

## Security, Audit, and Data

- Do not expose a predictable `/admin` page. A non-obvious route is defense-in-depth only; require authentication, authorization, rate limiting, audit events, and `noindex`.
- Reject authentication controls that can be brute-forced in about one minute; use platform password hashing, throttling/backoff, and MFA where appropriate.
- Do not hard-delete production records by default. Prefer `deletedAt`/`deleted_at` plus explicit active-record filters, while honoring verified erasure and retention obligations.
- Audit security-sensitive mutations without logging health data, secrets, credentials, or unnecessary identifiers.
- Never run destructive commands against production or shared environments — no database drops, mass deletes, or force operations. Verify target hostnames, paths, and backups before any irreversible action.

## Git Commits

- Keep commits atomic: stage only the files you touched and list each path explicitly (convention details in `docs/agents/git-workflow.md`).
- Tracked files: `git commit -m "<scoped message>" -- path/to/file1 path/to/file2`.
- Brand-new files: `git restore --staged :/ && git add "path/to/file1" "path/to/file2" && git commit -m "<scoped message>" -- path/to/file1 path/to/file2`.

## Verification and Closeout

- For browser-rendered changes, verify every affected surface with agent-browser (`/browser gstack`) and fix UI/UX issues before stopping. For docs, tooling, schemas, or native-only changes without a browser surface, record why browser QA is not applicable and run the relevant CLI/native checks.
- After non-trivial changes, run the `autoreview` skill in local mode, verify every finding in context, and fix all justified in-scope issues.

## Shell Rules

- Avoid `head`, `tail`, `less`, and `more` in monitoring and evidence-gathering flows.
- Avoid truncation pipes such as `| head -n 20`.
- Prefer direct commands or tool-specific limit flags.
- Prefer reading logs directly instead of chaining pipes.
- Use tmux for long-running, interactive, or multi-step shell workflows.

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
