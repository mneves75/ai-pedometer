# Git Workflow

## Commits
- Follow Conventional Commits patterns seen in history (e.g., `feat: ...`, `chore: ...`).
- Keep commits atomic: commit only the files you touched and list each path explicitly.
  - Review `git diff` and `git diff --cached`, then stage explicit task-owned paths with `git add -- path/to/file1 path/to/file2`.
  - Run `bash .githooks/pre-commit` and commit the reviewed candidate. Preserve unrelated staging; do not clear the index to prepare a commit.
- Enable repo hooks: `git config core.hooksPath .githooks`. The hook checks the staged Swift sources, instruction contract and device identifiers.

## Parallel work

- Use the current checkout unless the user requests a worktree. Give parallel workers disjoint file ownership; keep project generation, staging and release in one session.
- For an authorized worktree, give it a distinct DerivedData directory and simulator. Share immutable package downloads where supported, but never share mutable build output or a running app's data store.
- Before retrying a stalled build, identify the process and owning repository. Do not stop another checkout's simulator or build process.
- Keep ignored `Config/Local.xcconfig` scoped to the checkout. Provision authorized
  release configuration separately, and verify its resolved kind before archiving.
  Record simulator ownership and output paths in the task plan so another session
  can avoid contention. Recheck ownership after a pause or resumed session.

## Beta delivery

- Follow the [testing gates](testing.md) and [payment runbook](../revenuecat/apple-payments-setup.md).
- Update the version/build in `project.yml`, regenerate, update docs and freeze the candidate before independent review. Use the initial task commit as the review base and the accepted plan as the specification.
- Review staged files for private data before an authorized push. This repository's visibility must be checked live; historical notes are not an access-control guarantee.
- Tag the shipped commit `v<version>-beta<count>` using the next unused count. Never move an existing remote tag.
- Verify archive/IPA version and build, upload processing and existing TestFlight group availability separately. Do not infer App Store publication or tester-invitation authority from a beta request.
- Required CI and CodeQL must finish successfully for the pushed candidate. The
  RevenueCat freshness workflow is tracked separately: exit 10 needs a current
  update/retention decision; network/provenance failure remains unresolved.

## Production delivery

When explicitly authorized, promote the verified TestFlight build after the testing
guide's physical and App Store gates pass. Use `v<version>` for the immutable shipped
commit. App Store submission is not publication; record Apple approval and verify
availability in the intended storefront before reporting production delivery.

## Pull Requests
- Include a brief summary and testing notes.
- Include screenshots for UI changes.

## Changelog
- Update `CHANGELOG.md` if a change is user-facing.
