# Phase 2 focused fix spec — isolate full-suite transient

## Scope

Target only the phase-2 full-unit verification criterion after two aggregate runs reported one issue while all focused monetization tests passed. Do not touch unrelated files.

## Procedure

1. Preserve complete console output for the explicit `AIPedometerTests` target.
2. If an exact failing test is reproduced, determine whether phase-2 state leaks across tests and make only the smallest test-fixture or marker-lifecycle correction.
3. If the explicit target passes, make no speculative code change; require the focused monetization suites and a fresh full-unit pass.
4. Keep all confirmed-pending and single-flight tests unchanged.

## Success gate

Re-run the original phase VERIFY block:

- `PremiumAccessStoreTests` and `TipJarStoreTests` pass.
- The explicit `AIPedometerTests` unit target passes with a non-zero test count.
- `bash .githooks/pre-commit` passes.
- All phase-2 acceptance criteria and cleanliness checks pass.
