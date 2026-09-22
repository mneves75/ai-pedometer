# MEMORY.md

Repo-local long-term memory for `ai-pedometer`. Current state, durable decisions and
open gaps only. Procedures live in [docs/agents/](docs/agents/), engineering failure
modes in [FOR_YOU_KNOW.md](FOR_YOU_KNOW.md), and release history in
[CHANGELOG.md](CHANGELOG.md). Delete entries here when the source contradicts them.

## Current state (2026-09-22)

- Source candidate is 1.0.5 (62) in `project.yml` (paywall diagnostics, retry, `StaticString` log
  events); release evidence is in `memory/2026-09-22.md`.
- 1.0.4 (60): Debug and Release simulator bundle values were verified.
  Source fixes are committed locally as `bc0542b`, with 682 unit tests passing on
  both iOS 27 and 26.5, Release/static analysis passing and autoreview P3 clean
  after one reproduced correction. Push/remote gates and the Argent QA limitation
  remain open. See `memory/2026-09-19.md`; older results below are historical.
- Stable Xcode 27.0 (27A266a) and beta 27.2 are both installed. The global selector
  currently points to beta; use both command-scoped pins documented in
  `docs/agents/build-and-dev.md` for reproducible stable builds. This supersedes
  the historical claim below that selecting Xcode.app was a no-op.
- RevenueCat remains pinned to 5.81.1 after review against 5.90.2. Freshness
  reports a newer SDK; no applicable required fix was established. The app uses
  its native package paywall and RevenueCatUI Customer Center, not PaywallView.
- **1.0.2 (58) did not fix the reported distances.** iMarcus reports `en_US` (lockdown); a US region with
  Measurement System = Metric keeps the identifier `en_US`, and `MeasurementFormatter` natural scale ignored
  the preference, so 1.0.2 still rendered miles there (reproduced on an iOS 27 simulator set through
  Settings). 1.0.3 fixes units via `UnitLength(forLocale:usage:)` and counts via `NumberFormatter`; see
  FOR_YOU_KNOW "Regional formatting". `v1.0.2-beta1` was pushed for a build that never reached TestFlight,
  contrary to the rule below; the tag is left in place (pushed tags are never moved).
- **Purchases on device (2026-09-21):** `Config/Local.xcconfig` holds the Apple `appl_` key
  since 2026-09-20 and the RevenueCat offering `default` resolves `$rc_monthly`/`$rc_annual` to
  the production product IDs, so the `test_` blocker below is superseded. The Release 1.0.4 (60)
  paywall on the iMarcus still shows no plans: StoreKit returns none of the products. Verified with
  `asc` on 2026-09-22: product IDs match, both have prices (175 territories, PRT included), en-US
  and pt-BR localizations, and the bundle ID has the In-App Purchase capability. Both are
  `MISSING_METADATA` only for the App Review screenshot, which Apple's TN3186 says sandbox does not
  need. The remaining sandbox/TestFlight blocker is therefore the Paid Apps Agreement, banking and
  tax status (not exposed by the ASC API; check the Business section as Account Holder). ASC
  prices are US$ 2.99 monthly and US$ 39.99 yearly (the 2026-09-20 journal's 6.99 is wrong).
  Before production: review screenshots, and the first subscription group submitted with a version.
  Diagnose with
  the `code` field of `premium.offerings_failed` and the `AIPedometer-Sandbox` scheme
  (FOR_YOU_KNOW "Health, AI and premium boundaries").
- **Superseded (historical `test_` blocker, checked 2026-09-15 by prefix only):**
  `Config/Local.xcconfig` carried a Test Store (`test_`) RevenueCat key at the time. `AppConstants.RevenueCat.resolveConfiguration` nils
  it outside DEBUG, so a Release archive resolves *no* key and premium/purchase/restore are dead;
  `validate-release-artifact.py` rejects it before export. The key is baked into `Info.plist` at archive time,
  so an Apple (`appl_`) key requires a new archive. No beta tag is created until a build actually ships.
- 2026-09-15 full review pass, two review rounds (finding ledger in `memory/2026-09-15.md`): unit 654/654 and
  UI 20/20 (iPhone 17 Pro, iOS 27.0) on the final 1.0.1 (57) tree, zero skips, validated result bundles.
  `testTrainingPlansOpensFromWorkouts` used to fail on the iPhone 17 Pro Max simulator (also at `08c0b72`):
  the card's center was below the app frame and `AppDriver.tap(id:)` retried without scrolling. The driver now
  scrolls an offscreen element into view; UI 20/20 on Pro Max as well.
- Live Activities work for the first time in 1.0.1 (`NSSupportsLiveActivities` was missing). Physical-device
  verification of the Lock Screen / Dynamic Island activity is still an explicit gap.
- Installed on iMarcus: 1.0.3 (59) Debug, confirmed by `devicectl` and launched on 2026-09-15.
- ASC authentication is healthy (`asc auth doctor`: seven checks OK, `AIPedometer` profile complete
  in the keychain and default). That proves the key loads and parses — not that it carries a
  publishing role, which only surfaces on a real upload attempt.
- CI and CodeQL are green on `b86b102` (1.0.3; CodeQL 27 rules, 0 alerts). The hosted runner uses Xcode 26.3 while this host uses
  27.0, so the supported-range selector is load-bearing, not a convenience.
- Open before any beta or production delivery: approved App Store Connect credentials,
  Apple (non-Test-Store) RevenueCat configuration, a signed artifact, and physical-device
  acceptance for HealthKit, motion, notifications, paired watch and purchases.
- Toolchain: native SwiftUI, iOS/watchOS 26 deployment targets, Swift 6.2, XcodeGen.
  Supported build toolchains are Xcode 26.x and 27.x. Verified 2026-09-10 on Xcode 27.0
  (27A266a): app, widgets, watch and both test targets build clean; unit suite 607/607.
  Run `bash Scripts/preflight.sh` before any build — it is the only check that proves the
  host can build at all, because the shell suites test fixtures and stay green regardless.
- **Corrected 2026-09-10:** the previous entry claimed the system Xcode was a beta and that
  every command needed `DEVELOPER_DIR=/Applications/Xcode.app` as "stable Xcode 26". No
  Xcode 26 was installed; that prefix resolved to 27.0 and was a no-op. The related claim
  that the pinned RevenueCat revision fails test builds under the 27 toolchain is **false**.
  What fails is a *generic* simulator destination, which compiles arm64 and x86_64 and
  reports `RevenueCat.swiftmodule ... built for incompatible target`. Use a concrete
  destination. A wrong instruction cost more than a missing one would have.
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
