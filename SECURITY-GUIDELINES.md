# Security Guidelines

These guidelines complement `SECURITY.md` and apply to all code changes in this repository.

## Core Principles

- Enforce least privilege for app capabilities, scripts, and CI workflows.
- Keep user data local-first where possible and minimize data collection.
- Prefer explicit allowlists over implicit trust.

## Input and Data Handling

- Validate all external input before processing.
- Treat HealthKit and AI-generated content as untrusted until validated for the current context.
- Avoid logging sensitive user data; redact identifiers and private fields in logs.

## Dependencies and Tooling

- Pin dependency revisions/versions intentionally.
- Review security impact before enabling new entitlements or background capabilities.
- Keep automated security checks enabled in CI.

## Authentication and Secrets

- Do not hardcode secrets, tokens, keys, UDIDs, or account identifiers in source or docs.
- Use local configuration overrides for machine-specific credentials.

## Release Hygiene

- Run relevant tests and security checks before tagging a release.
- Use private vulnerability reporting flow documented in `SECURITY.md`.
- If a vulnerability is found, prioritize containment and coordinated disclosure.
