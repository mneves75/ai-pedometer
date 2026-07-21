SUPERGOAL_PHASE_START
Phase: 7 of 8 — Docs + DX batch
Task: Fix confirmed doc drift and CI/tooling friction (all small, no app behavior change)
Type: brownfield, docs, dx
Mandatory commands: bash Scripts/check-agents-sync.sh, shellcheck Scripts/*.sh Scripts/tests/*.sh Scripts/tests/fixtures/*.sh Scripts/lib/*.sh .githooks/pre-commit, bash Scripts/tests/xcresult-summary.sh, bash Scripts/verify-entitlements.sh
Acceptance criteria: 5
Evidence required: each gate output, already-fixed skips with proof
Depends on phases: none

## Shared context (read first)

- Repo: /Users/mneves/dev/PROJETOS_MOBILE/ai-pedometer.
- Leave ALL changes uncommitted. Never run git commit/push/add. Never touch: `.supergoal/`, `memory/`, `MEMORY.md`, `plans/`, `agent_planning/`, `CHANGELOG.md`, `project.yml` version fields, `output/`.
- `AGENTS.md` contains a `## GUIDELINES-REF` section that is diff-checked against `/Users/mneves/dev/GUIDELINES-REF/AGENTS.md` by `Scripts/check-agents-sync.sh` — all edits must stay ABOVE that marker and the gate must stay green. Do not edit the synced section.
- No emojis in repository documentation.

## Why

Confirmed drift: a lint command in docs covers fewer files than CI; an empty docs section governs nothing; a renamed skill leaves two dead pointers; CI pins an Xcode version that will break on runner-image rotation; the contributor entry point omits the mandatory lint gate; two script robustness gaps.

## Work

1. `docs/agents/testing.md` — replace the shellcheck command with EXACTLY the file list CI uses (`.github/workflows/ci.yml`): `Scripts/*.sh Scripts/tests/*.sh Scripts/tests/fixtures/*.sh Scripts/lib/*.sh .githooks/pre-commit`; remove the duplicate standalone `python3 Scripts/tests/test_xcresult_summary.py` line (the shell loop on the same line already invokes it via `Scripts/tests/xcresult-summary.sh`).
2. `docs/agents/coding-style.md` — the empty `## Formatting` section: write "No enforced formatter — match the style of the surrounding file." (one line; no tool adoption).
3. `CLAUDE.md` + `AGENTS.md` — replace the `autoreview` skill reference with `review` (the skill was renamed; keep the "local mode" wording). AGENTS.md: edit ONLY above the `## GUIDELINES-REF` marker; run the sync gate after.
4. `.github/workflows/ci.yml` + `.github/workflows/codeql.yml` — replace the hardcoded `sudo xcode-select -s /Applications/Xcode_26.3.app` with a runtime resolution of the newest installed 26.x (e.g. `ls -d /Applications/Xcode_26*.app | sort -V | tail -1`) with a clear failure if none is found. Keep the printed `xcodebuild -version` step.
5. `CONTRIBUTING.md` — add a short "Prerequisites" note: `git config core.hooksPath .githooks`, `brew install ast-grep ripgrep shellcheck`, and align its test commands with the README's `-parallel-testing-enabled NO` forms.
6. `Scripts/e2e-simulator.sh` — add a preflight near `aipedometer_select_xcode_26`: `command -v rg python3` with a brew-install hint on failure (mirror the `require_cmd` style used in `Scripts/install-on-device.sh`).
7. `Scripts/restore-entitlements.sh` — in `write_entitlement`, add `trap 'rm -f "$temp_file"' RETURN` so a `plutil -lint` failure cannot leave `*.tmp.$$` files in a tracked directory.

If any item is already fixed when you get there, skip it and show proof.

## Acceptance criteria (all must pass — verify each in transcript)

1. `bash Scripts/check-agents-sync.sh` green.
2. `shellcheck Scripts/*.sh Scripts/tests/*.sh Scripts/tests/fixtures/*.sh Scripts/lib/*.sh .githooks/pre-commit` green.
3. `bash Scripts/tests/xcresult-summary.sh` green.
4. `bash Scripts/verify-entitlements.sh` green.
5. No `.swift` file modified (diff scope is docs/scripts/CI only — print `git diff --stat`).

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `bash Scripts/check-agents-sync.sh`
- `shellcheck Scripts/*.sh Scripts/tests/*.sh Scripts/tests/fixtures/*.sh Scripts/lib/*.sh .githooks/pre-commit`
- `bash Scripts/tests/xcresult-summary.sh`
- `bash Scripts/verify-entitlements.sh`

## Evidence required in transcript

- Each gate's tail output + exit code
- `git diff --stat` proving docs/scripts/CI-only scope
- Skipped items (if any) with already-fixed proof

## Notes

- Do not reformat or reflow any doc beyond the listed edits.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in .supergoal/PROTOCOL.md without further
instruction needed here.
