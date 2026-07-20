# 015 — Validate build performance, harden dependencies, and cut 0.94

**Written against commit** `cff33ec`. Category: build / CI / release operations.
Confidence: MED-HIGH. Impact: MED. Effort: M. Fix risk: MED.

**Status:** IN PROGRESS for 0.94 (50); local build/E2E passed, final review, push, and remote checks remain.

## Goal

Use measured build evidence to accept only safe optimization changes, improve dependency/tool
visibility, run production-grade gates, then release the verified local diff as 0.94 (50).

## Constraints

- Stable Xcode 26 remains pinned with `DEVELOPER_DIR=/Applications/Xcode.app`.
- Do not enable staged Enhanced Security entitlements without the required interactive provisioning
  refresh.
- Keep GitHub Actions commit-SHA pinned and least-privilege.
- Do not add a dependency bot or build optimization without a deterministic validation path.
- Preserve unrelated user changes and include them in the final user-authorized commit.

## Implementation plan

1. Record three clean and three zero-change builds, resolved settings, per-file compiler timings,
   and build-graph diagnostics. Apply only optimizations supported by the evidence.
2. Keep E2E DerivedData outside uploaded artifacts, wait for the final simulator/watch boot, avoid
   recompiling the already embedded widget, and make operational scripts select Xcode 26 or fail
   fast with an exact remediation. Capture both stdout and stderr from every `xcodebuild` so the
   existing transient-simulator classifier can actually recover `NSMachErrorDomain`/MIG failures.
3. Add a signing-disabled `arm64_32` watch compile gate, give test bundles target-owned generated
   plists/identifiers rather than inheriting app metadata, and cover both Enhanced Security and SPM
   arm64e restoration branches without enabling the staged entitlements.
4. Update obsolete GitHub Action majors to reviewed commit SHAs and add exact tool-version
   assertions/checksum-verified installation where practical.
5. Add a scheduled, reviewable check for the RevenueCat revision in `project.yml`; it must never
   mutate the repository or merge a dependency automatically.
6. Run script tests, actionlint, shellcheck, source/security scans, builds, static analysis, unit/UI
   tests, simulator E2E, and the exact staged pre-commit snapshot gate.
7. Run local `autoreview`, fix every verified in-scope finding, and rerun it only when the diff
   changes.
8. Bump `MARKETING_VERSION` to 0.94 and build to 50, regenerate XcodeGen artifacts, and update the
   changelog plus existing README/agent/security/release docs that contain affected facts. Archive
   or relabel stale `progress.md` proof and remove obsolete RevenueCat/Xcode-beta explanations.
9. Stage all authorized changes, commit atomically, push `master`, and verify local/remote parity and
   post-push CI/CodeQL.

## Done when

- Benchmark and compiler artifacts have machine-readable evidence and generated local output is
  ignored from Git.
- Build changes have measured benefit or are explicitly rejected; no speculative setting remains.
- CI does not retain compiler products; operational scripts are deterministic about Xcode 26; the
  physical-watch architecture compiles; and test bundles no longer inherit app-only metadata.
- Dependency checks are deterministic and CI workflows pass syntax/security validation.
- Full stable-Xcode build/test/analyze/E2E gates, security review, and autoreview pass.
- Version/docs agree on 0.94 (50), the exact staged hook passes, and `master == origin/master` with
  successful required remote checks.
