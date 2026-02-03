# Repository Guidelines

## Project Overview
AIPedometer is a Swift 6.2 SwiftUI iOS pedometer app with AI-powered insights, plus watchOS and widget targets.

## Agent Notes
Run notes are stored at `agent_planning/ultrawork-notes.txt` (append each run with what worked, what didn’t, and missing context; reuse between sessions). Link: [agent_planning/ultrawork-notes.txt](agent_planning/ultrawork-notes.txt).

## Package Manager
This project does not use npm; it relies on Xcode/XcodeGen tooling.

## Non-Standard Commands
- `xcodegen generate`: regenerate `AIPedometer.xcodeproj` from `project.yml` (required after config/target changes).

## Release Checklist
- Bump `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
- Update `CHANGELOG.md` and the version in `README.md`.
- Validate HealthKit source filtering behavior (Apple sources preferred) and keep tests in sync.
- Tag the release after tests pass.

## Detailed Guides
- [Project structure and configuration](docs/agents/project-structure.md)
- [Build, test, and utilities](docs/agents/build-and-dev.md)
- [Coding style and naming](docs/agents/coding-style.md)
- [Testing guidelines](docs/agents/testing.md)
- [Git workflow](docs/agents/git-workflow.md)

## GUIDELINES-REF
Synced from `~/dev/GUIDELINES-REF/AGENTS.md` (use `bash Scripts/check-agents-sync.sh`).
GUIDELINES-REF is a curated, opinionated knowledge base for building production software with AI agents across security, logging/audit, web/mobile, databases, infra, and language runtimes.

Essentials (apply to every task):
- Always work through lists/todo/plans items; do not stop until all work is done and you are certain it works.
- Read `PRAGMATIC-RULES.md` and `SECURITY-GUIDELINES.md` before starting any task.
- If instructions conflict, security rules take precedence.
- Use `INDEX.md` or `GUIDELINES_INDEX.json` to locate task-specific guidance.
- Do not create new markdown docs unless required by a behavior/API change or explicitly requested.
- Treat this as a private repo: no public disclosure, use `SECURITY.md` for vulnerability reporting.
- Follow `.github/pull_request_template.md` and keep review routing aligned with `OWNERS.md`/`.github/CODEOWNERS`.

More detailed guidance (progressive disclosure):
- Mission & mindset: `docs/agents/mission-mindset.md`
- Reasoning protocol: `docs/agents/reasoning-protocol.md`
- Communication, scope, and tool use: `docs/agents/communication-and-scope.md`
- Knowledge base and guideline index: `docs/agents/knowledge-base.md`

<skills_system priority="1">

## Available Skills

<!-- SKILLS_TABLE_START -->
<usage>
When users ask you to perform tasks, check if any of the available skills below can help complete the task more effectively. Skills provide specialized capabilities and domain knowledge.

How to use skills:
- Invoke: Bash("openskills read <skill-name>")
- The skill content will load with detailed instructions on how to complete the task
- Base directory provided in output for resolving bundled resources (references/, scripts/, assets/)

Usage notes:
- Only use skills listed in <available_skills> below
- Do not invoke a skill that is already loaded in your context
- Each skill invocation is stateless
</usage>

<available_skills>

<skill>
<name>algorithmic-art</name>
<description>Creating algorithmic art using p5.js with seeded randomness and interactive parameter exploration. Use this when users request creating art using code, generative art, algorithmic art, flow fields, or particle systems. Create original algorithmic art rather than copying existing artists' work to avoid copyright violations.</description>
<location>global</location>
</skill>

<skill>
<name>artifacts-builder</name>
<description>Suite of tools for creating elaborate, multi-component claude.ai HTML artifacts using modern frontend web technologies (React, Tailwind CSS, shadcn/ui). Use for complex artifacts requiring state management, routing, or shadcn/ui components - not for simple single-file HTML/JSX artifacts.</description>
<location>global</location>
</skill>

<skill>
<name>brand-guidelines</name>
<description>Applies Anthropic's official brand colors and typography to any sort of artifact that may benefit from having Anthropic's look-and-feel. Use it when brand colors or style guidelines, visual formatting, or company design standards apply.</description>
<location>global</location>
</skill>

<skill>
<name>canvas-design</name>
<description>Create beautiful visual art in .png and .pdf documents using design philosophy. You should use this skill when the user asks to create a poster, piece of art, design, or other static piece. Create original visual designs, never copying existing artists' work to avoid copyright violations.</description>
<location>global</location>
</skill>

<skill>
<name>dimillian-app-store-changelog</name>
<description>Create user-facing App Store release notes by collecting and summarizing all user-impacting changes since the last git tag (or a specified ref). Use when asked to generate a comprehensive release changelog, App Store "What's New" text, or release notes based on git history or tags.</description>
<location>global</location>
</skill>

<skill>
<name>dimillian-gh-issue-fix-flow</name>
<description>End-to-end GitHub issue fix workflow using gh, local code changes, builds/tests, and git push. Use when asked to take an issue number, inspect the issue via gh, implement a fix, run XcodeBuildMCP builds/tests, commit with a closing message, and push.</description>
<location>global</location>
</skill>

<skill>
<name>dimillian-ios-debugger-agent</name>
<description>Use XcodeBuildMCP to build, run, launch, and debug the current iOS project on a booted simulator. Trigger when asked to run an iOS app, interact with the simulator UI, inspect on-screen state, capture logs/console output, or diagnose runtime behavior using XcodeBuildMCP tools.</description>
<location>global</location>
</skill>

<skill>
<name>dimillian-macos-spm-app-packaging</name>
<description>Scaffold, build, and package SwiftPM-based macOS apps without an Xcode project. Use when you need a from-scratch macOS app layout, SwiftPM targets/resources, a custom .app bundle assembly script, or signing/notarization/appcast steps outside Xcode.</description>
<location>global</location>
</skill>

<skill>
<name>dimillian-swift-concurrency-expert</name>
<description>Swift Concurrency review and remediation for Swift 6.2+. Use when asked to review Swift Concurrency usage, improve concurrency compliance, or fix Swift concurrency compiler errors in a feature or file.</description>
<location>global</location>
</skill>

<skill>
<name>dimillian-swiftui-liquid-glass</name>
<description>Implement, review, or improve SwiftUI features using the iOS 26+ Liquid Glass API. Use when asked to adopt Liquid Glass in new SwiftUI UI, refactor an existing feature to Liquid Glass, or review Liquid Glass usage for correctness, performance, and design alignment.</description>
<location>global</location>
</skill>

<skill>
<name>dimillian-swiftui-performance-audit</name>
<description>Audit and improve SwiftUI runtime performance from code review and architecture. Use for requests to diagnose slow rendering, janky scrolling, high CPU/memory usage, excessive view updates, or layout thrash in SwiftUI apps, and to provide guidance for user-run Instruments profiling when code review alone is insufficient.</description>
<location>global</location>
</skill>

<skill>
<name>dimillian-swiftui-ui-patterns</name>
<description>Best practices and example-driven guidance for building SwiftUI views and components. Use when creating or refactoring SwiftUI UI, designing tab architecture with TabView, composing screens, or needing component-specific patterns and examples.</description>
<location>global</location>
</skill>

<skill>
<name>dimillian-swiftui-view-refactor</name>
<description>Refactor and review SwiftUI view files for consistent structure, dependency injection, and Observation usage. Use when asked to clean up a SwiftUI view’s layout/ordering, handle view models safely (non-optional when possible), or standardize how dependencies and @Observable state are initialized and passed.</description>
<location>global</location>
</skill>

<skill>
<name>agent-readiness</name>
<description>Evaluate codebase readiness for AI coding agents using automated assessment. Use when onboarding repos, diagnosing agent struggles, or planning infrastructure improvements. Factory.ai aligned with 9 pillars, 51+ checks, multi-language support.</description>
<location>global</location>
</skill>

<skill>
<name>mneves-agent-workflows</name>
<description>Enforce AGENTS_GUIDELINES.md compliance for mandatory guideline references, code quality standards, workflow standards (tmux, git commits), testing, logging/audit requirements, and security-first principles</description>
<location>global</location>
</skill>

<skill>
<name>mneves-ai-code-security</name>
<description>Enforce AI-CODE-SECURITY-GUIDELINES.md compliance for AI-generated code - prevent XSS (86% failure rate), SQL injection, hardcoded secrets, dependency hallucination, and other AI-specific vulnerabilities</description>
<location>global</location>
</skill>

<skill>
<name>mneves-api-design</name>
<description>Enforce REST/HTTP API design standards including endpoint naming, error responses, rate limiting, versioning, OpenAPI specs, and security headers (user)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-audit</name>
<description>Enforce AUDIT-GUIDELINES.md compliance for complete audit trails with immutability, privacy-first logging, multi-tenant isolation, GDPR compliance, and retention policies</description>
<location>global</location>
</skill>

<skill>
<name>mneves-brazilian-legal-contracts</name>
<description>Enforce Brazilian legal contracts compliance for IP ownership (CLT/PJ/co-founders), API terms (SLAs, rate limits), SaaS contracts, Marco Civil, and CDC requirements.</description>
<location>global</location>
</skill>

<skill>
<name>mneves-bun</name>
<description>Enforce BUN-GUIDELINES.md compliance for Bun 1.2+ runtime with native TypeScript, bun:sqlite, bun:test, Workspace support, and 28x faster package management (user)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-ci-cd</name>
<description>Enforce CI/CD standards for GitHub Actions workflows with matrix builds, caching strategies, secret management, deployment gates, and release automation (user)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-cloudflare</name>
<description>Enforce CLOUDFARE-GUIDELINES.md compliance for Cloudflare Workers, Pages, Workers AI, D1, Durable Objects, Pipelines, R2, Hyperdrive, Zero Trust, post-quantum (PQ) networking, and observability (2025-2026)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-database</name>
<description>Enforce DB-GUIDELINES.md compliance - soft deletes, indexes, transactions, parameterized queries, normalization, and database security</description>
<location>global</location>
</skill>

<skill>
<name>mneves-dev-standards</name>
<description>Enforce DEV-GUIDELINES.md compliance for code quality, type safety, error handling, security, performance, testing, and John Carmack-level review standards</description>
<location>global</location>
</skill>

<skill>
<name>mneves-execution-planning</name>
<description>Enforce EXECPLANS-GUIDELINES.md (PLANS.md) compliance for creating living execution plans (ExecPlans) that are self-contained, novice-guiding, outcome-focused, with Progress tracking, Decision Logs, and Surprises & Discoveries documentation</description>
<location>global</location>
</skill>

<skill>
<name>mneves-expo</name>
<description>Enforce EXPO-GUIDELINES.md compliance for Expo SDK 54+, EAS Build, Config Plugins, dev-client, native modules, OTA updates, and Expo Router patterns (user)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-git-workflow</name>
<description>Enforce git workflow standards including conventional commits, atomic commits, branch naming, pre-commit hooks, PR templates, and trunk-based development patterns (user)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-ios</name>
<description>Enforce IOS-GUIDELINES.md compliance for iOS 26+, iPadOS 26+, macOS 15 Sequoia+ with Xcode 26, SwiftUI 6, SwiftData 2, Observation framework, App Store compliance, MetricKit instrumentation, and native Apple platform delivery</description>
<location>global</location>
</skill>

<skill>
<name>mneves-lgpd-compliance</name>
<description>Enforce Brazilian LGPD (Lei Geral de Proteção de Dados) compliance for data processing, consent management, data subject rights, retention policies, and ANPD requirements.</description>
<location>global</location>
</skill>

<skill>
<name>mneves-liquid-glass-ui</name>
<description>Enforce iOS 26+ Liquid Glass design system compliance with translucent materials, depth effects, smooth animations, haptic feedback, and premium UI polish for Expo and SwiftUI</description>
<location>global</location>
</skill>

<skill>
<name>mneves-logging</name>
<description>Enforce LOG-GUIDELINES.md compliance for structured logging, observability, privacy-first data handling, request context propagation, cost tracking, and retention policies</description>
<location>global</location>
</skill>

<skill>
<name>mneves-mcporter</name>
<description>Enforce MCPORTER-GUIDELINES.md compliance for MCP server tool calls using mcporter CLI (list, call, generate-cli, emit-ts commands) with proper timeout handling, output formats, and TypeScript generation</description>
<location>global</location>
</skill>

<skill>
<name>mneves-mercado-pago</name>
<description>Enforce MERCADO-PAGO-API-GUIDELINES.md compliance for Brazilian payment processing with Payment Link API, PIX/card/boleto support, HMAC webhook verification, LGPD compliance, and Hono best practices (user)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-mobile-development</name>
<description>Enforce MOBILE-GUIDELINES.md compliance for iOS 26+, Android 15/16, Expo SDK 54, React Native 0.81.5+ - New Architecture, React Compiler, performance, accessibility, offline-first patterns</description>
<location>global</location>
</skill>

<skill>
<name>mneves-nextjs</name>
<description>Enforce WEB-NEXTJS-GUIDELINES.md compliance for Next.js 15/16 projects - App Router, Server Components, Server Actions, Turbopack, Cache Components, and production deployment</description>
<location>global</location>
</skill>

<skill>
<name>mneves-python</name>
<description>Enforce PYTHON-GUIDELINES.md compliance for Python 3.12+/3.14, type hints, uv package manager, ruff linting, pytest testing, async patterns, and modern Python idioms (user)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-rag-chatbot</name>
<description>Enforce RAG-CHATBOT-GUIDELINES.md compliance for AI SDK RAG chatbots with pgvector embeddings, chunking strategies, retrieval optimization, citations, rate limiting, and streaming responses (user)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-react</name>
<description>Enforce REACT-GUIDELINES.md compliance for React 19+ projects - React Compiler, new hooks (use, useActionState, useOptimistic), Server Components, concurrent rendering, and modern patterns</description>
<location>global</location>
</skill>

<skill>
<name>mneves-react-useeffect</name>
<description>Enforce REACT_USE_EFEECT-GUIDELINES.md compliance - proper useEffect usage, dependency arrays, cleanup functions, and avoiding common anti-patterns</description>
<location>global</location>
</skill>

<skill>
<name>mneves-security</name>
<description>Enforce SECURITY-GUIDELINES.md compliance - defense-in-depth, CSP, input validation, secure authentication, OWASP best practices, and vulnerability prevention</description>
<location>global</location>
</skill>

<skill>
<name>mneves-sqlite</name>
<description>Enforce SQLITE-GUIDELINES.md compliance for WAL mode, STRICT tables, concurrency patterns, indexing strategies, soft deletes, and Cloudflare D1 edge deployment (user)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-supabase</name>
<description>Enforce SUPABASE-GUIDELINES.md compliance for Supabase Auth, Database (Postgres + pgvector), Edge Functions, Queues, Cron, Branching 2.0, RLS, Storage, Realtime, Analytics Buckets, and observability (2025-2026)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-swift</name>
<description>Enforce SWIFT-GUIDELINES.md compliance for Swift 6+ with Xcode 26, data-race safety, typed errors, ownership types, macros, SwiftData migrations, Swift Testing, privacy manifests, and audit logging</description>
<location>global</location>
</skill>

<skill>
<name>mneves-testing</name>
<description>Enforce TESTING-IN-MEMORY-DATABASE-GUIDELINES.md compliance for unit/integration testing with Jest, Vitest, in-memory database patterns, mock strategies, coverage thresholds, and test-first development (user)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-typescript</name>
<description>Enforce TYPESCRIPT-GUIDELINES.md compliance for TypeScript 5.6+ with strict configuration, Decorators 1.0, Project References, runtime validation, type-only imports, and build/testing standards</description>
<location>global</location>
</skill>

<skill>
<name>mneves-ui</name>
<description>Enforce opinionated UI/UX design constraints for building interfaces inspired by Mercury, Notion, Apple, and Vercel. This skill should be used when designing or implementing frontend interfaces, creating new components, or reviewing UI code. Triggers on requests like "design my app", "create a landing page", "build UI components", or any frontend development task.</description>
<location>global</location>
</skill>

<skill>
<name>mneves-vercel</name>
<description>Enforce VERCEL-GUIDELINES.md compliance for Vercel deployments with Next.js 15+, Fluid compute, Rolling Releases, Cron Jobs, Edge Config, Observability Plus, WAF/Protectd security, and audit logging (2025-2026)</description>
<location>global</location>
</skill>

<skill>
<name>mneves-web-development</name>
<description>Enforce WEB-GUIDELINES.md compliance for Next.js 15+, React 19+, Vite 6 projects - Core Web Vitals (INP, LCP, CLS), WCAG 2.2 accessibility, modern CSS, security (CSP/CORS), and 2025/2026 web standards</description>
<location>global</location>
</skill>

<skill>
<name>mneves-whatsapp-bot</name>
<description>Enforce EVOLUTION-API-GUIDELINES.md compliance for WhatsApp automation via Evolution API or WAHA with webhook handling, message deduplication, rate limiting, and multi-instance management (user)</description>
<location>global</location>
</skill>

<skill>
<name>vercel-react-best-practices</name>
<description>React and Next.js performance optimization guidelines from Vercel Engineering. This skill should be used when writing, reviewing, or refactoring React/Next.js code to ensure optimal performance patterns. Triggers on tasks involving React components, Next.js pages, data fetching, bundle optimization, or performance improvements.</description>
<location>global</location>
</skill>

<skill>
<name>web-design-guidelines</name>
<description>Review UI code for Web Interface Guidelines compliance. Use when asked to "review my UI", "check accessibility", "audit design", "review UX", or "check my site against best practices".</description>
<location>global</location>
</skill>

<skill>
<name>webapp-testing</name>
<description>Toolkit for interacting with and testing local web applications using Playwright. Supports verifying frontend functionality, debugging UI behavior, capturing browser screenshots, and viewing browser logs.</description>
<location>global</location>
</skill>

</available_skills>
<!-- SKILLS_TABLE_END -->

</skills_system>
