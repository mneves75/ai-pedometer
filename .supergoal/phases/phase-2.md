SUPERGOAL_PHASE_START
Phase: 2 of 8 — Purchase marker reconciliation
Task: Reconcile orphaned purchase-attempt markers without ever clearing confirmed pending purchases
Type: brownfield, bugfix, revenue-critical
Mandatory commands: DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test, ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all
Acceptance criteria: 4
Evidence required: red test output before fix, green after, confirmed-pending distinction statement
Depends on phases: none

## Shared context (read first)

- Repo: /Users/mneves/dev/PROJETOS_MOBILE/ai-pedometer. Swift 6.2 strict concurrency, warnings-as-errors, Swift Testing.
- TOOLCHAIN: every xcodebuild MUST use `DEVELOPER_DIR=/Applications/Xcode.app` (stable 26.6). NEVER the default Xcode 27 beta.
- Leave ALL changes uncommitted. Never run git commit/push/add. Never touch: `.supergoal/`, `memory/`, `MEMORY.md`, `plans/`, `agent_planning/`, `CHANGELOG.md`, `project.yml` version fields, `output/`.
- Reproducer-first: failing test proven red before any production change.
- REVENUE-CRITICAL: this phase touches purchase state. Conservative beats clever. When in doubt, preserve money-path behavior and report instead of improvising.

## Why

`PremiumAccessStore` persists a pending marker BEFORE awaiting StoreKit; on launch it treats any surviving marker as an in-progress purchase and blocks `purchase()`. If the process died between persisting the marker and any platform resolution (kill/crash at the StoreKit sheet), no CustomerInfo change ever resolves the marker — purchases stay disabled across every subsequent launch. `TipJarStore` has the same write-before-await shape.

## Work

Current state (verified):
- `AIPedometer/Core/Monetization/PremiumAccessStore.swift`: init reads `pendingProductKey` from `pendingPurchaseDefaults` and sets `hasPendingPurchase`/`isPurchaseInProgress` from it; `purchase(_:)` guards on `!isPurchaseInProgress`; markers clear only via `pendingPurchaseWasResolved(by:)` which requires purchase/expiration dates to advance vs a persisted baseline; `result.userCancelled` clears.
- `AIPedometer/Features/About/TipJarStore.swift`: persists `.pending` before awaiting `driver.purchase()`; restores `.pending` at init; foreground handling is a no-op.
- Existing tests prove confirmed pending purchases INTENTIONALLY survive recreation (that behavior is correct and must stay).

Required change:
1. Persist two DISTINCT phases: `attempting` (written before the platform call, not yet confirmed by any platform signal) and confirmed `pending` (a platform transaction/unfinished state exists — e.g. StoreKit unfinished transaction, Ask-to-Buy).
2. On launch, reconcile `attempting` markers: inspect verified unfinished transactions and CustomerInfo; if a platform state exists, promote to `pending` (existing resolution logic takes over); if none exists, clear the orphan and unblock purchases.
3. NEVER auto-clear confirmed `pending`. No time-based auto-clear anywhere.
4. Mirror the same distinction in `TipJarStore` IF its marker contract matches; if it differs materially, implement PremiumAccessStore first, then mirror carefully, and describe the difference in the transcript.
5. Keep `purchase()` single-flight; do not introduce any path that can start a second concurrent purchase.

Test plan (red first):
- New recreation test: write an attempt marker as if the process died before the await returned, recreate the store with no platform transactions → marker cleared, purchase unblocked (red before fix).
- Existing confirmed-pending survival tests must stay green WITHOUT modification (if one needs changes, STOP and report).
- Duplicate-attempt guard test stays green.

## Acceptance criteria (all must pass — verify each in transcript)

1. Orphan-marker recreation test passes (red proven before fix, green after — outputs shown).
2. Confirmed-pending survival tests unchanged and green (list their names).
3. `purchase()` remains single-flight; no new duplicate-attempt path (state the guard).
4. PremiumAccessStoreTests + TipJarStoreTests + full `AIPedometerTests` green; ast-grep scan clean (tail output + exit codes).

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests/PremiumAccessStoreTests -only-testing:AIPedometerTests/TipJarStoreTests test`
- `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIPedometerTests test`
- `ast-grep scan --config sgconfig.yml --error=unused-suppression --error=no-suppress-all`

## Evidence required in transcript

- Red/green outputs for the orphan test
- One paragraph: exactly how `attempting` vs confirmed `pending` is distinguished at reconcile time, and why a genuine Ask-to-Buy-style pending can never be auto-cleared
- Any deviation from this spec and why

## Notes

- Verification-fail-closed behavior (failed Trusted Entitlements verification ⇒ no premium) is a documented design decision — do not touch it.
- If StoreKit 2 unfinished-transaction inspection on the simulator proves unreliable for the test, use the existing PurchasesClientProtocol test double seam; do not weaken the production code to make testing easier.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in .supergoal/PROTOCOL.md without further
instruction needed here.
