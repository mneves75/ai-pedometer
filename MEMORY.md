# MEMORY.md

Repo-local long-term memory for `ai-pedometer`. Current state, durable decisions and
open gaps only. Procedures live in [docs/agents/](docs/agents/), engineering failure
modes in [FOR_YOU_KNOW.md](FOR_YOU_KNOW.md), and release history in
[CHANGELOG.md](CHANGELOG.md). Delete entries here when the source contradicts them.

## Current state (2026-09-24)

- **1.0.8 (67) is in TestFlight** (2026-09-24): build `fb000a65` `VALID` (encryption exempt), Internal
  Testers, attached to the App Store version 1.0.8 in place of 66; archive from a clean `git archive` of
  `725530e` with Xcode 27.0, IPA SHA-256 `bd20fa23…5d05`, both validator passes OK; CI green on `725530e`,
  tag `v1.0.8-beta3` → `725530e`. Production stays blocked
  on owner declarations only (`asc validate`: 24 age-rating fields, 4 review-contact fields, content rights).
- **1.0.8 (67) source** (2026-09-24): the AI Coach now receives the user's Apple Health data with the turn
  (first turn of a session, after 30 min / a new day / a rebuilt session, and any message naming Apple
  Health), because the on-device model almost never called its tools and asked the user for data (owner
  screenshots). Settings no longer clears reminder preferences when notification permission is missing; the
  suspended-reminder resume has one owner and shares an in-flight generation. Real-model replay
  `Scripts/coach-grounding-eval.swift`: before 14/20 replies asked for data, after 0/20, 20/20 quote it.
  mneves-verify (GPT-6 Astra, two fresh rounds) ended FAIL on residuals fixed afterwards without a third
  independent round (journal). Final tree: unit 653/653, UI 31/31 (iOS 27.0), watch arm64_32, analyze.
- **App Store submission 1.0.8 (2026-09-25)**: Tip Jar IAP `6816210322` (R$ 9,90, owner's price) is
  `READY_TO_SUBMIT` and added to review submission `98a5302a`; age rating, content rights, review contact
  and notes are filled (owner + peer session); Premium subscriptions deleted; iPhone/iPad and Apple Watch
  screenshots uploaded. Adding the version to the submission is refused only for the owner's regulated
  medical device declaration (App Information, web 2FA). Production tag `v1.0.8` goes on `725530e` when
  Apple approves and the version is released, not at submission.

- **1.0.8 (66) is in TestFlight** (2026-09-24): build `d318f6fd` `VALID`, Internal Testers, tag
  `v1.0.8-beta2` → `2bff42b`, IPA SHA-256 `baa01b94…79be`; installed on owner-iPhone (launch waited on
  unlock). Fixes CI's iOS 26 accessibility failure on build 65 (VoiceOver read SF Symbol names on the
  AI-unavailable banner). CI + CodeQL green on `2bff42b`; iOS 26.5 and 27.0 unit 637/637, UI 30/30.
  Pushes go over SSH (`git@github.com:mneves75/ai-pedometer.git`) while `gh` is logged out.
- **1.0.8 (65) was in TestFlight** (2026-09-23): build `aa7d8a9f` `VALID`, encryption `exempt`, added to
  `Internal Testers` (no testers invited); IPA SHA-256 `eae7362e…204e`, built with Xcode 27.0 from
  `e9eb05e`, tag `v1.0.8-beta1` (created locally; pushing waits on `gh auth login`). Release build installed
  and launched on owner-iPhone. Final HEAD `d696431`: unit 637/637, UI 30/30. Independent verification (GPT-6)
  ended FAIL after its one correction round; open: the two never-submitted ASC subscription records
  (deleting is irreversible, owner decision) and the pre-existing Settings behavior that turns smart
  reminders off when notification permission is gone.
- **1.0.8 (65): one-time R$ 1,99 purchase, no subscription** (2026-09-23, owner decision, like LUME
  and CaptureVault). RevenueCat, `PremiumAccessStore`, the paywall and every Premium gate are gone;
  AI is gated only by Apple Intelligence availability; the optional StoreKit 2 Tip Jar stays and
  unlocks nothing. `store/app-store/` (`asc metadata`) is the listing source: "One-time purchase, no
  subscription", BRA price point `p:10006` (R$ 1,99, proceeds R$ 1,48), App Privacy `Data Not
  Collected` (`privacy.json`), privacy/support on AIPedometer's conhecendotudo.com.br pages, which the
  app's About links also open (`StoreListingTests`). Onboarding redesigned to the HIG (value, goal
  presets, one-button "Connect Apple Health" pre-permission screen). A smart reminder suspended by the
  old subscription, or by on-device AI becoming unavailable, resumes when the model is available
  (`SettingsSideEffects.suspendedSmartReminderAction`, key `smartRemindersSuspended`). The site's
  AIPedometer policy for the paid app is live (conhecendotudo v0.9.3, image v19); github.io
  `privacy.html` points there. App Store Connect (2026-09-23): version 1.0.8, listing identical to the
  repo, `Data Not Collected` published, price R$ 1,99, 175 territories. The App Store Connect subscriptions (`premium.monthly`/`.yearly`) were never
  submitted and are left untouched (not deleted).
- **1.0.6 (63) is in TestFlight** (2026-09-23, commit `e6de263`, tag `v1.0.6-beta1`, build
  `4eff36c5`): `VALID`, export compliance `exempt` automatically (the `ITSAppUsesNonExemptEncryption`
  key works), added to `Internal Testers` (still 0 testers). IPA SHA-256 `8a008a85…4b21`.
  Independent verification (Codex `gpt-6-astra`; `gpt-6-sol` is refused on the personal ChatGPT
  account) ended FAIL after its single correction round; the open items are in the journal.
- **1.0.6 (63)** carries the fixes of the 2026-09-23 review and security audit (`memory/2026-09-23.md`):
  paywall 3.1.2 disclosures with EULA and privacy links, working About links (the old
  `aipedometer.app` domain never resolved), restore feedback, Ask to Buy lockout, HealthKit
  `Int(Double)` trap, CoreMotion pause/resume double count, AI Coach Settings button, widget plural.
  Unit 697/697; UI 28/29 in the full run with the accessibility audit timing out on a saturated host
  and passing alone. App Store Connect has never had a version submitted: 1.0.4 has sat in
  `PREPARE_FOR_SUBMISSION` since June, so production is a first App Review submission. `asc validate`
  lists 33 blocking errors there (24 age-rating fields, 4 review-contact fields, content rights,
  availability, screenshots, copyright, no build attached), on top of the Paid Apps Agreement,
  subscription review screenshots and physical-device acceptance. The age rating, content rights,
  copyright and contact answers are owner declarations. App Store Connect still
  has `https://mneves75.github.io/ai-pedometer/privacy.html` as the privacy policy URL (set
  2026-09-23); 1.0.7 replaces it, see below.

- **1.0.5 (62) is the first build of this app in App Store Connect** (2026-09-22, commit `363d2af`,
  tag `v1.0.5-beta1`): `VALID`, export compliance answered, `READY_FOR_BETA_TESTING` and added
  to the existing `Internal Testers` group, which has no testers yet (adding them is an owner
  decision). External testing is blocked on beta-review contact details and "What to Test".
  Build 61 was rejected with ITMS-90183 (no `CFBundlePackageType`). Evidence: `memory/2026-09-22.md`.
- 1.0.4 (60): Debug and Release simulator bundle values were verified.
  Source fixes are committed locally as `bc0542b`, with 682 unit tests passing on
  both iOS 27 and 26.5, Release/static analysis passing and autoreview P3 clean
  after one reproduced correction. Push/remote gates and the Argent QA limitation
  remain open. See `memory/2026-09-19.md`; older results below are historical.
- Stable Xcode 27.0 (27A266a) and beta 27.2 are both installed. The global selector
  currently points to beta; use both command-scoped pins documented in
  `docs/agents/build-and-dev.md` for reproducible stable builds. This supersedes
  the historical claim below that selecting Xcode.app was a no-op.
- Through 1.0.7 the app used a RevenueCat subscription; its pins, offerings, `test_`/`appl_` key
  history and sandbox diagnosis are in `memory/2026-09-1x/2x.md` and Git. Superseded by 1.0.8.
- **1.0.2 (58) did not fix the reported distances.** owner-iPhone reports `en_US` (lockdown); a US region with
  Measurement System = Metric keeps the identifier `en_US`, and `MeasurementFormatter` natural scale ignored
  the preference, so 1.0.2 still rendered miles there (reproduced on an iOS 27 simulator set through
  Settings). 1.0.3 fixes units via `UnitLength(forLocale:usage:)` and counts via `NumberFormatter`; see
  FOR_YOU_KNOW "Regional formatting". `v1.0.2-beta1` was pushed for a build that never reached TestFlight,
  contrary to the rule below; the tag is left in place (pushed tags are never moved).
- 2026-09-15 full review pass, two review rounds (finding ledger in `memory/2026-09-15.md`): unit 654/654 and
  UI 20/20 (iPhone 17 Pro, iOS 27.0) on the final 1.0.1 (57) tree, zero skips, validated result bundles.
  `testTrainingPlansOpensFromWorkouts` used to fail on the iPhone 17 Pro Max simulator (also at `08c0b72`):
  the card's center was below the app frame and `AppDriver.tap(id:)` retried without scrolling. The driver now
  scrolls an offscreen element into view; UI 20/20 on Pro Max as well.
- Live Activities work for the first time in 1.0.1 (`NSSupportsLiveActivities` was missing). Physical-device
  verification of the Lock Screen / Dynamic Island activity is still an explicit gap.
- Installed on owner-iPhone: 1.0.3 (59) Debug, confirmed by `devicectl` and launched on 2026-09-15.
- ASC authentication is healthy (`asc auth doctor`: seven checks OK, `AIPedometer` profile complete
  in the keychain and default). That proves the key loads and parses — not that it carries a
  publishing role, which only surfaces on a real upload attempt.
- CI and CodeQL are green on `b86b102` (1.0.3; CodeQL 27 rules, 0 alerts). The hosted runner uses Xcode 26.3 while this host uses
  27.0, so the supported-range selector is load-bearing, not a convenience.
- Open before production delivery: the Paid Apps Agreement/banking/tax status (needed for the
  R$ 1,99 price and the Tip Jar), and physical-device acceptance for HealthKit, motion,
  notifications, paired watch and the Tip Jar. ASC credentials and a signed upload path are done.
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
