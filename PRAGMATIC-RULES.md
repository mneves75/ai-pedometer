# Pragmatic Rules

These rules define execution standards for contributors and coding agents in this repository.

## Delivery

- Ship complete, verifiable outcomes.
- Prefer small, reviewable changes with deterministic behavior.
- Keep implementation and tests aligned; do not weaken tests to make them pass.

## Scope Discipline

- Validate repository scope before editing (`pwd`, `git status`, target files).
- Avoid touching unrelated files in dirty working trees.
- Preserve existing architectural patterns unless a change explicitly requires refactoring.

## Verification

- Run relevant tests for every behavior change.
- Treat failing or skipped tests as unresolved work.
- Capture what was validated and what was not validated.

## Quality Bar

- Favor maintainability over cleverness.
- Keep public behavior explicit and documented in `CHANGELOG.md` when it changes.
- Use existing design tokens/localization patterns; avoid hardcoded UX strings and visual constants when project abstractions already exist.

## Safety

- Never commit secrets, tokens, private keys, or generated credentials.
- Prefer fail-safe defaults in all runtime paths (especially background, sync, and AI flows).
