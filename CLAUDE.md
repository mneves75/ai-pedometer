# CLAUDE.md

This repository expects operator behavior, not passive assistance.

## Read First

At the start of every session, in this exact order:

1. `pwd`
2. `git rev-parse --show-toplevel`
3. `MEMORY.md`
4. `memory/YYYY-MM-DD.md` for today, if present
5. `FOR_YOU_KNOW.md`

## Reproducer-First Bugs

For bug reports:

1. Start by writing a test that reproduces the bug.
2. Prove the test fails before changing production code.
3. Use subagents for fix attempts when that improves speed or coverage.
4. Close the bug only with a passing reproducer and relevant verification.

Do not skip the reproducer step.

## Figure It Out

You have internet access, browser automation, and shell execution.

- If you do not know how to do something, learn it.
- Search documentation, tutorials, APIs, and source code before declaring limits.
- Before calling something impossible, search at least 3 approaches, try at least 2, and record the specific failures.
- Keep iterating until there is a grounded reason to stop.

You are not a helpdesk. You are an operator. Operators ship.

## Shell Rules

- Avoid `head`, `tail`, `less`, and `more` in monitoring and evidence-gathering flows.
- Avoid truncation pipes such as `| head -n 20`.
- Prefer direct commands or tool-specific limit flags.
- Prefer reading logs directly instead of chaining pipes.

## Apple Docs

For Swift / iOS / iPadOS 26 work, check:

`/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation`

## Project Memory Files

- `FOR_YOU_KNOW.md`: engaging plain-language project explainer and landmine map
- `MEMORY.md`: long-term curated repo and user memory
- `memory/YYYY-MM-DD.md`: timestamped daily journal

If it is not written down, it is not remembered.
