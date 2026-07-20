# 010 — Harden premium environment and privacy boundaries

**Written against commit** `cff33ec`. Category: security / privacy / monetization.
Confidence: HIGH. Impact: HIGH. Effort: M. Fix risk: MED.

**Status:** DONE for 0.94 (50).

## Goal

Prevent non-production RevenueCat entitlements from unlocking production AI, require deliberate
confirmation before opening model-generated external links, and align privacy manifests with the
app's verified local-only health-data flow.

## Constraints

- Premium remains fail-closed when RevenueCat is missing, unverified, or unavailable.
- Test Store keys remain forbidden in Release builds.
- Do not transmit HealthKit/Core Motion values, identifiers, or model context to a new service.
- Keep all existing URL scheme, credential, loopback, and private-address rejection rules.
- Do not include secrets or local RevenueCat configuration in tests, source, logs, or docs.

## Implementation plan

1. Add a failing premium regression test proving an active sandbox entitlement does not unlock a
   production environment, while current-environment sandbox/TestFlight access still works.
2. Resolve configured entitlement IDs and aliases only through
   `activeInCurrentEnvironment`; remove every `active`/any-environment fallback.
3. Add failing link-flow tests proving a permitted model-generated URL is not opened before user
   confirmation. Reject literal IP hosts and show normalized host plus full URL in the prompt.
4. Inspect all production network egress. If health/fitness data is never transmitted off-device,
   set each target's `NSPrivacyCollectedDataTypes` to an empty array and add a deterministic
   manifest-policy check so the declaration cannot drift silently.
5. Update the existing privacy/security/revenue docs with the exact boundary; do not add a new
   standalone report.
6. Keep new SwiftData stores in the app's private Application Support directory. If an existing
   app-group store is present, continue opening it in place: do not copy, move, overwrite, or delete
   its SQLite store or WAL sidecars during startup.

## SwiftData store isolation boundary

Starting with 0.94, a fresh installation selects private Application Support for SwiftData. Widgets
continue to read only the bounded `SharedStepData` snapshot from app-group `UserDefaults`.

An installation that already has `default.store` in the app-group continues using that exact URL.
This is deliberately a compatibility fallback, not a claim that every upgraded installation is
fully isolated. SwiftData exposes a configured store URL but no public store-relocation API; a raw
copy of the SQLite file and its WAL/SHM sidecars is not an acceptable production migration without
real-store fixtures and interruption recovery proof. Full legacy relocation remains residual
hardening. The current policy never copies, deletes, or overwrites persisted health data.

## Done when

- New regression tests fail for the old entitlement and link behavior, then pass after the fix.
- Premium, AI-link-policy, and manifest-policy tests pass.
- Store-selection tests prove fresh installs use private Application Support and a legacy app-group
  store remains authoritative and byte-for-byte untouched.
- `plutil -lint` passes for all privacy manifests.
- A source-wide network-egress review finds no health/fitness upload path.
- Release configuration still rejects Test Store keys and premium remains fail-closed.
