# MEMORY.md

Repo-local long-term memory for `ai-pedometer`. Current state, durable decisions and
open gaps only. Procedures live in [docs/agents/](docs/agents/), engineering failure
modes in [FOR_YOU_KNOW.md](FOR_YOU_KNOW.md), and release history in
[CHANGELOG.md](CHANGELOG.md). Delete entries here when the source contradicts them.

## Current state (2026-09-09)

- Source is 0.98 (54) in `project.yml`, pushed at `5145374`, not a deployed release.
  Hosted CI 34309651078 and CodeQL 34309651111 both passed on that commit.
- Open before any beta or production delivery: approved App Store Connect credentials,
  Apple (non-Test-Store) RevenueCat configuration, a signed artifact, and physical-device
  acceptance for HealthKit, motion, notifications, paired watch and purchases.
- Toolchain: native SwiftUI, iOS/watchOS 26 targets, Swift 6.2, XcodeGen. The selected
  system Xcode is a beta, so every build/test/analyze command needs an explicit stable
  developer directory — see the [build guide](docs/agents/build-and-dev.md).
- AGENTS.md is the canonical contract and CLAUDE.md imports it. Do not restore copied
  guideline or skill catalogs; `Scripts/check-agents-sync.sh` validates the staged contract
  without an external checkout.

## User working style

- Operator behavior over hand-holding; evidence over optimism.
- Root checks before work: `pwd`, `git rev-parse --show-toplevel`, `git status -sb`.
- Bug work is reproducer-first: write the test, prove it fails, then fix.
- No buffered shell inspection (`head`, `tail`, `less`, `more`) in evidence flows.
- Project memory is written to disk, not left implicit in chat.

## Project layout

`AIPedometer/` app, `Shared/` cross-target code, `AIPedometerWatch/` watch companion,
`AIPedometerWidgets/` widgets and Live Activity, `AIPedometerTests/` unit tests,
`AIPedometerUITests/` UI tests. `project.yml` generates the Xcode project.

## Durable technical decisions

- The canonical `DEVELOPMENT_TEAM` for device installs lives in `Config/Local.xcconfig`.
  Do not derive it from `security find-identity`: that returns the personal Apple
  Development team suffix and provisioning lookup then fails.
- Swift 6.2 with complete strict concurrency and warnings-as-errors is enforced in
  `project.yml`, not in the xcconfigs.
- AI inference runs on-device through Apple Foundation Models; health context stays local.
- RevenueCat gates premium AI surfaces and fails closed when unconfigured or when Trusted
  Entitlements verification fails. It is pinned by an immutable annotated-tag object in
  `project.yml` while `Package.resolved` records the resolving commit; run
  `Scripts/check-revenuecat-staleness.sh` before release and never swap the pin for a branch.
- A `test_…` RevenueCat key is rejected outside DEBUG by
  `AppConstants.RevenueCat.resolveConfiguration` (`allowsTestStoreAPIKeys`), so premium fails
  closed instead of reaching the SDK's own Release trap. Reproducers live in `AppConstantsTests`.
  `Config/Local.xcconfig` is gitignored and carries a Test Store key, so Release installs with
  it are unsupported by design.
- `asc` has two authentication planes and only one can publish: `asc web auth` is a browser
  session for `asc web …` and cannot mint an API key or upload a build; app, build, TestFlight
  and `asc publish` need `asc auth login` with key ID, issuer ID and a `chmod 600` `.p8`.
  Never substitute web-session provider identifiers for the issuer ID, and always pass `--app`
  explicitly rather than trusting the CLI's default app ID.
- `SKIP_INSTALL: YES` on the watch target is release-critical. With `NO`, the archive holds two
  apps under `Products/Applications`, Xcode writes no `ApplicationProperties`, and
  `-exportArchive` reports an empty set of distribution methods (`expected one {}` means "no
  valid methods", not a bad method name). The watch still ships embedded at `AIPedometer.app/Watch/`.
- A certificate is usable only with its private key on this Mac; profiles must be created
  against the local distribution certificate. Pass the authentication key to both `archive`
  and `-exportArchive`, and read the real distribution logs under
  `…/T/AIPedometer_*.xcdistributionlogs/IDEDistribution.standard.log` rather than the CLI's
  one-line error. Cloud signing needs an Admin/App Manager key role, not Developer.
- Entitlements are rewritten on every `xcodegen generate` by `Scripts/restore-entitlements.sh`;
  entitlement changes belong in that script. Hardened-process keys stay staged behind
  `ENHANCED_SECURITY_ENTITLEMENTS=1` until provisioning supports the capability.
- In Release, `LaunchConfiguration.isOverridable` is unconditionally false: launch arguments and
  environment are attacker input through `devicectl`. Do not reintroduce Release overrides.
- Because the project is XcodeGen-generated, new Swift files need `xcodegen generate`, and version
  fields must change in `project.yml` *before* generation or the built bundle keeps the old version.

## Operator lessons

- The reproducer test is the contract for a bug report, and `Executed 0 tests` is not evidence.
- A concurrency regression test is trustworthy only if it fails without the fix: instrument a
  max-concurrent counter, bypass the guard once to see red, then restore.
- `@MainActor` is not a reentrancy guard for `async` methods. "Idempotent under @MainActor" is a
  false justification; a prior cycle made exactly that mistake on `refreshTodayData()`.
- `await Task.yield()` is never a synchronization primitive in a test — it guarantees only that the
  current task suspends once. Use an explicit completion latch.
- A "no user-visible effect" justification must trace every consumer, not the obvious UI. Duplicate
  `EarnedBadge` rows were invisible in the grid but surfaced through the AI prompt.
- Review-agent findings inflate severity and misread code: verify every claimed critical or high
  against real source first. In one cycle all fourteen were refuted, and applying the suggested
  "fixes" would have introduced bugs (inverting a `max(by:)` comparator, breaking open-ended goal
  semantics, flipping RevenueCat verification mode).
- Autoreview your own uncommitted diff before committing; it has a far better hit rate than
  auditing unchanged code. Six review lenses over existing source found nothing while review of the
  new diff caught two customer-harming regressions that a 613-test suite passed cleanly.
- When successive fixes to the same seam each introduce a worse bug, the underlying question is
  probably a product decision, not an engineering one. Escalate instead of iterating.
- Dot-directories can hold tracked files. Run `git ls-files <dir>` before any `rm`, and restore a
  deleted tracked file with `git show HEAD:<path> > <path>`.
- Warnings-as-errors applies to test doubles too; fake clients must be warning-clean before their
  results mean anything.
- Serialize simulator jobs. A `** TEST FAILED **` line can be `Mach error -308 … server died`, the
  simulator server dying under contention, and a single full-suite XCUITest "element not found" on
  a loaded machine is usually a launch-timing flake — confirm by isolated re-run before treating
  either as a regression.
- Large `xcodebuild -showBuildSettings` output must be parsed from a file. Capturing it in a shell
  variable and feeding it to `awk` through a here-string can fill Bash's pipe and deadlock after an
  otherwise successful build.
- `Scripts/lib/logged-command.sh` enables `pipefail` inside its own subshell; a helper cannot assume
  its caller did, or `xcodebuild | tee` reports success for a failed build.
- `Scripts/install-on-device.sh --launch` exits non-zero when the phone is locked at launch time
  even though build and install succeeded. Verify independently with
  `xcrun devicectl device info apps --device <name> --bundle-id com.mneves.aipedometer`.

## Memory rules

- If the user says "remember this", write it down immediately.
- Record the mistake and its prevention rule when something goes wrong.
- Distill durable lessons from the daily journals into this file, and delete entries the source
  no longer supports.
