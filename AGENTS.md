# Repository Guidelines

## Project Overview
AIPedometer is a Swift 6.2 SwiftUI iOS pedometer app with AI-powered insights, plus watchOS and widget targets.

## Agent Notes
Run notes are stored at `agent_planning/ultrawork-notes.txt` (append each run and reuse between sessions).

## Package Manager
This project does not use npm; it relies on Xcode/XcodeGen tooling.

## Non-Standard Commands
- `xcodegen generate`: regenerate `AIPedometer.xcodeproj` from `project.yml` (required after config/target changes).

## Detailed Guides
- [Project structure and configuration](docs/agents/project-structure.md)
- [Build, test, and utilities](docs/agents/build-and-dev.md)
- [Coding style and naming](docs/agents/coding-style.md)
- [Testing guidelines](docs/agents/testing.md)
- [Git workflow](docs/agents/git-workflow.md)

## GUIDELINES-REF
Synced from `~/dev/GUIDELINES-REF/AGENTS.md` (use `bash Scripts/check-agents-sync.sh`).


**ALWAYS work through lists/todo/plans items and not stop until all work is done and you are 100% certain it works!**

## Mission & Mindset

- Operate as senior engineer across Next.js, TypeScript, Swift, and mobile platforms
- Default to first-principles thinking; question assumptions, surface risks, document rationale
- Treat John Carmack as your reviewer: pursue clarity, correctness, and simplicity over speed
- Never settle for "good enough" - strive for perfection in implementation
- Push reasoning to 100%. Explain non-trivial choices explicitly
- Keep tone professional, terse, and emoji-free

## Comprehensive Guidelines Reference

**All guidelines are located in `DOCS/GUIDELINES-REF/`. This folder is your knowledge base—consult it first whenever you need help, and capture any broadly useful learning there using filenames like `a_very_descriptive_name.md`. Cite which guidelines influenced your decisions.**

### Platform-Specific Guidelines

| Guideline | When to Use | Key Topics |
|-----------|-------------|------------|
| **MOBILE-GUIDELINES.md** | All mobile development (React Native/Expo) | iOS 26+, Android 15/16 (16KB pages), Expo SDK 54, React Native 0.81.5, React 19.1, New Architecture, React Compiler, performance, offline-first |
| **IOS-GUIDELINES.md** | Native iOS/iPadOS/macOS development | Xcode 26, SwiftUI 6, SwiftData 2, Liquid Glass UI, MetricKit, Privacy Manifests, App Store compliance |
| **WEB-NEXTJS-GUIDELINES.md** | Next.js projects | Next.js 15/16, React 19, Server Components, PPR, Server Actions, Authentication (DAL pattern, CVE-2025-29927), Drizzle ORM, Vitest + Playwright |
| **WEB-GUIDELINES.md** | General web development (landing pages, dashboards) | Core Web Vitals (INP, LCP, CLS), WCAG 2.2, Modern CSS (Container Queries, View Transitions), TypeScript 5.9+, Vite 6 |

### Language & Framework Guidelines

| Guideline | When to Use | Key Topics |
|-----------|-------------|------------|
| **TYPESCRIPT-GUIDELINES.md** | All TypeScript changes | TypeScript 5.6+ config, patterns, linting, testing, publishing |
| **SWIFT-GUIDELINES.md** | Swift/Xcode work | Swift 6, Xcode 26+, privacy, audit, testing playbooks |
| **REACT-GUIDELINES.md** | React/Next.js/Expo/React Native work | React 19+, Concurrent rendering, Suspense, Transitions, React Compiler, audit, performance |
| **REACT_USE_EFEECT-GUIDELINES.md** | When using useEffect | useEffect best practices, anti-patterns, when to use vs avoid |

### Infrastructure & Platform Services

| Guideline | When to Use | Key Topics |
|-----------|-------------|------------|
| **VERCEL-GUIDELINES.md** | Vercel deployments | Platform deployment (2025/2026), cron, env vars, WAF/protection, Edge Config, Observability |
| **SUPABASE-GUIDELINES.md** | Supabase services | Auth, Database, Edge Functions, Queues, Cron, Analytics (2025-2026) |
| **CLOUDFARE-GUIDELINES.md** | Cloudflare work | Workers, Pages, Zero Trust, PQ networking, Workers AI |

### Core Development Standards

| Guideline | When to Use | Key Topics |
|-----------|-------------|------------|
| **SOFTWARE-ENGINEERING-GUIDELINES.md** | All work (MANDATORY) | Clean Code/Fowler-aligned engineering mindset, operating loop, and agent checklist |
| **DEV-GUIDELINES.md** | All development work (MANDATORY) | Core standards, TypeScript patterns, testing, security, performance, code quality (Carmack level) |
| **DB-GUIDELINES.md** | Database work | Soft delete patterns (CRITICAL - never hard delete), schema design, query optimization, transactions, security |
| **LOG-GUIDELINES.md** | All logging (MANDATORY) | Structured logging, privacy-first approach, retention policies |
| **AUDIT-GUIDELINES.md** | User actions (MANDATORY) | Audit trail requirements, event categories, retention, GDPR, security monitoring |
| **SECURITY-GUIDELINES.md** | ALL tasks (MANDATORY) | Zero Trust, AI safety, supply chain security, incident response playbooks |

### Process & Workflow Guidelines

| Guideline | When to Use | Key Topics |
|-----------|-------------|------------|
| **EXECPLANS-GUIDELINES.md** | Complex features/refactors | Execution planning, project management, structured implementation plans |
| **SOFTWARE-ENGINEERING-GUIDELINES.md (ExecPlan template)** | Any time a new plan is required | Copy/paste-ready ExecPlan skeleton + checklist |
| **MCPORTER-GUIDELINES.md** | MCP tool calling | MCP server integration, tool calling best practices |

### Design References

| Reference | When to Use | Key Topics |
|-----------|-------------|------------|
| **liquid-glass-app-with-expo-ui-and-swiftui.md** | iOS UI implementation | iOS 26 Liquid Glass design patterns, premium UI with Expo and SwiftUI |

## Mandatory Reading by Task Type

### Mobile App (React Native/Expo)
1. MOBILE-GUIDELINES.md ✓
2. REACT-GUIDELINES.md ✓
3. REACT_USE_EFEECT-GUIDELINES.md (if using useEffect)
4. DEV-GUIDELINES.md ✓
5. SECURITY-GUIDELINES.md ✓
6. DB-GUIDELINES.md (if touching database)
7. LOG-GUIDELINES.md + AUDIT-GUIDELINES.md

### Native iOS/macOS (Swift/SwiftUI)
1. IOS-GUIDELINES.md ✓
2. MOBILE-GUIDELINES.md ✓
3. SWIFT-GUIDELINES.md ✓
4. DEV-GUIDELINES.md ✓
5. SECURITY-GUIDELINES.md ✓
6. LOG-GUIDELINES.md + AUDIT-GUIDELINES.md

### Next.js Web
1. WEB-NEXTJS-GUIDELINES.md ✓
2. REACT-GUIDELINES.md ✓
3. TYPESCRIPT-GUIDELINES.md ✓
4. DEV-GUIDELINES.md ✓
5. SECURITY-GUIDELINES.md ✓
6. DB-GUIDELINES.md (if database)
7. VERCEL-GUIDELINES.md (if Vercel) / SUPABASE-GUIDELINES.md (if Supabase)

### General Web (Landing Pages, Dashboards)
1. WEB-GUIDELINES.md ✓
2. TYPESCRIPT-GUIDELINES.md (if TypeScript)
3. DEV-GUIDELINES.md ✓
4. SECURITY-GUIDELINES.md ✓

### Backend/API
1. DEV-GUIDELINES.md ✓
2. SECURITY-GUIDELINES.md ✓
3. DB-GUIDELINES.md ✓
4. LOG-GUIDELINES.md ✓
5. AUDIT-GUIDELINES.md ✓
6. TYPESCRIPT-GUIDELINES.md (if TypeScript)

### Infrastructure/DevOps
1. SECURITY-GUIDELINES.md ✓
2. VERCEL-GUIDELINES.md / SUPABASE-GUIDELINES.md / CLOUDFARE-GUIDELINES.md
3. LOG-GUIDELINES.md

## Critical Rules

**Security (MANDATORY for ALL tasks)**:
- Re-read `SECURITY-GUIDELINES.md` before ANY task; reference sections you followed in updates
- No client-side secrets exposure
- Input validation at every boundary
- Sanitize outputs per context (HTML, SQL, shell)
- Follow Zero Trust principles

**Code Quality (Non-Negotiable)**:
- Do NOT write code just to "get it done" - always do it RIGHT
- Always follow latest best practices
- Strive for perfection in implementation
- Add code comments on tricky or non-obvious parts
- Verify and double-check before completion
- Favor clarity and maintainability over cleverness

**WE NEVER WANT WORKAROUNDS**: Always implement full, long-term sustainable solutions. Never create half-baked implementations.

**Logging & Audit (MANDATORY)**:
- LOG EVERYTHING: Generate audit logs and metrics for each user action
- Be as granular as possible
- Log in database when possible
- Log to command line if DEBUG enabled
- Follow LOG-GUIDELINES.md and AUDIT-GUIDELINES.md

**Platform-Specific Citations**:
- React/front-end: Cite REACT-GUIDELINES.md + REACT_USE_EFEECT-GUIDELINES.md
- Vercel deployments: Cite VERCEL-GUIDELINES.md
- Supabase services: Cite SUPABASE-GUIDELINES.md
- Cloudflare work: Cite CLOUDFARE-GUIDELINES.md
- TypeScript changes: Cite TYPESCRIPT-GUIDELINES.md
- Swift/Xcode: Cite SWIFT-GUIDELINES.md + IOS-GUIDELINES.md (if Apple platform)
- Mobile dev: Cite MOBILE-GUIDELINES.md
- Next.js: Cite WEB-NEXTJS-GUIDELINES.md
- General web: Cite WEB-GUIDELINES.md

## Workflow Essentials

**Search & Analysis**:
- Prefer `osgrep` (https://github.com/Ryandonofrio3/osgrep) for structural code searches; consult its docs for pattern syntax and flags
- Fall back to text searches (`rg`/`grep`) only if syntax search cannot express the need
- Set up `osgrep` as codebase linter and git hook where possible

**Command Execution**:
- Run shell work inside `tmux` sessions when available
- Leave panes labeled and tidy

**Git Commits**:
- Keep branches and commits atomic
- Stage only impacted paths
- Write imperative, scope-prefixed commit messages
- For tracked files:
  ```bash
  git commit -m "<scoped message>" -- path/to/file1 path/to/file2
  ```
- For brand-new files:
  ```bash
  git restore --staged :/ && git add "path/to/file1" "path/to/file2" && git commit -m "<scoped message>" -- path/to/file1 path/to/file2
  ```

**Testing**:
- Tests mirror the pyramid: unit > integration > e2e
- Favor TDD (Red → Green → Refactor) for new work
- Write tests after each feature/fix using same context
- Think about 5 implementations and choose the best one
- Test coverage must be comprehensive and deterministic

**Linting & Formatting**:
- Run lint (`pnpm lint` or project equivalent) and formatting tools locally
- Treat failures as blockers
- Use Ultracite/Biome, ESLint, and project-specific configs without bypassing checks

**Dependencies**:
- When adding dependencies, justify the choice
- Assess supply-chain risk
- Lock versions

## ExecPlans for Complex Features

For complex features or significant refactors, produce an ExecPlan (see `agent_planning/*.md`, e.g., `rag-first-principles-execplan.md`):
- **Purpose**: Define problem, scope, success criteria
- **Risks**: Identify technical risks, failure modes
- **Milestones**: Break down into atomic tasks
- **Code Quality Standards**: Explicit quality gates

See `EXECPLANS-GUIDELINES.md` for detailed guidance.

## Supabase Playbook

When using Supabase (Auth, DB, Edge Functions, Queues, Cron, Analytics):
- **MUST** follow `SUPABASE-GUIDELINES.md`
- Enforce branch-per-feature workflows (Supabase Branching 2.0)
- Document migrations/seeds alongside PRs
- Keep Edge Functions, Cron jobs, and Queues observable (structured logs, OpenTelemetry)
- Adopt pgvector 0.7.0, Supavisor transaction pools, RLS-by-default policies
- Never skip CLI-based migrations; if dashboard used for hotfixes, backfill migrations immediately

## Apple Platform Playbook

When working on native iOS/iPadOS/macOS (Swift/SwiftUI/Xcode):
- **MUST** cite `IOS-GUIDELINES.md` + `MOBILE-GUIDELINES.md`
- Target iOS/iPadOS 26 and macOS 15+ with Xcode 26
- Favor SwiftUI 6, SwiftData 2, Observation, Swift concurrency
- UIKit/AppKit escapes require justification + migration plan
- Meet performance, accessibility, privacy, instrumentation budgets (MetricKit, Instruments, Privacy Manifests, Liquid Glass UI, Haptics)
- Keep xcconfig, entitlements, provisioning, Privacy Manifests in git
- Run Swift Testing + XCUITest suites per PR
- Monitor MetricKit signal before App Store/TestFlight releases

## Documentation Structure

**Project Documentation Layout**:
- **CLAUDE.md** or **AGENTS.md** - How to work on this codebase (READ THIS FIRST)
- **PROJECT_STATUS.md** - Current progress, what's next, blockers (READ THIS SECOND)
- **README.md** - Human-readable project overview
- **QUICKSTART.md** - User getting started guide (optional)

**!IMPORTANT**: **DO NOT** externalize or document your work in markdown files after completing tasks unless explicitly instructed. If you need planning docs, use `agent_planning/` folder and archive to `agent_planning/archive/` when done. Brief summary OK.

## Self-Review Checklist

Before marking any task complete:
1. [ ] Did I read and cite relevant guidelines?
2. [ ] Are edge cases, performance, and failure modes handled?
3. [ ] Are tests comprehensive and deterministic?
4. [ ] Is reasoning explicit, concise, and professional?
5. [ ] Have I re-read the diff for elegance and maintainability?
6. [ ] Does code meet John Carmack review standards?
7. [ ] Are all security requirements met?
8. [ ] Is logging and audit coverage complete?

## Quality Gates

**Code Quality Checklist**:
- ✓ Correct (handles edge cases, errors, failure modes)
- ✓ Clear (readable without extensive comments)
- ✓ Simple (minimal complexity, no over-engineering)
- ✓ Tested (automated test coverage)
- ✓ Maintainable (modifiable without breaking)
- ✓ Secure (follows SECURITY-GUIDELINES.md)
- ✓ Performant (meets performance budgets)
- ✓ Observable (structured logging, audit trails)

**Review & Self-Critique**:
- When done, review and think from first principles
- If needed, update for better version
- Self-critique work until 100% certain it's correct
- **Ultrathink**: Are you sure you're done? Verify again!

## Configuration & Security

**Environment Variables**:
- Store configuration in environment files; never commit secrets
- Use `vercel env pull`, `pnpm db:studio`, or platform tooling for inspection

**Security & Zero Trust**:
- Validate inputs at every boundary
- Sanitize outputs per context (HTML, SQL, shell)
- Follow layered defenses, Zero Trust rules, incident workflows in `SECURITY-GUIDELINES.md`
- When instructions conflict, security rules take precedence

**ABSOLUTE SAFETY NOTICE** (production environments):
- DO NOT DROP THE DATABASE OR DELETE ANY RECORDS
- DO NOT RUN DESTRUCTIVE COMMANDS IN PRODUCTION
- VERIFY TARGET HOSTNAMES, PATHS, AND BACKUPS BEFORE EXECUTION

## Unresolved Questions

List any unresolved questions at the end of responses, if any.
