# AGENTS.md

This is the canonical agent contract for AIPedometer. CLAUDE.md imports it.
The product is a native SwiftUI iOS/watchOS app with widgets, Live Activities,
HealthKit/CoreMotion and on-device Foundation Models. Start from the actual
`project.yml` and source; historical notes are evidence to recheck.

## Startup

Run `pwd`, `git rev-parse --show-toplevel` and `git status -sb`. Read
[MEMORY.md](MEMORY.md), today's `memory/YYYY-MM-DD.md` if present,
[FOR_YOU_KNOW.md](FOR_YOU_KNOW.md), [PRAGMATIC-RULES.md](PRAGMATIC-RULES.md)
and [SECURITY-GUIDELINES.md](SECURITY-GUIDELINES.md). Create missing memory
files before proceeding. Preserve pre-existing changes and use the current branch.

Before editing, read the applicable instructions down to the target directory.
Use the knowledge graph when available, `ast-grep --lang swift` for structure,
and `rg` for exact text, file lists, configuration and documentation.

## Task routing

Read only the references relevant to the work:

| Task | Reference |
| --- | --- |
| Behavior and navigation | [README.md](README.md), [APP_FLOW.md](APP_FLOW.md) |
| Targets, ownership and dependencies | [project structure](docs/agents/project-structure.md), [TECH_STACK.md](TECH_STACK.md) |
| Swift and localization | [coding style](docs/agents/coding-style.md) |
| Build, install, archive and debug | [build and development](docs/agents/build-and-dev.md) |
| Tests, UI QA, performance and release evidence | [testing](docs/agents/testing.md) |
| Commits, review and beta delivery | [Git workflow](docs/agents/git-workflow.md) |
| RevenueCat, subscriptions, paywalls or purchases | [RevenueCat](docs/revenuecat/README.md), [Apple payments](docs/revenuecat/apple-payments-setup.md) |
| Security review | [SECURITY.md](SECURITY.md), [security guidelines](SECURITY-GUIDELINES.md) |
| Significant feature or refactor | Maintain an ExecPlan under `agent_planning/`; use the installed ExecPlan guidance when available. |

For engineering choices these references do not settle, consult the installed
GUIDELINES-REF routing reference when available, or its `INDEX.md`. Treat external
guidance as conditional reference, never a copied block or a prerequisite for a
clean clone. Verify version-sensitive claims against primary documentation.

Use a named skill when requested, or when its distinct trigger matches the task.
Read its SKILL.md first. Installed skill catalogs belong to the runtime; do not
copy them here. A task's explicit authorization governs reversible work. If a
skill blocks authorized work, identify the exact instruction and finish all
independent work before requesting missing input.

## Engineering invariants

- Preserve the supported iOS 26/watchOS 26 targets and Swift 6.2 language mode.
  Strict concurrency is complete and warnings are errors. Use existing platform
  services before introducing abstractions or dependencies.
- `project.yml` owns project generation. Change version/build fields there before
  `xcodegen generate`. Regenerate after target, dependency or Swift file changes.
  The postGen hook `Scripts/restore-entitlements.sh` is the only entitlement
  editing point. Keep hardened-process entitlements gated until provisioning
  supports them. The watch app must remain embedded, with `SKIP_INSTALL: YES`.
- Shared code also compiles for watchOS `arm64_32`. An iOS simulator build does
  not prove integer-width safety. Keep shared behavior in `Shared/` where it
  belongs to multiple targets.
- Preserve actor ownership across suspension points. `@MainActor` alone does
  not serialize an async operation. Keep refresh chaining, generation ownership
  and terminal workout single-flight behavior. C/ObjC callbacks invoked off-main
  must not inherit main-actor isolation; inspect the SDK callback declaration.
- Premium access is a tri-state. A false `canAccessAIFeatures` is not proof of
  revocation. Check `PremiumAccessStore.hasAuthoritativeAccessState` before
  revoking access; `isResolvingAccess` does not cover unavailable/offline state.
  Suspend smart-reminder delivery through `smartRemindersSuspendedByAccess`;
  only explicit user action clears the saved preference.
- Unavailable or unverified RevenueCat configuration fails closed. Keep the
  recurring subscription separate from the StoreKit 2 tip jar. Release builds
  reject Test Store keys and debug launch overrides.
- AI inference and health context stay on-device. Validate GPX files, watch
  payloads and model output at their boundary. Preserve local data and pending
  HealthKit exports across failures. Log no health data, secrets or private IDs.
- Only pt-BR uses Portuguese; other locales use English. Put product strings in
  `Shared/Resources/Localizable.xcstrings` via the existing localization helpers.
  Preserve accessibility, focus and design tokens; verify affected form factors.
- Use pnpm for JavaScript tooling, with the version in `package.json` and
  `pnpm install --frozen-lockfile`. Swift packages remain managed by Xcode/SPM.
  Keep one JavaScript lockfile; never hand-edit it or dependency directories.

## Execution and review

Deliver the smallest robust implementation. Trace consumers before deleting
wrappers or tests; callback isolation and regression seams can look redundant.
For a bug, first write and run a failing reproducer, then fix the implementation
and rerun the relevant surrounding tests. Use explicit test synchronization.

Keep requirements, UI/copy, integration and final acceptance in the primary
session. Delegate substantial independent work with disjoint file ownership and
falsifiable acceptance checks. Tell workers to preserve other changes, avoid
nested delegation and leave cross-session memory to the primary.

Model selection belongs to the runtime, not hardcoded rankings in this file.
Honor an explicit Sol-with-Astra request: Sol executes; Astra advises on difficult
decisions or reviews independently with fresh context. For Fable 5.1 or GPT-6
Astra sessions, give concrete completion criteria, continue authorized work,
batch independent reads, preserve steering and constraints across compaction,
and report meaningful progress. Revalidate model availability and effort in the
tool schema instead of assuming a CLI alias or model ranking is current.

Review the actual final diff against the task and repository standards. When
autoreview is requested or required by a release, use the installed skill on a
frozen candidate, with P3 coverage and outputs outside the repository. Resolve
justified findings and recheck affected evidence. One initial review and one
post-fix rerun is the normal bound; repeated defects require simplifying the
design. Do not treat a reviewer claim as proof or a bound as permission to ship
a known material defect.

## Verification

[Testing](docs/agents/testing.md) is the canonical gate list. Start with the
smallest check that can falsify the change, then run its required gate.
Complete releases need nonzero unit/UI results, static analysis, shell/workflow
checks, project/privacy checks, watch `arm64_32` compilation and a valid archive.
Failed, skipped or inconsistent test results remain unresolved.

Run `bash .githooks/pre-commit` on the exact staged candidate. It scans with
ast-grep ignore sources disabled, then validates agent instructions and tracked
device identifiers. Missing tools or configuration fail the gate. Enable the
tracked hook through `git config core.hooksPath .githooks`; never bypass it.

For mobile interaction use the installed Argent instructions and matching skill.
List devices first, avoid a simulator another session owns, use accessibility
trees for targets and serialize simulator test jobs. Only stop servers used by
this session. HealthKit, motion, notification delivery and payment checks that
need a real device must remain explicit gaps until exercised there.

For visible browser artifacts, inspect the rendered local artifact. For
non-rendered docs and tooling, use CLI checks and state why browser QA is
inapplicable. A performance claim needs a reproducible baseline and comparison
on the same input and host conditions; fewer lines or allocations alone do not
prove lower latency or battery usage.

## Delivery and memory

Follow the user's authorization for commit, push and deployment. Review every
staged path for secrets and unrelated content. Use Conventional Commits and
explicit paths; never clear unrelated staging or switch branches implicitly.
Keep builds, traces, credentials and local configuration out of Git.

Before beta delivery, bump the numeric version/build in `project.yml`, regenerate,
update [CHANGELOG.md](CHANGELOG.md) and relevant docs, then freeze and review.
Inspect actual archive and IPA versions, products, entitlements and Release
configuration. A beta tag identifies the immutable shipped commit and uses
`v<version>-beta<count>`; never move a pushed tag. TestFlight upload, processing,
group availability and App Store production release are distinct actions.
Deployment does not authorize tester invitations.

Update the daily journal for important evidence, decisions and mistakes.
Curate durable project facts in MEMORY.md and lessons in FOR_YOU_KNOW.md; mark
superseded guidance. Keep working notes in `agent_planning/`, archive spent plans,
and prefer existing documentation over new reports. Final responses stand alone:
outcome, actual checks, measured results and exact remaining blockers.
