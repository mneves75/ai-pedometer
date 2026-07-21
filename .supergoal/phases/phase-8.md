SUPERGOAL_PHASE_START
Phase: 8 of 8 — Polish & Harden
Task: Re-verify the cumulative diff against every repo gate and prove diff hygiene
Type: brownfield, verification
Mandatory commands: DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test, bash Scripts/e2e-simulator.sh, ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all, bash Scripts/verify-entitlements.sh, bash Scripts/check-agents-sync.sh
Acceptance criteria: 5
Evidence required: every gate tail output, final git diff --stat
Depends on phases: 1, 2, 3, 4, 5, 6, 7

## Shared context (read first)

- Repo: /Users/mneves/dev/PROJETOS_MOBILE/ai-pedometer. TOOLCHAIN: `DEVELOPER_DIR=/Applications/Xcode.app` on every xcodebuild.
- Leave ALL changes uncommitted. Never run git commit/push/add. Never touch: `.supergoal/`, `memory/`, `MEMORY.md`, `plans/`, `agent_planning/`, `CHANGELOG.md`, `project.yml` version fields, `output/`.
- This phase changes NO production code unless a gate failure traces directly to an earlier phase's edit (then fix minimally and re-run the gate).

## Why

Per-phase self-reports can pass while the cumulative diff breaks something across phases. This is the full-gate re-verification before the main session's release steps (version bump, tags, deploys — NOT part of this run).

## Work

1. Run every mandatory command; capture tail output + exit code for each.
2. Review the complete cumulative diff for hygiene: no debug prints, no new TODO/FIXME, no commented-out code, no out-of-scope files.
3. Write the closeout summary.

## Acceptance criteria (all must pass — verify each in transcript)

1. Full `AIPedometerTests` green — exact count printed and reconciled against baseline 592 (plus phase additions, minus the deliberately removed tautology test).
2. `bash Scripts/e2e-simulator.sh` full pass (unit + all XCUITests + watchOS build) — summary printed from its output dir.
3. ast-grep scan clean; `bash Scripts/verify-entitlements.sh` green; `bash Scripts/check-agents-sync.sh` green.
4. `git status --porcelain` + `git diff --stat` printed; confirmed: only expected source/test/docs/scripts/CI files changed; `.supergoal/`, `memory/`, `MEMORY.md`, `plans/`, `output/`, `CHANGELOG.md`, `project.yml` version fields untouched; no new TODO/FIXME (grep proof).
5. One-paragraph-per-phase closeout: what changed, what was deliberately NOT changed, any deviations from specs.

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test`
- `bash Scripts/e2e-simulator.sh`
- `ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all`
- `bash Scripts/verify-entitlements.sh`
- `bash Scripts/check-agents-sync.sh`

## Evidence required in transcript

- Every gate's tail output + exit code
- The hygiene greps (TODO/FIXME, print statements)
- Final `git diff --stat`

## Notes

- The e2e script takes ~25 minutes; that is expected. Do not shorten it.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in .supergoal/PROTOCOL.md without further
instruction needed here.
