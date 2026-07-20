# Git Workflow

## Commits
- Follow Conventional Commits patterns seen in history (e.g., `feat: ...`, `chore: ...`).
- Keep commits atomic: commit only the files you touched and list each path explicitly.
  - Tracked files: `git commit -m "<scoped message>" -- path/to/file1 path/to/file2`.
  - Brand-new files: `git restore --staged :/ && git add "path/to/file1" "path/to/file2" && git commit -m "<scoped message>" -- path/to/file1 path/to/file2`.
- Enable repo hooks: `git config core.hooksPath .githooks` (enforces AGENTS.md sync on commit).

## Pull Requests
- Include a brief summary and testing notes.
- Include screenshots for UI changes.

## Changelog
- Update `CHANGELOG.md` if a change is user-facing.
