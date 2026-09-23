# Product Requirements (Inferred)

This PRD is derived from the current codebase, README, and app behavior. Validate and revise as needed.

## Product Goal
Provide a calm, reliable, on-device step tracking experience with AI-guided insights and coaching, without cloud inference.

## Core Requirements
- Step tracking via HealthKit with Apple Watch and iPhone data merged.
- Daily goal tracking, streaks, and progress visualization.
- AI Insights: daily insight and weekly trend analysis when on-device AI is available.
- AI Coach: conversational coaching with strict guardrails and no medical advice.
- AI Training Plans: create, view, and manage plans with weekly targets.
- Pricing: one-time paid download (R$ 1,99 in Brazil) with no subscription; every feature is included. AI features need a device with Apple Intelligence available.
- Workouts: start, track, pause/resume, and end walking workouts; Live Activity support.
- Badges: milestones and streak achievements with celebration.
- watchOS companion: glanceable daily summary.
- Widgets: step count, progress ring, weekly chart, and live activity.
- Localization: English (en) and Portuguese Brazil (pt-BR).
- Accessibility: VoiceOver labels, Dynamic Type, and adequate touch targets.
- Tip Jar: optional one-time StoreKit purchase in About.

## Non-Functional Requirements
- On-device AI only (Foundation Models).
- Privacy-first: health/activity data and AI prompts are not sent to cloud inference; only Apple processes App Store purchase data (the app and the optional tip).
- Swift 6.2 with strict concurrency and Swift Testing.
- iOS 26+ target with watchOS and widget targets.

## Constraints
- No medical advice or health outcome claims in AI output.
- Tip jar must remain optional and not gate features.

## Out of Scope (Current)
- Remote AI inference and any cloud storage of health or activity data: inference and health
  context stay on device. Purchase commerce is the deliberate exception, handled only by Apple
  (the App Store purchase and the StoreKit tip jar), as stated under Non-Functional Requirements.

## Open Questions
- Release channel details for remote ASC validation. The App Store app record exists; its
  identifier belongs in the release runbook and the daily journal, not in product docs.
- Final public support, marketing, and privacy-policy URLs for App Store metadata.
